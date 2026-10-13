## ChatBox.gd
## Ortak sohbet kutusu — Lobby (LOBBY modu) ve HUD (GAME modu) kullanır. Mesajlar NetworkManager.send_chat()
## ile host'a gider, NetworkManager.chat_received ile gelir; geçmiş NetworkManager.chat_history'de (sahne geçişinde korunur).
##
## Kanallar: "all" (HERKES) / "team" (TAKIM). Kısayollar:
##   Enter: aç / gönder      Tab (yazarken): kanal değiştir      Esc: kapat
##   T (sadece GAME): takım kanalıyla aç      "/t mesaj" → takım, "/a mesaj" → herkes
## GAME modu: lobi geçmişi gösterilmez, sadece maç sırasında gelen mesajlar. Kapalıyken her mesaj
## SHOW_TIME sn görünür, sonra FADE_TIME içinde söner. Açıkken son GAME_OPEN_LINES mesaj görünür.
## is_typing (statik): yazarken Player.gd hareket/ateşi, HUD TAB skor tablosunu kilitler.

class_name ChatBox
extends PanelContainer

enum Mode { LOBBY, GAME }

const SHOW_TIME := 4.5
const FADE_TIME := 0.6
const GAME_OPEN_LINES := 8
const GAME_KEEP_LINES := 30

static var is_typing := false

var mode: Mode = Mode.LOBBY
## HUD menü/oyun sonu ekranı açıkken false yapar
var enabled := true

var _log: RichTextLabel
var _input_row: HBoxContainer
var _channel_btn: Button
var _line: LineEdit
var _hint: Label
var _channel := "all"
var _game_lines: Array[Dictionary] = []  # GAME: {msg, t} — sadece maç içinde gelenler
var _rendered_any := false
var _style_open: StyleBoxFlat
var _style_closed: StyleBoxFlat


func _ready() -> void:
	_style_open = UITheme.style(Color(UITheme.BG, 0.82), 12, UITheme.BORDER, 1, 12, 10)
	_style_closed = UITheme.style(Color.TRANSPARENT, 12, Color.TRANSPARENT, 0, 12, 10)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	if mode == Mode.LOBBY:
		var head := HBoxContainer.new()
		box.add_child(head)
		var cap := UITheme.label("SOHBET", 10, UITheme.TEXT_DIM, UITheme.font_caps)
		cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(cap)
		head.add_child(UITheme.label("TAB: KANAL", 9, Color(UITheme.TEXT_DIM, 0.6), UITheme.font_caps))

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = false
	if mode == Mode.GAME:
		# Satırlar kutunun altına yaslı dursun (oyuncu kartının hemen üstünde), karanlıkta okunsun
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(spacer)
		_log.fit_content = true
		_log.scroll_active = false
		_log.size_flags_vertical = Control.SIZE_SHRINK_END
		_log.add_theme_constant_override("outline_size", 4)
		_log.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	else:
		_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log.add_theme_font_override("bold_font", UITheme.font_bold)
	_log.add_theme_font_size_override("bold_font_size", 13)
	_log.add_theme_constant_override("line_separation", 3)
	_log.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_log.mouse_filter = Control.MOUSE_FILTER_PASS if mode == Mode.LOBBY else Control.MOUSE_FILTER_IGNORE
	box.add_child(_log)

	_input_row = HBoxContainer.new()
	_input_row.add_theme_constant_override("separation", 6)
	box.add_child(_input_row)

	_channel_btn = Button.new()
	_channel_btn.custom_minimum_size = Vector2(78, 0)
	_channel_btn.focus_mode = Control.FOCUS_NONE
	_channel_btn.add_theme_font_override("font", UITheme.font_caps)
	_channel_btn.add_theme_font_size_override("font_size", 10)
	_channel_btn.tooltip_text = "Kanal değiştir (Tab)"
	_channel_btn.pressed.connect(_toggle_channel)
	_input_row.add_child(_channel_btn)

	_line = LineEdit.new()
	_line.max_length = NetworkManager.CHAT_MAX_LEN
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.placeholder_text = "Mesaj yaz…  (Enter)"
	_line.add_theme_font_size_override("font_size", 13)
	_line.context_menu_enabled = false
	_line.text_submitted.connect(_on_submit)
	_line.focus_entered.connect(func() -> void: is_typing = true)
	_line.focus_exited.connect(_on_focus_exited)
	_input_row.add_child(_line)

	if mode == Mode.GAME:
		_hint = UITheme.label("ENTER: GÖNDER  ·  TAB: KANAL  ·  ESC: KAPAT", 9, Color(UITheme.TEXT_DIM, 0.7), UITheme.font_caps)
		box.add_child(_hint)

	NetworkManager.chat_received.connect(_on_chat_received)
	NetworkManager.player_list_updated.connect(_update_channel_btn)
	# Lobi geçmişi sadece lobide; oyun içi sohbet temiz başlar
	if mode == Mode.LOBBY:
		for msg: Dictionary in NetworkManager.chat_history:
			_log.append_text(_format(msg, 1.0))
		if NetworkManager.chat_history.is_empty():
			_log.append_text("[color=#%s]Takımınla ya da herkesle buradan konuş.[/color]\n" % UITheme.TEXT_DIM.to_html(false))

	_update_channel_btn()
	_set_open(mode == Mode.LOBBY)


func _exit_tree() -> void:
	is_typing = false  # statik — sahne değişince kilit kalmasın


func _process(_delta: float) -> void:
	# GAME + kapalı: görünür/sönen satır varsa her kare yeniden çiz (en fazla birkaç satır)
	if mode != Mode.GAME or _line.has_focus():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var any_visible := false
	for e: Dictionary in _game_lines:
		if now - float(e["t"]) < SHOW_TIME + FADE_TIME:
			any_visible = true
			break
	if any_visible or _rendered_any:
		_render_game()


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not is_visible_in_tree():
		return
	if _line.has_focus():
		if k.keycode == KEY_ESCAPE:
			_close()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_TAB:
			_toggle_channel()
			get_viewport().set_input_as_handled()
		return
	if not enabled:
		return
	if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		_open()
		get_viewport().set_input_as_handled()
	elif mode == Mode.GAME and k.keycode == KEY_T and _team_available():
		_channel = "team"
		_open()
		get_viewport().set_input_as_handled()  # 't' harfi kutuya yazılmasın


# ─────────────────────────────────────────────
#  Aç / kapat / gönder
# ─────────────────────────────────────────────

func _open() -> void:
	_set_open(true)
	_update_channel_btn()
	_line.grab_focus()


func _close() -> void:
	_line.release_focus()
	if mode == Mode.GAME:
		_line.text = ""
		_set_open(false)


func _on_focus_exited() -> void:
	is_typing = false
	if mode == Mode.GAME:
		_set_open(false)


func _set_open(open: bool) -> void:
	add_theme_stylebox_override("panel", _style_open if open or mode == Mode.LOBBY else _style_closed)
	_input_row.visible = open or mode == Mode.LOBBY
	if _hint:
		_hint.visible = open
	_log.get_v_scroll_bar().modulate.a = 1.0 if open or mode == Mode.LOBBY else 0.0
	if mode == Mode.GAME:
		_render_game(open)


func _on_submit(text: String) -> void:
	var clean := text.strip_edges()
	var channel := _channel
	if clean.begins_with("/t "):
		channel = "team"
		clean = clean.substr(3)
	elif clean.begins_with("/a "):
		channel = "all"
		clean = clean.substr(3)
	_line.text = ""
	if clean.strip_edges().is_empty():
		_close()
		return
	NetworkManager.send_chat(clean, channel if channel != "team" or _team_available() else "all")
	if mode == Mode.GAME:
		_close()


func _toggle_channel() -> void:
	_channel = "team" if _channel == "all" and _team_available() else "all"
	_update_channel_btn()


func _team_available() -> bool:
	return NetworkManager.players.get(NetworkManager.get_local_id(), {}).get("team_id", -1) >= 0


func _update_channel_btn() -> void:
	if _channel_btn == null:
		return
	if _channel == "team" and not _team_available():
		_channel = "all"
	var team_id: int = NetworkManager.players.get(NetworkManager.get_local_id(), {}).get("team_id", -1)
	var col := TeamManager.get_color(team_id) if _channel == "team" else UITheme.TEXT
	_channel_btn.text = "TAKIM" if _channel == "team" else "HERKES"
	var st := UITheme.style(Color(col, 0.14), 8, Color(col, 0.5), 1, 8, 6)
	for key: String in ["normal", "hover", "pressed"]:
		_channel_btn.add_theme_stylebox_override(key, st)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		_channel_btn.add_theme_color_override(key, col)


# ─────────────────────────────────────────────
#  Mesaj gösterimi
# ─────────────────────────────────────────────

func _on_chat_received(msg: Dictionary) -> void:
	if mode == Mode.LOBBY:
		_log.append_text(_format(msg, 1.0))
		return
	_game_lines.append({"msg": msg, "t": Time.get_ticks_msec() / 1000.0})
	if _game_lines.size() > GAME_KEEP_LINES:
		_game_lines.pop_front()
	_render_game(_line.has_focus())


## GAME: açıkken son GAME_OPEN_LINES mesaj; kapalıyken sadece SHOW_TIME içindekiler, sonra sönerek kaybolur
func _render_game(open: bool = false) -> void:
	var parts: PackedStringArray = []
	var now := Time.get_ticks_msec() / 1000.0
	var start := maxi(_game_lines.size() - GAME_OPEN_LINES, 0) if open else 0
	for i in range(start, _game_lines.size()):
		var e: Dictionary = _game_lines[i]
		var alpha := 1.0
		if not open:
			var age := now - float(e["t"])
			if age >= SHOW_TIME + FADE_TIME:
				continue
			alpha = clampf(1.0 - (age - SHOW_TIME) / FADE_TIME, 0.0, 1.0)
		# Sondaki "\n" kırpılır — fit_content yüksekliği boş satırla büyümesin
		parts.append(_format(e["msg"], alpha).trim_suffix("\n"))
	_rendered_any = not parts.is_empty()
	_log.text = "\n".join(parts)


func _format(msg: Dictionary, alpha: float) -> String:
	var channel: String = msg.get("channel", "all")
	var text := _escape(String(msg.get("text", "")))
	if channel == "system":
		return "[color=#%s]•  %s[/color]\n" % [Color(UITheme.ACCENT, alpha).to_html(true), text]
	var team: int = msg.get("team", -1)
	var name_col := Color(TeamManager.get_color(team) if team >= 0 else UITheme.TEXT_DIM, alpha)
	var line := ""
	if channel == "team":
		line += "[color=#%s][lb]TAKIM][/color] " % name_col.to_html(true)
	var is_me: bool = int(msg.get("sender", 0)) == NetworkManager.get_local_id()
	line += "[b][color=#%s]%s%s:[/color][/b] " % [name_col.to_html(true), _escape(String(msg.get("name", "???"))), " (Sen)" if is_me else ""]
	line += "[color=#%s]%s[/color]\n" % [Color(UITheme.TEXT, alpha).to_html(true), text]
	return line


## Oyuncu metnindeki BBCode etiketlerini etkisizleştir
func _escape(s: String) -> String:
	return s.replace("[", "[lb]")

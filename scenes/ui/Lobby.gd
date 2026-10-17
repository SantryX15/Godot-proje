## Lobby.gd
## Oda içi bekleme ekranı: 4 tıklanabilir takım kartı (slot sayısı = takım boyutu, kompakt), alt bölümde
## sohbet | ODA AYARLARI (harita, takım boyutu 2v2v2v2-5v5v5v5, şifre — sadece host değiştirir) | takımsızlar +
## hazır/başlat. UI tamamen kodla kurulur; görünüm UITheme'den gelir,
## arka plan MainMenu ile aynı MenuBackground3D (fenerli askerler; fare feneri kendi takımının rengine döner).

extends Control

# Oda ayarları paneli
var _map_option: OptionButton
var _size_option: OptionButton
var _pw_status: Label
var _pw_input: LineEdit
var _pw_row: HBoxContainer
var _pw_remove: Button
var _settings_hint: Label
var _settings_summary: Label
var _draft_note: Label
var _save_btn: Button
var _settings_modal: Control
var _settings_card: Control
var _blur_mat: ShaderMaterial

const MENU_BACKGROUND := preload("res://scenes/ui/MenuBackground3D.gd")
const MENU_OVERLAY := preload("res://scenes/ui/MenuOverlay.gdshader")
var _background: Node = null
var _light_color := UITheme.ACCENT

var _room_name_lbl: Label
var _room_code_lbl: Label
var _copy_btn: Button
var _player_count_lbl: Label

var _teams: Array[Dictionary] = []   # her eleman: {panel, count_lbl, slots, footer, footer_lbl}
var _hovered_team := -1

var _unassigned_row: HBoxContainer
var _check_balance: Label
var _check_ready: Label
var _ready_btn: Button
var _start_btn: Button
var _host_hint: Label


func _ready() -> void:
	UITheme.apply(get_tree())
	NetworkManager.player_list_updated.connect(_refresh_player_list)
	NetworkManager.host_migrated.connect(_on_host_migrated)
	NetworkManager.room_settings_changed.connect(_on_settings_changed)
	GameManager.game_started.connect(_on_game_started)

	_build_ui()
	_update_room_info()
	_refresh_settings()
	_refresh_player_list()


func _process(delta: float) -> void:
	# Fare feneri yavaşça kendi takımının rengine döner
	if _background:
		_background.light_color = (_background.light_color as Color).lerp(_light_color, 1.0 - exp(-3.0 * delta))


# ─────────────────────────────────────────────
#  Yerleşim
# ─────────────────────────────────────────────

func _build_ui() -> void:
	# 3D arka plan (MainMenu ile aynı): fenerli askerler devriyede, fare feneri takım renginde
	_background = MENU_BACKGROUND.new()
	add_child(_background)
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var om := ShaderMaterial.new()
	om.shader = MENU_OVERLAY
	overlay.material = om
	add_child(overlay)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	root.add_child(_build_header())

	# Takım kartları: içerik kadar yükseklik (slot sayısı = takım boyutu) — boş alan alt bölüme kalır
	var team_row := HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 14)
	root.add_child(team_row)
	for i in range(NetworkManager.TEAM_COUNT):
		team_row.add_child(_build_team_card(i))

	# Alt bölüm: sohbet | oda ayarları | takımsızlar + hazır/başlat
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(bottom)

	var chat := ChatBox.new()
	chat.mode = ChatBox.Mode.LOBBY
	chat.custom_minimum_size = Vector2(340, 150)
	chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(chat)


	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size = Vector2(330, 0)
	bottom.add_child(right)
	right.add_child(_build_unassigned_strip())
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(fill)
	right.add_child(_build_bottom_bar())

	# Ayarlar penceresi en üstte (⚙ ile açılır, arka plan bulanıklaşır)
	_build_settings_modal()


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)
	title_box.add_child(UITheme.label("LOBİ  ·  TAKIMINI SEÇ", 11, UITheme.TEXT_DIM, UITheme.font_caps))
	_room_name_lbl = UITheme.label("", 26, UITheme.TEXT, UITheme.font_bold)
	_room_name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_box.add_child(_room_name_lbl)
	# Ayar özeti (format · harita · şifre) — ayrıntılar ⚙ penceresinde
	_settings_summary = UITheme.label("", 11, UITheme.TEXT_DIM, UITheme.font_caps)
	title_box.add_child(_settings_summary)

	# Oyuncu sayısı
	var count_chip := PanelContainer.new()
	count_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count_chip.add_theme_stylebox_override("panel", UITheme.style(UITheme.SURFACE, 12, UITheme.BORDER, 1, 14, 10))
	var count_box := VBoxContainer.new()
	count_box.add_theme_constant_override("separation", 0)
	count_chip.add_child(count_box)
	count_box.add_child(UITheme.label("OYUNCU", 10, UITheme.TEXT_DIM, UITheme.font_caps))
	_player_count_lbl = UITheme.label("", 18, UITheme.TEXT, UITheme.font_bold)
	count_box.add_child(_player_count_lbl)
	header.add_child(count_chip)

	# Oda kodu + kopyala
	var code_chip := PanelContainer.new()
	code_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	code_chip.add_theme_stylebox_override("panel", UITheme.style(Color(UITheme.ACCENT, 0.08), 12, Color(UITheme.ACCENT, 0.35), 1, 14, 10))
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 14)
	code_chip.add_child(code_row)
	var code_box := VBoxContainer.new()
	code_box.add_theme_constant_override("separation", 0)
	code_row.add_child(code_box)
	code_box.add_child(UITheme.label("ODA KODU", 10, UITheme.TEXT_DIM, UITheme.font_caps))
	_room_code_lbl = UITheme.label("", 18, UITheme.ACCENT, UITheme.font_title)
	code_box.add_child(_room_code_lbl)
	_copy_btn = Button.new()
	_copy_btn.text = "Kopyala"
	_copy_btn.theme_type_variation = "GhostButton"
	_copy_btn.focus_mode = Control.FOCUS_NONE
	_copy_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_copy_btn.pressed.connect(_on_copy_code)
	code_row.add_child(_copy_btn)
	header.add_child(code_chip)

	var leave := Button.new()
	leave.text = "←  Ayrıl"
	leave.theme_type_variation = "GhostButton"
	leave.tooltip_text = "Lobiden ayrıl (ESC)"
	leave.focus_mode = Control.FOCUS_NONE
	leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(_on_back_pressed)

	# ⚙ Oda ayarları (sağ üst, oda bilgilerinin yanında)
	var gear := Button.new()
	gear.text = "⚙"
	gear.tooltip_text = "Oda ayarları"
	gear.focus_mode = Control.FOCUS_NONE
	gear.custom_minimum_size = Vector2(46, 46)
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gear.add_theme_font_size_override("font_size", 22)
	gear.pressed.connect(_open_settings)
	header.add_child(gear)
	header.move_child(gear, leave.get_index())
	header.add_child(leave)
	return header


func _build_team_card(team_id: int) -> Control:
	var color := TeamManager.get_color(team_id)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_panel_input.bind(team_id))
	panel.mouse_entered.connect(_on_team_hover.bind(team_id, true))
	panel.mouse_exited.connect(_on_team_hover.bind(team_id, false))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)

	# Başlık: renk şeridi + isim + doluluk
	var header := PanelContainer.new()
	var hs := UITheme.style(Color(color, 0.12), 0, Color.TRANSPARENT, 0, 14, 9)
	hs.corner_radius_top_left = 12
	hs.corner_radius_top_right = 12
	hs.border_width_top = 3
	hs.border_color = color
	header.add_theme_stylebox_override("panel", hs)
	box.add_child(header)
	var hrow := HBoxContainer.new()
	header.add_child(hrow)
	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 0)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(name_box)
	name_box.add_child(UITheme.label(TeamManager.get_team_name(team_id).to_upper(), 17, color, UITheme.font_title))
	var count_lbl := UITheme.label("0/%d" % NetworkManager.get_team_size(), 14, UITheme.TEXT, UITheme.font_bold)
	count_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hrow.add_child(count_lbl)

	# Slotlar (kompakt — kart yüksekliği slot sayısı kadar)
	var slots_margin := MarginContainer.new()
	for side: String in ["left", "right"]:
		slots_margin.add_theme_constant_override("margin_" + side, 8)
	slots_margin.add_theme_constant_override("margin_top", 8)
	slots_margin.add_theme_constant_override("margin_bottom", 8)
	box.add_child(slots_margin)
	var slots := VBoxContainer.new()
	slots.add_theme_constant_override("separation", 4)
	slots_margin.add_child(slots)

	# Alt şerit
	var footer := PanelContainer.new()
	footer.custom_minimum_size = Vector2(0, 28)
	box.add_child(footer)
	var footer_lbl := UITheme.label("", 11, UITheme.TEXT_DIM, UITheme.font_caps)
	footer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(footer_lbl)

	_ignore_mouse_recursive(box)
	_teams.append({"panel": panel, "count_lbl": count_lbl, "slots": slots, "footer": footer, "footer_lbl": footer_lbl})
	return panel


func _build_unassigned_strip() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var cap := UITheme.label("TAKIM SEÇMEYENLER", 10, UITheme.TEXT_DIM, UITheme.font_caps)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	_unassigned_row = HBoxContainer.new()
	_unassigned_row.add_theme_constant_override("separation", 8)
	row.add_child(_unassigned_row)
	return row


func _build_bottom_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UITheme.style(UITheme.SURFACE, 14, UITheme.BORDER, 1, 16, 12))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	bar.add_child(col)

	var checks := VBoxContainer.new()
	checks.add_theme_constant_override("separation", 3)
	col.add_child(checks)
	_check_balance = UITheme.label("", 13, UITheme.TEXT_DIM)
	checks.add_child(_check_balance)
	_check_ready = UITheme.label("", 13, UITheme.TEXT_DIM)
	checks.add_child(_check_ready)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)

	_host_hint = UITheme.label("Oyunu oda sahibi başlatacak", 12, UITheme.TEXT_DIM)
	_host_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_host_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_host_hint)

	_ready_btn = Button.new()
	_ready_btn.custom_minimum_size = Vector2(140, 44)
	_ready_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ready_btn.focus_mode = Control.FOCUS_NONE
	_ready_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_ready_btn.add_theme_font_size_override("font_size", 15)
	_ready_btn.pressed.connect(_on_ready_btn_pressed)
	row.add_child(_ready_btn)

	_start_btn = Button.new()
	_start_btn.text = "OYUNU BAŞLAT  ▶"
	_start_btn.theme_type_variation = "PrimaryButton"
	_start_btn.custom_minimum_size = Vector2(150, 44)
	_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_btn.focus_mode = Control.FOCUS_NONE
	_start_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_start_btn.add_theme_font_size_override("font_size", 15)
	_start_btn.pressed.connect(_on_start_btn_pressed)
	row.add_child(_start_btn)
	return bar


## ⚙ Ayarlar penceresi: tam ekran katman (bulanık + karartılmış arka plan, dışına tıklayınca/ESC kapanır)
## + ortada kart. Host düzenler; diğerleri aynı pencereyi salt-okunur görür.
func _build_settings_modal() -> void:
	_settings_modal = Control.new()
	_settings_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_modal.visible = false
	add_child(_settings_modal)

	var blur := ColorRect.new()
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_STOP
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = preload("res://scenes/ui/BlurBackdrop.gdshader")
	blur.material = _blur_mat
	blur.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_close_settings())
	_settings_modal.add_child(blur)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_modal.add_child(center)
	_settings_card = _build_settings_panel()
	center.add_child(_settings_card)


func _open_settings() -> void:
	_load_draft()
	_settings_modal.visible = true
	_settings_card.pivot_offset = _settings_card.size * 0.5
	_settings_card.modulate.a = 0.0
	_settings_card.scale = Vector2(0.96, 0.96)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float) -> void: _blur_mat.set_shader_parameter("amount", v), 0.0, 1.0, 0.18)
	tw.tween_property(_settings_card, "modulate:a", 1.0, 0.16)
	tw.tween_property(_settings_card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Kapat = taslağı at (değişiklikler uygulanmaz). Kaydet önce _apply_draft çağırır.
func _close_settings() -> void:
	if not _settings_modal.visible:
		return
	_pw_input.text = ""
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float) -> void: _blur_mat.set_shader_parameter("amount", v), 1.0, 0.0, 0.14)
	tw.tween_property(_settings_card, "modulate:a", 0.0, 0.12)
	tw.chain().tween_callback(func() -> void: _settings_modal.visible = false)


## ODA AYARLARI kartı: harita, takım boyutu, şifre. TASLAK mantığı — kontroller sadece taslağı değiştirir,
## [KAYDET] hepsini birlikte uygular, [KAPAT]/✕/ESC/dışına tıklama taslağı atar.
func _build_settings_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	var st := UITheme.style(UITheme.SURFACE_2, 16, Color(UITheme.ACCENT, 0.3), 1, 24, 20)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 30
	panel.add_theme_stylebox_override("panel", st)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(UITheme.label("⚙  ODA AYARLARI", 11, UITheme.ACCENT, UITheme.font_caps))
	_settings_hint = UITheme.label("", 12, UITheme.TEXT_DIM)
	titles.add_child(_settings_hint)
	var close_x := Button.new()
	close_x.text = "✕"
	close_x.theme_type_variation = "GhostButton"
	close_x.focus_mode = Control.FOCUS_NONE
	close_x.tooltip_text = "Kaydetmeden kapat (ESC)"
	close_x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_x.pressed.connect(_close_settings)
	head.add_child(close_x)
	box.add_child(HSeparator.new())

	# Harita
	_map_option = OptionButton.new()
	for m: Dictionary in NetworkManager.MAPS:
		_map_option.add_item(m["name"])
	_map_option.item_selected.connect(func(_i: int) -> void: _update_draft_ui())
	box.add_child(_setting_row("HARİTA", _map_option))

	# Takım boyutu: 2v2v2v2 … 5v5v5v5
	_size_option = OptionButton.new()
	for s in range(NetworkManager.TEAM_SIZE_MIN, NetworkManager.TEAM_SIZE_MAX + 1):
		_size_option.add_item("%s  (%d oyuncu)" % [NetworkManager.get_format_text(s), s * NetworkManager.TEAM_COUNT])
	_size_option.item_selected.connect(func(_i: int) -> void: _update_draft_ui())
	box.add_child(_setting_row("FORMAT", _size_option))

	# Şifre: mevcut durum + (host) yeni şifre yaz VEYA kaldır işaretle
	_pw_status = UITheme.label("", 13, UITheme.TEXT)
	box.add_child(_setting_row("ŞİFRE", _pw_status))
	_pw_row = HBoxContainer.new()
	_pw_row.add_theme_constant_override("separation", 6)
	box.add_child(_pw_row)
	_pw_input = LineEdit.new()
	_pw_input.placeholder_text = "Yeni şifre (boş = değiştirme)"
	_pw_input.secret = true
	_pw_input.max_length = 24
	_pw_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pw_input.text_changed.connect(func(t: String) -> void:
		if not t.strip_edges().is_empty():
			_pw_remove.set_pressed_no_signal(false)
		_update_draft_ui())
	_pw_input.text_submitted.connect(func(_t: String) -> void: _on_save_settings())
	_pw_row.add_child(_pw_input)
	_pw_remove = Button.new()
	_pw_remove.text = "Şifreyi kaldır"
	_pw_remove.toggle_mode = true
	_pw_remove.theme_type_variation = "GhostButton"
	_pw_remove.focus_mode = Control.FOCUS_NONE
	_pw_remove.toggled.connect(func(on: bool) -> void:
		if on:
			_pw_input.text = ""
		_update_draft_ui())
	_pw_row.add_child(_pw_remove)

	# Kaydedilecek değişikliklerin özeti
	_draft_note = UITheme.label("", 12, UITheme.TEXT_DIM)
	_draft_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_draft_note)

	# Alt butonlar: KAPAT (taslağı at) / KAYDET (uygula)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	footer.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(footer)
	var cancel := Button.new()
	cancel.text = "Kapat"
	cancel.theme_type_variation = "GhostButton"
	cancel.custom_minimum_size = Vector2(110, 42)
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(_close_settings)
	footer.add_child(cancel)
	_save_btn = Button.new()
	_save_btn.text = "KAYDET"
	_save_btn.theme_type_variation = "PrimaryButton"
	_save_btn.custom_minimum_size = Vector2(140, 42)
	_save_btn.focus_mode = Control.FOCUS_NONE
	_save_btn.pressed.connect(_on_save_settings)
	footer.add_child(_save_btn)
	return panel


func _setting_row(caption: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var cap := UITheme.label(caption, 10, UITheme.TEXT_DIM, UITheme.font_caps)
	cap.custom_minimum_size = Vector2(80, 0)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


## Pencere açılırken taslağı mevcut ayarlardan doldur
func _load_draft() -> void:
	var map_id: String = NetworkManager.get_map_info()["id"]
	for i in NetworkManager.MAPS.size():
		if NetworkManager.MAPS[i]["id"] == map_id:
			_map_option.select(i)
	_size_option.select(NetworkManager.get_team_size() - NetworkManager.TEAM_SIZE_MIN)
	_pw_input.text = ""
	_pw_remove.set_pressed_no_signal(false)
	var is_host := NetworkManager.is_host()
	_map_option.disabled = not is_host
	_size_option.disabled = not is_host
	_pw_row.visible = is_host
	_save_btn.visible = is_host
	_settings_hint.text = "Değişiklikler KAYDET'e basınca uygulanır" if is_host else "Sadece oda sahibi değiştirebilir"
	_update_draft_ui()


## Taslak ile mevcut ayar farkı → özet metni + KAYDET aktif/pasif
func _update_draft_ui() -> void:
	var has_pw: bool = NetworkManager.room_settings.get("has_password", false)
	_pw_status.text = "🔒  Şifreli" if has_pw else "Açık oda"
	_pw_status.add_theme_color_override("font_color", UITheme.ACCENT if has_pw else UITheme.TEXT_DIM)
	_pw_remove.disabled = not has_pw
	var changes: PackedStringArray = []
	var new_map: Dictionary = NetworkManager.MAPS[_map_option.selected]
	if new_map["id"] != NetworkManager.get_map_info()["id"]:
		changes.append("harita → %s" % new_map["name"])
	var new_size := NetworkManager.TEAM_SIZE_MIN + _size_option.selected
	if new_size != NetworkManager.get_team_size():
		changes.append("format → %s" % NetworkManager.get_format_text(new_size))
		var overflow := 0
		for tid in NetworkManager.TEAM_COUNT:
			overflow += maxi(NetworkManager.get_team_count(tid) - new_size, 0)
		if overflow > 0:
			changes.append("%d oyuncu takımından çıkar" % overflow)
	if not _pw_input.text.strip_edges().is_empty():
		changes.append("şifre değişecek" if has_pw else "şifre eklenecek")
	elif _pw_remove.button_pressed and has_pw:
		changes.append("şifre kaldırılacak")
	_save_btn.disabled = changes.is_empty()
	if not NetworkManager.is_host():
		_draft_note.text = ""
	elif changes.is_empty():
		_draft_note.text = "Değişiklik yok"
		_draft_note.add_theme_color_override("font_color", Color(UITheme.TEXT_DIM, 0.7))
	else:
		_draft_note.text = "Kaydedilince: " + ", ".join(changes)
		_draft_note.add_theme_color_override("font_color", UITheme.ACCENT)


## KAYDET: taslağı tek seferde uygula, pencereyi kapat
func _on_save_settings() -> void:
	if not NetworkManager.is_host() or _save_btn.disabled:
		return
	var new_map: String = NetworkManager.MAPS[_map_option.selected]["id"]
	if new_map != NetworkManager.get_map_info()["id"]:
		NetworkManager.set_map(new_map)
	var new_size := NetworkManager.TEAM_SIZE_MIN + _size_option.selected
	if new_size != NetworkManager.get_team_size():
		NetworkManager.set_team_size(new_size)
	var pw := _pw_input.text.strip_edges()
	if not pw.is_empty():
		NetworkManager.set_room_password(pw)
	elif _pw_remove.button_pressed:
		NetworkManager.set_room_password("")
	_close_settings()


func _on_settings_changed() -> void:
	_refresh_settings()
	_refresh_player_list()
	# Pencere açıkken ayarlar başka yerden değişirse (ör. host devri) farkı yeniden hesapla
	if _settings_modal and _settings_modal.visible:
		_update_draft_ui()


## Başlıktaki özet (pencere taslağına dokunmaz)
func _refresh_settings() -> void:
	if _settings_summary == null:
		return
	var has_pw: bool = NetworkManager.room_settings.get("has_password", false)
	_settings_summary.text = "%s  ·  %s%s" % [NetworkManager.get_format_text(), String(NetworkManager.get_map_info()["name"]).to_upper(),
		"  ·  🔒 ŞİFRELİ" if has_pw else ""]


# ─────────────────────────────────────────────
#  Satır / slot oluşturucular
# ─────────────────────────────────────────────

func _build_player_slot(peer_id: int, data: Dictionary, team_color: Color, is_me: bool) -> Control:
	var player_name: String = data.get("name", "???")
	var ready_flag: bool = data.get("is_ready", false)

	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(0, 30)
	var st := UITheme.style(Color(1, 1, 1, 0.04), 8, Color.TRANSPARENT, 0, 8, 3)
	if is_me:
		st.bg_color = Color(team_color, 0.14)
		st.border_color = Color(team_color, 0.55)
		st.set_border_width_all(1)
	slot.add_theme_stylebox_override("panel", st)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	slot.add_child(row)

	row.add_child(_avatar(player_name, team_color))

	var name_lbl := UITheme.label(player_name, 13, UITheme.TEXT, UITheme.font_bold if is_me else null)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.clip_text = true
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_lbl)

	if peer_id == 1:
		var host := UITheme.label("★", 12, UITheme.ACCENT)
		host.tooltip_text = "Oda sahibi"
		host.mouse_filter = Control.MOUSE_FILTER_PASS
		host.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(host)

	row.add_child(_ready_pill(ready_flag))
	return slot


func _build_empty_slot() -> Control:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(0, 30)
	slot.add_theme_stylebox_override("panel", UITheme.style(Color.TRANSPARENT, 8, Color(1, 1, 1, 0.06), 1, 12, 3))
	var lbl := UITheme.label("+   Boş slot", 12, Color(UITheme.TEXT_DIM, 0.55))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.add_child(lbl)
	return slot


func _avatar(player_name: String, color: Color) -> Control:
	var av := PanelContainer.new()
	av.custom_minimum_size = Vector2(24, 24)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av.add_theme_stylebox_override("panel", UITheme.style(Color(color, 0.85), 12))
	var initial := player_name.substr(0, 1).to_upper() if not player_name.is_empty() else "?"
	var lbl := UITheme.label(initial, 13, Color(0.05, 0.05, 0.08), UITheme.font_bold)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	av.add_child(lbl)
	return av


func _ready_pill(ready_flag: bool) -> Control:
	var pill := PanelContainer.new()
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col := UITheme.SUCCESS if ready_flag else UITheme.TEXT_DIM
	pill.add_theme_stylebox_override("panel", UITheme.style(Color(col, 0.14), 8, Color.TRANSPARENT, 0, 7, 2))
	pill.add_child(UITheme.label("HAZIR" if ready_flag else "BEKLİYOR", 9, col, UITheme.font_caps))
	return pill


# ─────────────────────────────────────────────
#  Girdi
# ─────────────────────────────────────────────

func _on_panel_input(event: InputEvent, team_id: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if team_id == _get_local_team() or _get_team_count(team_id) >= NetworkManager.get_team_size():
		return
	NetworkManager.request_change_team(team_id)


func _on_team_hover(team_id: int, entered: bool) -> void:
	if entered:
		_hovered_team = team_id
	elif _hovered_team == team_id:
		_hovered_team = -1
	_update_team_styles()


func _on_copy_code() -> void:
	DisplayServer.clipboard_set(RoomManager.room_code)
	_copy_btn.text = "Kopyalandı ✓"
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(_copy_btn):
		_copy_btn.text = "Kopyala"


func _on_ready_btn_pressed() -> void:
	NetworkManager.set_ready(not _is_local_ready())


func _on_start_btn_pressed() -> void:
	if NetworkManager.is_host():
		GameManager.start_game()


func _on_game_started() -> void:
	pass  # GameManager sahne geçişini halleder


func _on_host_migrated() -> void:
	_update_room_info()
	_refresh_settings()
	_refresh_player_list()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		# Ayarlar açıksa ESC sadece pencereyi kapatır
		if _settings_modal and _settings_modal.visible:
			_close_settings()
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	NetworkManager.disconnect_all()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


# ─────────────────────────────────────────────
#  Durum
# ─────────────────────────────────────────────

func _get_local_team() -> int:
	return NetworkManager.players.get(NetworkManager.get_local_id(), {}).get("team_id", -1)


func _is_local_ready() -> bool:
	return NetworkManager.players.get(NetworkManager.get_local_id(), {}).get("is_ready", false)


func _get_team_count(team_id: int) -> int:
	var n := 0
	for p: Dictionary in NetworkManager.players.values():
		if p.get("team_id", -1) == team_id:
			n += 1
	return n


func _update_room_info() -> void:
	_room_name_lbl.text = NetworkManager.room_name if not NetworkManager.room_name.is_empty() else "Oda"
	_room_code_lbl.text = RoomManager.room_code if not RoomManager.room_code.is_empty() else "-------"


func _refresh_player_list() -> void:
	if _teams.is_empty():
		return

	var local_id := NetworkManager.get_local_id()
	var local_team := _get_local_team()

	# Takımlara dağıt
	var per_team: Array = [[], [], [], []]
	var unassigned: Array = []
	var ready_count := 0
	for pid: int in NetworkManager.players:
		var data: Dictionary = NetworkManager.players[pid]
		var tid: int = data.get("team_id", -1)
		if data.get("is_ready", false):
			ready_count += 1
		if tid < 0 or tid >= 4:
			unassigned.append(pid)
		else:
			(per_team[tid] as Array).append(pid)

	# Takım kartları
	for i in range(4):
		var t: Dictionary = _teams[i]
		var slots: VBoxContainer = t["slots"]
		for child in slots.get_children():
			child.queue_free()
		var members: Array = per_team[i]
		var color := TeamManager.get_color(i)
		for pid: int in members:
			slots.add_child(_build_player_slot(pid, NetworkManager.players[pid], color, pid == local_id))
		for _k in range(maxi(NetworkManager.get_team_size() - members.size(), 0)):
			slots.add_child(_build_empty_slot())
		(t["count_lbl"] as Label).text = "%d/%d" % [members.size(), NetworkManager.get_team_size()]
		_ignore_mouse_recursive(slots)

	# Takım seçmeyenler
	for child in _unassigned_row.get_children():
		child.queue_free()
	if unassigned.is_empty():
		_unassigned_row.add_child(UITheme.label("Herkes bir takımda", 12, Color(UITheme.TEXT_DIM, 0.7)))
	for pid: int in unassigned:
		var data: Dictionary = NetworkManager.players[pid]
		var chip := PanelContainer.new()
		var is_me: bool = pid == local_id
		chip.add_theme_stylebox_override("panel", UITheme.style(Color(1, 1, 1, 0.05), 12,
			Color(UITheme.ACCENT, 0.5) if is_me else Color.TRANSPARENT, 1 if is_me else 0, 10, 3))
		var label_text: String = data.get("name", "???")
		if is_me:
			label_text += "  (Sen)"
		chip.add_child(UITheme.label(label_text, 12, UITheme.TEXT if is_me else UITheme.TEXT_DIM))
		_unassigned_row.add_child(chip)

	# Kontrol listesi
	var total := NetworkManager.players.size()
	var balanced := NetworkManager._are_teams_balanced()
	_set_check(_check_balance, balanced, "Takımlar dengeli", "En az 2 takımda eşit oyuncu gerekli")
	_set_check(_check_ready, ready_count == total and total > 0,
		"Herkes hazır  (%d/%d)" % [ready_count, total], "Hazır olanlar  %d/%d" % [ready_count, total])
	_player_count_lbl.text = "%d / %d" % [total, NetworkManager.get_max_players()]

	# Butonlar
	var is_host := NetworkManager.is_host()
	_start_btn.visible = is_host
	_host_hint.visible = not is_host
	_start_btn.disabled = not (balanced and ready_count == total)
	_style_ready_button(_is_local_ready(), local_team)

	# El feneri ışığı kendi takımının rengine döner
	_light_color = TeamManager.get_color(local_team).lerp(UITheme.ACCENT, 0.35) if local_team >= 0 else UITheme.ACCENT
	_update_team_styles()


func _set_check(lbl: Label, ok: bool, ok_text: String, fail_text: String) -> void:
	lbl.text = ("✓  " + ok_text) if ok else ("•  " + fail_text)
	lbl.add_theme_color_override("font_color", UITheme.SUCCESS if ok else UITheme.TEXT_DIM)


func _style_ready_button(ready_flag: bool, local_team: int) -> void:
	if ready_flag:
		_ready_btn.text = "HAZIRSIN ✓"
		_ready_btn.tooltip_text = "Tıkla: hazır durumunu iptal et"
		_ready_btn.theme_type_variation = ""
		var g := UITheme.SUCCESS
		_ready_btn.add_theme_stylebox_override("normal", UITheme.style(Color(g, 0.16), UITheme.RADIUS, Color(g, 0.7), 1))
		_ready_btn.add_theme_stylebox_override("hover", UITheme.style(Color(g, 0.24), UITheme.RADIUS, g, 1))
		_ready_btn.add_theme_stylebox_override("pressed", UITheme.style(Color(g, 0.1), UITheme.RADIUS, g, 1))
		for key: String in ["font_color", "font_hover_color", "font_pressed_color"]:
			_ready_btn.add_theme_color_override(key, g)
	else:
		_ready_btn.text = "HAZIRIM"
		_ready_btn.tooltip_text = "" if local_team >= 0 else "Önce bir takım seçmen önerilir"
		for key: String in ["normal", "hover", "pressed"]:
			_ready_btn.remove_theme_stylebox_override(key)
		for key: String in ["font_color", "font_hover_color", "font_pressed_color"]:
			_ready_btn.remove_theme_color_override(key)
		# Host'ta ana vurgu "Başlat"ta olsun, client'ta "Hazırım"da
		_ready_btn.theme_type_variation = "" if NetworkManager.is_host() else "PrimaryButton"


func _update_team_styles() -> void:
	var local_team := _get_local_team()
	for i in range(_teams.size()):
		var t: Dictionary = _teams[i]
		var color := TeamManager.get_color(i)
		var is_mine := i == local_team
		var is_full := _get_team_count(i) >= NetworkManager.get_team_size()
		var is_hover := i == _hovered_team and not is_mine and not is_full

		var ps := UITheme.style(UITheme.SURFACE_2 if is_hover else UITheme.SURFACE, 14, UITheme.BORDER, 1)
		if is_mine:
			ps.border_color = color
			ps.set_border_width_all(2)
			ps.shadow_color = Color(color, 0.3)
			ps.shadow_size = 16
		elif is_hover:
			ps.border_color = Color(color, 0.5)
		ps.set_content_margin_all(2)
		var panel: PanelContainer = t["panel"]
		panel.add_theme_stylebox_override("panel", ps)
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not (is_mine or is_full) else Control.CURSOR_ARROW

		var fs := UITheme.style(Color(1, 1, 1, 0.025), 0)
		fs.corner_radius_bottom_left = 12
		fs.corner_radius_bottom_right = 12
		var footer_lbl: Label = t["footer_lbl"]
		if is_mine:
			fs.bg_color = color
			footer_lbl.text = "✓  TAKIMIN"
			footer_lbl.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))
		elif is_full:
			footer_lbl.text = "DOLU"
			footer_lbl.add_theme_color_override("font_color", Color(UITheme.TEXT_DIM, 0.6))
		else:
			if is_hover:
				fs.bg_color = Color(color, 0.18)
			footer_lbl.text = "KATIL"
			footer_lbl.add_theme_color_override("font_color", color if is_hover else UITheme.TEXT_DIM)
		(t["footer"] as PanelContainer).add_theme_stylebox_override("panel", fs)


func _ignore_mouse_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse_recursive(child)

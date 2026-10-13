## HUD.gd
## Oyun içi ekran. UI tamamen kodla kurulur (tscn sadece CanvasLayer), görünüm UITheme paletinden gelir.
##   Sol üst   : takım skorları (kill)            Üst orta : hedef (kart) durumu + uyarı bandı
##   Sağ üst   : kill feed                         Sağ alt  : minimap (Minimap.gd)
##   Sol alt   : oyuncu kartı (karakter, can, mermi + şarjör ilerlemesi)
##   Katmanlar : düşük can vinyeti, ölüm/yeniden doğuş, TAB skor tablosu, ESC menü, oyun sonu.
## Oyun mantığına dokunmaz — sadece GameManager/TeamManager/Player sinyallerini dinler.

extends CanvasLayer

const KILL_FEED_MAX := 5
const RESPAWN_TIME := 3.0  # GameManager._schedule_respawn ile aynı

var _root: Control
var _local_player: Node = null
var _carrier_peer := -1

# Skor
var _score_rows: Array[Dictionary] = []  # {panel, value}

# Hedef + uyarı
var _objective_chip: PanelContainer
var _objective_lbl: Label
var _alert_chip: PanelContainer
var _alert_lbl: Label
var _banner_tween: Tween = null

# Kill feed
var _kill_feed_root: VBoxContainer

# Oyuncu kartı
var _char_lbl: Label
var _team_chip_lbl: Label
var _hp_value: Label
var _hp_max: Label
var _health_bar: ProgressBar
var _hp_fill: StyleBoxFlat
var _ammo_value: Label
var _ammo_max: Label
var _ammo_bar: ProgressBar
var _ammo_fill: StyleBoxFlat
var _ammo_caption: Label
var _reload_tween: Tween = null
var _last_health := -1.0

# Katmanlar
var _vignette: TextureRect
var _hit_flash := 0.0
var _death_overlay: Control
var _death_count: Label
var _death_killer: Label
var _death_time := 0.0
var _scoreboard_panel: PanelContainer
var _scoreboard_content: VBoxContainer
var _scoreboard_visible := false
var _pause_panel: Control
var _end_overlay: Control
var _end_title: Label
var _end_sub: Label
var _end_stats: Label


func _ready() -> void:
	UITheme.apply(get_tree())
	TeamManager.score_updated.connect(_on_score_updated)
	GameManager.game_ended.connect(_on_game_ended)
	GameManager.card_picked_up.connect(_on_card_picked_up)
	GameManager.card_dropped.connect(_on_card_dropped)
	GameManager.kill_happened.connect(_on_kill_happened)
	GameManager.local_player_spawned.connect(_on_local_player_spawned)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_setup_vignette()
	_setup_scores()
	_setup_objective()
	_setup_kill_feed()
	_setup_player_card()
	_setup_minimap()
	_setup_death_overlay()
	_setup_scoreboard()
	_setup_pause_menu()
	_setup_end_overlay()

	_carrier_peer = GameManager.card_carrier_peer_id
	_refresh_scores()
	_update_objective()


func _process(delta: float) -> void:
	# TAB skor tablosu
	var tab := Input.is_key_pressed(KEY_TAB) and not _pause_panel.visible and not _end_overlay.visible
	if tab != _scoreboard_visible:
		_scoreboard_visible = tab
		_scoreboard_panel.visible = tab
		if tab:
			_refresh_scoreboard()

	# Hasar flaşı + düşük can vinyeti
	_hit_flash = maxf(_hit_flash - delta * 2.5, 0.0)
	var low := 0.0
	if _local_player and is_instance_valid(_local_player) and not _local_player.is_dead:
		var ratio: float = _local_player.health / maxf(_local_player.max_health, 1.0)
		if ratio < 0.35:
			low = (0.35 - ratio) / 0.35 * (0.75 + 0.25 * sin(Time.get_ticks_msec() / 180.0))
	_vignette.modulate.a = clampf(maxf(low, _hit_flash), 0.0, 1.0)

	# Ölüm ekranı + geri sayım
	var dead: bool = _local_player != null and is_instance_valid(_local_player) and _local_player.is_dead
	if dead and not _death_overlay.visible and not _end_overlay.visible:
		_death_overlay.visible = true
		_death_time = RESPAWN_TIME
	elif not dead and _death_overlay.visible:
		_death_overlay.visible = false
	if _death_overlay.visible:
		_death_time = maxf(_death_time - delta, 0.0)
		_death_count.text = "%d" % ceili(_death_time) if _death_time > 0.0 else "…"

	# Kart sendeyse hedef çipi nabız atar
	if _carrier_peer == NetworkManager.get_local_id() and _carrier_peer != -1:
		_objective_chip.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 150.0)
	else:
		_objective_chip.modulate.a = 1.0


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		# Oyun bitmişse ESC menüsü açılmasın
		if _end_overlay.visible:
			return
		_toggle_pause_menu()
		get_viewport().set_input_as_handled()


# ─────────────────────────────────────────────
#  Kurulum
# ─────────────────────────────────────────────

func _setup_vignette() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(UITheme.DANGER, 0.0))
	grad.set_color(1, Color(UITheme.DANGER, 0.55))
	grad.add_point(0.55, Color(UITheme.DANGER, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	_vignette = TextureRect.new()
	_vignette.texture = tex
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_root.add_child(_vignette)


func _setup_scores() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(200, 0)
	panel.add_theme_stylebox_override("panel", UITheme.style(Color(UITheme.BG, 0.78), 12, UITheme.BORDER, 1, 12, 10))
	_root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	box.add_child(UITheme.label("TAKIM SKORU", 10, UITheme.TEXT_DIM, UITheme.font_caps))

	for i in range(4):
		var color := TeamManager.get_color(i)
		var row_panel := PanelContainer.new()
		row_panel.add_theme_stylebox_override("panel", UITheme.style(Color.TRANSPARENT, 6, Color.TRANSPARENT, 0, 6, 2))
		box.add_child(row_panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row_panel.add_child(row)
		var strip := ColorRect.new()
		strip.color = color
		strip.custom_minimum_size = Vector2(3, 16)
		strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(strip)
		var name_lbl := UITheme.label(TeamManager.get_team_name(i).to_upper(), 12, color, UITheme.font_caps)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var value := UITheme.label("0", 15, UITheme.TEXT, UITheme.font_bold)
		row.add_child(value)
		_score_rows.append({"panel": row_panel, "value": value})
	_ignore_mouse_recursive(panel)


func _setup_objective() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_TOP)
	col.offset_left = -260
	col.offset_right = 260
	col.offset_top = 16
	col.offset_bottom = 16
	col.add_theme_constant_override("separation", 10)
	_root.add_child(col)

	var wrap := CenterContainer.new()
	col.add_child(wrap)
	_objective_chip = PanelContainer.new()
	wrap.add_child(_objective_chip)
	_objective_lbl = UITheme.label("", 13, UITheme.ACCENT, UITheme.font_caps)
	_objective_chip.add_child(_objective_lbl)

	var alert_wrap := CenterContainer.new()
	col.add_child(alert_wrap)
	_alert_chip = PanelContainer.new()
	_alert_chip.modulate.a = 0.0
	alert_wrap.add_child(_alert_chip)
	_alert_lbl = UITheme.label("", 17, UITheme.TEXT, UITheme.font_bold)
	_alert_chip.add_child(_alert_lbl)
	_ignore_mouse_recursive(col)


func _setup_kill_feed() -> void:
	_kill_feed_root = VBoxContainer.new()
	_kill_feed_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_kill_feed_root.offset_left = -340
	_kill_feed_root.offset_right = -16
	_kill_feed_root.offset_top = 16
	_kill_feed_root.add_theme_constant_override("separation", 6)
	_kill_feed_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_kill_feed_root)


func _setup_player_card() -> void:
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	card.offset_left = 16
	card.offset_top = -16
	card.offset_bottom = -16
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.custom_minimum_size = Vector2(340, 0)
	card.add_theme_stylebox_override("panel", UITheme.style(Color(UITheme.BG, 0.8), 14, UITheme.BORDER, 1, 16, 12))
	_root.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)

	# Üst satır: karakter + takım
	var top := HBoxContainer.new()
	box.add_child(top)
	_char_lbl = UITheme.label("—", 14, UITheme.TEXT, UITheme.font_caps)
	_char_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_char_lbl)
	_team_chip_lbl = UITheme.label("", 10, UITheme.TEXT_DIM, UITheme.font_caps)
	top.add_child(_team_chip_lbl)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 18)
	box.add_child(stats)

	# Can
	var hp_box := VBoxContainer.new()
	hp_box.add_theme_constant_override("separation", 4)
	hp_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(hp_box)
	hp_box.add_child(UITheme.label("CAN", 10, UITheme.TEXT_DIM, UITheme.font_caps))
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 4)
	hp_box.add_child(hp_row)
	_hp_value = UITheme.label("100", 30, UITheme.TEXT, UITheme.font_title)
	hp_row.add_child(_hp_value)
	_hp_max = UITheme.label("/100", 13, UITheme.TEXT_DIM)
	_hp_max.size_flags_vertical = Control.SIZE_SHRINK_END
	hp_row.add_child(_hp_max)
	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.custom_minimum_size = Vector2(0, 6)
	_health_bar.max_value = 100.0
	_health_bar.value = 100.0
	_hp_fill = UITheme.style(UITheme.SUCCESS, 3)
	_health_bar.add_theme_stylebox_override("fill", _hp_fill)
	_health_bar.add_theme_stylebox_override("background", UITheme.style(Color(1, 1, 1, 0.07), 3))
	hp_box.add_child(_health_bar)

	stats.add_child(VSeparator.new())

	# Mermi
	var ammo_box := VBoxContainer.new()
	ammo_box.add_theme_constant_override("separation", 4)
	ammo_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(ammo_box)
	_ammo_caption = UITheme.label("MERMİ", 10, UITheme.TEXT_DIM, UITheme.font_caps)
	ammo_box.add_child(_ammo_caption)
	var ammo_row := HBoxContainer.new()
	ammo_row.add_theme_constant_override("separation", 4)
	ammo_box.add_child(ammo_row)
	_ammo_value = UITheme.label("30", 30, UITheme.TEXT, UITheme.font_title)
	ammo_row.add_child(_ammo_value)
	_ammo_max = UITheme.label("/30", 13, UITheme.TEXT_DIM)
	_ammo_max.size_flags_vertical = Control.SIZE_SHRINK_END
	ammo_row.add_child(_ammo_max)
	_ammo_bar = ProgressBar.new()
	_ammo_bar.show_percentage = false
	_ammo_bar.custom_minimum_size = Vector2(0, 6)
	_ammo_bar.max_value = 1.0
	_ammo_bar.value = 1.0
	_ammo_fill = UITheme.style(UITheme.ACCENT, 3)
	_ammo_bar.add_theme_stylebox_override("fill", _ammo_fill)
	_ammo_bar.add_theme_stylebox_override("background", UITheme.style(Color(1, 1, 1, 0.07), 3))
	ammo_box.add_child(_ammo_bar)

	_ignore_mouse_recursive(card)


func _setup_minimap() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_left = -196
	box.offset_top = -216
	box.offset_right = -16
	box.offset_bottom = -16
	box.add_theme_constant_override("separation", 4)
	_root.add_child(box)
	var cap := UITheme.label("TAKTİK HARİTA", 10, UITheme.TEXT_DIM, UITheme.font_caps)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(cap)
	var minimap := Control.new()
	minimap.set_script(load("res://scenes/ui/Minimap.gd"))
	box.add_child(minimap)
	_ignore_mouse_recursive(box)


func _setup_death_overlay() -> void:
	_death_overlay = ColorRect.new()
	(_death_overlay as ColorRect).color = Color(0.04, 0.0, 0.01, 0.55)
	_death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.visible = false
	_root.add_child(_death_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	center.add_child(box)
	var t := UITheme.label("ETKİSİZ HALE GETİRİLDİN", 14, UITheme.DANGER, UITheme.font_caps)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	_death_count = UITheme.label("3", 72, UITheme.TEXT, UITheme.font_title)
	_death_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_death_count)
	var sub := UITheme.label("YENİDEN DOĞUŞ", 11, UITheme.TEXT_DIM, UITheme.font_caps)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	_death_killer = UITheme.label("", 13, UITheme.TEXT_DIM)
	_death_killer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_death_killer)
	_ignore_mouse_recursive(_death_overlay)


func _setup_scoreboard() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_scoreboard_panel = PanelContainer.new()
	_scoreboard_panel.custom_minimum_size = Vector2(620, 0)
	var st := UITheme.style(Color(UITheme.SURFACE, 0.96), 16, UITheme.BORDER, 1, 22, 18)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 24
	_scoreboard_panel.add_theme_stylebox_override("panel", st)
	_scoreboard_panel.visible = false
	center.add_child(_scoreboard_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_scoreboard_panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := UITheme.label("SKOR TABLOSU", 20, UITheme.TEXT, UITheme.font_title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UITheme.label("TAB", 10, UITheme.TEXT_DIM, UITheme.font_caps))
	box.add_child(_score_columns_row("OYUNCU", "KARAKTER", "K", "Ö", UITheme.TEXT_DIM, UITheme.font_caps, 10))

	_scoreboard_content = VBoxContainer.new()
	_scoreboard_content.add_theme_constant_override("separation", 10)
	box.add_child(_scoreboard_content)
	_ignore_mouse_recursive(center)


func _setup_pause_menu() -> void:
	_pause_panel = ColorRect.new()
	(_pause_panel as ColorRect).color = Color(0, 0, 0, 0.6)
	_pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_panel.visible = false
	_root.add_child(_pause_panel)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_panel.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(320, 0)
	var st := UITheme.style(UITheme.SURFACE_2, 16, Color(UITheme.ACCENT, 0.25), 1, 26, 24)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 30
	card.add_theme_stylebox_override("panel", st)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	box.add_child(UITheme.label("DURAKLATILDI", 11, UITheme.ACCENT, UITheme.font_caps))
	box.add_child(UITheme.label("MENÜ", 26, UITheme.TEXT, UITheme.font_title))
	var hint := UITheme.label("Oyun arka planda devam ediyor.", 12, UITheme.TEXT_DIM)
	box.add_child(hint)
	box.add_child(_vspace(6))

	var resume := _menu_button("DEVAM ET", "PrimaryButton")
	resume.pressed.connect(_toggle_pause_menu)
	box.add_child(resume)
	var leave := _menu_button("ANA MENÜYE DÖN", "")
	leave.pressed.connect(_on_leave_pressed)
	box.add_child(leave)
	var quit := _menu_button("OYUNU KAPAT", "GhostButton")
	quit.add_theme_color_override("font_color", UITheme.DANGER)
	quit.add_theme_color_override("font_hover_color", UITheme.DANGER.lightened(0.2))
	quit.pressed.connect(get_tree().quit)
	box.add_child(quit)


func _setup_end_overlay() -> void:
	_end_overlay = ColorRect.new()
	(_end_overlay as ColorRect).color = Color(0, 0, 0, 0.72)
	_end_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_end_overlay.visible = false
	_root.add_child(_end_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	center.add_child(box)

	var cap := UITheme.label("OYUN BİTTİ", 12, UITheme.TEXT_DIM, UITheme.font_caps)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap)
	_end_title = UITheme.label("ZAFER", 84, UITheme.ACCENT, UITheme.font_title)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_title)
	_end_sub = UITheme.label("", 18, UITheme.TEXT, UITheme.font_bold)
	_end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_sub)
	_end_stats = UITheme.label("", 13, UITheme.TEXT_DIM, UITheme.font_caps)
	_end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_stats)
	box.add_child(_vspace(18))

	var btn_wrap := CenterContainer.new()
	box.add_child(btn_wrap)
	var back := _menu_button("ANA MENÜYE DÖN", "PrimaryButton")
	back.custom_minimum_size = Vector2(260, 50)
	back.pressed.connect(_on_back_btn_pressed)
	btn_wrap.add_child(back)


# ─────────────────────────────────────────────
#  Yardımcılar
# ─────────────────────────────────────────────

func _menu_button(text: String, variation: String) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(0, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func _vspace(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _score_columns_row(a: String, b: String, c: String, d: String, color: Color, font: Font, font_size: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var widths := [0.0, 130.0, 50.0, 50.0]
	var texts := [a, b, c, d]
	for i in range(4):
		var lbl := UITheme.label(texts[i], font_size, color, font)
		if i == 0:
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		else:
			lbl.custom_minimum_size = Vector2(widths[i], 0)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if i > 1 else HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(lbl)
	return row


func _get_local_team() -> int:
	return NetworkManager.players.get(NetworkManager.get_local_id(), {}).get("team_id", -1)


func _ignore_mouse_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse_recursive(child)


# ─────────────────────────────────────────────
#  Oyuncu kartı
# ─────────────────────────────────────────────

func _on_local_player_spawned(player: Node) -> void:
	_local_player = player
	player.health_changed.connect(_on_health_changed)
	player.ammo_changed.connect(_on_ammo_changed)
	_health_bar.max_value = player.max_health
	_hp_max.text = "/%d" % int(player.max_health)
	_last_health = player.health
	_on_health_changed(player.health)

	var team_id: int = player.team_id
	_char_lbl.text = String(player.character_type).to_upper()
	_char_lbl.add_theme_color_override("font_color", TeamManager.get_color(team_id))
	_team_chip_lbl.text = "%s TAKIM" % TeamManager.get_team_name(team_id).to_upper()
	_refresh_scores()
	_update_objective()

	# Başlangıç ammo göstergesini karakter silahına göre ayarla
	if player.current_weapon:
		_on_ammo_changed(player.current_weapon.current_ammo, player.current_weapon.max_ammo, false)


func _on_health_changed(new_health: float) -> void:
	if _last_health >= 0.0 and new_health < _last_health:
		_hit_flash = 0.6
	_last_health = new_health
	_health_bar.value = new_health
	_hp_value.text = "%d" % int(new_health)
	var t := new_health / maxf(_health_bar.max_value, 1.0)
	var col := UITheme.SUCCESS if t > 0.6 else (UITheme.ACCENT if t > 0.3 else UITheme.DANGER)
	_hp_fill.bg_color = col
	_hp_value.add_theme_color_override("font_color", UITheme.TEXT if t > 0.3 else UITheme.DANGER)


func _on_ammo_changed(current: int, total: int, reloading: bool) -> void:
	if _reload_tween and _reload_tween.is_valid():
		_reload_tween.kill()
	_ammo_max.text = "/%d" % total
	if reloading:
		_ammo_caption.text = "ŞARJÖR DEĞİŞİYOR"
		_ammo_caption.add_theme_color_override("font_color", UITheme.ACCENT)
		_ammo_value.text = "—"
		_ammo_value.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		_ammo_fill.bg_color = Color(UITheme.ACCENT, 0.6)
		_ammo_bar.value = 0.0
		var reload_time := 1.5
		if _local_player and is_instance_valid(_local_player) and _local_player.current_weapon:
			reload_time = _local_player.current_weapon.reload_time
		_reload_tween = create_tween()
		_reload_tween.tween_property(_ammo_bar, "value", 1.0, reload_time)
		return
	_ammo_caption.text = "MERMİ"
	_ammo_caption.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_ammo_value.text = "%d" % current
	var ratio := float(current) / float(maxi(total, 1))
	_ammo_bar.value = ratio
	var low := current <= maxi(1, int(total * 0.2)) and total > 1
	var empty := current <= 0
	_ammo_value.add_theme_color_override("font_color", UITheme.DANGER if empty else (UITheme.ACCENT if low else UITheme.TEXT))
	_ammo_fill.bg_color = UITheme.DANGER if empty or low else UITheme.ACCENT


# ─────────────────────────────────────────────
#  Skor + skor tablosu
# ─────────────────────────────────────────────

func _refresh_scores() -> void:
	var local_team := _get_local_team()
	for i in range(_score_rows.size()):
		var r: Dictionary = _score_rows[i]
		(r["value"] as Label).text = str(TeamManager.scores.get(i, 0))
		var bg := Color(TeamManager.get_color(i), 0.14) if i == local_team else Color.TRANSPARENT
		(r["panel"] as PanelContainer).add_theme_stylebox_override("panel", UITheme.style(bg, 6, Color.TRANSPARENT, 0, 6, 2))


func _on_score_updated(_team_id: int, _score: int) -> void:
	_refresh_scores()


func _refresh_scoreboard() -> void:
	for child in _scoreboard_content.get_children():
		child.queue_free()

	var local_id := NetworkManager.get_local_id()
	var local_team := _get_local_team()

	# Oyuncuları takımlara göre grupla
	var teams: Dictionary = {}  # team_id -> Array[int]
	for pid in NetworkManager.players:
		var tid: int = NetworkManager.players[pid].get("team_id", -1)
		if tid < 0:
			continue
		if not teams.has(tid):
			teams[tid] = []
		teams[tid].append(int(pid))

	# Takımları kill skoruna göre sırala (yüksekten düşüğe)
	var team_ids: Array = teams.keys()
	team_ids.sort_custom(func(a: int, b: int) -> bool:
		return TeamManager.scores.get(a, 0) > TeamManager.scores.get(b, 0)
	)

	for tid: int in team_ids:
		var team_color: Color = TeamManager.get_color(tid)
		var team_peers: Array = teams[tid]
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", 3)
		_scoreboard_content.add_child(group)

		# Takım başlığı
		var header := PanelContainer.new()
		var hs := UITheme.style(Color(team_color, 0.14), 8, Color.TRANSPARENT, 0, 10, 6)
		hs.border_width_left = 3
		hs.border_color = team_color
		header.add_theme_stylebox_override("panel", hs)
		group.add_child(header)
		var hrow := HBoxContainer.new()
		header.add_child(hrow)
		var tname := UITheme.label(TeamManager.get_team_name(tid).to_upper(), 13, team_color, UITheme.font_caps)
		tname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hrow.add_child(tname)
		hrow.add_child(UITheme.label("%d KILL" % TeamManager.scores.get(tid, 0), 12, UITheme.TEXT, UITheme.font_caps))

		# Oyuncuları kill'e göre sırala
		team_peers.sort_custom(func(a: int, b: int) -> bool:
			var ka: int = GameManager.player_stats.get(a, {"kills": 0})["kills"]
			var kb: int = GameManager.player_stats.get(b, {"kills": 0})["kills"]
			return ka > kb
		)

		for pid: int in team_peers:
			var data: Dictionary = NetworkManager.players[pid]
			var stats: Dictionary = GameManager.player_stats.get(pid, {"kills": 0, "deaths": 0})
			var is_me: bool = pid == local_id
			var player_name: String = data.get("name", "???")
			# Kart taşıyıcısı sadece kendi takımında gösterilir
			if pid == _carrier_peer and tid == local_team:
				player_name = "◆ " + player_name
			if is_me:
				player_name += "  (Sen)"
			var row_panel := PanelContainer.new()
			row_panel.add_theme_stylebox_override("panel",
				UITheme.style(Color(1, 1, 1, 0.05) if is_me else Color.TRANSPARENT, 6, Color.TRANSPARENT, 0, 10, 4))
			row_panel.add_child(_score_columns_row(player_name, String(data.get("character", "—")),
				str(stats.get("kills", 0)), str(stats.get("deaths", 0)),
				UITheme.TEXT if is_me else Color(UITheme.TEXT, 0.85), UITheme.font_bold if is_me else null, 13))
			group.add_child(row_panel)
	_ignore_mouse_recursive(_scoreboard_content)


# ─────────────────────────────────────────────
#  Kart / hedef + uyarı bandı
# ─────────────────────────────────────────────

func _update_objective() -> void:
	var local_id := NetworkManager.get_local_id()
	var local_team := _get_local_team()
	var text := ""
	var col := UITheme.ACCENT
	if _carrier_peer == -1:
		text = "◆  KART YERDE  ·  BUL VE AL"
	elif _carrier_peer == local_id:
		text = "◆  KART SENDE  ·  KAPIYA GÖTÜR!"
		col = UITheme.SUCCESS
	else:
		var tid: int = NetworkManager.players.get(_carrier_peer, {}).get("team_id", -1)
		if tid == local_team:
			text = "◆  KART TAKIMINDA  ·  TAŞIYICIYI KORU"
			col = TeamManager.get_color(tid)
		else:
			text = "◆  KART %s TAKIMINDA  ·  DURDUR!" % TeamManager.get_team_name(tid).to_upper()
			col = TeamManager.get_color(tid)
	_objective_lbl.text = text
	_objective_lbl.add_theme_color_override("font_color", col)
	_objective_chip.add_theme_stylebox_override("panel", UITheme.style(Color(UITheme.BG, 0.8), 18, Color(col, 0.5), 1, 18, 7))


func _show_banner(text: String, color: Color) -> void:
	_alert_lbl.text = text
	_alert_lbl.add_theme_color_override("font_color", color)
	var st := UITheme.style(Color(UITheme.BG, 0.85), 10, Color(color, 0.7), 1, 22, 10)
	st.shadow_color = Color(color, 0.25)
	st.shadow_size = 16
	_alert_chip.add_theme_stylebox_override("panel", st)

	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	# Not: container içinde olduğu için scale animasyonu kullanılamaz (container sıralarken sıfırlar)
	_alert_chip.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(_alert_chip, "modulate:a", 1.0, 0.18)
	_banner_tween.tween_interval(2.5)
	_banner_tween.tween_property(_alert_chip, "modulate:a", 0.0, 0.5)


func _on_card_picked_up(carrier_peer_id: int, _carrier_pos: Vector3, carrier_team_id: int) -> void:
	_carrier_peer = carrier_peer_id
	_update_objective()
	var team_name := TeamManager.get_team_name(carrier_team_id).to_upper()
	if carrier_peer_id == NetworkManager.get_local_id():
		_show_banner("KARTI ALDIN!  KAPIYA KOŞ", UITheme.SUCCESS)
	else:
		_show_banner("⚠  %s TAKIM KARTI ALDI!" % team_name, TeamManager.get_color(carrier_team_id))


func _on_card_dropped(_drop_pos: Vector3, carrier_team_id: int) -> void:
	_carrier_peer = -1
	_update_objective()
	var team_name := TeamManager.get_team_name(carrier_team_id).to_upper()
	_show_banner("◆  %s TAKIM KARTI DÜŞÜRDÜ!" % team_name, TeamManager.get_color(carrier_team_id))


# ─────────────────────────────────────────────
#  Kill feed
# ─────────────────────────────────────────────

func _on_kill_happened(killer_peer_id: int, victim_peer_id: int) -> void:
	# Maksimum KILL_FEED_MAX satır — en eskiyi sil
	if _kill_feed_root.get_child_count() >= KILL_FEED_MAX:
		_kill_feed_root.get_child(0).queue_free()

	var local_id := NetworkManager.get_local_id()
	var kd: Dictionary = NetworkManager.players.get(killer_peer_id, {})
	var vd: Dictionary = NetworkManager.players.get(victim_peer_id, {})
	var kname: String = kd.get("name", "???")
	var vname: String = vd.get("name", "???")
	var kcol: Color = TeamManager.get_color(kd.get("team_id", -1))
	var vcol: Color = TeamManager.get_color(vd.get("team_id", -1))

	var border := Color.TRANSPARENT
	if killer_peer_id == local_id:
		border = Color(UITheme.ACCENT, 0.8)
	elif victim_peer_id == local_id:
		border = Color(UITheme.DANGER, 0.8)
		_death_killer.text = "Seni vuran: %s" % kname

	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_theme_stylebox_override("panel", UITheme.style(Color(UITheme.BG, 0.78), 8, border, 1, 12, 5))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	h.add_child(UITheme.label(kname, 13, kcol, UITheme.font_bold))
	h.add_child(UITheme.label("▸", 12, UITheme.TEXT_DIM))
	h.add_child(UITheme.label(vname, 13, vcol, UITheme.font_bold))
	_ignore_mouse_recursive(row)
	_kill_feed_root.add_child(row)

	row.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(row, "modulate:a", 1.0, 0.15)
	tw.tween_interval(4.0)
	tw.tween_property(row, "modulate:a", 0.0, 0.6)
	tw.tween_callback(row.queue_free)

	if _scoreboard_visible:
		_refresh_scoreboard()


# ─────────────────────────────────────────────
#  Menü / oyun sonu
# ─────────────────────────────────────────────

func _toggle_pause_menu() -> void:
	_pause_panel.visible = not _pause_panel.visible


func _on_leave_pressed() -> void:
	_pause_panel.hide()
	GameManager.return_to_menu()


func _on_game_ended(winning_team: int) -> void:
	_pause_panel.hide()
	_scoreboard_panel.hide()
	_death_overlay.hide()
	var won := winning_team == _get_local_team()
	var team_color := TeamManager.get_color(winning_team)
	_end_title.text = "ZAFER" if won else "YENİLGİ"
	_end_title.add_theme_color_override("font_color", team_color if won else UITheme.DANGER)
	_end_sub.text = "%s TAKIMI KAZANDI" % TeamManager.get_team_name(winning_team).to_upper()
	_end_sub.add_theme_color_override("font_color", team_color)
	var stats: Dictionary = GameManager.player_stats.get(NetworkManager.get_local_id(), {"kills": 0, "deaths": 0})
	_end_stats.text = "%d KILL   ·   %d ÖLÜM" % [stats.get("kills", 0), stats.get("deaths", 0)]
	_end_overlay.modulate.a = 0.0
	_end_overlay.show()
	create_tween().tween_property(_end_overlay, "modulate:a", 1.0, 0.4)


func _on_back_btn_pressed() -> void:
	GameManager.return_to_menu()

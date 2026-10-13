## MainMenu.gd
## Giriş ekranı: solda oyun kimliği + oyuncu adı, sağda sekmeli panel
## (Odalar / Oda Kur / Kod ile Katıl) ve şifreli odalar için modal.
## UI tamamen kodla kurulur; görünüm UITheme autoload'undaki temadan gelir.
## Arka plan MenuBackdrop.gdshader: fareyi takip eden el feneri + taktik ızgara.

extends Control

const SETTINGS_PATH := "user://settings.cfg"
const NAME_MAX_LEN := 16
const CALLSIGNS: Array[String] = ["Kurt", "Gölge", "Baykuş", "Şahin", "Kobra", "Tilki", "Atmaca", "Hayalet", "Puma", "Akrep"]

var _backdrop_mat: ShaderMaterial
var _light_pos := Vector2.ZERO

var _name_input: LineEdit
var _status_lbl: Label
var _tab_buttons: Dictionary = {}   # tab adı → Button
var _pages: Dictionary = {}         # tab adı → Control
var _current_tab := ""

# Odalar
var _room_list: VBoxContainer
var _room_scroll: ScrollContainer
var _empty_state: Control
var _scan_dot: Label
var _room_count_lbl: Label

# Oda kur
var _room_name_input: LineEdit
var _password_input: LineEdit
var _host_btn: Button

# Kod ile katıl
var _code_input: LineEdit
var _code_pw_input: LineEdit
var _join_btn: Button

# Şifre modalı
var _modal: Control
var _modal_room_lbl: Label
var _modal_pw_input: LineEdit
var _modal_status: Label
var _modal_room_ip := ""


func _ready() -> void:
	UITheme.apply(get_tree())  # sahne tek başına (F6) çalıştırılırsa da tema gelsin
	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.joined_server.connect(_on_joined_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.kicked.connect(_on_kicked)
	RoomManager.rooms_updated.connect(_refresh_room_list)

	_build_ui()
	_name_input.text = _load_name()
	_light_pos = get_viewport_rect().size * Vector2(0.3, 0.4)
	_show_tab("browse")


func _process(delta: float) -> void:
	# El feneri fareyi yumuşakça takip eder
	_light_pos = _light_pos.lerp(get_local_mouse_position(), 1.0 - exp(-5.0 * delta))
	_backdrop_mat.set_shader_parameter("light_pos", _light_pos)
	_backdrop_mat.set_shader_parameter("rect_size", size)
	# "Taranıyor" göstergesi nabız gibi yanıp söner
	if _scan_dot and _current_tab == "browse":
		_scan_dot.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _modal.visible:
		_close_modal()
		get_viewport().set_input_as_handled()


# ─────────────────────────────────────────────
#  Yerleşim
# ─────────────────────────────────────────────

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop_mat = ShaderMaterial.new()
	_backdrop_mat.shader = preload("res://scenes/ui/MenuBackdrop.gdshader")
	backdrop.material = _backdrop_mat
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 56)
	margin.add_theme_constant_override("margin_right", 56)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 48)
	margin.add_child(columns)

	columns.add_child(_build_brand_column())
	columns.add_child(_build_main_panel())

	_build_password_modal()


func _build_brand_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(360, 0)
	col.add_theme_constant_override("separation", 0)

	var eyebrow := UITheme.label("5v5v5v5  ·  TAKTİK NİŞANCI", 11, UITheme.TEXT_DIM, UITheme.font_caps)
	col.add_child(eyebrow)
	col.add_child(_spacer(10))

	col.add_child(UITheme.label("TACTICAL", 34, UITheme.TEXT, UITheme.font_title))
	var dark := UITheme.label("DARK", 72, UITheme.ACCENT, UITheme.font_title)
	dark.add_theme_constant_override("line_spacing", -12)
	col.add_child(dark)
	col.add_child(_spacer(10))

	var tagline := UITheme.label("Zifiri karanlıkta yalnızca el fenerin var.\nKartı bul, kapıya ulaştır, takımını zafere taşı.", 14, UITheme.TEXT_DIM)
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(tagline)
	col.add_child(_spacer(20))

	# Takım renkleri
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 8)
	for i in range(4):
		var c: Color = TeamManager.TEAM_COLORS[i]
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UITheme.style(Color(c, 0.12), 12, Color(c, 0.45), 1, 10, 3))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		chip.add_child(row)
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(7, 7)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.add_theme_stylebox_override("panel", UITheme.style(c, 4))
		row.add_child(dot)
		row.add_child(UITheme.label(String(TeamManager.TEAM_NAMES[i]).to_upper(), 10, c, UITheme.font_caps))
		teams.add_child(chip)
	col.add_child(teams)

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(fill)

	# Oyuncu adı kartı
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.style(UITheme.SURFACE, 14, UITheme.BORDER, 1, 18, 16))
	col.add_child(card)
	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 8)
	card.add_child(card_box)
	card_box.add_child(UITheme.label("OPERATÖR ADI", 11, UITheme.TEXT_DIM, UITheme.font_caps))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	card_box.add_child(name_row)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Oyuncu adı"
	_name_input.max_length = NAME_MAX_LEN
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.add_theme_font_override("font", UITheme.font_bold)
	_name_input.add_theme_font_size_override("font_size", 17)
	_name_input.text_changed.connect(func(_t: String) -> void: _set_status(""))
	name_row.add_child(_name_input)
	var dice := Button.new()
	dice.text = "↻"
	dice.tooltip_text = "Rastgele isim"
	dice.custom_minimum_size = Vector2(46, 0)
	dice.add_theme_font_size_override("font_size", 18)
	dice.pressed.connect(func() -> void: _name_input.text = _random_name())
	name_row.add_child(dice)

	col.add_child(_spacer(14))
	col.add_child(UITheme.label("LAN  ·  PORT %d  ·  v0.1" % NetworkManager.PORT, 10, Color(UITheme.TEXT_DIM, 0.6), UITheme.font_caps))
	return col


func _build_main_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UITheme.style(UITheme.SURFACE, 16, UITheme.BORDER, 1, 0, 0))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)

	# Sekmeler
	var tab_margin := MarginContainer.new()
	tab_margin.add_theme_constant_override("margin_left", 14)
	tab_margin.add_theme_constant_override("margin_right", 14)
	tab_margin.add_theme_constant_override("margin_top", 10)
	box.add_child(tab_margin)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	tab_margin.add_child(tab_row)

	var group := ButtonGroup.new()
	for tab: Array in [["browse", "ODALAR"], ["create", "ODA KUR"], ["code", "KOD İLE KATIL"]]:
		var b := Button.new()
		b.text = tab[1]
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "TabButton"
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_show_tab.bind(tab[0]))
		tab_row.add_child(b)
		_tab_buttons[tab[0]] = b

	box.add_child(HSeparator.new())

	# Sayfalar
	var pages_margin := MarginContainer.new()
	pages_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right"]:
		pages_margin.add_theme_constant_override("margin_" + side, 24)
	pages_margin.add_theme_constant_override("margin_top", 20)
	pages_margin.add_theme_constant_override("margin_bottom", 12)
	box.add_child(pages_margin)

	_pages["browse"] = _build_browse_page()
	_pages["create"] = _build_create_page()
	_pages["code"]   = _build_code_page()
	for key: String in _pages:
		pages_margin.add_child(_pages[key])

	# Durum satırı
	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override("margin_left", 24)
	status_margin.add_theme_constant_override("margin_right", 24)
	status_margin.add_theme_constant_override("margin_bottom", 16)
	box.add_child(status_margin)
	_status_lbl = UITheme.label("", 13, UITheme.TEXT_DIM)
	_status_lbl.custom_minimum_size = Vector2(0, 20)
	status_margin.add_child(_status_lbl)
	return panel


func _build_browse_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	page.add_child(header)
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)
	title_box.add_child(UITheme.label("Yerel Ağdaki Odalar", 20, UITheme.TEXT, UITheme.font_bold))
	var scan_row := HBoxContainer.new()
	scan_row.add_theme_constant_override("separation", 6)
	title_box.add_child(scan_row)
	_scan_dot = UITheme.label("●", 10, UITheme.SUCCESS)
	scan_row.add_child(_scan_dot)
	_room_count_lbl = UITheme.label("", 11, UITheme.TEXT_DIM, UITheme.font_caps)
	scan_row.add_child(_room_count_lbl)

	var refresh := Button.new()
	refresh.text = "↻  Yenile"
	refresh.theme_type_variation = "GhostButton"
	refresh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	refresh.pressed.connect(_refresh_room_list)
	header.add_child(refresh)

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(stack)

	_room_scroll = ScrollContainer.new()
	_room_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_room_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(_room_scroll)
	_room_list = VBoxContainer.new()
	_room_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_list.add_theme_constant_override("separation", 8)
	_room_scroll.add_child(_room_list)

	# Boş durum
	var empty := CenterContainer.new()
	empty.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(empty)
	_empty_state = empty
	var empty_box := VBoxContainer.new()
	empty_box.add_theme_constant_override("separation", 6)
	empty.add_child(empty_box)
	var icon := UITheme.label("◎", 44, Color(UITheme.ACCENT, 0.5))
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_box.add_child(icon)
	var e1 := UITheme.label("Henüz oda bulunamadı", 17, UITheme.TEXT, UITheme.font_bold)
	e1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_box.add_child(e1)
	var e2 := UITheme.label("Aynı ağdaki odalar burada otomatik belirir.", 13, UITheme.TEXT_DIM)
	e2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_box.add_child(e2)
	empty_box.add_child(_spacer(8))
	var e_btns := HBoxContainer.new()
	e_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	e_btns.add_theme_constant_override("separation", 10)
	empty_box.add_child(e_btns)
	var go_create := Button.new()
	go_create.text = "Oda Kur"
	go_create.theme_type_variation = "PrimaryButton"
	go_create.pressed.connect(_show_tab.bind("create"))
	e_btns.add_child(go_create)
	var go_code := Button.new()
	go_code.text = "Kod ile Katıl"
	go_code.pressed.connect(_show_tab.bind("code"))
	e_btns.add_child(go_code)
	return page


func _build_create_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	page.add_child(UITheme.label("Yeni Oda Kur", 20, UITheme.TEXT, UITheme.font_bold))
	var info := UITheme.label("Odan yerel ağda yayınlanır. Arkadaşların listeden ya da oda kodunla katılabilir.", 13, UITheme.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(info)
	page.add_child(_spacer(4))

	_room_name_input = LineEdit.new()
	_room_name_input.max_length = 32
	_room_name_input.text_submitted.connect(func(_t: String) -> void: _on_host_pressed())
	_room_name_input.focus_entered.connect(func() -> void:
		_room_name_input.placeholder_text = "%s'nin Odası" % _get_player_name("Oyuncu"))
	page.add_child(_field("ODA ADI", _room_name_input))

	_password_input = LineEdit.new()
	_password_input.placeholder_text = "Boş bırakırsan herkese açık olur"
	_password_input.secret = true
	_password_input.text_submitted.connect(func(_t: String) -> void: _on_host_pressed())
	page.add_child(_field("ŞİFRE  (OPSİYONEL)", _password_input, _make_reveal_button(_password_input)))

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(fill)

	_host_btn = Button.new()
	_host_btn.text = "ODAYI KUR"
	_host_btn.theme_type_variation = "PrimaryButton"
	_host_btn.custom_minimum_size = Vector2(0, 50)
	_host_btn.add_theme_font_size_override("font_size", 16)
	_host_btn.pressed.connect(_on_host_pressed)
	page.add_child(_host_btn)
	return page


func _build_code_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	page.add_child(UITheme.label("Kod ile Katıl", 20, UITheme.TEXT, UITheme.font_bold))
	var info := UITheme.label("Oda sahibinden 7 haneli oda kodunu iste. Yerel test için IP adresi de yazabilirsin.", 13, UITheme.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(info)
	page.add_child(_spacer(4))

	_code_input = LineEdit.new()
	_code_input.placeholder_text = "ABCD234"
	_code_input.max_length = 15
	_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_input.add_theme_font_override("font", UITheme.font_title)
	_code_input.add_theme_font_size_override("font_size", 28)
	_code_input.text_changed.connect(_on_code_text_changed)
	_code_input.text_submitted.connect(func(_t: String) -> void: _on_join_code_pressed())
	page.add_child(_field("ODA KODU", _code_input))

	_code_pw_input = LineEdit.new()
	_code_pw_input.placeholder_text = "Oda şifreliyse"
	_code_pw_input.secret = true
	_code_pw_input.text_submitted.connect(func(_t: String) -> void: _on_join_code_pressed())
	page.add_child(_field("ŞİFRE", _code_pw_input, _make_reveal_button(_code_pw_input)))

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(fill)

	_join_btn = Button.new()
	_join_btn.text = "KATIL"
	_join_btn.theme_type_variation = "PrimaryButton"
	_join_btn.custom_minimum_size = Vector2(0, 50)
	_join_btn.add_theme_font_size_override("font_size", 16)
	_join_btn.pressed.connect(_on_join_code_pressed)
	page.add_child(_join_btn)
	return page


func _build_password_modal() -> void:
	_modal = ColorRect.new()
	(_modal as ColorRect).color = Color(0, 0, 0, 0.65)
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.visible = false
	add_child(_modal)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	var card_style := UITheme.style(UITheme.SURFACE_2, 16, Color(UITheme.ACCENT, 0.3), 1, 24, 22)
	card_style.shadow_color = Color(0, 0, 0, 0.5)
	card_style.shadow_size = 30
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)
	box.add_child(UITheme.label("🔒  ŞİFRELİ ODA", 12, UITheme.ACCENT, UITheme.font_caps))
	_modal_room_lbl = UITheme.label("", 20, UITheme.TEXT, UITheme.font_bold)
	box.add_child(_modal_room_lbl)

	_modal_pw_input = LineEdit.new()
	_modal_pw_input.placeholder_text = "Oda şifresi"
	_modal_pw_input.secret = true
	_modal_pw_input.text_submitted.connect(func(_t: String) -> void: _on_modal_join())
	box.add_child(_modal_pw_input)

	_modal_status = UITheme.label("", 12, UITheme.DANGER)
	box.add_child(_modal_status)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	btns.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(btns)
	var cancel := Button.new()
	cancel.text = "Vazgeç"
	cancel.theme_type_variation = "GhostButton"
	cancel.pressed.connect(_close_modal)
	btns.add_child(cancel)
	var join := Button.new()
	join.text = "KATIL"
	join.theme_type_variation = "PrimaryButton"
	join.custom_minimum_size = Vector2(120, 0)
	join.pressed.connect(_on_modal_join)
	btns.add_child(join)


func _build_room_row(code: String, room: Dictionary) -> Control:
	var has_pw: bool = room.get("has_password", false)
	var room_ip: String = room.get("ip", "")
	var count: int = room.get("player_count", 0)
	var room_name: String = room.get("room_name", code)
	var full := count >= NetworkManager.MAX_PLAYERS

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UITheme.style(UITheme.SURFACE_2, 12, UITheme.BORDER, 1, 16, 12))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)

	# Simge kutusu
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(40, 40)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.add_theme_stylebox_override("panel", UITheme.style(Color(UITheme.ACCENT, 0.1), 10))
	var icon := UITheme.label("🔒" if has_pw else "◆", 16, UITheme.ACCENT)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_box.add_child(icon)
	h.add_child(icon_box)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(info)
	var name_lbl := UITheme.label(room_name, 16, UITheme.TEXT, UITheme.font_bold)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(name_lbl)
	var sub := "KOD  %s" % code
	if has_pw:
		sub += "  ·  ŞİFRELİ"
	info.add_child(UITheme.label(sub, 10, UITheme.TEXT_DIM, UITheme.font_caps))

	# Doluluk
	var cap_box := VBoxContainer.new()
	cap_box.add_theme_constant_override("separation", 4)
	cap_box.custom_minimum_size = Vector2(80, 0)
	cap_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(cap_box)
	var cap_lbl := UITheme.label("%d / %d" % [count, NetworkManager.MAX_PLAYERS], 13,
		UITheme.DANGER if full else UITheme.TEXT, UITheme.font_bold)
	cap_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cap_box.add_child(cap_lbl)
	var cap_bar := ProgressBar.new()
	cap_bar.show_percentage = false
	cap_bar.custom_minimum_size = Vector2(0, 4)
	cap_bar.max_value = NetworkManager.MAX_PLAYERS
	cap_bar.value = count
	if full:
		cap_bar.add_theme_stylebox_override("fill", UITheme.style(UITheme.DANGER, 4))
	cap_box.add_child(cap_bar)

	var btn := Button.new()
	btn.text = "DOLU" if full else "KATIL"
	btn.disabled = full
	btn.theme_type_variation = "PrimaryButton"
	btn.custom_minimum_size = Vector2(96, 40)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_on_room_join_btn.bind(code, room_name, room_ip, has_pw))
	h.add_child(btn)
	return row


# ─────────────────────────────────────────────
#  Küçük yardımcılar
# ─────────────────────────────────────────────

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _field(caption: String, input: LineEdit, trailing: Control = null) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(UITheme.label(caption, 11, UITheme.TEXT_DIM, UITheme.font_caps))
	input.custom_minimum_size.y = 44
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_changed.connect(func(_t: String) -> void: _set_status(""))
	if trailing:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(input)
		row.add_child(trailing)
		box.add_child(row)
	else:
		box.add_child(input)
	return box


func _make_reveal_button(target: LineEdit) -> Button:
	var b := Button.new()
	b.text = "Göster"
	b.toggle_mode = true
	b.theme_type_variation = "GhostButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(76, 0)
	b.toggled.connect(func(on: bool) -> void:
		target.secret = not on
		b.text = "Gizle" if on else "Göster")
	return b


func _set_status(text: String, kind: String = "info") -> void:
	if _status_lbl == null:
		return
	_status_lbl.text = text
	var col := UITheme.TEXT_DIM
	match kind:
		"error": col = UITheme.DANGER
		"ok":    col = UITheme.SUCCESS
		"busy":  col = UITheme.ACCENT
	_status_lbl.add_theme_color_override("font_color", col)


func _set_busy(busy: bool) -> void:
	_host_btn.disabled = busy
	_join_btn.disabled = busy


## Geçerli oyuncu adını döner; boşsa hata gösterip "" döner (fallback verilirse onu döner).
func _get_player_name(fallback: String = "") -> String:
	var n := _name_input.text.strip_edges()
	if n.is_empty() and fallback.is_empty():
		_set_status("Önce bir operatör adı gir.", "error")
		_name_input.grab_focus()
	return n if not n.is_empty() else fallback


func _random_name() -> String:
	return "%s_%d" % [CALLSIGNS.pick_random(), randi_range(10, 99)]


func _load_name() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var saved: String = cfg.get_value("player", "name", "")
		if not saved.is_empty():
			return saved
	return _random_name()


func _save_name(player_name: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("player", "name", player_name)
	cfg.save(SETTINGS_PATH)


# ─────────────────────────────────────────────
#  Sekmeler
# ─────────────────────────────────────────────

func _show_tab(which: String) -> void:
	if _current_tab == which:
		return
	_current_tab = which
	for key: String in _pages:
		(_pages[key] as Control).visible = (key == which)
	(_tab_buttons[which] as Button).set_pressed_no_signal(true)
	_set_status("")
	# Oda keşfi sadece Odalar sekmesinde açık
	if which == "browse":
		RoomManager.start_listening()
		_refresh_room_list()
	else:
		RoomManager.stop_listening()


# ─────────────────────────────────────────────
#  Odalar
# ─────────────────────────────────────────────

func _refresh_room_list() -> void:
	for child in _room_list.get_children():
		child.queue_free()
	var rooms := RoomManager.discovered_rooms
	_empty_state.visible = rooms.is_empty()
	_room_scroll.visible = not rooms.is_empty()
	_room_count_lbl.text = "TARANIYOR..." if rooms.is_empty() else "%d ODA BULUNDU" % rooms.size()
	for code: String in rooms:
		_room_list.add_child(_build_room_row(code, rooms[code]))


func _on_room_join_btn(room_code: String, room_name: String, room_ip: String, has_password: bool) -> void:
	var player_name := _get_player_name()
	if player_name.is_empty():
		return
	if has_password:
		_modal_room_ip = room_ip
		_modal_room_lbl.text = room_name
		_modal_pw_input.text = ""
		_modal_status.text = ""
		_modal.visible = true
		_modal_pw_input.grab_focus()
	else:
		_save_name(player_name)
		_set_status("Bağlanıyor: %s ..." % room_name, "busy")
		NetworkManager.join_server(room_ip, player_name, "")


func _on_modal_join() -> void:
	var player_name := _get_player_name()
	if player_name.is_empty():
		_close_modal()
		return
	_save_name(player_name)
	_modal_status.add_theme_color_override("font_color", UITheme.ACCENT)
	_modal_status.text = "Bağlanıyor..."
	NetworkManager.join_server(_modal_room_ip, player_name, _modal_pw_input.text)


func _close_modal() -> void:
	_modal.visible = false


# ─────────────────────────────────────────────
#  Oda kur / Kod ile katıl
# ─────────────────────────────────────────────

func _on_host_pressed() -> void:
	var player_name := _get_player_name()
	if player_name.is_empty():
		return
	var r_name := _room_name_input.text.strip_edges()
	if r_name.is_empty():
		r_name = player_name + "'nin Odası"
	_save_name(player_name)
	_set_busy(true)
	_set_status("Sunucu oluşturuluyor...", "busy")
	NetworkManager.create_server(player_name, r_name, _password_input.text)


func _on_code_text_changed(new_text: String) -> void:
	# Kodu yazarken otomatik büyük harfe çevir (IP girilirse dokunma)
	if new_text.contains("."):
		return
	var upper := new_text.to_upper()
	if upper != new_text:
		var caret := _code_input.caret_column
		_code_input.text = upper
		_code_input.caret_column = caret


func _on_join_code_pressed() -> void:
	var player_name := _get_player_name()
	if player_name.is_empty():
		return
	var code := _code_input.text.strip_edges().to_upper()
	if code.is_empty():
		_set_status("Oda kodunu gir.", "error")
		_code_input.grab_focus()
		return
	var ip := RoomManager.get_ip_for_code(code)
	if ip.to_lower() == "localhost":
		ip = "127.0.0.1"  # kod kutusu otomatik büyük harfe çevirir
	if not NetworkManager.is_valid_address(ip):
		_set_status("Geçersiz oda kodu. Kod 7 haneli olmalı (ör. ABCD234) ya da bir IP adresi gir.", "error")
		_code_input.select_all()
		_code_input.grab_focus()
		return
	_save_name(player_name)
	_set_busy(true)
	_set_status("Bağlanıyor...", "busy")
	NetworkManager.join_server(ip, player_name, _code_pw_input.text)


# ─────────────────────────────────────────────
#  Ağ olayları
# ─────────────────────────────────────────────

func _on_server_created() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/ui/Lobby.tscn")


func _on_joined_server() -> void:
	RoomManager.stop_listening()
	get_tree().change_scene_to_file.call_deferred("res://scenes/ui/Lobby.tscn")


func _on_connection_failed() -> void:
	_set_busy(false)
	_set_status("Bağlantı başarısız! Oda kapanmış ya da kod hatalı olabilir.", "error")
	if _modal.visible:
		_modal_status.add_theme_color_override("font_color", UITheme.DANGER)
		_modal_status.text = "Bağlantı başarısız!"


func _on_kicked(reason: String) -> void:
	_set_busy(false)
	if _modal.visible:
		# Muhtemelen yanlış şifre — modal açık kalsın, tekrar denensin
		_modal_status.add_theme_color_override("font_color", UITheme.DANGER)
		_modal_status.text = reason
		_modal_pw_input.select_all()
		_modal_pw_input.grab_focus()
	_set_status(reason, "error")

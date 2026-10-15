## CharacterSelect.gd
## Oyun başladıktan sonra karakter seçim ekranı.
## Her takım üyesi 5 karakterden birini seçer (takım içinde benzersiz).
## Tüm oyuncular seçimini tamamladığında GameManager oyunu başlatır.
##
## UI tamamen kodla kurulur: kartın tamamı tıklanabilir (çift tık = seç + onayla),
## hover/seçili kartta 3D önizleme hafifçe sallanır, altta takım arkadaşlarının seçimleri listelenir.

extends Control

const CHARACTERS: Array[Dictionary] = [
	{"name": "Tank",     "role": "Ön Hat",       "color": Color(0.9,  0.35, 0.25), "stats": {"Can": 150.0, "Hız": 5.5,  "Hasar": 22.0,  "Menzil": 45.0}},
	{"name": "Visioner", "role": "Keşif",        "color": Color(0.25, 0.55, 1.0),  "stats": {"Can": 100.0, "Hız": 8.0,  "Hasar": 18.0,  "Menzil": 35.0}},
	{"name": "Runner",   "role": "Hızlı Sızma",  "color": Color(0.25, 0.9,  0.35), "stats": {"Can": 75.0,  "Hız": 13.0, "Hasar": 11.0,  "Menzil": 25.0}},
	{"name": "Sniper",   "role": "Uzun Menzil",  "color": Color(0.95, 0.85, 0.15), "stats": {"Can": 80.0,  "Hız": 7.0,  "Hasar": 120.0, "Menzil": 130.0}},
	{"name": "Medic",    "role": "Destek",       "color": Color(0.85, 0.35, 0.95), "stats": {"Can": 110.0, "Hız": 7.5,  "Hasar": 45.0,  "Menzil": 55.0}},
]

const STAT_ORDER: Array[String] = ["Can", "Hız", "Hasar", "Menzil"]
const STAT_MAX: Dictionary  = {"Can": 150.0, "Hız": 13.0, "Hasar": 120.0, "Menzil": 130.0}

const COL_BG_TOP     := Color(0.085, 0.095, 0.15)
const COL_BG_BOTTOM  := Color(0.015, 0.015, 0.03)
const COL_CARD       := Color(0.075, 0.08, 0.115)
const COL_CARD_HOVER := Color(0.105, 0.115, 0.165)
const COL_TEXT       := Color(0.92, 0.93, 0.96)
const COL_TEXT_DIM   := Color(0.55, 0.57, 0.65)
const COL_TRACK      := Color(1, 1, 1, 0.07)
const CARD_RADIUS := 14

var _local_selected: String = ""
var _confirmed: bool = false
var _hovered: String = ""
## Her eleman: {name, color, panel, preview, footer, footer_lbl, badge, badge_lbl}
var _cards: Array[Dictionary] = []
var _confirm_btn: Button = null
var _status_lbl: Label = null
var _progress: ProgressBar = null
var _roster_row: HBoxContainer = null
var _team_color: Color = Color.WHITE

var _font_title: FontVariation
var _font_bold: FontVariation
var _font_caps: FontVariation


func _ready() -> void:
	_init_fonts()
	NetworkManager.player_list_updated.connect(_refresh)
	_build_ui()
	_refresh()


func _process(delta: float) -> void:
	# Hover veya seçili karakter önizlemesi yavaşça sağa-sola döner
	var t := Time.get_ticks_msec() / 1000.0
	var w := 1.0 - exp(-4.0 * delta)
	for c: Dictionary in _cards:
		var preview: Node3D = c["preview"]
		var active: bool = c["name"] == _hovered or c["name"] == _local_selected
		var target := sin(t * 1.1) * 0.5 if active else 0.0
		preview.rotation.y = lerp_angle(preview.rotation.y, target, w)


func _init_fonts() -> void:
	var base := ThemeDB.fallback_font
	_font_title = FontVariation.new()
	_font_title.base_font = base
	_font_title.variation_embolden = 0.9
	_font_title.spacing_glyph = 6

	_font_bold = FontVariation.new()
	_font_bold.base_font = base
	_font_bold.variation_embolden = 0.7
	_font_bold.spacing_glyph = 2

	_font_caps = FontVariation.new()
	_font_caps.base_font = base
	_font_caps.variation_embolden = 0.35
	_font_caps.spacing_glyph = 3


# ─────────────────────────────────────────────
#  Yerleşim
# ─────────────────────────────────────────────

func _build_ui() -> void:
	var local_data: Dictionary = NetworkManager.players.get(NetworkManager.get_local_id(), {})
	var team_id: int = local_data.get("team_id", -1)
	_team_color = TeamManager.get_color(team_id)

	# Arka plan: üstten aşağı koyulaşan radyal degrade + takım renginde hafif parıltı
	var bg_grad := Gradient.new()
	bg_grad.set_color(0, COL_BG_TOP)
	bg_grad.set_color(1, COL_BG_BOTTOM)
	var bg_tex := GradientTexture2D.new()
	bg_tex.gradient  = bg_grad
	bg_tex.fill      = GradientTexture2D.FILL_RADIAL
	bg_tex.fill_from = Vector2(0.5, 0.0)
	bg_tex.fill_to   = Vector2(0.5, 1.1)
	var bg := TextureRect.new()
	bg.texture = bg_tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var glow_grad := Gradient.new()
	glow_grad.set_color(0, Color(_team_color, 0.16))
	glow_grad.set_color(1, Color(_team_color, 0.0))
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = glow_grad
	glow_tex.fill_from = Vector2(0, 0)
	glow_tex.fill_to   = Vector2(0, 1)
	var glow := TextureRect.new()
	glow.texture = glow_tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_TOP_WIDE)
	glow.offset_bottom = 160
	add_child(glow)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	root.add_child(_build_header(team_id))

	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 16)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cards_row)

	for char_data: Dictionary in CHARACTERS:
		cards_row.add_child(_build_card(char_data))

	root.add_child(_build_footer())


func _build_header(team_id: int) -> Control:
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 4)

	var eyebrow := _make_label("TAKTİK HAZIRLIK", 12, COL_TEXT_DIM, _font_caps)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(eyebrow)

	var title := _make_label("KARAKTERİNİ SEÇ", 30, COL_TEXT, _font_title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)

	# Takım rozeti (pill)
	var chip := PanelContainer.new()
	var chip_style := _rounded_style(Color(_team_color, 0.14), 20)
	chip_style.border_color = Color(_team_color, 0.6)
	chip_style.set_border_width_all(1)
	chip_style.content_margin_left  = 16
	chip_style.content_margin_right = 16
	chip_style.content_margin_top   = 4
	chip_style.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", chip_style)

	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	chip.add_child(chip_row)

	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", _rounded_style(_team_color, 4))
	chip_row.add_child(dot)
	chip_row.add_child(_make_label("%s TAKIM" % TeamManager.get_team_name(team_id).to_upper(), 12, _team_color, _font_caps))

	var chip_wrap := CenterContainer.new()
	chip_wrap.add_child(chip)
	header.add_child(chip_wrap)
	return header


func _build_footer() -> Control:
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)

	# Takım arkadaşlarının seçimleri — _refresh_roster ile doldurulur
	_roster_row = HBoxContainer.new()
	_roster_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_roster_row.add_theme_constant_override("separation", 8)
	footer.add_child(_roster_row)

	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 22)
	footer.add_child(action_row)

	# Genel ilerleme (tüm oyuncular)
	var progress_box := VBoxContainer.new()
	progress_box.add_theme_constant_override("separation", 5)
	progress_box.custom_minimum_size = Vector2(240, 0)
	progress_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action_row.add_child(progress_box)

	_status_lbl = _make_label("", 12, COL_TEXT_DIM, _font_caps)
	progress_box.add_child(_status_lbl)

	_progress = _make_bar(Color(0.85, 0.87, 0.95), 4)
	progress_box.add_child(_progress)

	_confirm_btn = Button.new()
	_confirm_btn.text = "ONAYLA"
	_confirm_btn.custom_minimum_size = Vector2(230, 48)
	_confirm_btn.disabled = true
	_confirm_btn.focus_mode = Control.FOCUS_NONE
	_confirm_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_confirm_btn.add_theme_font_override("font", _font_bold)
	_confirm_btn.add_theme_font_size_override("font_size", 16)
	_confirm_btn.pressed.connect(_on_confirm)
	action_row.add_child(_confirm_btn)

	var hint := _make_label("Çift tık: seç ve onayla", 11, Color(COL_TEXT_DIM, 0.7))
	hint.custom_minimum_size = Vector2(240, 0)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action_row.add_child(hint)

	_style_confirm_button(Color(0.4, 0.42, 0.5))
	return footer


func _build_card(char_data: Dictionary) -> PanelContainer:
	var char_name: String = char_data["name"]
	var char_color: Color = char_data["color"]

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(196, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_card_input.bind(char_name))
	panel.mouse_entered.connect(_on_card_hover.bind(char_name, true))
	panel.mouse_exited.connect(_on_card_hover.bind(char_name, false))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	# ── 3D önizleme (üst köşeleri yuvarlak maske ile kırpılır) ──
	var mask := Panel.new()
	mask.custom_minimum_size = Vector2(0, 190)
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	var mask_style := _rounded_style(Color.WHITE, 0)
	mask_style.corner_radius_top_left  = CARD_RADIUS - 2
	mask_style.corner_radius_top_right = CARD_RADIUS - 2
	mask.add_theme_stylebox_override("panel", mask_style)
	vbox.add_child(mask)

	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	mask.add_child(svc)

	var sv := SubViewport.new()
	sv.size = Vector2i(196, 190)
	sv.transparent_bg = false
	sv.msaa_3d = Viewport.MSAA_2X
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Her kartın kendi 3D dünyası — yoksa 5 önizleme aynı World3D'yi paylaşır ve
	# tüm karakterler (ve ışıkları) her kartta üst üste görünür
	sv.own_world_3d = true
	svc.add_child(sv)

	var preview := _build_preview_world(sv, char_name, char_color)

	# Önizlemenin altını kart rengine erit
	var fade_grad := Gradient.new()
	fade_grad.set_color(0, Color(COL_CARD, 0.0))
	fade_grad.set_color(1, COL_CARD)
	var fade_tex := GradientTexture2D.new()
	fade_tex.gradient = fade_grad
	fade_tex.fill_from = Vector2(0, 0)
	fade_tex.fill_to   = Vector2(0, 1)
	var fade := TextureRect.new()
	fade.texture = fade_tex
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	fade.offset_top = -56
	mask.add_child(fade)

	# Sağ üst durum rozeti (ALINDI / SEN)
	var badge := PanelContainer.new()
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left  = -86
	badge.offset_right = -10
	badge.offset_top   = 10
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.visible = false
	mask.add_child(badge)
	var badge_lbl := _make_label("", 10, Color.WHITE, _font_caps)
	badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(badge_lbl)

	# ── İsim / rol / statlar ──
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left",   14)
	content_margin.add_theme_constant_override("margin_right",  14)
	content_margin.add_theme_constant_override("margin_top",    2)
	content_margin.add_theme_constant_override("margin_bottom", 12)
	content_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content_margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content_margin.add_child(content)

	content.add_child(_make_label(char_name.to_upper(), 18, COL_TEXT, _font_bold))

	var role_row := HBoxContainer.new()
	role_row.add_theme_constant_override("separation", 8)
	content.add_child(role_row)
	var accent := ColorRect.new()
	accent.color = char_color
	accent.custom_minimum_size = Vector2(18, 2)
	accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	role_row.add_child(accent)
	role_row.add_child(_make_label((char_data["role"] as String).to_upper(), 10, char_color, _font_caps))

	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 7)
	content.add_child(stats_box)
	var spacer_top := Control.new()
	spacer_top.custom_minimum_size = Vector2(0, 2)
	stats_box.add_child(spacer_top)

	var stats: Dictionary = char_data["stats"]
	for stat_name: String in STAT_ORDER:
		var value: float = stats[stat_name]
		var stat_col := VBoxContainer.new()
		stat_col.add_theme_constant_override("separation", 3)
		stats_box.add_child(stat_col)

		var label_row := HBoxContainer.new()
		stat_col.add_child(label_row)
		var name_lbl := _make_label(stat_name.to_upper(), 9, COL_TEXT_DIM, _font_caps)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label_row.add_child(name_lbl)
		#label_row.add_child(_make_label("%g" % value, 10, COL_TEXT, _font_bold))
		label_row.add_child(_make_label(str(value), 10, COL_TEXT, _font_bold))

		var bar := _make_bar(char_color, 5)
		bar.value = value / (STAT_MAX[stat_name] as float)
		stat_col.add_child(bar)

	# ── Alt şerit: durum ──
	var footer := PanelContainer.new()
	footer.custom_minimum_size = Vector2(0, 34)
	vbox.add_child(footer)
	var footer_lbl := _make_label("", 11, COL_TEXT_DIM, _font_caps)
	footer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(footer_lbl)

	# Tıklama/hover olaylarını sadece kart alsın
	_ignore_mouse_recursive(vbox)

	_cards.append({
		"name": char_name, "color": char_color, "panel": panel, "preview": preview,
		"footer": footer, "footer_lbl": footer_lbl, "badge": badge, "badge_lbl": badge_lbl,
	})
	return panel


## SubViewport içine kodsuz Player.tscn + ışık + kamera kurar, döndürülecek kök node'u döner.
func _build_preview_world(sv: SubViewport, char_name: String, char_color: Color) -> Node3D:
	var world := Node3D.new()
	sv.add_child(world)

	var env_node := WorldEnvironment.new()
	var env_res  := Environment.new()
	env_res.background_mode    = Environment.BG_COLOR
	env_res.background_color   = COL_CARD.lerp(char_color, 0.08)
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color  = Color(0.25, 0.25, 0.32)
	env_res.ambient_light_energy = 0.6
	env_res.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env_res
	world.add_child(env_node)

	# Player.tscn'yi script olmadan (kodsuz) önizleme için kullan
	var player_scene := preload("res://scenes/player/Player.tscn") as PackedScene
	var player_inst: Node3D = player_scene.instantiate()
	player_inst.set_script(null)
	player_inst.get_node("NameLabel").visible          = false
	player_inst.get_node("HealthLabel").visible        = false
	player_inst.get_node("AmmoLabel").visible          = false
	player_inst.get_node("CardIndicatorLabel").visible = false
	player_inst.get_node("Flashlight").visible         = false
	player_inst.get_node("BodyLight").visible          = false
	world.add_child(player_inst)

	# CharacterMesh içindeki AnimationPlayer'ı bul, mixamo_com animasyonunu ayarla
	var char_mesh: Node3D = player_inst.get_node("CharacterMesh")
	if char_mesh.has_method("apply_outfit"):
		char_mesh.apply_outfit(char_name)  # karaktere özel kıyafet (SurvivalistModel)
	var ap := _find_anim_player(char_mesh)
	if ap:
		var candidates := ["Idle", "mixamo_com", "mixamo.com", "Breathing Idle", "idle"]
		var anim_name := ""
		for c in candidates:
			if ap.has_animation(c):
				anim_name = c
				break
		if anim_name.is_empty():
			for a: StringName in ap.get_animation_list():
				var s := a as String
				if s != "RESET" and s != "Take 001":
					anim_name = s
					break
		if not anim_name.is_empty():
			var anim: Animation = ap.get_animation(anim_name)
			if anim and anim.loop_mode == Animation.LOOP_NONE:
				anim.loop_mode = Animation.LOOP_LINEAR
			ap.autoplay = anim_name

	# Ana ışık nötr (kıyafet renkleri doğru görünsün); karakter rengi sadece arkadan kenar ışığı olarak
	var key_light := OmniLight3D.new()
	key_light.position    = Vector3(0.9, 2.6, -2.2)
	key_light.light_color  = Color(1.0, 0.96, 0.9)
	key_light.light_energy = 2.2
	key_light.omni_range   = 8.0
	world.add_child(key_light)

	var rim_light := OmniLight3D.new()
	rim_light.position    = Vector3(0.0, 2.4, 1.6)
	rim_light.light_color  = char_color
	rim_light.light_energy = 2.0
	rim_light.omni_range   = 5.0
	world.add_child(rim_light)

	# Dolgu ışığı (nötr, diğer taraftan)
	var fill_light := OmniLight3D.new()
	fill_light.position    = Vector3(-1.5, 1.6, -1.8)
	fill_light.light_energy = 1.0
	fill_light.omni_range   = 7.0
	world.add_child(fill_light)

	# Kamera — yakın plan: yüz + omuzlar (göğüs hizasından başın üstüne). CharacterMesh -Z yönüne bakar, kamera karşısında.
	var cam := Camera3D.new()
	cam.position         = Vector3(0.0, 1.62, -1.6)
	cam.rotation_degrees = Vector3(-4.0, 180.0, 0.0)
	cam.fov              = 30.0
	world.add_child(cam)

	return player_inst


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result := _find_anim_player(child)
		if result:
			return result
	return null


# ─────────────────────────────────────────────
#  Girdi
# ─────────────────────────────────────────────

func _on_card_input(event: InputEvent, char_name: String) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_on_card_clicked(char_name)
	if mb.double_click:
		_on_confirm()


func _on_card_hover(char_name: String, entered: bool) -> void:
	if entered:
		_hovered = char_name
	elif _hovered == char_name:
		_hovered = ""
	_update_card_visuals()


func _on_card_clicked(char_name: String) -> void:
	if _confirmed or _get_team_taken().has(char_name):
		return
	_local_selected = char_name
	_update_card_visuals()


func _on_confirm() -> void:
	if _local_selected.is_empty() or _confirmed:
		return
	_confirmed = true
	_confirm_btn.text = "BEKLENİYOR..."
	_update_card_visuals()
	NetworkManager.request_select_character(_local_selected)


# ─────────────────────────────────────────────
#  Durum güncelleme
# ─────────────────────────────────────────────

func _refresh() -> void:
	if _cards.is_empty():
		return

	var selected_count: int = 0
	for pid: int in NetworkManager.players:
		if not (NetworkManager.players[pid].get("character", "") as String).is_empty():
			selected_count += 1
	var total: int = NetworkManager.players.size()

	_status_lbl.text = "%d / %d OYUNCU HAZIR" % [selected_count, total]
	_progress.value = float(selected_count) / float(maxi(total, 1))
	_refresh_roster()
	_update_card_visuals()


## Takım içinde alınan karakterler: karakter adı → oyuncu adı
func _get_team_taken() -> Dictionary:
	var local_team: int = NetworkManager.players.get(NetworkManager.get_local_id(), {}).get("team_id", -1)
	var taken: Dictionary = {}
	for pid: int in NetworkManager.players:
		var pdata: Dictionary = NetworkManager.players[pid]
		if pdata.get("team_id", -1) != local_team:
			continue
		var ch: String = pdata.get("character", "")
		if not ch.is_empty():
			taken[ch] = pdata.get("name", "???")
	return taken


func _refresh_roster() -> void:
	for child in _roster_row.get_children():
		child.queue_free()

	var local_id := NetworkManager.get_local_id()
	var local_team: int = NetworkManager.players.get(local_id, {}).get("team_id", -1)
	for pid: int in NetworkManager.players:
		var pdata: Dictionary = NetworkManager.players[pid]
		if pdata.get("team_id", -1) != local_team:
			continue
		var ch: String = pdata.get("character", "")
		var ch_color := _get_char_color(ch)

		var chip := PanelContainer.new()
		var style := _rounded_style(Color(1, 1, 1, 0.045), 8)
		style.content_margin_left   = 12
		style.content_margin_right  = 12
		style.content_margin_top    = 5
		style.content_margin_bottom = 5
		style.border_width_left = 3
		style.border_color = ch_color if not ch.is_empty() else Color(1, 1, 1, 0.12)
		chip.add_theme_stylebox_override("panel", style)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		chip.add_child(row)

		var player_name: String = pdata.get("name", "???")
		if pid == local_id:
			player_name += " (Sen)"
		row.add_child(_make_label(player_name, 12, COL_TEXT))
		if ch.is_empty():
			row.add_child(_make_label("seçiyor…", 11, COL_TEXT_DIM))
		else:
			row.add_child(_make_label(ch.to_upper(), 11, ch_color, _font_caps))
		_roster_row.add_child(chip)


func _update_card_visuals() -> void:
	var taken := _get_team_taken()
	var my_char: String = NetworkManager.players.get(NetworkManager.get_local_id(), {}).get("character", "")

	for c: Dictionary in _cards:
		var char_name: String = c["name"]
		var char_color: Color = c["color"]
		var panel: PanelContainer = c["panel"]
		var footer: PanelContainer = c["footer"]
		var footer_lbl: Label = c["footer_lbl"]
		var badge: PanelContainer = c["badge"]
		var badge_lbl: Label = c["badge_lbl"]

		var is_mine: bool        = (my_char == char_name)
		var is_pending: bool     = (_local_selected == char_name and not is_mine)
		var is_taken_other: bool = (taken.has(char_name) and not is_mine)
		var is_hover: bool       = (_hovered == char_name and not is_taken_other and not _confirmed)

		# Kart çerçevesi — kenar kalınlığı sabit (2px), içerik kaymasın diye sadece renk değişir
		var style := _rounded_style(COL_CARD_HOVER if is_hover else COL_CARD, CARD_RADIUS)
		style.set_border_width_all(2)
		style.set_content_margin_all(2)
		if is_mine:
			style.border_color = char_color
			style.shadow_color = Color(char_color, 0.45)
			style.shadow_size  = 18
		elif is_pending:
			style.border_color = Color(char_color, 0.85)
			style.shadow_color = Color(char_color, 0.25)
			style.shadow_size  = 12
		elif is_hover:
			style.border_color = Color(char_color, 0.4)
		else:
			style.border_color = Color(1, 1, 1, 0.06)
		panel.add_theme_stylebox_override("panel", style)

		# Alt şerit
		var footer_style := _rounded_style(Color(1, 1, 1, 0.03), 0)
		footer_style.corner_radius_bottom_left  = CARD_RADIUS - 2
		footer_style.corner_radius_bottom_right = CARD_RADIUS - 2
		if is_mine:
			footer_style.bg_color = char_color
			footer_lbl.text = "✓  KİLİTLENDİ"
			footer_lbl.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))
		elif is_pending:
			footer_style.bg_color = Color(char_color, 0.22)
			footer_lbl.text = "BEKLENİYOR..." if _confirmed else "SEÇİLDİ"
			footer_lbl.add_theme_color_override("font_color", char_color)
		elif is_taken_other:
			footer_lbl.text = "ALINDI"
			footer_lbl.add_theme_color_override("font_color", COL_TEXT_DIM)
		else:
			footer_lbl.text = "" if _confirmed else "SEÇ"
			footer_lbl.add_theme_color_override("font_color", char_color if is_hover else COL_TEXT_DIM)
		footer.add_theme_stylebox_override("panel", footer_style)

		# Rozet: başkası aldıysa onun adı
		badge.visible = is_taken_other
		if is_taken_other:
			var badge_style := _rounded_style(Color(0, 0, 0, 0.65), 10)
			badge_style.content_margin_left  = 8
			badge_style.content_margin_right = 8
			badge_style.content_margin_top    = 3
			badge_style.content_margin_bottom = 3
			badge.add_theme_stylebox_override("panel", badge_style)
			badge_lbl.text = String(taken[char_name]).to_upper()

		panel.modulate = Color(1, 1, 1, 0.4) if is_taken_other else Color.WHITE
		var selectable := not _confirmed and not is_taken_other
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if selectable else Control.CURSOR_ARROW

	# Onay butonu seçili karakterin rengini alır
	if _confirmed:
		_confirm_btn.disabled = true
	else:
		_confirm_btn.disabled = _local_selected.is_empty()
		_confirm_btn.text = "ONAYLA" if _local_selected.is_empty() else "%s İLE ONAYLA" % _local_selected.to_upper()
	_style_confirm_button(_get_char_color(_local_selected) if not _local_selected.is_empty() else Color(0.4, 0.42, 0.5))


# ─────────────────────────────────────────────
#  Stil yardımcıları
# ─────────────────────────────────────────────

func _get_char_color(char_name: String) -> Color:
	for c: Dictionary in CHARACTERS:
		if c["name"] == char_name:
			return c["color"]
	return COL_TEXT_DIM


func _rounded_style(bg: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


func _make_label(text: String, font_size: int, color: Color, font: Font = null) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	if font:
		lbl.add_theme_font_override("font", font)
	return lbl


func _make_bar(fill_color: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_stylebox_override("background", _rounded_style(COL_TRACK, height))
	bar.add_theme_stylebox_override("fill", _rounded_style(fill_color, height))
	return bar


func _style_confirm_button(accent: Color) -> void:
	var normal := _rounded_style(accent.darkened(0.15), 24)
	var hover  := _rounded_style(accent, 24)
	var pressed := _rounded_style(accent.darkened(0.3), 24)
	var disabled := _rounded_style(Color(1, 1, 1, 0.06), 24)
	disabled.border_color = Color(1, 1, 1, 0.1)
	disabled.set_border_width_all(1)
	hover.shadow_color = Color(accent, 0.4)
	hover.shadow_size = 12
	_confirm_btn.add_theme_stylebox_override("normal", normal)
	_confirm_btn.add_theme_stylebox_override("hover", hover)
	_confirm_btn.add_theme_stylebox_override("pressed", pressed)
	_confirm_btn.add_theme_stylebox_override("disabled", disabled)
	var text_col := Color(0.05, 0.05, 0.08) if accent.get_luminance() > 0.45 else Color.WHITE
	for key: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		_confirm_btn.add_theme_color_override(key, text_col)
	_confirm_btn.add_theme_color_override("font_disabled_color", COL_TEXT_DIM)


func _ignore_mouse_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse_recursive(child)

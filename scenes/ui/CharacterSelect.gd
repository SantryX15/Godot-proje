## CharacterSelect.gd
## Oyun başladıktan sonra karakter seçim ekranı.
## Her takım üyesi 5 karakterden birini seçer (takım içinde benzersiz).
## Tüm oyuncular seçimini tamamladığında GameManager oyunu başlatır.

extends Control

const CHARACTERS: Array[Dictionary] = [
	{"name": "Tank",     "color": Color(0.9,  0.35, 0.25), "stats": {"Can": 150.0, "Hız": 5.5,  "Hasar": 22.0,  "Menzil": 45.0}},
	{"name": "Visioner", "color": Color(0.25, 0.55, 1.0),  "stats": {"Can": 100.0, "Hız": 8.0,  "Hasar": 18.0,  "Menzil": 35.0}},
	{"name": "Runner",   "color": Color(0.25, 0.9,  0.35), "stats": {"Can": 75.0,  "Hız": 13.0, "Hasar": 11.0,  "Menzil": 25.0}},
	{"name": "Sniper",   "color": Color(0.95, 0.85, 0.15), "stats": {"Can": 80.0,  "Hız": 7.0,  "Hasar": 120.0, "Menzil": 130.0}},
	{"name": "Medic",    "color": Color(0.85, 0.35, 0.95), "stats": {"Can": 110.0, "Hız": 7.5,  "Hasar": 45.0,  "Menzil": 55.0}},
]

const STAT_MAX: Dictionary  = {"Can": 150.0, "Hız": 13.0, "Hasar": 120.0, "Menzil": 130.0}
const STAT_COLORS: Dictionary = {
	"Can":    Color(0.9, 0.3,  0.3),
	"Hız":    Color(0.3, 0.85, 0.3),
	"Hasar":  Color(0.95, 0.6, 0.1),
	"Menzil": Color(0.3, 0.6,  1.0),
}

var _local_selected: String = ""
var _confirmed: bool = false
var _char_panels: Array = []
var _confirm_btn: Button = null
var _status_lbl: Label = null


func _ready() -> void:
	NetworkManager.player_list_updated.connect(_refresh)
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := VBoxContainer.new()
	center.anchor_left   = 0.5
	center.anchor_right  = 0.5
	center.anchor_top    = 0.5
	center.anchor_bottom = 0.5
	center.offset_left   = -560.0
	center.offset_right  =  560.0
	center.offset_top    = -310.0
	center.offset_bottom =  310.0
	center.add_theme_constant_override("separation", 14)
	add_child(center)

	var title := Label.new()
	title.text = "KARAKTER SEÇ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	center.add_child(title)

	var local_id := NetworkManager.get_local_id()
	var local_data: Dictionary = NetworkManager.players.get(local_id, {})
	var team_id: int = local_data.get("team_id", -1)

	var team_lbl := Label.new()
	team_lbl.text = "Takımın: %s" % TeamManager.get_team_name(team_id)
	team_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	team_lbl.add_theme_font_size_override("font_size", 15)
	team_lbl.modulate = TeamManager.get_color(team_id)
	center.add_child(team_lbl)

	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 14)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(cards_row)

	for char_data: Dictionary in CHARACTERS:
		var panel := _build_card(char_data)
		_char_panels.append(panel)
		cards_row.add_child(panel)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Onayla"
	_confirm_btn.custom_minimum_size = Vector2(200, 46)
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm)
	var btn_wrap := CenterContainer.new()
	btn_wrap.add_child(_confirm_btn)
	center.add_child(btn_wrap)

	_status_lbl = Label.new()
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_font_size_override("font_size", 14)
	_status_lbl.modulate = Color(0.65, 0.65, 0.65)
	center.add_child(_status_lbl)


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result := _find_anim_player(child)
		if result:
			return result
	return null


func _build_card(char_data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(190, 340)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# ── 3D karakter önizlemesi ──────────────────
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(0, 165)
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.stretch = true
	vbox.add_child(svc)

	var sv := SubViewport.new()
	sv.size = Vector2i(190, 165)
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)

	var world := Node3D.new()
	sv.add_child(world)

	# Arka plan rengi (WorldEnvironment)
	var env_node := WorldEnvironment.new()
	var env_res  := Environment.new()
	env_res.background_mode    = Environment.BG_COLOR
	env_res.background_color   = Color(0.08, 0.08, 0.13, 1.0)
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color  = Color(0.25, 0.25, 0.32)
	env_res.ambient_light_energy = 0.6
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
	var ap := _find_anim_player(char_mesh)
	if ap:
		var candidates := ["mixamo_com", "mixamo.com", "Breathing Idle", "idle", "Idle"]
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

	# Karakterin rengiyle boyalı ana ışık
	var key_light := OmniLight3D.new()
	key_light.position    = Vector3(1.5, 3.0, 2.0)
	key_light.light_color  = char_data["color"]
	key_light.light_energy = 2.5
	key_light.omni_range   = 9.0
	world.add_child(key_light)

	# Dolgu ışığı (nötr beyaz)
	var fill_light := OmniLight3D.new()
	fill_light.position    = Vector3(-1.2, 2.0, 1.5)
	fill_light.light_energy = 1.0
	fill_light.omni_range   = 7.0
	world.add_child(fill_light)

	# Kamera — karakterin üst gövdesini gösterir
	var cam := Camera3D.new()
	cam.position         = Vector3(0.0, 1.3, 2.5)
	cam.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	world.add_child(cam)

	# ── İsim + Stat barları (kenarlara margin ile) ──
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left",  10)
	content_margin.add_theme_constant_override("margin_right", 10)
	content_margin.add_theme_constant_override("margin_top",    4)
	content_margin.add_theme_constant_override("margin_bottom", 0)
	vbox.add_child(content_margin)

	var content_vbox := VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 4)
	content_margin.add_child(content_vbox)

	var name_lbl := Label.new()
	name_lbl.text = (char_data["name"] as String).to_upper()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.modulate = char_data["color"]
	content_vbox.add_child(name_lbl)

	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 3)
	content_vbox.add_child(stats_box)

	for stat_name: String in ["Can", "Hız", "Hasar", "Menzil"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		stats_box.add_child(row)

		var stat_lbl := Label.new()
		stat_lbl.text = stat_name
		stat_lbl.add_theme_font_size_override("font_size", 10)
		stat_lbl.custom_minimum_size = Vector2(42, 0)
		stat_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stat_lbl.modulate = STAT_COLORS[stat_name]
		row.add_child(stat_lbl)

		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = (char_data["stats"] as Dictionary)[stat_name] / (STAT_MAX[stat_name] as float)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 11)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.modulate = STAT_COLORS[stat_name]
		row.add_child(bar)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var btn := Button.new()
	btn.name = "SelectBtn"
	btn.text = "Seç"
	btn.pressed.connect(_on_card_clicked.bind(char_data["name"]))
	vbox.add_child(btn)

	var taken_lbl := Label.new()
	taken_lbl.name = "TakenLabel"
	taken_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	taken_lbl.add_theme_font_size_override("font_size", 11)
	taken_lbl.modulate = Color(0.55, 0.55, 0.55)
	taken_lbl.text = ""
	taken_lbl.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(taken_lbl)

	return panel


func _on_card_clicked(char_name: String) -> void:
	if _confirmed:
		return
	_local_selected = char_name
	_update_card_visuals()
	_confirm_btn.disabled = false


func _on_confirm() -> void:
	if _local_selected.is_empty() or _confirmed:
		return
	_confirmed = true
	_confirm_btn.disabled = true
	_confirm_btn.text = "Bekleniyor..."
	NetworkManager.request_select_character(_local_selected)


func _refresh() -> void:
	if _char_panels.is_empty():
		return

	var local_id := NetworkManager.get_local_id()
	var local_team: int = NetworkManager.players.get(local_id, {}).get("team_id", -1)

	# Takım içinde alınan karakterler
	var taken: Dictionary = {}
	for pid: int in NetworkManager.players:
		var pdata: Dictionary = NetworkManager.players[pid]
		if pdata.get("team_id", -1) != local_team:
			continue
		var ch: String = pdata.get("character", "")
		if not ch.is_empty():
			taken[ch] = pdata.get("name", "???")

	# Kaç kişi seçimini tamamladı
	var selected_count: int = 0
	for pid: int in NetworkManager.players:
		if not (NetworkManager.players[pid].get("character", "") as String).is_empty():
			selected_count += 1

	_status_lbl.text = "%d / %d oyuncu seçimini tamamladı" % [selected_count, NetworkManager.players.size()]
	_update_card_visuals_with_taken(taken)


func _update_card_visuals() -> void:
	var local_id := NetworkManager.get_local_id()
	var local_team: int = NetworkManager.players.get(local_id, {}).get("team_id", -1)
	var taken: Dictionary = {}
	for pid: int in NetworkManager.players:
		var pdata: Dictionary = NetworkManager.players[pid]
		if pdata.get("team_id", -1) != local_team:
			continue
		var ch: String = pdata.get("character", "")
		if not ch.is_empty():
			taken[ch] = pdata.get("name", "???")
	_update_card_visuals_with_taken(taken)


func _update_card_visuals_with_taken(taken: Dictionary) -> void:
	var local_id := NetworkManager.get_local_id()
	var my_char: String = NetworkManager.players.get(local_id, {}).get("character", "")

	for i in range(_char_panels.size()):
		var char_name: String = CHARACTERS[i]["name"]
		var char_color: Color = CHARACTERS[i]["color"]
		var panel: PanelContainer = _char_panels[i]
		var vbox: VBoxContainer = panel.get_child(0)
		var btn: Button = vbox.get_node("SelectBtn")
		var taken_lbl: Label = vbox.get_node("TakenLabel")

		var is_mine: bool        = (my_char == char_name)
		var is_pending: bool     = (_local_selected == char_name and not _confirmed)
		var is_taken_other: bool = (taken.has(char_name) and not is_mine)

		# Panel stili
		var style := StyleBoxFlat.new()
		if is_mine:
			style.bg_color = char_color * Color(1, 1, 1, 0.22)
			style.border_width_left   = 3
			style.border_width_right  = 3
			style.border_width_top    = 3
			style.border_width_bottom = 3
			style.border_color = char_color
		elif is_pending:
			style.bg_color = char_color * Color(1, 1, 1, 0.1)
			style.border_width_left   = 2
			style.border_width_right  = 2
			style.border_width_top    = 2
			style.border_width_bottom = 2
			style.border_color = char_color * Color(1, 1, 1, 0.55)
		elif is_taken_other:
			style.bg_color = Color(0.07, 0.07, 0.1, 1.0)
		else:
			style.bg_color = Color(0.12, 0.12, 0.18, 1.0)
		panel.add_theme_stylebox_override("panel", style)

		# Buton durumu
		if is_mine:
			btn.text     = "Seçildi ✓"
			btn.disabled = true
		elif is_taken_other:
			btn.text     = "Alındı"
			btn.disabled = true
		elif _confirmed:
			btn.text     = "Seç"
			btn.disabled = true
		else:
			btn.text     = "Seç"
			btn.disabled = false

		# Kimin aldığı etiketi
		if is_taken_other:
			taken_lbl.text = taken[char_name]
		elif is_mine:
			taken_lbl.text = "Sen seçtin"
		else:
			taken_lbl.text = ""

		# Başkasının aldığı kartları soluklaştır
		panel.modulate = Color(0.5, 0.5, 0.5) if is_taken_other else Color.WHITE

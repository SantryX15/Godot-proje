## Lobby.gd
## Wolfteam tarzı lobi: 4 tıklanabilir takım paneli.

extends Control

@onready var title_label:    Label         = $Margin/VBox/Title
@onready var team_container: HBoxContainer = $Margin/VBox/TeamContainer
@onready var spectator_list: HBoxContainer = $Margin/VBox/SpectatorSection/SpectatorList
@onready var ready_btn:      Button        = $Margin/VBox/BottomBar/ReadyBtn
@onready var start_btn:      Button        = $Margin/VBox/BottomBar/StartBtn
@onready var status_label:   Label         = $Margin/VBox/BottomBar/StatusLabel

var is_ready: bool = false
var _team_panels:       Array = []   # PanelContainer × 4
var _team_player_lists: Array = []   # VBoxContainer × 4


func _ready() -> void:
	NetworkManager.player_list_updated.connect(_refresh_player_list)
	NetworkManager.host_migrated.connect(_on_host_migrated)
	GameManager.game_started.connect(_on_game_started)

	start_btn.visible = NetworkManager.is_host()
	_setup_team_panels()
	_refresh_player_list()
	title_label.text = "Lobi  —  %s  |  Kod: %s" % [NetworkManager.room_name, RoomManager.room_code]


func _setup_team_panels() -> void:
	for i in range(4):
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(_on_panel_input.bind(i))

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 6)
		vbox.mouse_filter = Control.MOUSE_FILTER_PASS
		panel.add_child(vbox)

		# Takım başlık alanı (renkli arka plan)
		var header := PanelContainer.new()
		header.mouse_filter = Control.MOUSE_FILTER_PASS
		var header_style := StyleBoxFlat.new()
		header_style.bg_color = TeamManager.get_color(i) * Color(1.0, 1.0, 1.0, 0.3)
		header_style.set_content_margin_all(8.0)
		header.add_theme_stylebox_override("panel", header_style)
		vbox.add_child(header)

		var team_label := Label.new()
		team_label.text = TeamManager.get_team_name(i).to_upper()
		team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		team_label.add_theme_font_size_override("font_size", 15)
		team_label.modulate = TeamManager.get_color(i)
		header.add_child(team_label)

		vbox.add_child(HSeparator.new())

		# Oyuncu listesi
		var player_list := VBoxContainer.new()
		player_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		player_list.add_theme_constant_override("separation", 4)
		player_list.mouse_filter = Control.MOUSE_FILTER_PASS
		vbox.add_child(player_list)

		_team_panels.append(panel)
		_team_player_lists.append(player_list)
		team_container.add_child(panel)

		_update_panel_style(i, false)


func _update_panel_style(team_id: int, is_selected: bool) -> void:
	if team_id < 0 or team_id >= _team_panels.size():
		return
	var style := StyleBoxFlat.new()
	if is_selected:
		style.bg_color = TeamManager.get_color(team_id) * Color(1.0, 1.0, 1.0, 0.15)
		style.border_width_left   = 3
		style.border_width_right  = 3
		style.border_width_top    = 3
		style.border_width_bottom = 3
		style.border_color = TeamManager.get_color(team_id)
	else:
		style.bg_color = Color(0.1, 0.1, 0.15, 1.0)
	_team_panels[team_id].add_theme_stylebox_override("panel", style)


func _on_panel_input(event: InputEvent, team_id: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		NetworkManager.request_change_team(team_id)


func _refresh_player_list() -> void:
	if _team_player_lists.is_empty():
		return

	for list in _team_player_lists:
		for child in list.get_children():
			child.queue_free()

	var local_id := NetworkManager.get_local_id()
	var local_team: int = NetworkManager.players.get(local_id, {}).get("team_id", -1)

	for child in spectator_list.get_children():
		child.queue_free()

	for peer_id in NetworkManager.players:
		var data: Dictionary = NetworkManager.players[peer_id]
		var team_id: int = data.get("team_id", -1)
		var ready_flag: bool = data.get("is_ready", false)
		var is_me: bool = (int(peer_id) == local_id)

		if team_id < 0 or team_id >= 4:
			# Takım seçmemiş → spectator
			var slbl := Label.new()
			slbl.text = ("▶ " if is_me else "") + data.get("name", "???")
			slbl.add_theme_font_size_override("font_size", 12)
			slbl.modulate = Color(0.8, 0.8, 0.8) if not is_me else Color.WHITE
			spectator_list.add_child(slbl)
			continue

		var lbl := Label.new()
		var prefix: String = "▶ " if is_me else "    "
		var suffix: String = "  ✓" if ready_flag else ""
		lbl.text = "%s%s%s" % [prefix, data.get("name", "???"), suffix]
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.modulate = TeamManager.get_color(team_id) if is_me else Color.WHITE
		_team_player_lists[team_id].add_child(lbl)

	for i in range(4):
		_update_panel_style(i, i == local_team)

	# Başlat butonu: sadece host, tüm oyuncular hazırsa ve takımlar dengeli ise aktif
	if NetworkManager.is_host():
		var all_ready := true
		for p in NetworkManager.players.values():
			if not p.get("is_ready", false):
				all_ready = false
				break
		var balanced := NetworkManager._are_teams_balanced()
		start_btn.disabled = not all_ready or not balanced
		if not balanced:
			status_label.text = "En az 2 takımda eşit oyuncu gerekli"
			status_label.modulate = Color(1.0, 0.5, 0.2)
		elif not all_ready:
			status_label.text = "Tüm oyuncular hazır değil"
			status_label.modulate = Color(0.8, 0.8, 0.8)
		else:
			status_label.text = ""


func _on_ready_btn_pressed() -> void:
	is_ready = not is_ready
	ready_btn.text = "Hazır DEĞİL" if is_ready else "Hazır"
	NetworkManager.set_ready(is_ready)


func _on_start_btn_pressed() -> void:
	if NetworkManager.is_host():
		GameManager.start_game()


func _on_game_started() -> void:
	pass  # GameManager sahne geçişini halleder


func _on_host_migrated() -> void:
	start_btn.visible = NetworkManager.is_host()
	title_label.text = "Lobi  —  %s  |  Kod: %s" % [NetworkManager.room_name, RoomManager.room_code]
	_refresh_player_list()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	NetworkManager.disconnect_all()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")

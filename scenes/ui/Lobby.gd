## Lobby.gd
## Lobi: Takım seçimi, hazır durumu ve oyuncu listesi.

extends Control

@onready var player_list: VBoxContainer = $HSplit/PlayerList/VBoxContainer
@onready var team_buttons: Array = [
	$HSplit/TeamPanel/VBox/Team0Btn,
	$HSplit/TeamPanel/VBox/Team1Btn,
	$HSplit/TeamPanel/VBox/Team2Btn,
	$HSplit/TeamPanel/VBox/Team3Btn,
]
@onready var ready_btn: Button = $HSplit/TeamPanel/VBox/ReadyBtn
@onready var start_btn: Button = $HSplit/TeamPanel/VBox/StartBtn
@onready var status_label: Label = $HSplit/TeamPanel/VBox/StatusLabel

var is_ready: bool = false


func _ready() -> void:
	NetworkManager.player_list_updated.connect(_refresh_player_list)
	GameManager.game_started.connect(_on_game_started)

	start_btn.visible = NetworkManager.is_host()
	_refresh_player_list()

	for i in range(team_buttons.size()):
		team_buttons[i].pressed.connect(_on_team_selected.bind(i))
		team_buttons[i].text = TeamManager.get_team_name(i)
		team_buttons[i].modulate = TeamManager.get_color(i)


func _refresh_player_list() -> void:
	for child in player_list.get_children():
		child.queue_free()

	for peer_id in NetworkManager.players:
		var data: Dictionary = NetworkManager.players[peer_id]
		var team_id: int = data.get("team_id", -1)
		var ready: bool = data.get("is_ready", false)
		var label := Label.new()
		var team_str := TeamManager.get_team_name(team_id) if team_id >= 0 else "Takım yok"
		label.text = "%s — %s %s" % [
			data.get("name", "???"),
			team_str,
			"✓" if ready else ""
		]
		if team_id >= 0:
			label.modulate = TeamManager.get_color(team_id)
		player_list.add_child(label)

	# Başlat butonu: tüm oyuncular hazırsa göster (sadece host)
	if NetworkManager.is_host():
		var all_ready := true
		for p in NetworkManager.players.values():
			if not p.get("is_ready", false):
				all_ready = false
				break
		start_btn.disabled = not all_ready


func _on_team_selected(team_id: int) -> void:
	NetworkManager.request_change_team(team_id)


func _on_ready_btn_pressed() -> void:
	is_ready = not is_ready
	ready_btn.text = "Hazır DEĞİL" if is_ready else "Hazır"
	NetworkManager.set_ready(is_ready)


func _on_start_btn_pressed() -> void:
	if NetworkManager.is_host():
		GameManager.start_game()


func _on_game_started() -> void:
	pass  # GameManager sahne geçişini halleder


func _on_back_pressed() -> void:
	NetworkManager.disconnect_all()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")

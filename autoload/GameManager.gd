## GameManager.gd
## Oyun durumunu, sahne geçişlerini ve spawn'ı yönetir.

extends Node

signal game_started
signal game_ended(winning_team: int)
signal local_player_spawned(player: Node)

enum State { MENU, LOBBY, IN_GAME, ENDED }

var state: State = State.MENU
var player_scene: PackedScene = null
var map_scene: PackedScene = null

## peer_id -> Player node referansı
var active_players: Dictionary = {}


func _ready() -> void:
	player_scene = preload("res://scenes/player/Player.tscn")
	map_scene = preload("res://scenes/world/Map.tscn")
	TeamManager.team_won.connect(_on_team_won)


# ─────────────────────────────────────────────
# Oyun Başlatma (sadece sunucu çağırır)
# ─────────────────────────────────────────────

func start_game() -> void:
	if not NetworkManager.is_host():
		return
	TeamManager.reset()
	_start_game_rpc.rpc()


@rpc("authority", "call_local", "reliable")
func _start_game_rpc() -> void:
	state = State.IN_GAME
	# Haritayı yükle
	get_tree().change_scene_to_packed(map_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	_spawn_local_player()
	emit_signal("game_started")


func _spawn_local_player() -> void:
	var local_id := NetworkManager.get_local_id()
	var player_data: Dictionary = NetworkManager.players.get(local_id, {})
	var team_id: int = player_data.get("team_id", 0)
	var spawn_pos := TeamManager.get_spawn_position(team_id)

	var player: CharacterBody2D = player_scene.instantiate()
	player.name = "Player_%d" % local_id
	player.set_multiplayer_authority(local_id)
	get_tree().current_scene.add_child(player)
	player.global_position = spawn_pos
	player.initialize(local_id, team_id)

	active_players[local_id] = player
	emit_signal("local_player_spawned", player)
	# Diğerlerine bildir
	_notify_player_spawned.rpc(local_id, team_id, spawn_pos)


@rpc("any_peer", "call_local", "reliable")
func _notify_player_spawned(peer_id: int, team_id: int, pos: Vector2) -> void:
	# Kendi spawn'ımızı zaten yaptık, başkalarını oluştur
	if peer_id == NetworkManager.get_local_id():
		return
	if active_players.has(peer_id):
		return
	var player: CharacterBody2D = player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)
	get_tree().current_scene.add_child(player)
	player.global_position = pos
	player.initialize(peer_id, team_id)
	active_players[peer_id] = player


# ─────────────────────────────────────────────
# Ölüm / Yeniden Doğma
# ─────────────────────────────────────────────

func handle_player_death(dead_peer_id: int, killer_peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	var killer_data: Dictionary = NetworkManager.players.get(killer_peer_id, {})
	var killing_team: int = killer_data.get("team_id", -1)
	if killing_team >= 0:
		TeamManager.add_kill(killing_team)
	# 3 saniye bekle, sonra server tarafında respawn et (RPC yok — player.respawn() içinde yayar)
	_schedule_respawn(dead_peer_id)


func _schedule_respawn(dead_peer_id: int) -> void:
	await get_tree().create_timer(3.0).timeout
	var player: Node = active_players.get(dead_peer_id)
	if player == null:
		return
	var player_data: Dictionary = NetworkManager.players.get(dead_peer_id, {})
	var team_id: int = player_data.get("team_id", 0)
	var spawn_pos := TeamManager.get_spawn_position(team_id)
	# player.respawn() içi _apply_respawn.rpc() çağırır → tüm clientlara yayılır
	player.respawn(spawn_pos)


# ─────────────────────────────────────────────
# Oyun Sonu
# ─────────────────────────────────────────────

func _on_team_won(team_id: int) -> void:
	if not NetworkManager.is_host():
		return
	state = State.ENDED
	_end_game_rpc.rpc(team_id)


@rpc("authority", "call_local", "reliable")
func _end_game_rpc(winning_team: int) -> void:
	state = State.ENDED
	emit_signal("game_ended", winning_team)


func return_to_menu() -> void:
	active_players.clear()
	state = State.MENU
	NetworkManager.disconnect_all()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")

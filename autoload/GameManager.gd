## GameManager.gd
## Oyun durumunu, sahne geçişlerini, spawn'ı ve kart/kapı mekaniğini yönetir. (3D)

extends Node

signal game_started
signal game_ended(winning_team: int)
signal local_player_spawned(player: Node)
signal card_picked_up(carrier_peer_id: int, carrier_pos: Vector3, carrier_team_id: int)
signal card_dropped(drop_pos: Vector3, carrier_team_id: int)
signal kill_happened(killer_peer_id: int, victim_peer_id: int)

enum State { MENU, LOBBY, IN_GAME, ENDED }

var state: State = State.MENU
var player_scene: PackedScene = null
var map_scene: PackedScene = null
var card_scene: PackedScene = null
var door_scene: PackedScene = null

## peer_id -> Player node referansı
var active_players: Dictionary = {}

## Kart durumu
var card_instance: Node = null
var door_instance: Node = null
var card_carrier_peer_id: int = -1  # -1 = kart yerde

## Kişisel istatistikler: peer_id -> {kills, deaths}
var player_stats: Dictionary = {}

## Migration: restore sırasında kullanılacak geçici pozisyonlar
var _pending_card_pos: Vector3 = Vector3.ZERO
var _pending_door_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	player_scene = preload("res://scenes/player/Player.tscn")
	map_scene = preload("res://scenes/world/Map.tscn")
	card_scene = preload("res://scenes/world/Card.tscn")
	door_scene = preload("res://scenes/world/Door.tscn")
	TeamManager.team_won.connect(_on_team_won)


# ─────────────────────────────────────────────
# Oyun Başlatma
# ─────────────────────────────────────────────

func start_game() -> void:
	if not NetworkManager.is_host():
		return
	TeamManager.reset()
	_start_game_rpc.rpc()


@rpc("authority", "call_local", "reliable")
func _start_game_rpc() -> void:
	state = State.IN_GAME
	card_carrier_peer_id = -1
	card_instance = null
	door_instance = null
	player_stats.clear()
	get_tree().change_scene_to_packed(map_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	_spawn_local_player()
	if NetworkManager.is_host():
		_spawn_card_and_door()
	emit_signal("game_started")


func _spawn_local_player() -> void:
	var local_id := NetworkManager.get_local_id()
	var player_data: Dictionary = NetworkManager.players.get(local_id, {})
	var team_id: int = player_data.get("team_id", 0)
	var spawn_pos: Vector3 = TeamManager.get_spawn_position(team_id)

	var player: CharacterBody3D = player_scene.instantiate()
	player.name = "Player_%d" % local_id
	player.set_multiplayer_authority(local_id)
	get_tree().current_scene.add_child(player)
	player.global_position = spawn_pos
	player.initialize(local_id, team_id)

	active_players[local_id] = player
	emit_signal("local_player_spawned", player)
	_notify_player_spawned.rpc(local_id, team_id, spawn_pos)
	# Mevcut oyuncuları talep et (migration / geç katılım için)
	if not NetworkManager.is_host():
		_request_active_players.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _notify_player_spawned(peer_id: int, team_id: int, pos: Vector3) -> void:
	if peer_id == NetworkManager.get_local_id():
		return
	if active_players.has(peer_id):
		return
	var player: CharacterBody3D = player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)
	get_tree().current_scene.add_child(player)
	player.global_position = pos
	player.initialize(peer_id, team_id)
	active_players[peer_id] = player


## Client, bağlandıktan sonra host'tan mevcut aktif oyuncuları talep eder
@rpc("any_peer", "reliable")
func _request_active_players() -> void:
	if not NetworkManager.is_host():
		return
	var requester := multiplayer.get_remote_sender_id()
	for pid in active_players:
		var p: Node = active_players[pid]
		if not is_instance_valid(p):
			continue
		var pteam: int = NetworkManager.players.get(pid, {}).get("team_id", 0)
		_notify_player_spawned.rpc_id(requester, pid, pteam, p.global_position)


# ─────────────────────────────────────────────
# Kart + Kapı Spawn
# ─────────────────────────────────────────────

func _spawn_card_and_door() -> void:
	var card_pos := Vector3(randf_range(-10.0, 10.0), 0.0, randf_range(-10.0, 10.0))
	var corners: Array[Vector3] = [
		Vector3(-47.0, 0.0, -42.0),
		Vector3( 47.0, 0.0, -42.0),
		Vector3(-47.0, 0.0,  42.0),
		Vector3( 47.0, 0.0,  42.0),
	]
	var door_pos: Vector3 = corners[randi() % corners.size()]
	_spawn_objects_rpc.rpc(card_pos, door_pos)


@rpc("authority", "call_local", "reliable")
func _spawn_objects_rpc(card_pos: Vector3, door_pos: Vector3) -> void:
	var card: Node = card_scene.instantiate()
	get_tree().current_scene.add_child(card)
	card.global_position = card_pos
	card_instance = card

	var door: Node = door_scene.instantiate()
	get_tree().current_scene.add_child(door)
	door.global_position = door_pos
	door_instance = door


# ─────────────────────────────────────────────
# Kart Alınması
# ─────────────────────────────────────────────

@rpc("any_peer", "reliable")
func request_card_pickup(picker_peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	if card_carrier_peer_id != -1:
		return
	handle_card_pickup(picker_peer_id)


func handle_card_pickup(picker_peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	if card_carrier_peer_id != -1:
		return
	var team_id: int = NetworkManager.players.get(picker_peer_id, {}).get("team_id", -1)
	var player: Node = active_players.get(picker_peer_id)
	var pos: Vector3 = player.global_position if player else Vector3.ZERO
	_apply_card_pickup_rpc.rpc(picker_peer_id, pos, team_id)


@rpc("authority", "call_local", "reliable")
func _apply_card_pickup_rpc(carrier_peer_id: int, carrier_pos: Vector3, carrier_team_id: int) -> void:
	card_carrier_peer_id = carrier_peer_id
	if card_instance and is_instance_valid(card_instance):
		card_instance.hide()
	var player: Node = active_players.get(carrier_peer_id)
	if player:
		player.pick_up_card()
	emit_signal("card_picked_up", carrier_peer_id, carrier_pos, carrier_team_id)


# ─────────────────────────────────────────────
# Kart Düşürülmesi
# ─────────────────────────────────────────────

func handle_card_drop(drop_pos: Vector3) -> void:
	if not NetworkManager.is_host():
		return
	var carrier_team: int = NetworkManager.players.get(card_carrier_peer_id, {}).get("team_id", -1)
	_apply_card_drop_rpc.rpc(drop_pos, carrier_team)


@rpc("authority", "call_local", "reliable")
func _apply_card_drop_rpc(drop_pos: Vector3, carrier_team_id: int) -> void:
	card_carrier_peer_id = -1
	for player in active_players.values():
		if is_instance_valid(player) and player.has_card:
			player.drop_card()
	if card_instance and is_instance_valid(card_instance):
		card_instance.global_position = drop_pos
		card_instance.show()
	emit_signal("card_dropped", drop_pos, carrier_team_id)


# ─────────────────────────────────────────────
# Kart Teslimatı
# ─────────────────────────────────────────────

@rpc("any_peer", "reliable")
func request_card_delivery(carrier_peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	if card_carrier_peer_id != carrier_peer_id:
		return
	handle_card_delivered(carrier_peer_id)


func handle_card_delivered(carrier_peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	var team_id: int = NetworkManager.players.get(carrier_peer_id, {}).get("team_id", -1)
	state = State.ENDED
	_end_game_rpc.rpc(team_id)


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

	_announce_kill_rpc.rpc(killer_peer_id, dead_peer_id)

	if card_carrier_peer_id == dead_peer_id:
		var dead_player: Node = active_players.get(dead_peer_id)
		var drop_pos: Vector3 = dead_player.global_position if dead_player else Vector3.ZERO
		handle_card_drop(drop_pos)

	_schedule_respawn(dead_peer_id)


@rpc("authority", "call_local", "reliable")
func _announce_kill_rpc(killer_peer_id: int, victim_peer_id: int) -> void:
	if not player_stats.has(killer_peer_id):
		player_stats[killer_peer_id] = {"kills": 0, "deaths": 0}
	if not player_stats.has(victim_peer_id):
		player_stats[victim_peer_id] = {"kills": 0, "deaths": 0}
	player_stats[killer_peer_id]["kills"] += 1
	player_stats[victim_peer_id]["deaths"] += 1
	emit_signal("kill_happened", killer_peer_id, victim_peer_id)


func _schedule_respawn(dead_peer_id: int) -> void:
	await get_tree().create_timer(3.0).timeout
	var player: Node = active_players.get(dead_peer_id)
	if player == null:
		return
	var player_data: Dictionary = NetworkManager.players.get(dead_peer_id, {})
	var team_id: int = player_data.get("team_id", 0)
	var spawn_pos: Vector3 = TeamManager.get_spawn_position(team_id)
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


# ─────────────────────────────────────────────
# Oyuncu Bağlantı Kesilmesi (host tarafından çağrılır)
# ─────────────────────────────────────────────

func on_player_disconnected(peer_id: int) -> void:
	# Kart taşıyıcıysa kartı düşür
	if card_carrier_peer_id == peer_id:
		var player: Node = active_players.get(peer_id)
		var drop_pos: Vector3 = player.global_position if player and is_instance_valid(player) else Vector3.ZERO
		handle_card_drop(drop_pos)
	# Player node'unu temizle
	var p: Node = active_players.get(peer_id)
	if p and is_instance_valid(p):
		p.queue_free()
	active_players.erase(peer_id)
	_check_last_team_standing()


func _check_last_team_standing() -> void:
	if not NetworkManager.is_host():
		return
	if state != State.IN_GAME:
		return
	var active_teams: Dictionary = {}
	for pid in NetworkManager.players:
		var tid: int = NetworkManager.players[pid].get("team_id", -1)
		if tid >= 0:
			active_teams[tid] = true
	if active_teams.size() == 1:
		state = State.ENDED
		_end_game_rpc.rpc(active_teams.keys()[0])


# ─────────────────────────────────────────────
# Host Migration
# ─────────────────────────────────────────────

## Mevcut oyun durumunun anlık görüntüsü (migration öncesi kaydedilir)
func get_migration_state() -> Dictionary:
	var gstate := { "game_state": state }
	if state != State.IN_GAME:
		return gstate
	# Kart pozisyonu: taşıyıcıda mı yoksa yerde mi?
	var card_pos := Vector3.ZERO
	if card_carrier_peer_id != -1:
		var carrier: Node = active_players.get(card_carrier_peer_id)
		if carrier and is_instance_valid(carrier):
			card_pos = carrier.global_position
	elif card_instance and is_instance_valid(card_instance):
		card_pos = card_instance.global_position
	var door_pos := Vector3.ZERO
	if door_instance and is_instance_valid(door_instance):
		door_pos = door_instance.global_position
	gstate["scores"]   = TeamManager.scores.duplicate()
	gstate["card_pos"] = card_pos
	gstate["door_pos"] = door_pos
	return gstate


## Migration sonrası oyunu geri yükle (yeni host + yeniden bağlanan clientlar)
func restore_from_migration(mig: Dictionary) -> void:
	# Skorları geri yükle
	var saved_scores: Dictionary = mig.get("scores", {})
	for tid in saved_scores:
		TeamManager.scores[tid] = int(saved_scores[tid])
	_pending_card_pos = mig.get("card_pos", Vector3.ZERO)
	_pending_door_pos = mig.get("door_pos", Vector3.ZERO)
	# Oyun durumunu sıfırla
	state = State.IN_GAME
	card_carrier_peer_id = -1
	card_instance = null
	door_instance = null
	for p in active_players.values():
		if is_instance_valid(p):
			p.queue_free()
	active_players.clear()
	# Haritayı yeniden yükle
	get_tree().change_scene_to_packed(map_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	_spawn_local_player()
	if NetworkManager.is_host():
		# Kart ve kapıyı kaydedilen pozisyona spawn et
		_spawn_objects_rpc.rpc(_pending_card_pos, _pending_door_pos)
	emit_signal("game_started")


func return_to_menu() -> void:
	active_players.clear()
	player_stats.clear()
	card_instance = null
	door_instance = null
	card_carrier_peer_id = -1
	state = State.MENU
	NetworkManager.disconnect_all()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")

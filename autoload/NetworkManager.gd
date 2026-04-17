## NetworkManager.gd
## Tüm ağ bağlantısı, lobby ve oyuncu senkronizasyonu işlemlerini yönetir.

extends Node

signal server_created
signal joined_server
signal connection_failed
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal player_list_updated
signal kicked(reason: String)

const PORT := 7777
const MAX_PLAYERS := 20  # 4 takım × 5 oyuncu

## peer_id -> { name, team_id, is_ready }
var players: Dictionary = {}
var local_player_name: String = ""
var room_name: String = ""
var _room_password: String = ""
var _pending_password: String = ""


# ─────────────────────────────────────────────
# Sunucu / İstemci Kurulum
# ─────────────────────────────────────────────

func create_server(player_name: String, p_room_name: String = "", p_password: String = "") -> void:
	local_player_name = player_name
	room_name         = p_room_name
	_room_password    = p_password
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		push_error("Sunucu oluşturulamadı: %s" % err)
		return
	multiplayer.multiplayer_peer = peer
	_connect_multiplayer_signals()
	# Host kendini ekle
	players[1] = { "name": local_player_name, "team_id": -1, "is_ready": false }
	RoomManager.create_room(p_room_name, p_password)
	emit_signal("server_created")
	emit_signal("player_list_updated")


func join_server(address: String, player_name: String, p_password: String = "") -> void:
	local_player_name  = player_name
	_pending_password  = p_password
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		push_error("Bağlantı hatası: %s" % err)
		emit_signal("connection_failed")
		return
	multiplayer.multiplayer_peer = peer
	_connect_multiplayer_signals()


func disconnect_all() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	room_name      = ""
	_room_password = ""
	_pending_password = ""
	RoomManager.stop_hosting()
	RoomManager.stop_listening()


# ─────────────────────────────────────────────
# Sinyal Bağlantıları
# ─────────────────────────────────────────────

func _connect_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)


func _on_peer_connected(id: int) -> void:
	emit_signal("player_connected", id)


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	emit_signal("player_disconnected", id)
	emit_signal("player_list_updated")
	if multiplayer.is_server():
		_broadcast_player_list()


func _on_connected_to_server() -> void:
	# joined_server emit etmiyoruz — host _accept_player RPC'si ile onaylayacak
	register_player.rpc_id(1, multiplayer.get_unique_id(), local_player_name, _pending_password)


func _on_connection_failed() -> void:
	emit_signal("connection_failed")


# ─────────────────────────────────────────────
# RPC: Oyuncu Kaydı
# ─────────────────────────────────────────────

@rpc("any_peer", "reliable")
func register_player(peer_id: int, player_name: String, password: String) -> void:
	if not multiplayer.is_server():
		return
	# Şifre kontrolü
	if not _room_password.is_empty() and password != _room_password:
		_reject_player.rpc_id(peer_id, "Yanlış şifre!")
		return
	players[peer_id] = { "name": player_name, "team_id": -1, "is_ready": false }
	# Yeni oyuncuya mevcut listeyi gönder, ardından kabul bildir
	receive_player_list.rpc_id(peer_id, players)
	_accept_player.rpc_id(peer_id)
	# Diğer herkese güncel listeyi gönder
	_broadcast_player_list()
	emit_signal("player_list_updated")


func _broadcast_player_list() -> void:
	receive_player_list.rpc(players)


@rpc("authority", "reliable")
func receive_player_list(player_list: Dictionary) -> void:
	players = player_list
	emit_signal("player_list_updated")


@rpc("authority", "reliable")
func _accept_player() -> void:
	emit_signal("joined_server")


@rpc("authority", "reliable")
func _reject_player(reason: String) -> void:
	emit_signal("kicked", reason)
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()


# ─────────────────────────────────────────────
# RPC: Takım Değiştir
# ─────────────────────────────────────────────

func request_change_team(team_id: int) -> void:
	var my_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_change_team(my_id, team_id)
	else:
		_change_team.rpc_id(1, my_id, team_id)


@rpc("any_peer", "reliable")
func _change_team(peer_id: int, team_id: int) -> void:
	if not multiplayer.is_server():
		return
	if players.has(peer_id):
		players[peer_id]["team_id"] = team_id
		_broadcast_player_list()
		emit_signal("player_list_updated")


# ─────────────────────────────────────────────
# RPC: Hazır Durumu
# ─────────────────────────────────────────────

func set_ready(is_ready: bool) -> void:
	var my_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_set_ready_rpc(my_id, is_ready)
	else:
		_set_ready_rpc.rpc_id(1, my_id, is_ready)


@rpc("any_peer", "reliable")
func _set_ready_rpc(peer_id: int, is_ready: bool) -> void:
	if not multiplayer.is_server():
		return
	if players.has(peer_id):
		players[peer_id]["is_ready"] = is_ready
		_broadcast_player_list()
		emit_signal("player_list_updated")
		_check_all_ready()


func _check_all_ready() -> void:
	if players.size() < 2:
		return
	for p in players.values():
		if not p["is_ready"]:
			return
	GameManager.start_game()


# ─────────────────────────────────────────────
# Yardımcı
# ─────────────────────────────────────────────

func get_local_id() -> int:
	return multiplayer.get_unique_id()


func is_host() -> bool:
	return multiplayer.is_server()


func get_player_count() -> int:
	return players.size()

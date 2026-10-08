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
signal host_migrated  # Yeni host seçildi (lobby durumunda UI güncellemek için)

const PORT := 7777
const MAX_PLAYERS := 20  # 4 takım × 5 oyuncu

## peer_id -> { name, team_id, is_ready }
var players: Dictionary = {}
var local_player_name: String = ""
var room_name: String = ""
var _room_password: String = ""
var _pending_password: String = ""

## Migration
var _saved_team_id: int = -1          # Kendi takımımız, migration boyunca korunur
var _is_migrating: bool = false        # Migration sürecinde mi?
var _pending_migration_state: Dictionary = {}  # Yeni host: bağlanan clientlara gönderilecek
var _migration_players: Dictionary = {}        # Eski player listesi (peer_id → data)
var _local_id_cache: int = 0           # get_unique_id() cache'i — peer kapandıktan sonra da kullanılabilir


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
	_local_id_cache = 1  # Host her zaman 1
	_connect_multiplayer_signals()
	# Eski (migration öncesi) oyuncu listesini temizle — kalıntı kayıt kalmasın
	players.clear()
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
	room_name         = ""
	_room_password    = ""
	_pending_password = ""
	_is_migrating     = false
	_saved_team_id    = -1
	_local_id_cache   = 0
	_pending_migration_state = {}
	_migration_players       = {}
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
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(id: int) -> void:
	emit_signal("player_connected", id)


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	emit_signal("player_disconnected", id)
	emit_signal("player_list_updated")
	if multiplayer.is_server():
		_broadcast_player_list()
	# Oyun sırasında ayrılan oyuncunun node'unu temizle (host + client)
	if GameManager.state == GameManager.State.IN_GAME:
		GameManager.on_player_disconnected(id)


func _on_connected_to_server() -> void:
	_local_id_cache = multiplayer.get_unique_id()  # Peer açıkken cache'le
	# joined_server emit etmiyoruz — host _accept_player RPC'si ile onaylayacak
	register_player.rpc_id(1, _local_id_cache, local_player_name, _pending_password, _saved_team_id)


func _on_connection_failed() -> void:
	emit_signal("connection_failed")


# ─────────────────────────────────────────────
# Host Migration
# ─────────────────────────────────────────────

func _on_server_disconnected() -> void:
	if _is_migrating:
		return
	_is_migrating = true

	# Peer kapandıktan sonra get_unique_id() hata verir — cache kullan
	var my_id := _local_id_cache
	_saved_team_id = players.get(my_id, {}).get("team_id", -1)
	_migration_players = players.duplicate(true)
	_pending_migration_state = GameManager.get_migration_state()
	var saved_room := room_name
	var saved_pw   := _pending_password  # Client sadece bunu bilir (password)

	# Bağlantıyı kapat
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

	# Kalan peer'ları bul (eski host peer_id=1 hariç)
	var remaining: Array = _migration_players.keys().filter(func(p): return p != 1)
	remaining.sort()

	if remaining.is_empty():
		# Kimse kalmadı, ana menüye dön
		_is_migrating = false
		players.clear()
		get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
		return

	if my_id == remaining[0]:
		# Ben yeni host oluyorum
		await get_tree().create_timer(0.3).timeout
		create_server(local_player_name, saved_room, saved_pw)
		# Kendi player datasını migration bilgisiyle güncelle
		players[1] = { "name": local_player_name, "team_id": _saved_team_id, "is_ready": false }
		emit_signal("player_list_updated")
		emit_signal("host_migrated")
		_is_migrating = false
		# Oyun durumuna göre sahneyi yönet
		var gstate = _pending_migration_state.get("game_state", GameManager.State.MENU)
		if gstate == GameManager.State.IN_GAME:
			GameManager.restore_from_migration(_pending_migration_state)
		else:
			get_tree().change_scene_to_file.call_deferred("res://scenes/ui/Lobby.tscn")
	else:
		# Yeni hostu bekle ve yeniden bağlan
		await get_tree().create_timer(1.5).timeout
		RoomManager.start_listening()
		_reconnect_loop(saved_room, saved_pw)


func _reconnect_loop(target_room: String, password: String) -> void:
	var timeout := 10.0
	var elapsed := 0.0
	while elapsed < timeout:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
		for room in RoomManager.discovered_rooms.values():
			if room.get("room_name", "") == target_room:
				RoomManager.stop_listening()
				join_server(room.get("ip", ""), local_player_name, password)
				return
	# Zaman aşımı: ana menüye dön
	_is_migrating = false
	RoomManager.stop_listening()
	players.clear()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


# ─────────────────────────────────────────────
# RPC: Oyuncu Kaydı
# ─────────────────────────────────────────────

@rpc("any_peer", "reliable")
func register_player(peer_id: int, player_name: String, password: String, saved_team_id: int = -1) -> void:
	if not multiplayer.is_server():
		return
	# Şifre kontrolü
	if not _room_password.is_empty() and password != _room_password:
		_reject_player.rpc_id(peer_id, "Yanlış şifre!")
		return
	# Migration sırasında eski takım bilgisini koru
	players[peer_id] = { "name": player_name, "team_id": saved_team_id, "is_ready": false }
	# Yeni oyuncuya mevcut listeyi gönder, ardından kabul bildir
	receive_player_list.rpc_id(peer_id, players)
	_accept_player.rpc_id(peer_id, _pending_migration_state, room_name, RoomManager.room_code)
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
func _accept_player(migration_state: Dictionary = {}, p_room_name: String = "", p_room_code: String = "") -> void:
	# Oda bilgisini client'a aktar
	if not p_room_name.is_empty():
		room_name = p_room_name
	if not p_room_code.is_empty():
		RoomManager.room_code = p_room_code
	_is_migrating = false
	var gstate = migration_state.get("game_state", -1)
	if gstate == GameManager.State.IN_GAME:
		RoomManager.stop_listening()
		GameManager.restore_from_migration(migration_state)
	else:
		# Normal katılım veya lobby migration
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


func _are_teams_balanced() -> bool:
	var team_counts: Dictionary = {}
	for p in players.values():
		var tid: int = p.get("team_id", -1)
		if tid < 0:
			continue
		team_counts[tid] = team_counts.get(tid, 0) + 1
	if team_counts.size() < 2:
		return false
	var count: int = team_counts[team_counts.keys()[0]]
	for tid in team_counts:
		if team_counts[tid] != count:
			return false
	return true


# ─────────────────────────────────────────────
# Karakter Seçimi
# ─────────────────────────────────────────────

func request_select_character(char_name: String) -> void:
	var my_id := get_local_id()
	if is_host():
		_apply_character_selection(my_id, char_name)
	else:
		_apply_character_selection.rpc_id(1, my_id, char_name)


@rpc("any_peer", "reliable")
func _apply_character_selection(peer_id: int, char_name: String) -> void:
	if not multiplayer.is_server():
		return
	if not players.has(peer_id):
		return
	# Aynı takımda bu karakter alınmış mı kontrol et
	var my_team: int = players[peer_id].get("team_id", -1)
	for other_id: int in players:
		if other_id == peer_id:
			continue
		var other: Dictionary = players[other_id]
		if other.get("team_id", -1) == my_team and other.get("character", "") == char_name:
			return  # Takım arkadaşı zaten almış
	players[peer_id]["character"] = char_name
	_broadcast_player_list()
	emit_signal("player_list_updated")
	GameManager.check_all_characters_selected()


# ─────────────────────────────────────────────
# Yardımcı
# ─────────────────────────────────────────────

func get_local_id() -> int:
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return _local_id_cache


func is_host() -> bool:
	return multiplayer.is_server()


func get_player_count() -> int:
	return players.size()

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
signal chat_received(msg: Dictionary)  # {sender, name, team, channel("all"/"team"/"system"), text}
signal room_settings_changed

const PORT := 7777
const TEAM_COUNT := 4
const TEAM_SIZE_MIN := 2   # 2v2v2v2
const TEAM_SIZE_MAX := 5   # 5v5v5v5
const MAX_PLAYERS := TEAM_COUNT * TEAM_SIZE_MAX  # ENet üst sınırı; gerçek kapasite get_max_players()

## Seçilebilir haritalar (Lobby ayarları, GameManager sahne yükleme, oda listesi)
const MAPS: Array[Dictionary] = [
	{"id": "maze", "name": "Labirent", "scene": "res://scenes/world/Map.tscn"},
]

## Oda ayarları — host değiştirir, _sync_room_settings ile herkese gider (yeni katılana da)
var room_settings: Dictionary = _default_settings()
var _migration_settings: Dictionary = {}
var _saved_character: String = ""
## Yeni host: migration sonrası yeniden bağlananları oyun sürerken de kabul etme penceresi
var _migration_window_until: int = 0
var _migration_room: String = ""
var _reconnect_attempts := 0
## Host her client'ın IP'sini herkese bildirir → host giderse yeni host'a (en küçük id) DOĞRUDAN bağlanılır.
## LAN yayını (RoomManager) sadece yedek — aynı makinede / bazı ağlarda broadcast ulaşmıyor.
var peer_addresses: Dictionary = {}
var _migration_addresses: Dictionary = {}
const MIGRATION_WINDOW_MS := 20000

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

## Sohbet
const CHAT_MAX_LEN := 140
const CHAT_HISTORY_MAX := 60
const CHAT_MIN_INTERVAL_MS := 350      # host tarafı flood koruması (oyuncu başına)
var chat_history: Array[Dictionary] = []  # sahne geçişlerinde korunur (lobi → oyun)
var _chat_last_ms: Dictionary = {}


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
	room_settings = _default_settings()
	room_settings["has_password"] = not p_password.is_empty()
	RoomManager.create_room(p_room_name, p_password)
	emit_signal("server_created")
	emit_signal("player_list_updated")


func join_server(address: String, player_name: String, p_password: String = "") -> void:
	local_player_name  = player_name
	_pending_password  = p_password
	# Geçersiz adresle create_client ENet'te C++ hatası üretir — önceden yakala
	if not is_valid_address(address):
		emit_signal("connection_failed")
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		push_error("Bağlantı hatası: %s" % err)
		emit_signal("connection_failed")
		return
	multiplayer.multiplayer_peer = peer
	_connect_multiplayer_signals()


## IPv4/IPv6 adresi veya "localhost" mu? (DNS adı desteklenmiyor — LAN oyunu)
static func is_valid_address(address: String) -> bool:
	var a := address.strip_edges()
	return a.to_lower() == "localhost" or a.is_valid_ip_address()


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
	_migration_settings      = {}
	_migration_addresses     = {}
	peer_addresses           = {}
	_saved_character         = ""
	_migration_window_until  = 0
	room_settings = _default_settings()
	chat_history.clear()
	_chat_last_ms.clear()
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
	var left_name: String = players.get(id, {}).get("name", "")
	players.erase(id)
	if multiplayer.is_server() and peer_addresses.erase(id) and multiplayer.get_peers().size() > 0:
		_sync_peer_addresses.rpc(peer_addresses)
	emit_signal("player_disconnected", id)
	emit_signal("player_list_updated")
	if multiplayer.is_server():
		_broadcast_player_list()
		if not left_name.is_empty():
			_chat_system("%s odadan ayrıldı" % left_name)
	# Oyun sırasında ayrılan oyuncunun node'unu temizle (host + client)
	if GameManager.state == GameManager.State.IN_GAME:
		GameManager.on_player_disconnected(id)


func _on_connected_to_server() -> void:
	_local_id_cache = multiplayer.get_unique_id()  # Peer açıkken cache'le
	# joined_server emit etmiyoruz — host _accept_player RPC'si ile onaylayacak
	register_player.rpc_id(1, _local_id_cache, local_player_name, _pending_password, _saved_team_id, _saved_character)


func _on_connection_failed() -> void:
	# Migration sırasında yeni host'a bağlanılamadıysa (henüz hazır değil) tekrar aramaya dön
	if _is_migrating and _reconnect_attempts < 3:
		_reconnect_attempts += 1
		multiplayer.multiplayer_peer = null
		RoomManager.start_listening()
		_reconnect_loop(_migration_room, _pending_password)
		return
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
	_saved_character = players.get(my_id, {}).get("character", "")
	_migration_players = players.duplicate(true)
	_migration_settings = room_settings.duplicate(true)
	_migration_addresses = peer_addresses.duplicate()
	_pending_migration_state = GameManager.get_migration_state()
	var saved_room := room_name
	var saved_pw   := _pending_password  # Client sadece bunu bilir (password)
	_migration_room = saved_room
	_reconnect_attempts = 0

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
		# Kendi player datasını migration bilgisiyle güncelle (karakter de korunur)
		players[1] = { "name": local_player_name, "team_id": _saved_team_id, "is_ready": false }
		if not _saved_character.is_empty():
			players[1]["character"] = _saved_character
		# Oda ayarları (harita, takım boyutu) eski host'tan devralınır
		if not _migration_settings.is_empty():
			room_settings = _migration_settings.duplicate(true)
			room_settings["has_password"] = not saved_pw.is_empty()
		# Diğerleri yeniden bağlanırken oyun sürüyor olsa da kabul et
		_migration_window_until = Time.get_ticks_msec() + MIGRATION_WINDOW_MS
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
		# Yeni hostu bekle ve yeniden bağlan — önce bilinen IP'sine doğrudan, olmazsa LAN yayınıyla ara
		await get_tree().create_timer(1.5).timeout
		var direct: String = _migration_addresses.get(remaining[0], "")
		if is_valid_address(direct):
			join_server(direct, local_player_name, saved_pw)
		else:
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
func register_player(peer_id: int, player_name: String, password: String, saved_team_id: int = -1, saved_character: String = "") -> void:
	if not multiplayer.is_server():
		return
	# Şifre kontrolü
	if not _room_password.is_empty() and password != _room_password:
		_reject_player.rpc_id(peer_id, "Yanlış şifre!")
		return
	# Oyun sürüyorsa yeni katılım yok — sadece host migration sonrası geri dönenler (pencere içinde)
	var reconnecting := Time.get_ticks_msec() < _migration_window_until
	if is_game_running() and not reconnecting:
		_reject_player.rpc_id(peer_id, "Oyun devam ediyor — bitince tekrar dene")
		return
	if players.size() >= get_max_players() and not reconnecting:
		_reject_player.rpc_id(peer_id, "Oda dolu")
		return
	# Migration sırasında eski takım + karakter bilgisini koru
	players[peer_id] = { "name": player_name, "team_id": saved_team_id, "is_ready": false }
	if not saved_character.is_empty():
		players[peer_id]["character"] = saved_character
	if reconnecting:
		GameManager.adopt_migrated_stats(peer_id, player_name)
	# Client adresini kaydet ve herkese yay (host migration'da doğrudan bağlantı için)
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet and enet.get_peer(peer_id):
		peer_addresses[peer_id] = enet.get_peer(peer_id).get_remote_address()
		_sync_peer_addresses.rpc(peer_addresses)
	# Yeni oyuncuya mevcut listeyi + oda ayarlarını gönder, ardından kabul bildir
	receive_player_list.rpc_id(peer_id, players)
	_sync_room_settings.rpc_id(peer_id, room_settings)
	_accept_player.rpc_id(peer_id, _pending_migration_state, room_name, RoomManager.room_code)
	# Diğer herkese güncel listeyi gönder
	_broadcast_player_list()
	emit_signal("player_list_updated")
	_chat_system("%s odaya katıldı" % player_name)


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
	if not players.has(peer_id) or team_id >= TEAM_COUNT:
		return
	# Takım boyutu sınırı host'ta da uygulanır (client UI'yi atlatmaya karşı)
	if team_id >= 0 and players[peer_id].get("team_id", -1) != team_id and get_team_count(team_id) >= get_team_size():
		return
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
# Sohbet — client → host (_chat_request) → host doğrular → ilgili peer'lara (_chat_receive)
# Gönderen kimliği RPC sender id'den alınır (client sahte isim/takım yollayamaz).
# ─────────────────────────────────────────────

## channel: "all" (herkes) veya "team" (sadece kendi takımı; takımsızsa "all"a düşer)
func send_chat(text: String, channel: String = "all") -> void:
	var clean := text.strip_edges()
	if clean.is_empty() or not multiplayer.has_multiplayer_peer():
		return
	if is_host():
		_chat_request(clean, channel)
	else:
		_chat_request.rpc_id(1, clean, channel)


@rpc("any_peer", "reliable")
func _chat_request(text: String, channel: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1  # host kendi mesajını doğrudan çağırdı
	if not players.has(sender):
		return
	var now := Time.get_ticks_msec()
	if now - int(_chat_last_ms.get(sender, -100000)) < CHAT_MIN_INTERVAL_MS:
		return
	_chat_last_ms[sender] = now

	var clean := text.strip_edges().substr(0, CHAT_MAX_LEN)
	if clean.is_empty():
		return
	var team: int = players[sender].get("team_id", -1)
	if channel != "team" or team < 0:
		channel = "all"
	var msg := {
		"sender": sender, "name": players[sender].get("name", "???"),
		"team": team, "channel": channel, "text": clean,
	}
	for pid: int in players:
		if channel == "team" and players[pid].get("team_id", -1) != team:
			continue
		_chat_deliver_to(pid, msg)


## Host: herkese sistem mesajı (katıldı/ayrıldı vb.)
func _chat_system(text: String) -> void:
	if not multiplayer.is_server():
		return
	var msg := {"sender": 0, "name": "", "team": -1, "channel": "system", "text": text}
	for pid: int in players:
		_chat_deliver_to(pid, msg)


func _chat_deliver_to(pid: int, msg: Dictionary) -> void:
	if pid == 1:
		_chat_receive(msg)
	else:
		_chat_receive.rpc_id(pid, msg)


@rpc("authority", "reliable")
func _chat_receive(msg: Dictionary) -> void:
	chat_history.append(msg)
	if chat_history.size() > CHAT_HISTORY_MAX:
		chat_history.pop_front()
	emit_signal("chat_received", msg)


# ─────────────────────────────────────────────
# Oda Ayarları — harita, takım boyutu (2v2v2v2 … 5v5v5v5), şifre. Sadece host değiştirir.
# ─────────────────────────────────────────────

static func _default_settings() -> Dictionary:
	return {"map": MAPS[0]["id"], "team_size": TEAM_SIZE_MAX, "has_password": false}


func get_team_size() -> int:
	return clampi(int(room_settings.get("team_size", TEAM_SIZE_MAX)), TEAM_SIZE_MIN, TEAM_SIZE_MAX)


func get_max_players() -> int:
	return TEAM_COUNT * get_team_size()


func get_team_count(team_id: int) -> int:
	var n := 0
	for p: Dictionary in players.values():
		if p.get("team_id", -1) == team_id:
			n += 1
	return n


func get_map_info(map_id: String = "") -> Dictionary:
	var id := map_id if not map_id.is_empty() else String(room_settings.get("map", ""))
	for m: Dictionary in MAPS:
		if m["id"] == id:
			return m
	return MAPS[0]


## "5v5v5v5"
func get_format_text(size: int = -1) -> String:
	var s := size if size > 0 else get_team_size()
	var parts: PackedStringArray = []
	for i in TEAM_COUNT:
		parts.append(str(s))
	return "v".join(parts)


func is_game_running() -> bool:
	return GameManager.state == GameManager.State.CHARACTER_SELECT or GameManager.state == GameManager.State.IN_GAME


## Oda listesi (RoomManager broadcast) için durum özeti
func get_room_status() -> Dictionary:
	return {
		"team_size": get_team_size(), "max_players": get_max_players(),
		"map_name": get_map_info()["name"], "state": "game" if is_game_running() else "lobby",
	}


func set_team_size(size: int) -> void:
	if not is_host() or is_game_running():
		return
	room_settings["team_size"] = clampi(size, TEAM_SIZE_MIN, TEAM_SIZE_MAX)
	_enforce_team_size()
	_push_settings()


func set_map(map_id: String) -> void:
	if not is_host() or is_game_running():
		return
	room_settings["map"] = get_map_info(map_id)["id"]
	_push_settings()


## Boş string = şifreyi kaldır
func set_room_password(password: String) -> void:
	if not is_host():
		return
	_room_password = password.strip_edges()
	_pending_password = _room_password  # host migration'da yeni host bu şifreyle oda kurar
	RoomManager.room_password = _room_password
	room_settings["has_password"] = not _room_password.is_empty()
	# Oda üyeleri yeni şifreyi bilsin — host değişirse yeni host aynı şifreyle kurar, diğerleri onunla bağlanır
	if multiplayer.get_peers().size() > 0:
		_sync_password.rpc(_room_password)
	_push_settings()


@rpc("authority", "reliable")
func _sync_peer_addresses(addresses: Dictionary) -> void:
	peer_addresses = addresses.duplicate()


@rpc("authority", "reliable")
func _sync_password(password: String) -> void:
	_pending_password = password


## Takım boyutu küçülünce fazla oyuncular (en son katılanlar) takımsıza düşer
func _enforce_team_size() -> void:
	var size := get_team_size()
	var changed := false
	for tid in TEAM_COUNT:
		var members: Array = players.keys().filter(func(pid): return players[pid].get("team_id", -1) == tid)
		members.sort()
		while members.size() > size:
			var pid: int = members.pop_back()
			players[pid]["team_id"] = -1
			players[pid]["is_ready"] = false
			changed = true
	if changed:
		_broadcast_player_list()
		emit_signal("player_list_updated")


func _push_settings() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_sync_room_settings.rpc(room_settings)
	else:
		_sync_room_settings(room_settings)


@rpc("authority", "call_local", "reliable")
func _sync_room_settings(settings: Dictionary) -> void:
	room_settings = settings.duplicate(true)
	emit_signal("room_settings_changed")


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

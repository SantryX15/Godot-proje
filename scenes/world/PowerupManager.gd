## PowerupManager.gd (Map.tscn → "PowerupManager" Node)
## Labirent köşelerinde (Map/PowerupPoints Marker3D'leri) zaman zaman kısa ömürlü güçler belirir.
## Oyuncu üzerinden geçince tek slotluk envanterine alır, Q ile kullanır. Ölünce slot boşalır.
##
## HOST YETKİLİ (GameManager ile aynı kural): spawn zamanlaması, alma, kullanma, bomba hasarı host'ta.
## Client'lar sadece istek yollar (request_pickup / request_use) ve görsel/HUD durumunu RPC ile alır.
##   _spawn_rpc / _despawn_rpc        → Powerup.gd nesneleri (tüm peer'lar)
##   _set_item_rpc(peer, type)        → envanter (herkese; HUD sadece kendini gösterir)
##   _bomb_rpc(...)                   → Bomb.gd görseli (herkese), hasar host'ta _detonate'te
##   _reveal_rpc(team, kind, süre)    → uydu: o takımın minimapinde kart+kapı ("objectives") / düşmanlar ("enemies")
## Sinyaller (HUD/Minimap dinler): inventory_changed(type), reveal_started(kind, dur, own_team), notice(text, color)

extends Node

signal inventory_changed(item_type: int)            # yerel oyuncunun slotu (-1 = boş)
signal reveal_started(kind: String, duration: float, own_team: bool)
signal notice(text: String, color: Color)

enum Type { BOMB, HEAL, INTEL_SAT, ENEMY_SAT }
const NONE := -1

## Görünüm/isim (HUD, Powerup.gd, Minimap ortak kullanır)
const INFO := {
	Type.BOMB:      {"name": "BOMBA",         "glyph": "✸", "color": Color(1.0, 0.42, 0.22), "desc": "Fareye fırlat, alan hasarı"},
	Type.HEAL:      {"name": "SAĞLIK",        "glyph": "✚", "color": Color(0.35, 0.95, 0.5),  "desc": "+%d can"},
	Type.INTEL_SAT: {"name": "UYDU",          "glyph": "◈", "color": Color(0.3, 0.85, 1.0),   "desc": "Kart + kapı haritada"},
	Type.ENEMY_SAT: {"name": "TAKIM UYDUSU",  "glyph": "◉", "color": Color(0.8, 0.45, 1.0),   "desc": "Düşmanlar haritada"},
}
const WEIGHTS := {Type.BOMB: 30, Type.HEAL: 30, Type.INTEL_SAT: 20, Type.ENEMY_SAT: 20}

## Zamanlama (sn)
const FIRST_SPAWN_DELAY := 12.0
const SPAWN_INTERVAL := Vector2(8.0, 15.0)
const LIFETIME := Vector2(5.0, 10.0)
const MAX_ACTIVE := 3

## Etkiler
const HEAL_AMOUNT := 60.0
const BOMB_DAMAGE := 75.0          # merkezde; kenarda %35'e düşer
const BOMB_RADIUS := 4.0
const BOMB_MAX_THROW := 12.0
const BOMB_FLIGHT := 0.55
const BOMB_FUSE := 1.2             # yere düştükten sonra
const INTEL_DURATION := 8.0
const ENEMY_SAT_DURATION := 6.0

const USE_KEY := KEY_Q
const PICKUP_RANGE := 2.5          # host doğrulaması

const POWERUP_SCRIPT := preload("res://scenes/world/Powerup.gd")
const BOMB_SCRIPT := preload("res://scenes/world/Bomb.gd")

## Host + client: id → Powerup node
var _items: Dictionary = {}
## Host + client: peer_id → Type (tek slot)
var inventory: Dictionary = {}
## Yerel: aktif açığa çıkarmalar (kind → bitiş zamanı, sn) — sadece kendi takımımız kullandıysa
var reveal_until: Dictionary = {}

var _points: Array[Vector3] = []
var _next_id := 1
var _spawn_timer := 0.0


func _ready() -> void:
	var root := get_parent().get_node_or_null("PowerupPoints")
	if root:
		for c in root.get_children():
			if c is Marker3D:
				_points.append((c as Marker3D).global_position)
	if _points.is_empty():
		push_warning("PowerupPoints bulunamadı — güç spawn edilmeyecek")
	_spawn_timer = FIRST_SPAWN_DELAY
	GameManager.kill_happened.connect(_on_kill_happened)
	# Geç katılan / migration sonrası client: aktif güçleri host'tan iste
	# (biraz beklenir — host'un Map/PowerupManager'ı henüz yüklenmemişse RPC "node bulunamadı" hatası verir)
	if not NetworkManager.is_host() and multiplayer.has_multiplayer_peer():
		await get_tree().create_timer(1.5).timeout
		if is_instance_valid(self) and multiplayer.has_multiplayer_peer() and not NetworkManager.is_host():
			_request_sync.rpc_id(1)


func _process(delta: float) -> void:
	if not NetworkManager.is_host() or GameManager.state != GameManager.State.IN_GAME or _points.is_empty():
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = randf_range(SPAWN_INTERVAL.x, SPAWN_INTERVAL.y)
	if _items.size() >= MAX_ACTIVE:
		return
	# Dolu olmayan ve oyunculara çok yakın olmayan bir köşe seç
	var free: Array[Vector3] = []
	for p in _points:
		if _is_point_free(p):
			free.append(p)
	if free.is_empty():
		return
	var id := _next_id
	_next_id += 1
	_spawn_rpc.rpc(id, _pick_type(), free.pick_random(), randf_range(LIFETIME.x, LIFETIME.y))


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.physical_keycode != USE_KEY or ChatBox.is_typing:
		return
	var me := _local_player()
	if me == null or me.is_dead or get_item(NetworkManager.get_local_id()) == NONE:
		return
	get_viewport().set_input_as_handled()
	var aim: Vector3 = me._get_aim_target()
	if NetworkManager.is_host():
		_request_use(aim)
	else:
		_request_use.rpc_id(1, aim)


# ─────────────────────────────────────────────
#  Yardımcılar
# ─────────────────────────────────────────────

func get_item(peer_id: int) -> int:
	return inventory.get(peer_id, NONE)


func is_revealed(kind: String) -> bool:
	return reveal_until.get(kind, 0.0) > Time.get_ticks_msec() / 1000.0


func _local_player() -> Node:
	var p: Variant = GameManager.active_players.get(NetworkManager.get_local_id())
	return p if p != null and is_instance_valid(p) else null


func _local_team() -> int:
	return NetworkManager.players.get(NetworkManager.get_local_id(), {}).get("team_id", -1)


func _pick_type() -> int:
	var total := 0
	for t: int in WEIGHTS:
		total += WEIGHTS[t]
	var roll := randi() % total
	for t: int in WEIGHTS:
		roll -= WEIGHTS[t]
		if roll < 0:
			return t
	return Type.HEAL


func _is_point_free(p: Vector3) -> bool:
	for item in _items.values():
		if is_instance_valid(item) and (item as Node3D).global_position.distance_to(p) < 1.0:
			return false
	for pl in GameManager.active_players.values():
		if is_instance_valid(pl) and (pl as Node3D).global_position.distance_to(p) < 4.0:
			return false
	return true


func _team_of(peer_id: int) -> int:
	return NetworkManager.players.get(peer_id, {}).get("team_id", -1)


# ─────────────────────────────────────────────
#  Spawn / despawn (herkes)
# ─────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _spawn_rpc(id: int, type: int, pos: Vector3, lifetime: float) -> void:
	if _items.has(id):
		return
	var item: Area3D = POWERUP_SCRIPT.new()
	item.setup(self, id, type, lifetime)
	get_parent().add_child(item)
	item.global_position = pos
	_items[id] = item
	if NetworkManager.is_host():
		_expire_later(id, lifetime)


func _expire_later(id: int, lifetime: float) -> void:
	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self) and _items.has(id):
		_despawn_rpc.rpc(id)


@rpc("authority", "call_local", "reliable")
func _despawn_rpc(id: int) -> void:
	var item: Variant = _items.get(id)
	_items.erase(id)
	if item != null and is_instance_valid(item):
		(item as Node).queue_free()


@rpc("any_peer", "reliable")
func _request_sync() -> void:
	if not NetworkManager.is_host():
		return
	var requester := multiplayer.get_remote_sender_id()
	for id: int in _items:
		var item: Node3D = _items[id]
		if is_instance_valid(item):
			_spawn_rpc.rpc_id(requester, id, item.get("item_type"), item.global_position, item.get("time_left"))
	for pid: int in inventory:
		_set_item_rpc.rpc_id(requester, pid, inventory[pid])


# ─────────────────────────────────────────────
#  Alma — Powerup.gd yerel oyuncu girince çağırır
# ─────────────────────────────────────────────

func local_touched(id: int) -> void:
	if get_item(NetworkManager.get_local_id()) != NONE:
		return  # slot dolu
	if NetworkManager.is_host():
		_request_pickup(id)
	else:
		_request_pickup.rpc_id(1, id)


@rpc("any_peer", "reliable")
func _request_pickup(id: int) -> void:
	if not NetworkManager.is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = 1
	var item: Variant = _items.get(id)
	var player: Variant = GameManager.active_players.get(peer)
	if item == null or not is_instance_valid(item) or player == null or not is_instance_valid(player):
		return
	if player.is_dead or get_item(peer) != NONE:
		return
	if (player as Node3D).global_position.distance_to((item as Node3D).global_position) > PICKUP_RANGE:
		return
	var type: int = item.get("item_type")
	_despawn_rpc.rpc(id)
	_set_item_rpc.rpc(peer, type)


@rpc("authority", "call_local", "reliable")
func _set_item_rpc(peer_id: int, type: int) -> void:
	if type == NONE:
		inventory.erase(peer_id)
	else:
		inventory[peer_id] = type
	if peer_id == NetworkManager.get_local_id():
		inventory_changed.emit(type)
		if type != NONE:
			notice.emit("%s %s alındı  ·  [Q] kullan" % [INFO[type]["glyph"], INFO[type]["name"]], Color(INFO[type]["color"]))


func _on_kill_happened(_killer: int, victim: int) -> void:
	# Ölünce slot boşalır (host karar verir)
	if NetworkManager.is_host() and get_item(victim) != NONE:
		_set_item_rpc.rpc(victim, NONE)


# ─────────────────────────────────────────────
#  Kullanma (host)
# ─────────────────────────────────────────────

@rpc("any_peer", "reliable")
func _request_use(aim: Vector3) -> void:
	if not NetworkManager.is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = 1
	var type := get_item(peer)
	var player: Variant = GameManager.active_players.get(peer)
	if type == NONE or player == null or not is_instance_valid(player) or player.is_dead:
		return
	_set_item_rpc.rpc(peer, NONE)
	var team := _team_of(peer)
	match type:
		Type.HEAL:
			player.health = minf(player.health + HEAL_AMOUNT, player.max_health)
			player._sync_health.rpc(player.health)
		Type.BOMB:
			_throw_bomb(peer, team, player as Node3D, aim)
		Type.INTEL_SAT:
			_reveal_rpc.rpc(team, "objectives", INTEL_DURATION, peer)
		Type.ENEMY_SAT:
			_reveal_rpc.rpc(team, "enemies", ENEMY_SAT_DURATION, peer)


func _throw_bomb(peer: int, team: int, player: Node3D, aim: Vector3) -> void:
	var from := player.global_position + Vector3(0, 1.2, 0)
	var flat := Vector3(aim.x - from.x, 0.0, aim.z - from.z)
	if flat.length() > BOMB_MAX_THROW:
		flat = flat.normalized() * BOMB_MAX_THROW
	var target := Vector3(from.x + flat.x, 0.15, from.z + flat.z)
	# Duvara çarparsa duvarın önüne düşer
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, Vector3(target.x, from.y, target.z))
	q.exclude = _player_rids()
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var back: Vector3 = (hit["position"] as Vector3) - flat.normalized() * 0.4
		target = Vector3(back.x, 0.15, back.z)
	var id := _next_id
	_next_id += 1
	_bomb_rpc.rpc(id, from, target, team)
	_detonate_later(peer, team, target)


func _detonate_later(peer: int, team: int, pos: Vector3) -> void:
	await get_tree().create_timer(BOMB_FLIGHT + BOMB_FUSE).timeout
	if not is_instance_valid(self) or GameManager.state != GameManager.State.IN_GAME:
		return
	var space := (get_parent() as Node3D).get_world_3d().direct_space_state
	var center := pos + Vector3(0, 0.6, 0)
	for pid: int in GameManager.active_players.keys():
		var pl: Variant = GameManager.active_players.get(pid)
		if pl == null or not is_instance_valid(pl) or pl.is_dead:
			continue
		if pid == peer or _team_of(pid) == team:
			continue  # dost ateşi / kendine hasar yok
		var target_pos := (pl as Node3D).global_position + Vector3(0, 0.9, 0)
		var d := center.distance_to(target_pos)
		if d > BOMB_RADIUS:
			continue
		# Duvar arkası korunur (oyuncuları yok say, sadece duvar/zemin)
		var q := PhysicsRayQueryParameters3D.create(center, target_pos)
		q.exclude = _player_rids()
		if not space.intersect_ray(q).is_empty():
			continue
		var dmg := BOMB_DAMAGE * lerpf(1.0, 0.35, d / BOMB_RADIUS)
		pl.take_damage(dmg, peer, 1)  # Player.DAMAGE_EXPLOSION — çömelme bombadan korumaz


func _player_rids() -> Array[RID]:
	var out: Array[RID] = []
	for pl in GameManager.active_players.values():
		if is_instance_valid(pl):
			out.append((pl as CollisionObject3D).get_rid())
	return out


@rpc("authority", "call_local", "reliable")
func _bomb_rpc(_id: int, from: Vector3, target: Vector3, team: int) -> void:
	var bomb: Node3D = BOMB_SCRIPT.new()
	bomb.setup(from, target, BOMB_FLIGHT, BOMB_FUSE, BOMB_RADIUS, TeamManager.get_color(team))
	get_parent().add_child(bomb)


@rpc("authority", "call_local", "reliable")
func _reveal_rpc(team: int, kind: String, duration: float, user_peer: int) -> void:
	var local_team := _local_team()
	var user_name: String = NetworkManager.players.get(user_peer, {}).get("name", "?")
	if team == local_team:
		reveal_until[kind] = Time.get_ticks_msec() / 1000.0 + duration
		reveal_started.emit(kind, duration, true)
		var txt := "◈ UYDU (%s): kart ve kapı haritada" if kind == "objectives" else "◉ TAKIM UYDUSU (%s): düşmanlar haritada"
		notice.emit(txt % user_name, Color(INFO[Type.INTEL_SAT if kind == "objectives" else Type.ENEMY_SAT]["color"]))
	elif kind == "enemies":
		reveal_started.emit(kind, duration, false)
		notice.emit("⚠ %s TAKIM UYDUSU KONUMUNUZU TESPİT ETTİ!" % TeamManager.get_team_name(team).to_upper(), UITheme.DANGER)

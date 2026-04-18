## Minimap.gd (3D)
## Ekranın sağ-alt köşesinde mini harita.
## Kendin ve takım arkadaşların her zaman görünür.
## Düşman kart taşıyıcı, pickup anında 3 saniyeliğine kırmızı alert olarak belirir.

extends Control

## Harita sınırları (3D dünya X/Z koordinatları)
const MAP_MIN := Vector2(-60.0, -55.0)
const MAP_MAX := Vector2(60.0, 55.0)
const SIZE := 180.0

## Kart alert (düşman kart aldığında 3 sn gösterilen son bilinen konum)
var _alert_timer: float = 0.0
var _alert_pos: Vector3 = Vector3.ZERO
var _alert_color: Color = Color.RED


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	GameManager.card_picked_up.connect(_on_card_picked_up)


func _process(delta: float) -> void:
	if _alert_timer > 0.0:
		_alert_timer -= delta
	queue_redraw()


func _draw() -> void:
	# ── Arka plan ──
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color(0.0, 0.0, 0.0, 0.65))
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color(1.0, 1.0, 1.0, 0.25), false, 1.5)

	if not multiplayer.has_multiplayer_peer():
		return

	var local_id := NetworkManager.get_local_id()
	var local_data: Dictionary = NetworkManager.players.get(local_id, {})
	var local_team: int = local_data.get("team_id", -1)

	# ── Oyuncular (kendin + takım arkadaşları) ──
	for peer_id: int in GameManager.active_players:
		var player: Node = GameManager.active_players[peer_id]
		if not is_instance_valid(player):
			continue
		if player.is_dead:
			continue

		var data: Dictionary = NetworkManager.players.get(peer_id, {})
		var team_id: int = data.get("team_id", -1)
		var is_self := (peer_id == local_id)
		var is_teammate := (team_id == local_team)

		if not (is_self or is_teammate):
			continue

		var p := _w2m(player.global_position)
		var color := TeamManager.get_color(team_id)
		var radius := 5.0 if is_self else 3.5

		draw_circle(p, radius + 1.5, Color.WHITE)
		draw_circle(p, radius, color)

		# Kart taşıyorsa sarı halka
		if player.has_card:
			draw_arc(p, radius + 4.0, 0.0, TAU, 20, Color(1.0, 0.9, 0.1), 2.0)

	# ── Kart alert (düşman kart taşıyıcı — 3 sn, blink + fade) ──
	if _alert_timer > 0.0:
		var alpha := minf(_alert_timer / 3.0, 1.0)
		var blink := (floori(_alert_timer * 5.0) % 2) == 0
		if blink:
			var p := _w2m(_alert_pos)
			draw_circle(p, 7.0, Color(_alert_color.r, _alert_color.g, _alert_color.b, alpha))
			draw_arc(p, 11.0, 0.0, TAU, 20, Color(_alert_color.r, _alert_color.g, _alert_color.b, alpha * 0.7), 2.5)


## 3D dünya konumunu (X/Z) minimap koordinatına çevirir
func _w2m(world_pos: Vector3) -> Vector2:
	var t := (Vector2(world_pos.x, world_pos.z) - MAP_MIN) / (MAP_MAX - MAP_MIN)
	return t * Vector2(SIZE, SIZE)


func _on_card_picked_up(carrier_peer_id: int, carrier_pos: Vector3, carrier_team_id: int) -> void:
	var local_id := NetworkManager.get_local_id()
	var local_team: int = NetworkManager.players.get(local_id, {}).get("team_id", -1)
	if carrier_team_id == local_team:
		return
	_alert_pos   = carrier_pos
	_alert_color = TeamManager.get_color(carrier_team_id)
	_alert_timer = 3.0

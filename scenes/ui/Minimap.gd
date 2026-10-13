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

var _bg_style: StyleBoxFlat = UITheme.style(Color(UITheme.BG, 0.82), 12, UITheme.BORDER, 1)


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	GameManager.card_picked_up.connect(_on_card_picked_up)


func _process(delta: float) -> void:
	if _alert_timer > 0.0:
		_alert_timer -= delta
	queue_redraw()


func _draw() -> void:
	# ── Arka plan: UITheme paletiyle yuvarlak panel + taktik ızgara ──
	var rect := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
	draw_style_box(_bg_style, rect)
	var step := SIZE / 6.0
	for i in range(1, 6):
		var o := step * i
		draw_line(Vector2(o, 6), Vector2(o, SIZE - 6), Color(1, 1, 1, 0.04), 1.0)
		draw_line(Vector2(6, o), Vector2(SIZE - 6, o), Color(1, 1, 1, 0.04), 1.0)

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

		# Kendi el feneri konisi (Player root -Z yönüne bakar)
		if is_self:
			var fwd3: Vector3 = -(player as Node3D).global_transform.basis.z
			var fwd := Vector2(fwd3.x, fwd3.z).normalized()
			var cone := PackedVector2Array([p, p + fwd.rotated(-0.45) * 26.0, p + fwd.rotated(0.45) * 26.0])
			draw_colored_polygon(cone, Color(UITheme.ACCENT, 0.22))

		draw_circle(p, radius + 1.5, Color(0.05, 0.05, 0.08))
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
	# Harita dışına taşan noktalar panelin kenarında kalsın
	return (t * Vector2(SIZE, SIZE)).clamp(Vector2(6, 6), Vector2(SIZE - 6, SIZE - 6))


func _on_card_picked_up(carrier_peer_id: int, carrier_pos: Vector3, carrier_team_id: int) -> void:
	var local_id := NetworkManager.get_local_id()
	var local_team: int = NetworkManager.players.get(local_id, {}).get("team_id", -1)
	if carrier_team_id == local_team:
		return
	_alert_pos   = carrier_pos
	_alert_color = TeamManager.get_color(carrier_team_id)
	_alert_timer = 3.0

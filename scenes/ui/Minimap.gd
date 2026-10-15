## Minimap.gd (3D)
## Ekranın sağ-alt köşesinde mini harita.
## Kendin ve takım arkadaşların her zaman görünür.
## Düşman kart taşıyıcı, pickup anında 3 saniyeliğine kırmızı alert olarak belirir.

extends Control

## Harita sınırları (3D dünya X/Z) — labirent (Maze_walls.obj) ayak izi, Maze_minimap.png ile birebir (1 px = 1 m)
const MAP_MIN := Vector2(-62.0, -46.0)
const MAP_MAX := Vector2(62.0, 46.0)
const SIZE := Vector2(200.0, 148.0)   # labirentin en/boy oranı (124:92)
const PAD := 6.0
const WALLS_TEXTURE := "res://asset model/Maze_minimap.png"
## false yapılırsa minimapte duvarlar çizilmez (sadece oyuncular)
const SHOW_WALLS := true

var _walls_tex: Texture2D = null
var _powerups: Node = null  # Map/PowerupManager (uydu açığa çıkarmaları)

## Kart alert (düşman kart aldığında 3 sn gösterilen son bilinen konum)
var _alert_timer: float = 0.0
var _alert_pos: Vector3 = Vector3.ZERO
var _alert_color: Color = Color.RED

var _bg_style: StyleBoxFlat = UITheme.style(Color(UITheme.BG, 0.82), 12, UITheme.BORDER, 1)


func _ready() -> void:
	custom_minimum_size = SIZE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # duvar pikselleri keskin kalsın
	if SHOW_WALLS and ResourceLoader.exists(WALLS_TEXTURE):
		_walls_tex = load(WALLS_TEXTURE)
	GameManager.card_picked_up.connect(_on_card_picked_up)


func _process(delta: float) -> void:
	if _alert_timer > 0.0:
		_alert_timer -= delta
	queue_redraw()


func _draw() -> void:
	# ── Arka plan: UITheme paletiyle yuvarlak panel + taktik ızgara ──
	draw_style_box(_bg_style, Rect2(Vector2.ZERO, SIZE))
	var inner := Rect2(Vector2(PAD, PAD), SIZE - Vector2(PAD, PAD) * 2.0)
	if _walls_tex:
		draw_texture_rect(_walls_tex, inner, false, Color(0.75, 0.78, 0.9, 0.28))
	else:
		for i in range(1, 6):
			var ox := inner.position.x + inner.size.x * i / 6.0
			var oy := inner.position.y + inner.size.y * i / 6.0
			draw_line(Vector2(ox, PAD), Vector2(ox, SIZE.y - PAD), Color(1, 1, 1, 0.04), 1.0)
			draw_line(Vector2(PAD, oy), Vector2(SIZE.x - PAD, oy), Color(1, 1, 1, 0.04), 1.0)

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

	# ── Uydu güçleri (PowerupManager) — sadece kendi takımımız kullandıysa ──
	_draw_satellite_reveals(local_team)

	# ── Kart alert (düşman kart taşıyıcı — 3 sn, blink + fade) ──
	if _alert_timer > 0.0:
		var alpha := minf(_alert_timer / 3.0, 1.0)
		var blink := (floori(_alert_timer * 5.0) % 2) == 0
		if blink:
			var p := _w2m(_alert_pos)
			draw_circle(p, 7.0, Color(_alert_color.r, _alert_color.g, _alert_color.b, alpha))
			draw_arc(p, 11.0, 0.0, TAU, 20, Color(_alert_color.r, _alert_color.g, _alert_color.b, alpha * 0.7), 2.5)


func _draw_satellite_reveals(local_team: int) -> void:
	if _powerups == null or not is_instance_valid(_powerups):
		_powerups = get_tree().current_scene.get_node_or_null("PowerupManager") if get_tree().current_scene else null
		if _powerups == null:
			return
	var now := Time.get_ticks_msec() / 1000.0
	var pulse := 0.6 + 0.4 * sin(now * 8.0)
	var font := ThemeDB.fallback_font
	var status := ""

	# ◈ Uydu: kart + kapı
	if _powerups.is_revealed("objectives"):
		var c: Color = _powerups.INFO[2]["color"]
		if GameManager.door_instance and is_instance_valid(GameManager.door_instance):
			var dp := _w2m(GameManager.door_instance.global_position)
			draw_rect(Rect2(dp - Vector2(5, 5), Vector2(10, 10)), Color(0.4, 0.7, 1.0), true)
			draw_rect(Rect2(dp - Vector2(8, 8), Vector2(16, 16)), Color(c, pulse), false, 1.5)
		var card_pos := Vector3.INF
		if GameManager.card_carrier_peer_id != -1:
			var carrier: Variant = GameManager.active_players.get(GameManager.card_carrier_peer_id)
			if carrier != null and is_instance_valid(carrier):
				card_pos = (carrier as Node3D).global_position
		elif GameManager.card_instance and is_instance_valid(GameManager.card_instance):
			card_pos = GameManager.card_instance.global_position
		if card_pos != Vector3.INF:
			var cp := _w2m(card_pos)
			draw_colored_polygon(PackedVector2Array([cp + Vector2(0, -7), cp + Vector2(6, 0), cp + Vector2(0, 7), cp + Vector2(-6, 0)]), Color(1.0, 0.9, 0.1))
			draw_arc(cp, 10.0, 0.0, TAU, 20, Color(c, pulse), 1.5)
		status += "◈ %d  " % ceili(_powerups.reveal_until["objectives"] - now)

	# ◉ Takım uydusu: tüm düşmanlar
	if _powerups.is_revealed("enemies"):
		var c2: Color = _powerups.INFO[3]["color"]
		for pid: int in GameManager.active_players:
			var pl: Variant = GameManager.active_players[pid]
			if pl == null or not is_instance_valid(pl) or pl.is_dead:
				continue
			var tid: int = NetworkManager.players.get(pid, {}).get("team_id", -1)
			if tid == local_team:
				continue
			var ep := _w2m((pl as Node3D).global_position)
			draw_circle(ep, 4.0, TeamManager.get_color(tid))
			draw_arc(ep, 7.0, 0.0, TAU, 16, Color(c2, pulse), 1.5)
		status += "◉ %d" % ceili(_powerups.reveal_until["enemies"] - now)

	if not status.is_empty():
		draw_string(font, Vector2(PAD + 4, SIZE.y - PAD - 4), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.9))


## 3D dünya konumunu (X/Z) minimap koordinatına çevirir
func _w2m(world_pos: Vector3) -> Vector2:
	var t := (Vector2(world_pos.x, world_pos.z) - MAP_MIN) / (MAP_MAX - MAP_MIN)
	var inner_size := SIZE - Vector2(PAD, PAD) * 2.0
	# Harita dışına taşan noktalar panelin kenarında kalsın
	return (Vector2(PAD, PAD) + t * inner_size).clamp(Vector2(PAD, PAD), SIZE - Vector2(PAD, PAD))


func _on_card_picked_up(carrier_peer_id: int, carrier_pos: Vector3, carrier_team_id: int) -> void:
	var local_id := NetworkManager.get_local_id()
	var local_team: int = NetworkManager.players.get(local_id, {}).get("team_id", -1)
	if carrier_team_id == local_team:
		return
	_alert_pos   = carrier_pos
	_alert_color = TeamManager.get_color(carrier_team_id)
	_alert_timer = 3.0

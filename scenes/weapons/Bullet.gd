## Bullet.gd
## Sadece atan oyuncunun clienti sunucuya hasar bildirir.

extends Area2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 600.0
var damage: float = 25.0
var shooter_peer_id: int = -1
var shooter_team_id: int = -1

const MAX_DISTANCE: float = 1000.0
var _travel_distance: float = 0.0


func initialize(
	dir: Vector2,
	spd: float,
	dmg: float,
	peer_id: int,
	team_id: int
) -> void:
	direction = dir.normalized()
	speed = spd
	damage = dmg
	shooter_peer_id = peer_id
	shooter_team_id = team_id
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	var move := direction * speed * delta
	global_position += move
	_travel_distance += move.length()
	if _travel_distance >= MAX_DISTANCE:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body is CharacterBody2D:
		# Takım dostu ateş engeli
		if body.get("team_id") == shooter_team_id:
			queue_free()
			return

		# Sadece atan oyuncunun clienti hasar bildirir
		# → çift hasar önlenir
		if NetworkManager.get_local_id() == shooter_peer_id:
			if NetworkManager.is_host():
				# Host: direkt çağır (kendine RPC gönderilemez)
				body.take_damage(damage, shooter_peer_id)
			else:
				# Client: sunucuya RPC gönder
				body.take_damage.rpc_id(1, damage, shooter_peer_id)

	queue_free()


func _on_area_entered(_area: Area2D) -> void:
	queue_free()

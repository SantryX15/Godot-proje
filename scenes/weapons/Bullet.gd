## Bullet.gd (3D)
## Sadece atan oyuncunun clienti sunucuya hasar bildirir.

extends Area3D

var direction: Vector3 = Vector3.FORWARD
var speed: float = 30.0
var damage: float = 25.0
var shooter_peer_id: int = -1
var shooter_team_id: int = -1

const MAX_DISTANCE: float = 60.0
var _travel_distance: float = 0.0


func initialize(
	dir: Vector3,
	spd: float,
	dmg: float,
	peer_id: int,
	team_id: int
) -> void:
	direction = dir.normalized()
	direction.y = 0.0  # Yatay düzlemde kal
	speed = spd
	damage = dmg
	shooter_peer_id = peer_id
	shooter_team_id = team_id


func _physics_process(delta: float) -> void:
	var move := direction * speed * delta
	global_position += move
	_travel_distance += move.length()
	if _travel_distance >= MAX_DISTANCE:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body is CharacterBody3D:
		# Shooter'ın kendi vücudu: mermiyi yok etme, geç
		if body.get("peer_id") == shooter_peer_id:
			return

		# Takım dostu ateş: mermiyi yok et, hasar verme
		if body.get("team_id") == shooter_team_id:
			queue_free()
			return

		# Sadece atan oyuncunun clienti hasar bildirir — çift hasar önlenir
		if NetworkManager.get_local_id() == shooter_peer_id:
			if NetworkManager.is_host():
				body.take_damage(damage, shooter_peer_id)
			else:
				body.take_damage.rpc_id(1, damage, shooter_peer_id)

	queue_free()

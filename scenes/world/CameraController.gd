## CameraController.gd
## Yerel oyuncuyu sinematik şekilde takip eden izometrik kamera.
## Exponential lerp kullanır: hedefe hızlı yaklaşır, varınca yumuşar.

extends Camera3D

const OFFSET       := Vector3(0, 14, 12)
const PITCH        := -50.0
const FOLLOW_SPEED := 7.0   # Yükselt = daha hızlı; düşür = daha geride kalır

var _target: Node3D = null
var _snapped: bool  = false


func _ready() -> void:
	rotation_degrees = Vector3(PITCH, 0.0, 0.0)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	GameManager.local_player_spawned.connect(_on_local_player_spawned)


func _on_local_player_spawned(player: Node) -> void:
	_target  = player
	_snapped = false   # Yeni oyuncu: ilk frame'de anında konumlan


func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var desired: Vector3 = _target.global_position + OFFSET
	if not _snapped:
		global_position = desired
		reset_physics_interpolation()
		_snapped = true
	else:
		# Exponential decay lerp — framerate bağımsız, sinematik yumuşaklık
		global_position = global_position.lerp(desired, 1.0 - exp(-FOLLOW_SPEED * delta))

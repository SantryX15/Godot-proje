## CameraController.gd
## Yerel oyuncuyu sinematik şekilde takip eden izometrik kamera.
## Exponential lerp kullanır: hedefe hızlı yaklaşır, varınca yumuşar.

extends Camera3D

const OFFSET       := Vector3(0, 14, 12)
const PITCH        := -50.0
const FOLLOW_SPEED := 7.0   # Yükselt = daha hızlı; düşür = daha geride kalır

## Ekran sarsıntısı (trauma modeli): add_trauma(0..1) — PowerupManager patlamada yakınlığa göre çağırır.
## Takip konumuna dokunmaz; h_offset/v_offset + hafif yuvarlanma ile uygulanır.
const SHAKE_MAX_OFFSET := 0.55   # m
const SHAKE_MAX_ROLL   := 2.5    # derece
const SHAKE_DECAY      := 1.4    # trauma/sn
const SHAKE_FREQ       := 28.0

var _target: Node3D = null
var _snapped: bool  = false
var _trauma := 0.0
var _shake_t := 0.0
var _noise := FastNoiseLite.new()


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## _physics_process'ten — kamera physics interpolation açık, dönüş fizik karesinde değişmeli
func _update_shake(delta: float) -> void:
	if _trauma <= 0.0:
		return
	_trauma = maxf(_trauma - SHAKE_DECAY * delta, 0.0)
	_shake_t += delta * SHAKE_FREQ
	var s := _trauma * _trauma
	h_offset = SHAKE_MAX_OFFSET * s * _noise.get_noise_2d(_shake_t, 0.0)
	v_offset = SHAKE_MAX_OFFSET * s * _noise.get_noise_2d(_shake_t, 100.0)
	rotation_degrees = Vector3(PITCH, 0.0, SHAKE_MAX_ROLL * s * _noise.get_noise_2d(_shake_t, 200.0))


func _ready() -> void:
	rotation_degrees = Vector3(PITCH, 0.0, 0.0)
	_noise.frequency = 0.4  # × SHAKE_FREQ ≈ 11 Hz titreşim
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	GameManager.local_player_spawned.connect(_on_local_player_spawned)


func _on_local_player_spawned(player: Node) -> void:
	_target  = player
	_snapped = false   # Yeni oyuncu: ilk frame'de anında konumlan


func _physics_process(delta: float) -> void:
	_update_shake(delta)
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

## Player.gd
## WASD hareketi, mouse ile nişan alma, ateş etme, el feneri ve sağlık sistemi.

extends CharacterBody2D

@export var speed: float = 200.0
@export var max_health: float = 100.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var flashlight: PointLight2D = $Flashlight
@onready var health_bar: ProgressBar = $HealthBar
@onready var name_label: Label = $NameLabel
@onready var weapon_holder: Node2D = $WeaponHolder
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var peer_id: int = 0
var team_id: int = -1
var health: float = 100.0
var is_dead: bool = false
var current_weapon: Node = null
var is_local: bool = false

var _target_position: Vector2 = Vector2.ZERO
var _target_weapon_rotation: float = 0.0
var _sync_timer: float = 0.0
const SYNC_RATE: float = 0.05


func initialize(p_peer_id: int, p_team_id: int) -> void:
	peer_id = p_peer_id
	team_id = p_team_id
	is_local = (p_peer_id == NetworkManager.get_local_id())
	health = max_health
	modulate = TeamManager.get_color(team_id)
	# El feneri koni texture'ı
	flashlight.texture = _make_flashlight_texture()

	var player_data: Dictionary = NetworkManager.players.get(peer_id, {})
	name_label.text = player_data.get("name", "???")
	name_label.modulate = TeamManager.get_color(team_id)

	health_bar.max_value = max_health
	health_bar.value = health
	_target_position = global_position

	if is_local:
		var cam := Camera2D.new()
		cam.name = "Camera2D"
		cam.zoom = Vector2(1.5, 1.5)
		add_child(cam)

	_equip_default_weapon()


func _equip_default_weapon() -> void:
	var weapon_scene := preload("res://scenes/weapons/Weapon.tscn")
	current_weapon = weapon_scene.instantiate()
	weapon_holder.add_child(current_weapon)


# ─────────────────────────────────────────────
# Fizik Döngüsü
# ─────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if is_local:
		_handle_local_input(delta)
	else:
		_interpolate_remote(delta)


func _handle_local_input(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):    dir.y -= 1
	if Input.is_action_pressed("move_down"):  dir.y += 1
	if Input.is_action_pressed("move_left"):  dir.x -= 1
	if Input.is_action_pressed("move_right"): dir.x += 1
	velocity = dir.normalized() * speed
	move_and_slide()

	var mouse_world := get_global_mouse_position()
	weapon_holder.look_at(mouse_world)
	flashlight.look_at(mouse_world)

	if Input.is_action_pressed("shoot") and current_weapon:
		current_weapon.try_shoot(peer_id, team_id)

	if Input.is_action_just_pressed("reload") and current_weapon:
		current_weapon.reload()

	_sync_timer += delta
	if _sync_timer >= SYNC_RATE:
		_sync_timer = 0.0
		_broadcast_state.rpc(global_position, weapon_holder.rotation)


func _interpolate_remote(delta: float) -> void:
	var t: float = minf(delta * 20.0, 1.0)
	global_position = global_position.lerp(_target_position, t)
	weapon_holder.rotation = lerp_angle(weapon_holder.rotation, _target_weapon_rotation, t)


@rpc("any_peer", "unreliable_ordered")
func _broadcast_state(pos: Vector2, weapon_rot: float) -> void:
	if is_local:
		return
	_target_position = pos
	_target_weapon_rotation = weapon_rot


# ─────────────────────────────────────────────
# Hasar — sadece SERVER işler
# ─────────────────────────────────────────────

@rpc("any_peer", "reliable")
func take_damage(amount: float, shooter_peer_id: int) -> void:
	# Sadece server hasar hesaplar
	if not NetworkManager.is_host():
		return
	if is_dead:
		return
	health -= amount
	health = clamp(health, 0.0, max_health)
	# Tüm clientlara sağlığı gönder
	_sync_health.rpc(health)
	if health <= 0.0:
		_die(shooter_peer_id)


# any_peer: server başkasının node'una RPC gönderebilsin
@rpc("any_peer", "call_local", "reliable")
func _sync_health(new_health: float) -> void:
	health = new_health
	health_bar.value = health


# ─────────────────────────────────────────────
# Ölüm — server tetikler, herkese yayar
# ─────────────────────────────────────────────

func _die(killer_peer_id: int) -> void:
	_apply_death.rpc()
	GameManager.handle_player_death(peer_id, killer_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _apply_death() -> void:
	is_dead = true
	sprite.modulate = Color(0.3, 0.3, 0.3, 0.5)
	flashlight.enabled = false
	collision_shape.set_deferred("disabled", true)
	if current_weapon:
		current_weapon.hide()


# ─────────────────────────────────────────────
# Respawn — server tetikler, herkese yayar
# ─────────────────────────────────────────────

func respawn(spawn_pos: Vector2) -> void:
	_apply_respawn.rpc(spawn_pos)


@rpc("any_peer", "call_local", "reliable")
func _apply_respawn(spawn_pos: Vector2) -> void:
	is_dead = false
	health = max_health
	health_bar.value = health
	global_position = spawn_pos
	_target_position = spawn_pos
	sprite.modulate = Color.WHITE
	collision_shape.set_deferred("disabled", false)
	flashlight.enabled = true
	modulate = TeamManager.get_color(team_id)
	if current_weapon:
		current_weapon.show()
		current_weapon.refill_ammo()


# ─────────────────────────────────────────────
# El Feneri Texture (koni şekli)
# ─────────────────────────────────────────────

static func _make_flashlight_texture() -> ImageTexture:
	var size: int = 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	for x in range(size):
		for y in range(size):
			var dir := Vector2(x, y) - center
			var dist: float = dir.length() / (size * 0.5)
			# Koni: sağa (açı 0) bakan, ±50 derece açı
			var angle: float = absf(dir.angle())
			var cone: float = clampf(1.0 - angle / (PI * 0.28), 0.0, 1.0)
			var fade: float = clampf(1.0 - dist, 0.0, 1.0)
			var alpha: float = pow(cone, 2.5) * pow(fade, 1.2)
			img.set_pixel(x, y, Color(1.0, 0.97, 0.88, alpha))
	return ImageTexture.create_from_image(img)

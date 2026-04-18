## Weapon.gd (3D)
## Ateş etme, şarj ve mermi yönetimi.

extends Node3D

signal ammo_changed(current: int, total: int, reloading: bool)

@export var damage: float = 25.0
@export var fire_rate: float = 0.15
@export var bullet_speed: float = 30.0
@export var max_ammo: int = 30
@export var reload_time: float = 1.8
@export var spread_degrees: float = 2.0
@export var is_semi_auto: bool = false

@onready var muzzle: Marker3D = $Muzzle
@onready var fire_timer: Timer = $FireTimer
@onready var reload_timer: Timer = $ReloadTimer

var current_ammo: int = 0
var is_reloading: bool = false
var _ammo_label: Label3D = null
var bullet_scene: PackedScene = preload("res://scenes/weapons/Bullet.tscn")


func _ready() -> void:
	current_ammo = max_ammo
	fire_timer.wait_time = fire_rate
	reload_timer.wait_time = reload_time
	reload_timer.one_shot = true
	fire_timer.one_shot = true
	# AmmoLabel, Player.tscn'dedir — ağaçta iki seviye üstte
	var player := get_parent().get_parent()
	if player and player.has_node("AmmoLabel"):
		_ammo_label = player.get_node("AmmoLabel") as Label3D
	_update_ammo_label()


# ─────────────────────────────────────────────
# Ateş Etme
# ─────────────────────────────────────────────

func try_shoot(shooter_peer_id: int, shooter_team_id: int) -> void:
	if is_reloading or current_ammo <= 0 or not fire_timer.is_stopped():
		return

	current_ammo -= 1
	_update_ammo_label()
	fire_timer.start()

	# WeaponHolder (parent) yönünde ilerle: -Z lokal ekseni = hedefe doğru
	var holder: Node3D = get_parent()
	var forward: Vector3 = -holder.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()

	# Saçılma: Y ekseninde rastgele rotasyon
	var spread_rad := deg_to_rad(randf_range(-spread_degrees, spread_degrees))
	var spread_rot := Basis(Vector3.UP, spread_rad)
	var direction := (spread_rot * forward).normalized()

	_spawn_bullet.rpc(muzzle.global_position, direction, shooter_peer_id, shooter_team_id)

	if current_ammo <= 0:
		reload()


@rpc("any_peer", "call_local", "reliable")
func _spawn_bullet(
	spawn_pos: Vector3,
	direction: Vector3,
	shooter_peer_id: int,
	shooter_team_id: int
) -> void:
	var bullet: Node3D = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = spawn_pos
	bullet.initialize(direction, bullet_speed, damage, shooter_peer_id, shooter_team_id)


# ─────────────────────────────────────────────
# Yeniden Şarj
# ─────────────────────────────────────────────

func configure(config: Dictionary) -> void:
	damage         = config.get("damage",         damage)
	fire_rate      = config.get("fire_rate",      fire_rate)
	bullet_speed   = config.get("bullet_speed",   bullet_speed)
	max_ammo       = config.get("max_ammo",       max_ammo)
	reload_time    = config.get("reload_time",    reload_time)
	spread_degrees = config.get("spread_degrees", spread_degrees)
	is_semi_auto   = config.get("is_semi_auto",   is_semi_auto)
	current_ammo   = max_ammo
	fire_timer.wait_time   = fire_rate
	reload_timer.wait_time = reload_time
	_update_ammo_label()


func reload() -> void:
	if is_reloading or current_ammo == max_ammo:
		return
	is_reloading = true
	if _ammo_label:
		_ammo_label.text = "Şarj..."
	emit_signal("ammo_changed", current_ammo, max_ammo, true)
	reload_timer.start()
	await reload_timer.timeout
	current_ammo = max_ammo
	is_reloading = false
	_update_ammo_label()


func refill_ammo() -> void:
	current_ammo = max_ammo
	is_reloading = false
	reload_timer.stop()
	_update_ammo_label()


func _update_ammo_label() -> void:
	if _ammo_label:
		_ammo_label.text = "%d/%d" % [current_ammo, max_ammo]
	emit_signal("ammo_changed", current_ammo, max_ammo, false)

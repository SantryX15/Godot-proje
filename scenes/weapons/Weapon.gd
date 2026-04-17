## Weapon.gd
## Ateş etme, şarj ve mermi yönetimi.

extends Node2D

# ─────────────────────────────────────────────
# Silah Ayarları
# ─────────────────────────────────────────────
@export var damage: float = 25.0
@export var fire_rate: float = 0.15        # Atışlar arası saniye
@export var bullet_speed: float = 600.0
@export var max_ammo: int = 30
@export var reload_time: float = 1.8
@export var spread_degrees: float = 2.0   # Saçılma açısı

# ─────────────────────────────────────────────
# Node Referansları
# ─────────────────────────────────────────────
@onready var muzzle: Marker2D = $Muzzle
@onready var fire_timer: Timer = $FireTimer
@onready var reload_timer: Timer = $ReloadTimer
@onready var ammo_label: Label = $AmmoLabel

# ─────────────────────────────────────────────
# Değişkenler
# ─────────────────────────────────────────────
var current_ammo: int = 0
var is_reloading: bool = false
var bullet_scene: PackedScene = preload("res://scenes/weapons/Bullet.tscn")


func _ready() -> void:
	current_ammo = max_ammo
	fire_timer.wait_time = fire_rate
	reload_timer.wait_time = reload_time
	reload_timer.one_shot = true
	fire_timer.one_shot = true
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

	# Mermi açısını hesapla (saçılma ekle)
	var spread := deg_to_rad(randf_range(-spread_degrees, spread_degrees))
	var direction := Vector2.RIGHT.rotated(global_rotation + spread)

	# Sunucu yetkili mermi oluşturma
	_spawn_bullet.rpc(
		muzzle.global_position,
		direction,
		shooter_peer_id,
		shooter_team_id
	)

	if current_ammo <= 0:
		reload()


@rpc("any_peer", "call_local", "reliable")
func _spawn_bullet(
	spawn_pos: Vector2,
	direction: Vector2,
	shooter_peer_id: int,
	shooter_team_id: int
) -> void:
	var bullet: Node2D = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = spawn_pos
	bullet.initialize(direction, bullet_speed, damage, shooter_peer_id, shooter_team_id)


# ─────────────────────────────────────────────
# Yeniden Şarj
# ─────────────────────────────────────────────

func reload() -> void:
	if is_reloading or current_ammo == max_ammo:
		return
	is_reloading = true
	ammo_label.text = "Şarj ediliyor..."
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
	if ammo_label:
		ammo_label.text = "%d / %d" % [current_ammo, max_ammo]

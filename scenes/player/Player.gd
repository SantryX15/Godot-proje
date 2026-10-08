## Player.gd (3D)
## WASD hareketi, mouse ile nişan alma, ateş etme, SpotLight3D el feneri ve sağlık sistemi.

extends CharacterBody3D

signal health_changed(new_health: float)
signal ammo_changed(current: int, total: int, reloading: bool)

@export var speed: float = 8.0
@export var max_health: float = 100.0

@onready var flashlight: SpotLight3D = $Flashlight
@onready var body_light: OmniLight3D = $BodyLight
@onready var health_label: Label3D = $HealthLabel
@onready var name_label: Label3D = $NameLabel
@onready var ammo_label: Label3D = $AmmoLabel
@onready var card_indicator: Label3D = $CardIndicatorLabel
@onready var weapon_holder: Node3D = $WeaponHolder
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

const GRAVITY := 9.8
const SYNC_RATE: float = 0.05
const BODY_LIGHT_LAYER_BIT: int = 20  # BodyLight'ın sadece karakter mesh'ine değmesi için özel render layer
const SELF_RIM_SHADER: Shader = preload("res://scenes/player/SelfVisibility.gdshader")

const CHARACTER_STATS: Dictionary = {
	"Tank":     {"health": 150.0, "speed": 5.5},
	"Visioner": {"health": 100.0, "speed": 8.0},
	"Runner":   {"health": 75.0,  "speed": 13.0},
	"Sniper":   {"health": 80.0,  "speed": 7.0},
	"Medic":    {"health": 110.0, "speed": 7.5},
}

const WEAPON_CONFIGS: Dictionary = {
	"Tank":     {"damage": 22.0,  "fire_rate": 0.10, "max_ammo": 30, "reload_time": 2.0, "spread_degrees": 3.0, "bullet_speed": 32.0, "is_semi_auto": false, "max_distance": 45.0},
	"Visioner": {"damage": 18.0,  "fire_rate": 0.09, "max_ammo": 28, "reload_time": 1.7, "spread_degrees": 2.5, "bullet_speed": 32.0, "is_semi_auto": false, "max_distance": 35.0},
	"Runner":   {"damage": 11.0,  "fire_rate": 0.06, "max_ammo": 40, "reload_time": 1.2, "spread_degrees": 4.5, "bullet_speed": 30.0, "is_semi_auto": false, "max_distance": 25.0},
	"Sniper":   {"damage": 120.0, "fire_rate": 0.5,  "max_ammo": 1,  "reload_time": 2.5, "spread_degrees": 0.0, "bullet_speed": 80.0, "is_semi_auto": true,  "max_distance": 130.0},
	"Medic":    {"damage": 45.0,  "fire_rate": 0.4,  "max_ammo": 7,  "reload_time": 2.0, "spread_degrees": 1.5, "bullet_speed": 35.0, "is_semi_auto": true,  "max_distance": 55.0},
}

var peer_id: int = 0
var team_id: int = -1
var character_type: String = "Visioner"
var health: float = 100.0
var is_dead: bool = false
var current_weapon: Node = null
var is_local: bool = false
var has_card: bool = false

var _char_mesh: Node3D = null
var _anim_player: AnimationPlayer = null
var _target_position: Vector3 = Vector3.ZERO
var _target_aim_y: float = 0.0
var _sync_timer: float = 0.0
var _card_pickup_blocked: float = 0.0


func initialize(p_peer_id: int, p_team_id: int, p_character: String = "Visioner") -> void:
	character_type = p_character
	var char_stats: Dictionary = CHARACTER_STATS.get(p_character, CHARACTER_STATS["Visioner"])
	max_health = char_stats["health"]
	speed      = char_stats["speed"]

	peer_id = p_peer_id
	team_id = p_team_id
	is_local = (p_peer_id == NetworkManager.get_local_id())
	floor_snap_length = 0.3  # Zemin tespitini güvenilir yapar, hız dalgalanmasını engeller
	health = max_health

	# FBX karakter mesh'ini bul
	_char_mesh = get_node_or_null("CharacterMesh")
	if _char_mesh:
		_anim_player = _find_anim_player(_char_mesh)
		_play_idle()
		# BodyLight sadece karakter mesh'ine değsin (zemine/duvara ışık/gölge taşmasın)
		_add_render_layer(_char_mesh, BODY_LIGHT_LAYER_BIT)
		# Flashlight kendi gövdesinden devasa gölge atmasın
		_disable_shadow_casting(_char_mesh)
		# Kendi karakterini karanlıkta görünür kılan kenar parıltısı — sadece yerel oyuncuda
		if is_local:
			_apply_self_rim(_char_mesh)

	# Tüm billboard label'lar gizlendi — bilgiler ekran HUD'ında gösterilir
	health_label.visible  = false
	name_label.visible    = false
	ammo_label.visible    = false
	card_indicator.visible = false

	# Kart göstergesi: büyük, okunaklı
	card_indicator.font_size       = 72
	card_indicator.outline_size    = 14
	card_indicator.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	card_indicator.no_depth_test   = true

	# Body ışığı sadece yerel oyuncuda — uzak oyuncuların üzerinde hale olmasın
	body_light.visible = is_local

	_target_position = global_position
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	reset_physics_interpolation()

	_equip_default_weapon()


func _add_render_layer(node: Node, layer_bit: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).set_layer_mask_value(layer_bit, true)
	for child in node.get_children():
		_add_render_layer(child, layer_bit)


func _apply_self_rim(node: Node) -> void:
	# material_overlay: mevcut malzemeyi bozmadan üstüne unshaded bir kenar parıltısı pass'i ekler.
	# Gerçek ışık değildir, sadece bu client'ta render edilir — zemine/duvara etkisi yok,
	# diğer oyuncular (kendi sahnelerini kendileri render ettiği için) bunu hiç görmez.
	if node is GeometryInstance3D:
		var mat := ShaderMaterial.new()
		mat.shader = SELF_RIM_SHADER
		(node as GeometryInstance3D).material_overlay = mat
	for child in node.get_children():
		_apply_self_rim(child)


func _disable_shadow_casting(node: Node) -> void:
	# El feneri kendi gövdesinden/silahtan devasa gölge atmasın
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadow_casting(child)


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result := _find_anim_player(child)
		if result:
			return result
	return null


func _play_idle() -> void:
	if _anim_player == null:
		return
	var all_anims := _anim_player.get_animation_list()
	if all_anims.is_empty():
		return
	# Tam isim eşleşmesi
	var candidates := ["mixamo_com", "mixamo.com", "Breathing Idle", "idle", "Idle"]
	var anim_name := ""
	for c in candidates:
		if _anim_player.has_animation(c):
			anim_name = c
			break
	# Library prefix ile arama ("LibName/AnimName" formatı)
	if anim_name.is_empty():
		for c in candidates:
			for a: StringName in all_anims:
				var s := a as String
				if s == c or s.ends_with("/" + c):
					anim_name = s
					break
			if not anim_name.is_empty():
				break
	# Son çare: RESET dışındaki ilk animasyon
	if anim_name.is_empty():
		for a: StringName in all_anims:
			if (a as String) != "RESET":
				anim_name = a
				break
	if anim_name.is_empty():
		return
	var anim: Animation = _anim_player.get_animation(anim_name)
	if anim and anim.loop_mode == Animation.LOOP_NONE:
		anim.loop_mode = Animation.LOOP_LINEAR
	_anim_player.play(anim_name)


func _equip_default_weapon() -> void:
	var weapon_scene := preload("res://scenes/weapons/Weapon.tscn")
	current_weapon = weapon_scene.instantiate()
	weapon_holder.add_child(current_weapon)
	if is_local:
		current_weapon.ammo_changed.connect(
			func(cur: int, tot: int, rel: bool): emit_signal("ammo_changed", cur, tot, rel)
		)
	current_weapon.configure(WEAPON_CONFIGS.get(character_type, WEAPON_CONFIGS["Visioner"]))
	_add_render_layer(current_weapon, BODY_LIGHT_LAYER_BIT)
	_disable_shadow_casting(current_weapon)


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
	if _card_pickup_blocked > 0.0:
		_card_pickup_blocked -= delta

	# WASD hareketi (X/Z düzlemi) — önce yatay hız, sonra yerçekimi
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_up"):    dir.z -= 1
	if Input.is_action_pressed("move_down"):  dir.z += 1
	if Input.is_action_pressed("move_left"):  dir.x -= 1
	if Input.is_action_pressed("move_right"): dir.x += 1
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	# Yerçekimi
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()

	# Mouse hedefine bak — gövde, silah ve el feneri birlikte döner (asker gibi hedefe yönelme)
	var aim := _get_aim_target()
	var flat_aim := Vector3(aim.x, global_position.y, aim.z)
	if flat_aim.distance_to(global_position) > 0.1:
		look_at(flat_aim, Vector3.UP)

	# Ateş et (semi-auto: sadece tıklama anında; otomatik: basılı tutunca)
	var shoot_pressed: bool
	if current_weapon and current_weapon.is_semi_auto:
		shoot_pressed = Input.is_action_just_pressed("shoot")
	else:
		shoot_pressed = Input.is_action_pressed("shoot")
	if shoot_pressed and current_weapon:
		current_weapon.try_shoot(peer_id, team_id)

	if Input.is_action_just_pressed("reload") and current_weapon:
		current_weapon.reload()

	# Pozisyon senkronizasyonu
	_sync_timer += delta
	if _sync_timer >= SYNC_RATE:
		_sync_timer = 0.0
		if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
			_broadcast_state.rpc(global_position, rotation.y)


func _get_aim_target() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return global_position + Vector3(0, 0, -1)
	var mouse := get_viewport().get_mouse_position()
	var from  := cam.project_ray_origin(mouse)
	var dir   := cam.project_ray_normal(mouse)
	if absf(dir.y) < 0.001:
		return global_position
	var t := (0.9 - from.y) / dir.y
	return from + dir * t


func _interpolate_remote(delta: float) -> void:
	var t := minf(delta * 20.0, 1.0)
	global_position = global_position.lerp(_target_position, t)
	rotation.y = lerp_angle(rotation.y, _target_aim_y, t)


@rpc("any_peer", "unreliable_ordered")
func _broadcast_state(pos: Vector3, aim_y: float) -> void:
	if is_local:
		return
	_target_position = pos
	_target_aim_y = aim_y


# ─────────────────────────────────────────────
# Hasar — sadece SERVER işler
# ─────────────────────────────────────────────

@rpc("any_peer", "reliable")
func take_damage(amount: float, shooter_peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	if is_dead:
		return
	health -= amount
	health = clampf(health, 0.0, max_health)
	_sync_health.rpc(health)
	if health <= 0.0:
		_die(shooter_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _sync_health(new_health: float) -> void:
	health = new_health
	if is_local:
		emit_signal("health_changed", health)


# ─────────────────────────────────────────────
# Ölüm
# ─────────────────────────────────────────────

func _die(killer_peer_id: int) -> void:
	_apply_death.rpc()
	GameManager.handle_player_death(peer_id, killer_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _apply_death() -> void:
	is_dead = true
	has_card = false
	if _char_mesh:
		_char_mesh.visible = false
	flashlight.visible = false
	body_light.visible = false
	collision_shape.set_deferred("disabled", true)
	if current_weapon:
		current_weapon.hide()
	card_indicator.visible = false


# ─────────────────────────────────────────────
# Respawn
# ─────────────────────────────────────────────

func respawn(spawn_pos: Vector3) -> void:
	_apply_respawn.rpc(spawn_pos)


@rpc("any_peer", "call_local", "reliable")
func _apply_respawn(spawn_pos: Vector3) -> void:
	is_dead = false
	has_card = false
	health = max_health
	if is_local:
		emit_signal("health_changed", health)
	global_position = spawn_pos
	_target_position = spawn_pos
	_card_pickup_blocked = 0.5
	reset_physics_interpolation()
	if _char_mesh:
		_char_mesh.visible = true
		_play_idle()
	collision_shape.disabled = false
	flashlight.visible = true
	body_light.visible = is_local
	card_indicator.visible = false
	if current_weapon:
		current_weapon.show()
		current_weapon.refill_ammo()


# ─────────────────────────────────────────────
# Kart Taşıma
# ─────────────────────────────────────────────

func pick_up_card() -> void:
	has_card = true
	# Sadece taşıyıcının kendi takımı (ve kendisi) görür
	var local_id  := NetworkManager.get_local_id()
	var local_team: int = NetworkManager.players.get(local_id, {}).get("team_id", -1)
	card_indicator.visible = (local_team == team_id)


func drop_card() -> void:
	has_card = false
	card_indicator.visible = false

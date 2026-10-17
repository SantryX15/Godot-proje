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

## Animasyon (SurvivalistModel kütüphanesi: Idle/Run/Walk/Death/...)
const ANIM_IDLE := &"Idle"
const ANIM_RUN := &"Run"
const ANIM_WALK := &"Walk"
const ANIM_CROUCH := &"CrouchWalk"
const ANIM_CROUCH_IDLE := &"CrouchIdle"
const ANIM_DEATH := &"Death"
const ANIM_BLEND := 0.18             # geçiş süresi (sn)
const ANIM_MOVE_THRESHOLD := 0.4     # m/s üstü = hareket ediyor

## Hareket modu — varsayılan yürüyüş, Shift koşu (dayanıklılıklı), Ctrl çömelme (süreli, mermiler üstünden geçer).
## Local tuşlar, uzaklara _broadcast_state ile senkron (host çömelme bağışıklığını bu değerle uygular).
enum MoveMode { RUN, WALK, CROUCH }
const MOVE_SPEED_MULT: Array[float] = [1.0, 0.55, 0.35]           # karakter hızının çarpanı (speed = koşu hızı)
const MOVE_ANIMS: Array[StringName] = [&"Run", &"Walk", &"CrouchWalk"]
## Animasyonun 1.0x oynadığı hız (m/s) — ayak kaymasın diye gerçek hızla oranlanır
## (Run: Tank 5.5 → ~0.9x, Runner 13 → ~2.2x; Walk/Crouch karakter hızının %55/%35'i)
const MOVE_ANIM_REF_SPEED: Array[float] = [6.0, 3.0, 2.0]
var move_mode: int = MoveMode.WALK

## Dayanıklılık (0..1) — sadece local oyuncuda işler, HUD okur
const SPRINT_MAX_TIME := 4.0        # tam dolu → kaç sn koşulur
const SPRINT_REGEN_TIME := 5.0      # boştan tama dolma süresi
const SPRINT_UNLOCK := 0.4          # tükendiyse bu seviyeye dolana kadar koşulamaz
const CROUCH_MAX_TIME := 3.0        # basılı tutarak en fazla
const CROUCH_REGEN_TIME := 4.0
const CROUCH_UNLOCK := 0.5
const STAMINA_REGEN_DELAY := 0.6    # bıraktıktan sonra dolmaya başlama gecikmesi
const DAMAGE_BULLET := 0
const DAMAGE_EXPLOSION := 1
var sprint_stamina := 1.0
var crouch_stamina := 1.0
var sprint_locked := false          # tükendi, yenileniyor
var crouch_locked := false
var _sprint_delay := 0.0
var _crouch_delay := 0.0

## Bacak yönü / omurga dönüşü (bkz _update_leg_facing)
const MAX_SPINE_TWIST := 1.92  # ~110°
const LEG_TURN_SPEED := 10.0
const AIM_CORR_GAIN := 10.0    # tüfek→nişan hizalama hızı (1/sn)
const MAX_AIM_CORR := 1.4      # ~80° en fazla düzeltme
var _aim_corr := 0.0
var _leg_yaw := 0.0
var _mesh_base_basis := Basis.IDENTITY
const SPINE_TWIST_SCRIPT := preload("res://scenes/player/SpineTwistModifier.gd")
const UPPER_BODY_SCRIPT := preload("res://scenes/player/UpperBodyLayer.gd")
const HAND_RIFLE_SCRIPT := preload("res://scenes/player/HandRifle.gd")
var _upper: Node = null       # UpperBodyLayer — tüfek pozları (AimIdle taban + aksiyonlar)
var _hand_rifle: Node = null  # HandRifle — tüfek görseli eller arasında

## Üst gövde aksiyonları (_action_rpc ile diğer peer'lara da oynatılır)
enum Action { RELOAD, TOSS, HIT }
const ANIM_AIM := &"AimIdle"
const ANIM_FIRE_STAND := &"FireStand"
const ANIM_FIRE_WALK := &"FireWalk"
const ANIM_RELOAD := &"Reload"
const ANIM_TOSS := &"Toss"
const ANIM_HIT := &"HitReact"
const ANIM_DYING := &"Dying"
const DYING_SPEED := 1.6          # Dying 4.4 s → ~2.75 s (respawn 3 s'den önce bitsin)
const TOSS_DURATION := 1.2        # Toss 3.2 s → bomba fırlatma hızında
const FIRE_HOLD := 0.22           # son atıştan sonra ateş pozu ne kadar sürsün
var _spine_twist: Node = null  # SpineTwistModifier (preload — global class cache'e bağımlı olmasın)
var _idle_anim: StringName = &""
var _last_anim_pos: Vector3 = Vector3.ZERO
var _move_speed := 0.0
var _death_token := 0
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
		# Karaktere göre kıyafet (SurvivalistModel.apply_outfit)
		if _char_mesh.has_method("apply_outfit"):
			_char_mesh.apply_outfit(p_character)
		# Bacaklar hareket yönüne / üst gövde nişana (bkz _update_leg_facing)
		_mesh_base_basis = _char_mesh.transform.basis
		var skeletons := _char_mesh.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty() and _spine_twist == null:
			var sk := skeletons[0] as Skeleton3D
			# Modifier sırası önemli: üst gövde pozu → omurga dönüşü → tüfek ellere hizalanır
			_upper = UPPER_BODY_SCRIPT.new()
			sk.add_child(_upper)
			_spine_twist = SPINE_TWIST_SCRIPT.new()
			sk.add_child(_spine_twist)
			var rifle: Node3D = HAND_RIFLE_SCRIPT.build_rifle_mesh()
			sk.add_child(rifle)
			_hand_rifle = HAND_RIFLE_SCRIPT.new()
			_hand_rifle.rifle = rifle
			_hand_rifle.aim_node = self  # root -Z = nişan
			sk.add_child(_hand_rifle)
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
	_last_anim_pos = global_position
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
	var candidates := ["Idle", "mixamo_com", "mixamo.com", "Breathing Idle", "idle"]
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
	_idle_anim = StringName(anim_name)
	_anim_player.speed_scale = 1.0
	_anim_player.play(anim_name)


## Hareket animasyonu (local + uzak oyuncular): hız konum farkından ölçülür (uzaklarda velocity yok),
## mod (koşu/yürüyüş/eğilme) local'de tuşlardan, uzakta _broadcast_state'ten gelir.
## Hareket: Run / Walk / CrouchWalk — adım hızı gerçek hıza göre, bakışa ters gidişte ters oynar.
## Duruş: Idle; eğilirken CrouchWalk ilk karesinde donar (ayrı çömelme-bekleme animasyonu yok).
func _update_animation(delta: float) -> void:
	if _anim_player == null or delta <= 0.0:
		return
	var p := global_position
	var step := Vector3(p.x - _last_anim_pos.x, 0.0, p.z - _last_anim_pos.z)
	_last_anim_pos = p
	_move_speed = lerpf(_move_speed, step.length() / delta, 1.0 - exp(-12.0 * delta))

	var moving := _move_speed > ANIM_MOVE_THRESHOLD
	_update_leg_facing(step, moving, delta)

	var clip: StringName = MOVE_ANIMS[move_mode]
	if not _anim_player.has_animation(clip):
		clip = ANIM_RUN
	if moving and _anim_player.has_animation(clip):
		# Bacaklar hareket yönüne döndüğü için animasyon hep ileri oynar
		_set_anim(clip, clampf(_move_speed / float(MOVE_ANIM_REF_SPEED[move_mode]), 0.6, 2.2))
	elif move_mode == MoveMode.CROUCH and _anim_player.has_animation(ANIM_CROUCH_IDLE):
		# Olduğu yerde çömelme: durağan CrouchIdle (SurvivalistModel üretir). speed_scale=0 KULLANMA —
		# AnimationPlayer geçişi (blend) de durur ve karakter Idle'da takılı kalır.
		_set_anim(ANIM_CROUCH_IDLE, 1.0)
	else:
		# "Idle" varsa her zaman onu kullan (kütüphane initialize'dan sonra yüklenmiş olsa bile)
		var idle: StringName = ANIM_IDLE if _anim_player.has_animation(ANIM_IDLE) else _idle_anim
		if idle != &"":
			_set_anim(idle, 1.0)


## Bacaklar hareket yönüne, üst gövde nişana: Player ROOT (= nişan, fener + silah) fareye bakmaya devam eder;
## sadece CharacterMesh root'a göre `_leg_yaw` kadar döner, omurga (SpineTwistModifier) aynı açıyı geri çevirir
## (en fazla MAX_SPINE_TWIST — fare tam arkadaysa üst gövde bir miktar yana bakar). Dururken bacaklar nişana döner.
func _update_leg_facing(step: Vector3, moving: bool, delta: float) -> void:
	if _char_mesh == null:
		return
	var target := 0.0
	if moving and step.length() > 0.0001:
		var move_yaw := atan2(-step.x, -step.z)  # rotation.y = θ ⇒ ileri = (-sinθ, 0, -cosθ)
		target = wrapf(move_yaw - rotation.y, -PI, PI)
	# Hedefi mevcut açıya göre aç (±180° civarında sağ/sol arasında zıplamasın)
	target = _leg_yaw + wrapf(target - _leg_yaw, -PI, PI)
	_leg_yaw = wrapf(lerpf(_leg_yaw, target, 1.0 - exp(-LEG_TURN_SPEED * delta)), -PI, PI)
	_char_mesh.transform.basis = Basis(Vector3.UP, _leg_yaw) * _mesh_base_basis
	# Nişan düzeltmesi: tüfek namlusu nişan yönüne bakana kadar omurgayı yumuşakça çevir (HandRifle ölçer).
	# Mixamo nişan pozu tüfeği gövdenin ~60° soluna tutar → düzeltme ~-60°'ye oturur. Şarjör/bomba sırasında dondurulur.
	if _hand_rifle and _hand_rifle.aim_valid and not (_upper and _upper.is_busy()):
		_aim_corr = clampf(_aim_corr - _hand_rifle.aim_error * minf(AIM_CORR_GAIN * delta, 1.0), -MAX_AIM_CORR, MAX_AIM_CORR)
	if _spine_twist:
		_spine_twist.twist = clampf(-_leg_yaw + _aim_corr, -MAX_SPINE_TWIST - MAX_AIM_CORR, MAX_SPINE_TWIST + MAX_AIM_CORR)


func _reset_leg_facing() -> void:
	_leg_yaw = 0.0
	if _char_mesh:
		_char_mesh.transform.basis = _mesh_base_basis
	if _spine_twist:
		_spine_twist.twist = 0.0


func _set_anim(anim_name: StringName, rate: float) -> void:
	if _anim_player.current_animation != anim_name:
		_anim_player.play(anim_name, ANIM_BLEND)
	_anim_player.speed_scale = rate


func _equip_default_weapon() -> void:
	var weapon_scene := preload("res://scenes/weapons/Weapon.tscn")
	current_weapon = weapon_scene.instantiate()
	weapon_holder.add_child(current_weapon)
	if is_local:
		current_weapon.ammo_changed.connect(
			func(cur: int, tot: int, rel: bool): emit_signal("ammo_changed", cur, tot, rel)
		)
		# Şarjör değişimi başladı → herkese Reload animasyonu
		current_weapon.ammo_changed.connect(func(_c: int, _t: int, rel: bool) -> void:
			if rel:
				_broadcast_action(Action.RELOAD))
	# Atış her peer'da tetiklenir (_spawn_bullet call_local) → ateş pozu
	current_weapon.fired.connect(_on_weapon_fired)
	current_weapon.configure(WEAPON_CONFIGS.get(character_type, WEAPON_CONFIGS["Visioner"]))
	_add_render_layer(current_weapon, BODY_LIGHT_LAYER_BIT)
	_disable_shadow_casting(current_weapon)
	# Üst gövde taban pozu: tüfek nişanda
	if _upper and _anim_player and _anim_player.has_animation(ANIM_AIM):
		_upper.set_base(_anim_player.get_animation(ANIM_AIM))


# ─────────────────────────────────────────────
# Üst gövde aksiyonları + tüfek görseli
# ─────────────────────────────────────────────

func _on_weapon_fired() -> void:
	if _upper == null or _anim_player == null or is_dead:
		return
	var clip := ANIM_FIRE_WALK if _move_speed > ANIM_MOVE_THRESHOLD else ANIM_FIRE_STAND
	if _anim_player.has_animation(clip):
		var hold_time: float = FIRE_HOLD + (current_weapon.fire_rate if current_weapon else 0.0)
		_upper.hold(_anim_player.get_animation(clip), hold_time)


## Local oyuncu: aksiyonu herkese oynat (bağlı peer yoksa sadece kendine)
func _broadcast_action(action: int) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_action_rpc.rpc(action)
	else:
		_action_rpc(action)


@rpc("any_peer", "call_local", "reliable")
func _action_rpc(action: int) -> void:
	play_action(action)


## Üst gövde aksiyonu (sadece görsel). Bomba fırlatmayı PowerupManager._bomb_rpc her peer'da çağırır.
func play_action(action: int) -> void:
	if _upper == null or _anim_player == null or is_dead:
		return
	match action:
		Action.RELOAD:
			if _anim_player.has_animation(ANIM_RELOAD):
				_upper.play_once(_anim_player.get_animation(ANIM_RELOAD), current_weapon.reload_time if current_weapon else -1.0)
		Action.TOSS:
			if _anim_player.has_animation(ANIM_TOSS):
				_upper.play_once(_anim_player.get_animation(ANIM_TOSS), TOSS_DURATION)
		Action.HIT:
			# Şarjör/bomba atma sürerken sarsılma onları bölmesin
			if _anim_player.has_animation(ANIM_HIT) and not _upper.is_busy():
				_upper.play_once(_anim_player.get_animation(ANIM_HIT), -1.0, 0.65)


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
	_update_animation(delta)


func _handle_local_input(delta: float) -> void:
	if _card_pickup_blocked > 0.0:
		_card_pickup_blocked -= delta

	# Sohbete yazılırken hareket/ateş/şarjör tuşları devre dışı (nişan + senkron devam eder)
	var typing := ChatBox.is_typing

	# WASD hareketi (X/Z düzlemi) — önce yatay hız, sonra yerçekimi
	var dir := Vector3.ZERO
	if not typing:
		if Input.is_action_pressed("move_up"):    dir.z -= 1
		if Input.is_action_pressed("move_down"):  dir.z += 1
		if Input.is_action_pressed("move_left"):  dir.x -= 1
		if Input.is_action_pressed("move_right"): dir.x += 1
	dir = dir.normalized()

	# Hareket modu: varsayılan yürüyüş; Ctrl = çömelme, Shift = koşu (ikisi de süreli + yenilenir)
	_update_move_mode(dir, typing, delta)
	var move_speed: float = speed * MOVE_SPEED_MULT[move_mode]
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed

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
	if shoot_pressed and current_weapon and not typing:
		current_weapon.try_shoot(peer_id, team_id)

	if Input.is_action_just_pressed("reload") and current_weapon and not typing:
		current_weapon.reload()

	# Pozisyon senkronizasyonu
	_sync_timer += delta
	if _sync_timer >= SYNC_RATE:
		_sync_timer = 0.0
		if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
			_broadcast_state.rpc(global_position, rotation.y, move_mode)


## Çömelme (Ctrl basılı, en fazla CROUCH_MAX_TIME) önceliklidir; sonra koşu (Shift + hareket, SPRINT_MAX_TIME).
## Tükenen dayanıklılık kilitlenir, *_UNLOCK seviyesine dolana kadar o mod kullanılamaz. Bırakınca
## STAMINA_REGEN_DELAY sonra dolar. Çömelmesi biten oyuncu otomatik kalkar.
func _update_move_mode(dir: Vector3, typing: bool, delta: float) -> void:
	var want_crouch := not typing and Input.is_physical_key_pressed(KEY_CTRL)
	var want_sprint := not typing and Input.is_physical_key_pressed(KEY_SHIFT) and dir != Vector3.ZERO
	move_mode = MoveMode.WALK

	if want_crouch and not crouch_locked and crouch_stamina > 0.0:
		move_mode = MoveMode.CROUCH
		crouch_stamina = maxf(crouch_stamina - delta / CROUCH_MAX_TIME, 0.0)
		_crouch_delay = STAMINA_REGEN_DELAY
		if crouch_stamina <= 0.0:
			crouch_locked = true
	else:
		_crouch_delay -= delta
		if _crouch_delay <= 0.0:
			crouch_stamina = minf(crouch_stamina + delta / CROUCH_REGEN_TIME, 1.0)
		if crouch_locked and crouch_stamina >= CROUCH_UNLOCK:
			crouch_locked = false

	if move_mode != MoveMode.CROUCH and want_sprint and not sprint_locked and sprint_stamina > 0.0:
		move_mode = MoveMode.RUN
		sprint_stamina = maxf(sprint_stamina - delta / SPRINT_MAX_TIME, 0.0)
		_sprint_delay = STAMINA_REGEN_DELAY
		if sprint_stamina <= 0.0:
			sprint_locked = true
	else:
		_sprint_delay -= delta
		if _sprint_delay <= 0.0:
			sprint_stamina = minf(sprint_stamina + delta / SPRINT_REGEN_TIME, 1.0)
		if sprint_locked and sprint_stamina >= SPRINT_UNLOCK:
			sprint_locked = false


func _reset_stamina() -> void:
	sprint_stamina = 1.0
	crouch_stamina = 1.0
	sprint_locked = false
	crouch_locked = false
	move_mode = MoveMode.WALK


## Çömelmiş (ve canlı) oyuncunun üstünden mermi geçer — Bullet.gd ve host take_damage kullanır
func is_crouching() -> bool:
	return move_mode == MoveMode.CROUCH and not is_dead


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
func _broadcast_state(pos: Vector3, aim_y: float, mode: int = MoveMode.WALK) -> void:
	if is_local:
		return
	_target_position = pos
	_target_aim_y = aim_y
	move_mode = clampi(mode, MoveMode.RUN, MoveMode.CROUCH)


# ─────────────────────────────────────────────
# Hasar — sadece SERVER işler
# ─────────────────────────────────────────────

## source: DAMAGE_BULLET (mermi — çömelmiş hedefe işlemez) / DAMAGE_EXPLOSION (bomba — çömelme korumaz)
@rpc("any_peer", "reliable")
func take_damage(amount: float, shooter_peer_id: int, source: int = DAMAGE_BULLET) -> void:
	if not NetworkManager.is_host():
		return
	if is_dead:
		return
	# Çömelme: mermiler üstünden geçer (host, hedefin _broadcast_state ile gelen moduna göre karar verir)
	if source == DAMAGE_BULLET and is_crouching():
		return
	health -= amount
	health = clampf(health, 0.0, max_health)
	_sync_health.rpc(health)
	if health <= 0.0:
		_die(shooter_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _sync_health(new_health: float) -> void:
	# Hasar aldı (ölmedi) → her peer'da sarsılma
	if new_health < health and new_health > 0.0:
		play_action(Action.HIT)
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
	_death_token += 1
	_reset_leg_facing()
	if _upper:
		_upper.set_enabled_smooth(false)  # tam gövde ölüm animasyonu
	if _char_mesh:
		# Mixamo Dying (daha dramatik) varsa onu, yoksa UE Death
		var death_clip := ANIM_DYING if _anim_player and _anim_player.has_animation(ANIM_DYING) else ANIM_DEATH
		var rate := DYING_SPEED if death_clip == ANIM_DYING else 1.0
		if _anim_player and _anim_player.has_animation(death_clip):
			# Ölüm animasyonu oynar, bitince ceset gizlenir (arada respawn olursa gizleme iptal)
			_anim_player.speed_scale = rate
			_anim_player.play(death_clip, ANIM_BLEND)
			_hide_corpse_later(_death_token, _anim_player.get_animation(death_clip).length / rate + 0.6)
		else:
			_char_mesh.visible = false
	flashlight.visible = false
	body_light.visible = false
	collision_shape.set_deferred("disabled", true)
	if current_weapon:
		current_weapon.hide()
	card_indicator.visible = false


func _hide_corpse_later(token: int, wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	if not is_instance_valid(self) or token != _death_token or not is_dead:
		return
	if _char_mesh:
		_char_mesh.visible = false


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
	_last_anim_pos = spawn_pos  # ışınlanma koşu animasyonu tetiklemesin
	_move_speed = 0.0
	_death_token += 1
	_reset_leg_facing()
	_reset_stamina()
	_card_pickup_blocked = 0.5
	reset_physics_interpolation()
	if _char_mesh:
		_char_mesh.visible = true
		_play_idle()
	if _upper:
		_upper.set_enabled_smooth(true)
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

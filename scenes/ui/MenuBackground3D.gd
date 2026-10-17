## MenuBackground3D.gd — Ana menü + Lobi arka planı: karanlık taktik ızgara üzerinde el feneriyle devriye gezen askerler.
## Kendi World3D'si olan SubViewport (oyun dünyasından bağımsız). Tamamen görsel, ağ/oyun mantığı yok.
##  - Askerler: Survivalist modeli + rastgele karakter kıyafeti, tüfek (HandRifle) + AimIdle üst gövde, Walk bacaklar.
##    Rastgele hedeflere yavaşça yürür, arada durup etrafı tarar, birbirinden kaçınır. Her birinin feneri var.
##  - Fare: yukarıdan fareye bakan spot ışık (eski 2D el feneri efektinin 3D hali). `light_color` lobide takım rengine döner.
## Kullanım: MainMenu/Lobby `preload(...).new()` → add_child (en altta), üstüne MenuOverlay.gdshader vinyeti.

extends SubViewportContainer

const SURVIVALIST := preload("res://scenes/player/SurvivalistModel.tscn")
const UPPER_BODY := preload("res://scenes/player/UpperBodyLayer.gd")
const SPINE_TWIST := preload("res://scenes/player/SpineTwistModifier.gd")
const HAND_RIFLE := preload("res://scenes/player/HandRifle.gd")
const FLOOR_SHADER := preload("res://scenes/ui/MenuFloor.gdshader")

const SOLDIER_COUNT := 5
const CHARACTERS: Array[String] = ["Tank", "Visioner", "Runner", "Sniper", "Medic"]
const BOUNDS := Vector2(9.0, 5.0)         # devriye alanı (kameradan görünen zemin, ±x / ±z)
const WALK_SPEED := Vector2(0.85, 1.35)    # m/s
const WALK_ANIM_REF := 1.3                 # Walk animasyonu bu hızda 1.0x (ayak kaymasın)
const TURN_RATE := 1.6                     # rad/s
const SEPARATION := 2.2                    # bu mesafeden yakın askerler birbirinden uzaklaşır

## Fare el fenerinin rengi (Lobby takım rengine göre ayarlar)
var light_color: Color = UITheme.ACCENT:
	set(v):
		light_color = v
		if _mouse_light:
			_mouse_light.light_color = v

var _vp: SubViewport
var _cam: Camera3D
var _mouse_light: SpotLight3D
var _mouse_target := Vector3.ZERO
var _walkers: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Ofsetler de sıfırlanmalı — set_anchors_preset ofsetleri koruyup boyutu 0 bırakıyordu
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()

	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = UITheme.BG
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.3, 0.33, 0.42)
	env.environment.ambient_light_energy = 0.07
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	env.environment.glow_intensity = 0.5
	_vp.add_child(env)

	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 60)
	floor_mesh.mesh = pm
	var fm := ShaderMaterial.new()
	fm.shader = FLOOR_SHADER
	floor_mesh.material_override = fm
	_vp.add_child(floor_mesh)

	_cam = Camera3D.new()
	_cam.fov = 42.0
	_vp.add_child(_cam)
	_cam.look_at_from_position(Vector3(0, 11.0, 8.0), Vector3(0, 0, 0.3))

	# Fareyi takip eden el feneri (yukarıdan, hafif önden)
	_mouse_light = SpotLight3D.new()
	_mouse_light.light_color = light_color
	_mouse_light.light_energy = 14.0
	_mouse_light.spot_range = 24.0
	_mouse_light.spot_angle = 15.0
	_mouse_light.spot_attenuation = 0.8
	_mouse_light.shadow_enabled = true
	_vp.add_child(_mouse_light)

	for i in SOLDIER_COUNT:
		_spawn_soldier(i)


func _spawn_soldier(i: int) -> void:
	var root := Node3D.new()
	_vp.add_child(root)
	var model: Node3D = SURVIVALIST.instantiate()
	model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)  # Player.tscn gibi 180° (model +Z'ye bakıyor)
	root.add_child(model)
	model.apply_outfit(CHARACTERS[i % CHARACTERS.size()])

	# Üst gövde tüfek pozu + omurga düzeltmesi + eldeki tüfek (Player ile aynı modifier zinciri)
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var upper: Node = UPPER_BODY.new()
	sk.add_child(upper)
	var twist: Node = SPINE_TWIST.new()
	sk.add_child(twist)
	var rifle: Node3D = HAND_RIFLE.build_rifle_mesh()
	sk.add_child(rifle)
	var hand: Node = HAND_RIFLE.new()
	hand.rifle = rifle
	hand.aim_node = root
	sk.add_child(hand)
	if ap.has_animation(&"AimIdle"):
		upper.set_base(ap.get_animation(&"AimIdle"))

	# Asker feneri (gövdeyle döner, hafif aşağı bakar)
	var fl := SpotLight3D.new()
	fl.position = Vector3(0.25, 1.35, -0.5)
	fl.rotation_degrees = Vector3(-26, 0, 0)
	fl.light_color = Color(1.0, 0.93, 0.8)
	fl.light_energy = 9.0
	fl.spot_range = 11.0
	fl.spot_angle = 26.0
	fl.spot_attenuation = 0.7
	fl.shadow_enabled = i < 3  # birkaçı gölgeli yeter (performans)
	root.add_child(fl)
	# Gövde ışığı (oyundaki BodyLight gibi) — karanlıkta asker silüeti seçilsin
	var body := OmniLight3D.new()
	body.position = Vector3(0, 1.2, 0.4)
	body.light_energy = 0.9
	body.omni_range = 2.2
	body.light_color = Color(0.85, 0.88, 1.0)
	root.add_child(body)

	var pos := Vector3(_rng.randf_range(-BOUNDS.x, BOUNDS.x), 0, _rng.randf_range(-BOUNDS.y, BOUNDS.y))
	root.position = pos
	var w := {
		"root": root, "ap": ap, "twist": twist, "hand": hand,
		"yaw": _rng.randf_range(-PI, PI), "speed": _rng.randf_range(WALK_SPEED.x, WALK_SPEED.y),
		"target": _random_target(), "pause": 0.0, "corr": 0.0, "scan": 0.0,
	}
	root.rotation.y = w["yaw"]
	_walkers.append(w)


func _random_target() -> Vector3:
	return Vector3(_rng.randf_range(-BOUNDS.x, BOUNDS.x), 0, _rng.randf_range(-BOUNDS.y, BOUNDS.y))


func _process(delta: float) -> void:
	_update_mouse_light(delta)
	for w: Dictionary in _walkers:
		_update_soldier(w, delta)


func _update_mouse_light(delta: float) -> void:
	if _cam == null:
		return
	var mp := get_local_mouse_position()
	var from := _cam.project_ray_origin(mp)
	var dir := _cam.project_ray_normal(mp)
	if absf(dir.y) > 0.001:
		var hit := from + dir * (-from.y / dir.y)
		_mouse_target = _mouse_target.lerp(hit, 1.0 - exp(-6.0 * delta))
	_mouse_light.position = _mouse_target + Vector3(0, 8.0, 2.5)
	_mouse_light.look_at(_mouse_target, Vector3.UP)


func _update_soldier(w: Dictionary, delta: float) -> void:
	var root: Node3D = w["root"]
	var ap: AnimationPlayer = w["ap"]
	var pos := root.position

	if w["pause"] > 0.0:
		# Durmuş: etrafı tara (yavaşça sağa-sola dön)
		w["pause"] -= delta
		w["scan"] += delta
		w["yaw"] = float(w["yaw"]) + sin(float(w["scan"]) * 1.3) * 0.6 * delta
		if ap.current_animation != &"Idle":
			ap.play(&"Idle", 0.3)
		ap.speed_scale = 1.0
	else:
		var to: Vector3 = w["target"] - pos
		to.y = 0
		if to.length() < 0.8:
			# Hedefe vardı: bazen dur, yeni hedef seç
			w["target"] = _random_target()
			if _rng.randf() < 0.45:
				w["pause"] = _rng.randf_range(1.2, 3.2)
				w["scan"] = 0.0
		var desired := to.normalized()
		# Diğer askerlerden uzak dur
		for o: Dictionary in _walkers:
			if o == w:
				continue
			var away: Vector3 = pos - (o["root"] as Node3D).position
			away.y = 0
			var d := away.length()
			if d > 0.01 and d < SEPARATION:
				desired += away / d * (SEPARATION - d) * 0.8
		if desired.length() > 0.01:
			var want_yaw := atan2(-desired.x, -desired.z)
			w["yaw"] = rotate_toward(float(w["yaw"]), want_yaw, TURN_RATE * delta)
		var fwd := Vector3(-sin(float(w["yaw"])), 0, -cos(float(w["yaw"])))
		root.position = pos + fwd * float(w["speed"]) * delta
		if ap.current_animation != &"Walk":
			ap.play(&"Walk", 0.3)
		ap.speed_scale = float(w["speed"]) / WALK_ANIM_REF
	root.rotation.y = w["yaw"]

	# Tüfek gövdenin önüne (Player._update_leg_facing ile aynı nişan düzeltmesi)
	var hand: Node = w["hand"]
	if hand.aim_valid:
		w["corr"] = clampf(float(w["corr"]) - float(hand.aim_error) * minf(10.0 * delta, 1.0), -1.4, 1.4)
	(w["twist"] as Node).twist = w["corr"]

## Powerup.gd — yerde duran güç nesnesi (PowerupManager oluşturur, sahne dosyası yok).
## Görsel: renkli parlayan sembol + taban halkası + ışık + etiket; süzülür ve döner, son 2 sn yanıp söner.
## Kart gibi SADECE yaklaşınca görünür (ProximityReveal). Alma: yerel oyuncu yakındaysa ve slotu boşsa
## PowerupManager.local_touched → host doğrular. (Area3D sinyali yerine mesafe kontrolü: slot boşalınca
## üzerinde duran oyuncu da tekrar alabilsin.)

extends Area3D

const PICK_RADIUS := 1.3
const PROXIMITY_SCRIPT := preload("res://scenes/world/ProximityReveal.gd")

var item_type := 0
var time_left := 5.0

var _manager: Node
var _id := 0
var _visual: Node3D
var _light: OmniLight3D
var _t := 0.0
var _touch_cooldown := 0.0


func setup(manager: Node, id: int, type: int, lifetime: float) -> void:
	_manager = manager
	_id = id
	item_type = type
	time_left = lifetime


func _ready() -> void:
	monitoring = false
	monitorable = false
	var info: Dictionary = _manager.INFO[item_type]
	var color: Color = info["color"]

	var glow := StandardMaterial3D.new()
	glow.albedo_color = color
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 2.2

	_visual = Node3D.new()
	_visual.position.y = 0.9
	add_child(_visual)
	var core := MeshInstance3D.new()
	match item_type:
		0:  # bomba — küre
			var s := SphereMesh.new()
			s.radius = 0.28
			s.height = 0.56
			core.mesh = s
		1:  # sağlık — artı
			var b := BoxMesh.new()
			b.size = Vector3(0.55, 0.18, 0.18)
			core.mesh = b
			var b2 := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.18, 0.55, 0.18)
			b2.mesh = bm
			b2.material_override = glow
			_visual.add_child(b2)
		2:  # uydu — elmas
			var pm := PrismMesh.new()
			pm.size = Vector3(0.45, 0.45, 0.45)
			core.mesh = pm
		4:  # flaş bombası — kısa silindir (sis/flaş el bombası)
			var c := CylinderMesh.new()
			c.top_radius = 0.14
			c.bottom_radius = 0.14
			c.height = 0.5
			core.mesh = c
		_:  # takım uydusu — halka
			var t := TorusMesh.new()
			t.inner_radius = 0.18
			t.outer_radius = 0.32
			core.mesh = t
	core.material_override = glow
	_visual.add_child(core)

	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.55
	rm.outer_radius = 0.62
	ring.mesh = rm
	var ring_mat := glow.duplicate() as StandardMaterial3D
	ring_mat.emission_energy_multiplier = 1.2
	ring.material_override = ring_mat
	ring.position.y = 0.05
	add_child(ring)

	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 1.8
	_light.omni_range = 4.0
	_light.position.y = 1.0
	add_child(_light)

	var label := Label3D.new()
	label.text = "%s %s" % [info["glyph"], info["name"]]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.outline_size = 10
	label.modulate = color
	label.position.y = 1.7
	add_child(label)

	var reveal = PROXIMITY_SCRIPT.new()
	reveal.reveal_far = 11.0
	reveal.reveal_near = 5.0
	add_child(reveal)


func _process(delta: float) -> void:
	_t += delta
	time_left -= delta
	_visual.position.y = 0.9 + sin(_t * 2.5) * 0.12
	_visual.rotation.y += delta * 1.8
	# Son 2 saniye: yanıp sön (kaybolmak üzere)
	if time_left < 2.0:
		_visual.visible = fmod(_t * 6.0, 1.0) > 0.35
	_try_pickup(delta)


func _try_pickup(delta: float) -> void:
	_touch_cooldown -= delta
	if _touch_cooldown > 0.0 or _manager == null:
		return
	var me: Variant = GameManager.active_players.get(NetworkManager.get_local_id())
	if me == null or not is_instance_valid(me) or me.is_dead:
		return
	var d := Vector2((me as Node3D).global_position.x - global_position.x, (me as Node3D).global_position.z - global_position.z).length()
	if d <= PICK_RADIUS:
		_touch_cooldown = 0.4  # host cevabını beklerken isteği tekrar yollama
		_manager.local_touched(_id)

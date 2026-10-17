## Bomb.gd — fırlatılan bombanın GÖRSELİ (her peer'da yerel; hasar PowerupManager._detonate_later'da host'ta).
## Yay çizerek hedefe uçar, yerde yanıp sönerek bekler (fitil), sonra patlama: ışık flaşı + genişleyen küre.
## Patlama yarıçapı yerde halka olarak gösterilir (kaçma şansı).
## is_flash: flaş bombası — gri/beyaz gövde, halka yok, patlamada kör edici beyaz flaş (hasar yok).
## exploded(pos, is_flash) → PowerupManager yerel etkileri uygular (ekran sarsıntısı, körlük).

extends Node3D

signal exploded(pos: Vector3, is_flash: bool)

var is_flash := false
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _flight := 0.5
var _fuse := 1.2
var _radius := 4.0
var _color := Color.WHITE
var _t := 0.0
var _exploded := false

var _ball: MeshInstance3D
var _ball_mat: StandardMaterial3D
var _warn_ring: MeshInstance3D
var _light: OmniLight3D


func setup(from: Vector3, to: Vector3, flight: float, fuse: float, radius: float, team_color: Color) -> void:
	_from = from
	_to = to
	_flight = flight
	_fuse = fuse
	_radius = radius
	_color = team_color


func _ready() -> void:
	_ball = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.16
	s.height = 0.32
	_ball.mesh = s
	_ball_mat = StandardMaterial3D.new()
	_ball_mat.albedo_color = Color(0.55, 0.58, 0.62) if is_flash else Color(0.12, 0.12, 0.12)
	_ball_mat.emission_enabled = true
	_ball_mat.emission = Color(0.75, 0.88, 1.0) if is_flash else Color(1.0, 0.35, 0.15)
	_ball_mat.emission_energy_multiplier = 0.5
	_ball.material_override = _ball_mat
	add_child(_ball)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.75, 0.88, 1.0) if is_flash else Color(1.0, 0.45, 0.2)
	_light.light_energy = 0.8
	_light.omni_range = 2.5
	add_child(_light)

	# Yerde patlama alanı uyarısı (fitil boyunca)
	_warn_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = _radius - 0.08
	tm.outer_radius = _radius
	_warn_ring.mesh = tm
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.albedo_color = Color(1.0, 0.3, 0.2, 0.0)
	_warn_ring.material_override = wm
	_warn_ring.visible = false
	add_child(_warn_ring)
	global_position = _from


func _process(delta: float) -> void:
	_t += delta
	if _t < _flight:
		# Yay: doğrusal + parabol
		var k := _t / _flight
		var p := _from.lerp(_to, k)
		p.y = lerpf(_from.y, _to.y, k) + sin(k * PI) * 1.6
		global_position = p
		_ball.rotation.x += delta * 12.0
	elif _t < _flight + _fuse:
		global_position = _to
		_warn_ring.visible = not is_flash
		_warn_ring.global_position = Vector3(_to.x, 0.06, _to.z)
		# Fitil: giderek hızlanan yanıp sönme
		var f := (_t - _flight) / _fuse
		var blink := fmod(_t * lerpf(4.0, 14.0, f), 1.0) > 0.5
		_ball_mat.emission_energy_multiplier = 4.0 if blink else 0.6
		_light.light_energy = 2.5 if blink else 0.5
		(_warn_ring.material_override as StandardMaterial3D).albedo_color.a = 0.25 + 0.35 * f
	elif not _exploded:
		_explode()


func _explode() -> void:
	_exploded = true
	_ball.visible = false
	_warn_ring.visible = false
	exploded.emit(_to, is_flash)
	if is_flash:
		_explode_flash()
		return
	_light.light_color = Color(1.0, 0.6, 0.3)
	_light.omni_range = _radius * 2.5
	_light.light_energy = 9.0
	_light.position.y = 1.0

	var blast := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	blast.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(1.0, 0.55, 0.2, 0.7)
	blast.material_override = bm
	blast.scale = Vector3.ONE * 0.3
	add_child(blast)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(blast, "scale", Vector3.ONE * _radius, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(bm, "albedo_color:a", 0.0, 0.45)
	tw.tween_property(_light, "light_energy", 0.0, 0.6)
	tw.chain().tween_callback(queue_free)


## Flaş: çok kısa, çok parlak beyaz ışık (karanlık labirentte koridoru bir anlığına aydınlatır) + küçük parlak küre
func _explode_flash() -> void:
	_light.light_color = Color(0.92, 0.96, 1.0)
	_light.omni_range = 16.0
	_light.light_energy = 22.0
	_light.position.y = 1.2

	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	core.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.albedo_color = Color(1, 1, 1, 0.95)
	core.material_override = cm
	core.position.y = 0.4
	add_child(core)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(core, "scale", Vector3.ONE * 2.2, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(cm, "albedo_color:a", 0.0, 0.3)
	tw.tween_property(_light, "light_energy", 0.0, 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	tw.chain().tween_callback(queue_free)

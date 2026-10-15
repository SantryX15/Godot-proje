## Modeli baked idle ile 3 açıdan render edip PNG kaydeder (görsel doğrulama).
extends SceneTree

const HIDE := ["SK_Miliary_FPS_Arms", "SK_Miliary_Military_FPS_Shirt3", "SK_Miliary_FPS_Arms_Gloves1",
	"SK_Military_Male_Arms1", "SK_Military_Vest1", "SK_Military_Backpack1"]

var _frame := 0
var _shots: Array = []
var _cams: Array[Camera3D] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var hide_parts := args.size() > 0 and args[0] == "select"
	get_root().size = Vector2i(900, 700)
	var world := Node3D.new()
	get_root().add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.27, 0.32)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(sun)

	var model: Node3D = (load("res://SK_Military_Survivalist.fbx") as PackedScene).instantiate()
	world.add_child(model)
	if hide_parts:
		for n in HIDE:
			var node := model.find_child(n, true, false) as Node3D
			if node:
				node.visible = false
	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	ap.add_animation_library(&"baked", load("res://survivalist_anims.res"))
	ap.play(&"baked/Breathing Idle")
	ap.seek(2.0, true)
	ap.pause()

	# Ön (+Z, modelin baktığı yön), yan, üstten (oyun kamerası açısı)
	for spec in [[Vector3(0, 1.1, 3.2), Vector3(0, 1.0, 0)], [Vector3(3.2, 1.1, 0), Vector3(0, 1.0, 0)], [Vector3(0, 5.5, 4.6), Vector3(0, 0.8, 0)]]:
		var cam := Camera3D.new()
		world.add_child(cam)
		cam.look_at_from_position(spec[0], spec[1])
		cam.fov = 45
		_cams.append(cam)
	_shots = ["front", "side", "top"]


func _process(_delta: float) -> bool:
	_frame += 1
	var idx := (_frame - 4) / 3
	if _frame >= 4 and (_frame - 4) % 3 == 0 and idx < _cams.size():
		_cams[idx].make_current()
	if _frame >= 6 and (_frame - 6) % 3 == 0:
		var i := (_frame - 6) / 3
		if i < _cams.size():
			var img := get_root().get_texture().get_image()
			var tag := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "all"
			img.save_png("res://shot_%s_%s.png" % [tag, _shots[i]])
		else:
			return true
	return false

## Survivalist (UE mannequin iskeleti) animasyon kütüphanesini kurar → anims/survivalist_anims.res
## Kaynak: anims/Basic+Demo+Animations/*.FBX (aynı iskelet, doğrudan uyumlu) + mevcut "Breathing Idle" (Mixamo bake'i).
## Temizlik: modelde olmayan kemiklerin (ik_*) track'leri, pelvis dışındaki position track'leri (kemik boyu farkı
## gerilme yapmasın — Death farklı rest'le gelmiş) ve scale track'leri atılır. Döngü ayarları burada.
## Kullanım (proje kökünde, editör kapalıyken ya da kopya projede):
##   godot --headless --path . --script tools/build_anim_library.gd
extends SceneTree

const MODEL := "res://asset model/Survivalist/SK_Military_Survivalist.fbx"
const SRC_DIR := "res://anims/Basic+Demo+Animations/"
const OUT := "res://anims/survivalist_anims.res"
## dosya → [kütüphanedeki ad, döngü]
const CLIPS := {
	"Idle.fbx": ["Idle", true],
	"Walk.FBX": ["Walk", true],
	"Run.FBX": ["Run", true],
	"Crouch_Walk.FBX": ["CrouchWalk", true],
	"Talk.FBX": ["Talk", true],
	"Jump.FBX": ["Jump", false],
	"Death.fbx": ["Death", false],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	get_root().add_child(model)
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]

	var lib := AnimationLibrary.new()
	# Eski kütüphanedeki Breathing Idle'ı koru (yedek idle)
	if ResourceLoader.exists(OUT):
		var old := load(OUT) as AnimationLibrary
		if old and old.has_animation(&"Breathing Idle"):
			lib.add_animation(&"Breathing Idle", old.get_animation(&"Breathing Idle"))

	for file: String in CLIPS:
		var path := SRC_DIR + file
		if not ResourceLoader.exists(path):
			print("YOK: ", path)
			continue
		var src: Node3D = (load(path) as PackedScene).instantiate()
		var ap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
		var src_anim: Animation = null
		for an in ap.get_animation_list():
			if an != &"RESET":
				src_anim = ap.get_animation(an)
				break
		var anim := src_anim.duplicate(true) as Animation
		var removed := 0
		for t in range(anim.get_track_count() - 1, -1, -1):
			var tp := anim.track_get_path(t)
			var bone := str(tp.get_concatenated_subnames())
			var type := anim.track_get_type(t)
			var drop := sk.find_bone(bone) < 0 \
				or type == Animation.TYPE_SCALE_3D \
				or (type == Animation.TYPE_POSITION_3D and bone != "pelvis")
			if drop:
				anim.remove_track(t)
				removed += 1
		anim.loop_mode = Animation.LOOP_LINEAR if CLIPS[file][1] else Animation.LOOP_NONE
		lib.add_animation(StringName(CLIPS[file][0]), anim)
		print("%-16s → %-10s len=%.2f tracks=%d (atılan %d)" % [file, CLIPS[file][0], anim.length, anim.get_track_count(), removed])
		src.free()

	var err := ResourceSaver.save(lib, OUT)
	print("kaydedildi ", OUT, " err=", err, " animasyonlar=", lib.get_animation_list())
	quit()

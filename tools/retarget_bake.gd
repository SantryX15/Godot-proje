## Mixamo (mixamorig_*) animasyonunu UE mannequin iskeletine (pelvis/spine_01/...) aktarıp Animation olarak kaydeder.
## Yöntem: model uzayında rest'e göre rotasyon farkı (Δ = srcPose · srcRest⁻¹), hedefte Δ · tgtRest.
## Kullanım: godot --headless --path <proje> --script bake.gd -- <src.fbx> <src_anim> <dst.fbx> <out.res>
extends SceneTree

const MAP := {
	"Hips": "pelvis", "Spine": "spine_01", "Spine1": "spine_02", "Spine2": "spine_03",
	"Neck": "neck_01", "Head": "head",
	"LeftShoulder": "clavicle_l", "LeftArm": "upperarm_l", "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l",
	"RightShoulder": "clavicle_r", "RightArm": "upperarm_r", "RightForeArm": "lowerarm_r", "RightHand": "hand_r",
	"LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l", "LeftToeBase": "ball_l",
	"RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r", "RightToeBase": "ball_r",
	"LeftHandThumb1": "thumb_01_l", "LeftHandThumb2": "thumb_02_l", "LeftHandThumb3": "thumb_03_l",
	"LeftHandIndex1": "index_01_l", "LeftHandIndex2": "index_02_l", "LeftHandIndex3": "index_03_l",
	"LeftHandMiddle1": "middle_01_l", "LeftHandMiddle2": "middle_02_l", "LeftHandMiddle3": "middle_03_l",
	"LeftHandRing1": "ring_01_l", "LeftHandRing2": "ring_02_l", "LeftHandRing3": "ring_03_l",
	"LeftHandPinky1": "pinky_01_l", "LeftHandPinky2": "pinky_02_l", "LeftHandPinky3": "pinky_03_l",
	"RightHandThumb1": "thumb_01_r", "RightHandThumb2": "thumb_02_r", "RightHandThumb3": "thumb_03_r",
	"RightHandIndex1": "index_01_r", "RightHandIndex2": "index_02_r", "RightHandIndex3": "index_03_r",
	"RightHandMiddle1": "middle_01_r", "RightHandMiddle2": "middle_02_r", "RightHandMiddle3": "middle_03_r",
	"RightHandRing1": "ring_01_r", "RightHandRing2": "ring_02_r", "RightHandRing3": "ring_03_r",
	"RightHandPinky1": "pinky_01_r", "RightHandPinky2": "pinky_02_r", "RightHandPinky3": "pinky_03_r",
}
const FPS := 30.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var src_root: Node3D = (load(args[0]) as PackedScene).instantiate()
	var dst_root: Node3D = (load(args[2]) as PackedScene).instantiate()
	get_root().add_child(src_root)
	get_root().add_child(dst_root)
	var src_sk: Skeleton3D = src_root.find_children("*", "Skeleton3D", true, false)[0]
	var dst_sk: Skeleton3D = dst_root.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = src_root.find_children("*", "AnimationPlayer", true, false)[0]
	var dst_ap: AnimationPlayer = dst_root.find_children("*", "AnimationPlayer", true, false)[0]
	var src_anim := ap.get_animation(args[1])
	print("src anim length=", src_anim.length, " tracks=", src_anim.get_track_count())
	print("dst AnimationPlayer root_node=", dst_ap.root_node, "  skeleton path from root=", dst_root.get_path_to(dst_sk))
	var sk_path := str(dst_root.get_path_to(dst_sk))

	# Eşleşme (indeksler) + hedef hiyerarşi sırası
	var pairs := {}  # dst_idx -> src_idx
	for m: String in MAP:
		var si := src_sk.find_bone("mixamorig_" + m)
		var di := dst_sk.find_bone(MAP[m])
		if si < 0 or di < 0:
			print("  eşleşmedi: ", m, " -> ", MAP[m], " (", si, ",", di, ")")
			continue
		pairs[di] = si
	var order := _hier_order(dst_sk)

	var src_rest_g := _global_rests(src_sk)
	var dst_rest_g := _global_rests(dst_sk)
	var src_hips := src_sk.find_bone("mixamorig_Hips")
	var dst_pelvis := dst_sk.find_bone("pelvis")
	var h_scale: float = dst_rest_g[dst_pelvis].origin.y / maxf(src_rest_g[src_hips].origin.y, 0.001)
	print("pelvis/hips height ratio=", h_scale)

	# Rest pozu farkı (ör. T-poz vs A-poz): her kemiğin rest yönünü (kemik → zincirdeki çocuğu) kaynağa hizala.
	# align[di] = hedef rest yönünü kaynak rest yönüne çeviren en kısa yay rotasyonu (model uzayı)
	var align := {}
	for m: String in MAP:
		var child_m := _chain_child(m)
		if child_m.is_empty() or not MAP.has(child_m):
			continue
		var si := src_sk.find_bone("mixamorig_" + m)
		var sc := src_sk.find_bone("mixamorig_" + child_m)
		var di := dst_sk.find_bone(MAP[m])
		var dc := dst_sk.find_bone(MAP[child_m])
		if si < 0 or sc < 0 or di < 0 or dc < 0:
			continue
		var ds: Vector3 = (src_rest_g[sc].origin - src_rest_g[si].origin).normalized()
		var dd: Vector3 = (dst_rest_g[dc].origin - dst_rest_g[di].origin).normalized()
		if ds.length() > 0.5 and dd.length() > 0.5:
			align[di] = Basis(Quaternion(dd, ds))
	var shl0 := src_sk.find_bone("mixamorig_LeftHand")
	var shr0 := src_sk.find_bone("mixamorig_RightHand")
	print("mixamo rest hand distance=", src_rest_g[shl0].origin.distance_to(src_rest_g[shr0].origin))

	var anim := Animation.new()
	anim.length = src_anim.length
	anim.loop_mode = Animation.LOOP_LINEAR
	var rot_tracks := {}
	for di: int in pairs:
		var t := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath("%s:%s" % [sk_path, dst_sk.get_bone_name(di)]))
		rot_tracks[di] = t
	var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, NodePath("%s:%s" % [sk_path, "pelvis"]))

	var frames := int(ceil(src_anim.length * FPS))
	for f in range(frames + 1):
		var time := minf(f / FPS, src_anim.length)
		ap.play(args[1])
		ap.seek(time, true)
		var src_g := _global_poses(src_sk)
		var dst_g := {}  # bone -> Basis (global)
		for di: int in order:
			var parent := dst_sk.get_bone_parent(di)
			var parent_b: Basis = dst_g[parent] if parent >= 0 else Basis.IDENTITY
			var gb: Basis
			if pairs.has(di):
				var si: int = pairs[di]
				var delta: Basis = src_g[si].basis.orthonormalized() * src_rest_g[si].basis.orthonormalized().inverse()
				var al: Basis = align.get(di, Basis.IDENTITY)
				gb = delta * al * dst_rest_g[di].basis.orthonormalized()
				var local_b := (parent_b.inverse() * gb).orthonormalized()
				anim.rotation_track_insert_key(rot_tracks[di], time, local_b.get_rotation_quaternion())
			else:
				gb = parent_b * dst_sk.get_bone_rest(di).basis.orthonormalized()
			dst_g[di] = gb
		# Kalça yer değiştirmesi (nefes alma iniş-çıkışı), boy oranıyla ölçekli — pelvis parent'ı (root) uzayında
		var src_off: Vector3 = src_g[src_hips].origin - src_rest_g[src_hips].origin
		var pel_parent := dst_sk.get_bone_parent(dst_pelvis)
		var parent_rest: Transform3D = dst_rest_g[pel_parent] if pel_parent >= 0 else Transform3D.IDENTITY
		var local_pos: Vector3 = dst_sk.get_bone_rest(dst_pelvis).origin + parent_rest.basis.inverse() * (src_off * h_scale)
		anim.position_track_insert_key(pos_track, time, local_pos)

	# Doğrulama: hedef iskelete uygula, el-el mesafesi (T-poz ~1.3m, idle ~0.5m beklenir)
	var lib := AnimationLibrary.new()
	lib.add_animation(&"Breathing Idle", anim)
	dst_ap.add_animation_library(&"baked", lib)
	var hl := dst_sk.find_bone("hand_l")
	var hr := dst_sk.find_bone("hand_r")
	print("rest hand distance=", dst_rest_g[hl].origin.distance_to(dst_rest_g[hr].origin))
	for tt in [0.0, src_anim.length * 0.5]:
		dst_ap.play(&"baked/Breathing Idle")
		dst_ap.seek(tt, true)
		print("baked t=%.2f hand distance=%.3f  pelvis y=%.3f head=%s" % [tt,
			dst_sk.get_bone_global_pose(hl).origin.distance_to(dst_sk.get_bone_global_pose(hr).origin),
			dst_sk.get_bone_global_pose(dst_pelvis).origin.y, dst_sk.get_bone_global_pose(dst_sk.find_bone("head")).origin])
	ap.seek(0.0, true)
	var shl := src_sk.find_bone("mixamorig_LeftHand")
	var shr := src_sk.find_bone("mixamorig_RightHand")
	print("mixamo idle hand distance=", src_sk.get_bone_global_pose(shl).origin.distance_to(src_sk.get_bone_global_pose(shr).origin))

	var err := ResourceSaver.save(lib, args[3])
	print("saved ", args[3], " err=", err, " frames=", frames + 1, " tracks=", anim.get_track_count())
	quit()


## Zincirdeki bir sonraki kemik (rest yönü hizalaması için)
func _chain_child(m: String) -> String:
	const NEXT := {
		"Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Neck", "Neck": "Head",
		"Shoulder": "Arm", "Arm": "ForeArm", "ForeArm": "Hand", "Hand": "HandMiddle1",
		"UpLeg": "Leg", "Leg": "Foot", "Foot": "ToeBase",
	}
	for side in ["Left", "Right"]:
		if m.begins_with(side):
			var rest := m.substr(side.length())
			if NEXT.has(rest):
				return side + NEXT[rest]
			# Parmaklar: HandIndex1 → HandIndex2 → HandIndex3
			var last := rest.right(1)
			if rest.begins_with("Hand") and (last == "1" or last == "2"):
				return side + rest.left(rest.length() - 1) + str(int(last) + 1)
	if NEXT.has(m):
		return NEXT[m]
	return ""


func _hier_order(sk: Skeleton3D) -> Array[int]:
	var out: Array[int] = []
	var stack: Array[int] = []
	for b in sk.get_bone_count():
		if sk.get_bone_parent(b) < 0:
			stack.append(b)
	while not stack.is_empty():
		var b: int = stack.pop_back()
		out.append(b)
		for c in sk.get_bone_children(b):
			stack.append(c)
	return out


func _global_rests(sk: Skeleton3D) -> Dictionary:
	var out := {}
	for b in _hier_order(sk):
		var p := sk.get_bone_parent(b)
		out[b] = (out[p] as Transform3D) * sk.get_bone_rest(b) if p >= 0 else sk.get_bone_rest(b)
	return out


func _global_poses(sk: Skeleton3D) -> Dictionary:
	var out := {}
	for b in _hier_order(sk):
		var p := sk.get_bone_parent(b)
		out[b] = (out[p] as Transform3D) * sk.get_bone_pose(b) if p >= 0 else sk.get_bone_pose(b)
	return out

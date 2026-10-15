## SpineTwistModifier.gd
## Animasyonun üstüne omurgayı (spine_01..03) dikey eksen etrafında döndürür — "bacaklar hareket yönüne,
## üst gövde nişana" için. Player.gd her kare `twist`'i (radyan) ayarlar: bacakların nişandan sapmasının tersi.
## Skeleton3D'nin çocuğu olmalı (SkeletonModifier3D). Dönüş kemiklere eşit bölünür.

class_name SpineTwistModifier
extends SkeletonModifier3D

const BONES: Array[String] = ["spine_01", "spine_02", "spine_03"]

## Toplam omurga dönüşü (radyan, iskelet uzayında +Y etrafında)
var twist := 0.0

var _bone_ids: Array[int] = []


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in BONES:
		var idx := sk.find_bone(b)
		if idx >= 0:
			_bone_ids.append(idx)


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or _bone_ids.is_empty() or absf(twist) < 0.001:
		return
	var per_bone := Basis(Vector3.UP, twist / _bone_ids.size())
	for idx in _bone_ids:
		# İskelet uzayındaki dikey eksen rotasyonunu kemiğin yerel uzayına taşı (konjugasyon)
		var g := sk.get_bone_global_pose(idx).basis.orthonormalized()
		var local_delta := g.inverse() * per_bone * g
		var pose_rot := Basis(sk.get_bone_pose_rotation(idx)) * local_delta
		sk.set_bone_pose_rotation(idx, pose_rot.get_rotation_quaternion())

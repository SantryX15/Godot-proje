## UpperBodyLayer.gd — üst gövde animasyon katmanı (SkeletonModifier3D, Skeleton3D'nin çocuğu).
## AnimationPlayer bacakları (Idle/Walk/Run/CrouchWalk) oynatır; bu katman spine_01 ve altındaki tüm kemiklere
## (kollar, boyun, baş, parmaklar) tüfek pozlarını uygular:
##   taban  : AimIdle (sürekli, tüfek nişanda)
##   aksiyon: Reload / Toss / HitReact (bir kez) ve FireStand / FireWalk (ateş ederken döngü, "hold")
## Animasyonlar Animation kaynağından doğrudan örneklenir (rotation_track_interpolate) — ikinci AnimationPlayer yok.
## Omurga kemikleri kısmi ağırlıkla karışır (koşunun gövde salınımı kaybolmasın). Sıra: bu → SpineTwistModifier → HandRifle.

extends SkeletonModifier3D

const ROOT_BONE := "spine_01"
## Kemik → bu katmanın ağırlığı (listede olmayanlar 1.0)
const BONE_WEIGHT := {"spine_01": 0.45, "spine_02": 0.65, "spine_03": 0.85}
const FADE_IN := 0.08
const FADE_OUT := 0.16

## 0..1 — ölüyken 0 (tam gövde Dying oynar)
var layer_weight := 1.0
var _layer_target := 1.0

var _base: Animation = null
var _base_t := 0.0

var _action: Animation = null
var _action_t := 0.0
var _action_speed := 1.0
var _action_w := 0.0
var _action_strength := 1.0  # aksiyonun en yüksek ağırlığı (HitReact kısmi)
var _action_loop := false
var _hold_until := 0.0       # loop aksiyonlar (ateş) bu zamana kadar sürer

var _bones: Array[int] = []
var _weights: Array[float] = []
var _track_cache: Dictionary = {}  # Animation → {bone_idx: track_idx}


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var root := sk.find_bone(ROOT_BONE)
	if root < 0:
		return
	var stack: Array[int] = [root]
	while not stack.is_empty():
		var b: int = stack.pop_back()
		_bones.append(b)
		_weights.append(float(BONE_WEIGHT.get(sk.get_bone_name(b), 1.0)))
		for c in sk.get_bone_children(b):
			stack.append(c)


func set_base(anim: Animation) -> void:
	_base = anim


func set_enabled_smooth(on: bool) -> void:
	_layer_target = 1.0 if on else 0.0


## Bir kez oynayan aksiyon (süre = anim uzunluğu / speed)
func play_once(anim: Animation, duration: float = -1.0, strength: float = 1.0) -> void:
	if anim == null:
		return
	_action = anim
	_action_t = 0.0
	_action_speed = anim.length / duration if duration > 0.0 else 1.0
	_action_loop = false
	_action_strength = strength
	_hold_until = 0.0


## Döngülü aksiyon (ateş): her çağrı süreyi uzatır; zaten oynuyorsa baştan başlamaz
func hold(anim: Animation, seconds: float) -> void:
	if anim == null:
		return
	# Bir kez oynayan güçlü aksiyon (reload/toss) sürüyorsa ateş onu kesmez
	if _action != null and not _action_loop and _action_t < _action.length:
		return
	if _action != anim:
		_action = anim
		_action_t = 0.0
	_action_speed = 1.0
	_action_loop = true
	_action_strength = 1.0
	_hold_until = Time.get_ticks_msec() / 1000.0 + seconds


func is_busy() -> bool:
	return _action != null and not _action_loop and _action_t < _action.length


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or _bones.is_empty() or _base == null:
		return
	layer_weight = move_toward(layer_weight, _layer_target, delta / 0.2)
	_base_t = fposmod(_base_t + delta, maxf(_base.length, 0.01))

	# Aksiyon zamanı + ağırlık
	var now := Time.get_ticks_msec() / 1000.0
	var action_active := false
	if _action != null:
		_action_t += delta * _action_speed
		if _action_loop:
			action_active = now < _hold_until
			_action_t = fposmod(_action_t, maxf(_action.length, 0.01))
		else:
			action_active = _action_t < _action.length - FADE_OUT * _action_speed
	var target_w := _action_strength if action_active else 0.0
	_action_w = move_toward(_action_w, target_w, delta / (FADE_IN if target_w > _action_w else FADE_OUT))
	if _action_w <= 0.0 and not action_active:
		_action = null

	if layer_weight <= 0.001:
		return
	var base_tracks := _tracks(_base)
	var act_tracks := _tracks(_action) if _action != null else {}
	var act_t := minf(_action_t, _action.length) if _action != null else 0.0
	for i in _bones.size():
		var b := _bones[i]
		if not base_tracks.has(b):
			continue
		var q: Quaternion = _base.rotation_track_interpolate(base_tracks[b], _base_t)
		if _action_w > 0.0 and act_tracks.has(b):
			q = q.slerp(_action.rotation_track_interpolate(act_tracks[b], act_t), _action_w)
		var w := _weights[i] * layer_weight
		sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b).slerp(q, w))


func _tracks(anim: Animation) -> Dictionary:
	if anim == null:
		return {}
	if _track_cache.has(anim):
		return _track_cache[anim]
	var sk := get_skeleton()
	var out := {}
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := sk.find_bone(str(anim.track_get_path(t).get_concatenated_subnames()))
		if bone >= 0:
			out[bone] = t
	_track_cache[anim] = out
	return out

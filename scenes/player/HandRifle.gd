## HandRifle.gd — eldeki tüfek görseli (SkeletonModifier3D, en son çalışır: UpperBodyLayer + SpineTwist sonrası).
## Tüfek her kare sağ elde (kabza) durur ve sol ele (ön el) doğru hizalanır → hangi animasyon oynarsa
## oynasın iki elin arasında kalır. Sol el ayrılınca (şarjör değiştirme / bomba atma) son geçerli tutuşu
## sağ ele göre korur. Sadece görsel — mermi Weapon/Muzzle'dan (gövde kökünden) çıkar.

extends SkeletonModifier3D

const GRIP_BONE := "hand_r"
const SUPPORT_BONE := "hand_l"
const VALID_HAND_DIST := Vector2(0.12, 0.65)  # bu aralıktaysa iki elle tutuş geçerli
## Kabzanın el kemiğine göre küçük ofseti (avuç içi), iskelet uzayında
const GRIP_OFFSET := Vector3(0.0, -0.03, 0.0)

var rifle: Node3D = null
## Nişan yönünü veren node (Player root, -Z = nişan). Atanırsa tüfeğin nişandan yatay sapması ölçülür.
var aim_node: Node3D = null
## Tüfek namlusunun nişan yönünden yatay sapması (rad, dünya +Y etrafında; + = sola). Player omurgayı
## bununla düzeltir (Mixamo nişan pozu tüfeği gövdenin ~60° soluna tutuyor).
var aim_error := 0.0
var aim_valid := false   # bu kare iki elle geçerli tutuş + ölçüm var mı
var _grip := -1
var _support := -1
var _rel_to_hand := Transform3D.IDENTITY   # son geçerli tutuşta tüfeğin sağ ele göre konumu
var _has_rel := false


func _ready() -> void:
	var sk := get_skeleton()
	if sk:
		_grip = sk.find_bone(GRIP_BONE)
		_support = sk.find_bone(SUPPORT_BONE)


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or rifle == null or _grip < 0 or _support < 0:
		return
	var hand := sk.get_bone_global_pose(_grip)
	var support := sk.get_bone_global_pose(_support)
	var grip_pos := hand.origin + GRIP_OFFSET
	var to_support := support.origin - grip_pos
	var d := to_support.length()
	var xf: Transform3D
	aim_valid = false
	if d > VALID_HAND_DIST.x and d < VALID_HAND_DIST.y:
		# -Z (namlu) sol ele doğru, yukarı iskelet +Y'ye yakın
		var fwd := to_support / d
		var up := Vector3.UP
		if absf(fwd.dot(up)) > 0.95:
			up = Vector3.FORWARD
		xf = Transform3D(Basis.looking_at(fwd, up), grip_pos)
		_rel_to_hand = hand.affine_inverse() * xf
		_has_rel = true
		if aim_node:
			var rifle_fwd := sk.global_transform.basis * fwd
			var aim_fwd := -aim_node.global_transform.basis.z
			var a := Vector2(aim_fwd.x, aim_fwd.z)
			var r := Vector2(rifle_fwd.x, rifle_fwd.z)
			if a.length() > 0.01 and r.length() > 0.01:
				# Dünya +Y etrafında aim → rifle işaretli açı (yukarıdan bakış, sağ el kuralı)
				aim_error = atan2(a.x * r.y - a.y * r.x, a.dot(r)) * -1.0
				aim_valid = true
	elif _has_rel:
		xf = hand * _rel_to_hand
	else:
		return
	# rifle iskeletin çocuğu → iskelet uzayı = rifle'ın yerel uzayı
	rifle.transform = xf


## Basit prosedürel tüfek (Weapon sahnesinde görsel yok). -Z = namlu; orijin = kabza (sağ el).
## Player ve menü arka planı (MenuBackground3D) kullanır.
static func build_rifle_mesh() -> Node3D:
	var rifle := Node3D.new()
	rifle.name = "HandRifle"
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.09, 0.09, 0.1)
	metal.metallic = 0.7
	metal.roughness = 0.45
	var polymer := StandardMaterial3D.new()
	polymer.albedo_color = Color(0.16, 0.15, 0.13)
	polymer.roughness = 0.8
	# [boyut, konum, malzeme] — gövde, el kundağı, dipçik, şarjör, kabza
	var parts := [
		[Vector3(0.06, 0.09, 0.36), Vector3(0, 0.03, -0.12), metal],
		[Vector3(0.055, 0.07, 0.26), Vector3(0, 0.025, -0.42), polymer],
		[Vector3(0.05, 0.1, 0.24), Vector3(0, 0.0, 0.17), polymer],
		[Vector3(0.035, 0.14, 0.06), Vector3(0, -0.07, -0.16), metal],
		[Vector3(0.035, 0.1, 0.045), Vector3(0, -0.04, 0.0), polymer],
	]
	for p: Array in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0]
		mi.mesh = bm
		mi.position = p[1]
		mi.material_override = p[2]
		rifle.add_child(mi)
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.012
	cm.height = 0.26
	barrel.mesh = cm
	barrel.rotation.x = PI / 2.0
	barrel.position = Vector3(0, 0.035, -0.66)
	barrel.material_override = metal
	rifle.add_child(barrel)
	return rifle

## SurvivalistModel.gd
## Military Survivalist karakter modeli (asset model/Survivalist/SK_Military_Survivalist.fbx) için sarmalayıcı.
## Player.tscn'de CharacterMesh olarak kullanılır; CharacterSelect önizlemesi de bunu görür.
##  - apply_outfit(karakter): karaktere göre parça seçimi (yelek/çanta/şapka/eldiven) + doku varyantı (skin1..4)
##    Player.initialize() ve CharacterSelect._build_preview_world() çağırır. Çağrılmazsa DEFAULT_OUTFIT.
##  - Malzemeler kodla kurulur (albedo + normal + roughness + AO + metal) — dokular
##    asset model/Survivalist_Textures/Textures/ altında (FBX'in kendi doku yolu kullanılmıyor).
##    Normal map'ler UE (DirectX) formatı → .import'ta normal_map_invert_y=true.
##  - Animasyonlar anims/survivalist_anims.res'ten (UE mannequin iskeleti — Basic Demo Animations doğrudan uyumlu):
##    Idle, Walk, Run, CrouchWalk, Talk, Jump, Death + yedek "Breathing Idle" (Mixamo bake'i, tools/retarget_bake.gd).
##    Varsayılan kütüphaneye eklenir; Player.gd Idle/Run/Death'i oynatır.

extends Node3D

## tools/build_anim_library.gd üretir (Basic Demo Animations + Breathing Idle)
const ANIM_LIBRARY := preload("res://anims/survivalist_anims.res")
const IDLE_NAME := &"Idle"
const FALLBACK_IDLE := &"Breathing Idle"
const CROUCH_IDLE_NAME := &"CrouchIdle"
const CROUCH_IDLE_FRAME := 0.0   # CrouchWalk'ın bu anı (ayaklar bir arada, toplu çömelme)
static var _crouch_idle_cache: Animation = null
const TEX := "res://asset model/Survivalist_Textures/Textures/"

## Her zaman gizli: 1. şahıs (FPS) kolları
const ALWAYS_HIDDEN: Array[String] = [
	"SK_Miliary_FPS_Arms", "SK_Miliary_Military_FPS_Shirt3", "SK_Miliary_FPS_Arms_Gloves1",
]

## Kıyafetler — vest: "none" / "plain" (Vest1) / "pouches" (Vest1_4, cepli)
##   backpack: bool (yelek varsa yeleğe oturan Backpack1_vest, yoksa Backpack1), cap / gloves: bool
##   skin: malzeme → doku varyantı (Shirt/Pants/Boots/Vest/Pouches 1-3, Backpack/Cap 1-4, Gloves 1-2)
const OUTFITS: Dictionary = {
	# Ön hat — siyah ağır teçhizat
	"Tank": {"vest": "pouches", "backpack": true, "cap": true, "gloves": true,
		"skin": {"Shirt": 1, "Pants": 2, "Boots": 2, "Vest": 1, "Pouches": 1, "Backpack": 1, "Cap": 1, "Gloves": 1}},
	# Keşif — orman yeşili, hafif yelek, çanta yok
	"Visioner": {"vest": "plain", "backpack": false, "cap": true, "gloves": true,
		"skin": {"Shirt": 2, "Pants": 2, "Boots": 1, "Vest": 2, "Pouches": 2, "Backpack": 3, "Cap": 3, "Gloves": 2}},
	# Hızlı sızma — teçhizatsız, çıplak el
	"Runner": {"vest": "none", "backpack": false, "cap": false, "gloves": false,
		"skin": {"Shirt": 1, "Pants": 2, "Boots": 2, "Vest": 1, "Pouches": 1, "Backpack": 1, "Cap": 1, "Gloves": 1}},
	# Uzun menzil — çöl/kum tonları
	"Sniper": {"vest": "pouches", "backpack": true, "cap": true, "gloves": true,
		"skin": {"Shirt": 3, "Pants": 3, "Boots": 3, "Vest": 3, "Pouches": 3, "Backpack": 4, "Cap": 4, "Gloves": 2}},
	# Destek — gri gömlek + zeytin yelek, sırt çantası (sağlık çantası); Visioner'dan gömlek/pantolonla ayrışır
	"Medic": {"vest": "plain", "backpack": true, "cap": true, "gloves": true,
		"skin": {"Shirt": 1, "Pants": 3, "Boots": 1, "Vest": 2, "Pouches": 2, "Backpack": 3, "Cap": 4, "Gloves": 1}},
}
const DEFAULT_OUTFIT := "Visioner"

## Malzeme adı → doku dosyaları (%d = skin numarası; skin'siz parçalar sabit)
const MATERIALS: Dictionary = {
	"Mat_Military_Head_1":     {"part": "", "albedo": "Body/T_Military_Head1_color.png", "normal": "Body/T_Military_Head1_nmap.png",
		"rough": "Body/T_Military_Head1_rough.png", "ao": "Body/T_Military_Head1_ao.png"},
	"Mat_Military_Eyes_1":     {"part": "", "albedo": "Body/T_Military_Eyes1_albedo.png", "normal": "Body/T_Military_Eyes1_normal.png"},
	"Mat_Military_Hands_1":    {"part": "", "albedo": "Body/T_Military_Hands1_color_skin1.png", "normal": "Body/T_Military_Hands1_nmap.png",
		"rough": "Body/T_Military_Hands1_rough.png", "ao": "Body/T_Military_Hands1_ao.png"},
	"Mat_Military_Gloves_1":   {"part": "Gloves", "albedo": "Equip/T_Military_Gloves1_color_skin%d.png", "normal": "Equip/T_Military_Gloves1_nmap.png",
		"rough": "Equip/T_Military_Gloves1_rough.png", "ao": "Equip/T_Military_Gloves1_ao.png"},
	"Mat_Military_Shirt_3":    {"part": "Shirt", "albedo": "Top/T_Military_Shirt3_Skin%d_color.png", "normal": "Top/T_Military_Shirt3_nmap.png",
		"rough": "Top/T_Military_Shirt3_rough.png", "ao": "Top/T_Military_Shirt3_ao.png", "metal": "Top/T_Military_Shirt3_metalness.png"},
	"Mat_Military_Pants_2":    {"part": "Pants", "albedo": "Bottom/T_Military_Pants2_color_skin%d.png", "normal": "Bottom/T_Military_Pants2_nmap.png",
		"rough": "Bottom/T_Military_Pants2_rough.png", "ao": "Bottom/T_Military_Pants2_ao.png", "metal": "Bottom/T_Military_Pants2_metalness.png"},
	"Mat_Military_Boots_3":    {"part": "Boots", "albedo": "Bottom/T_Military_Boots3_Skin%d_color.png", "normal": "Bottom/T_Military_Boots3_nmap.png",
		"rough": "Bottom/T_Military_Boots3_rough.png", "ao": "Bottom/T_Military_Boots3_ao.png", "metal": "Bottom/T_Military_Boots3_metalness.png"},
	"Mat_Military_Cap_1":      {"part": "Cap", "albedo": "Top/T_Military_Cap1_skin%d_color.png", "normal": "Top/T_Military_Cap1_nmap.png",
		"rough": "Top/T_Military_Cap1_rough.png", "ao": "Top/T_Military_Cap1_ao.png", "metal": "Top/T_Military_Cap1_metalness.png"},
	"Mat_Military_Vest_1":     {"part": "Vest", "albedo": "Equip/T_Military_Vest1_Skin%d_color.png", "normal": "Equip/T_Military_Vest1_nmap.png",
		"rough": "Equip/T_Military_Vest1_rough.png", "ao": "Equip/T_Military_Vest1_ao.png", "metal": "Equip/T_Military_Vest1_metalness.png"},
	"Mat_Military_Pouches_1":  {"part": "Pouches", "albedo": "Equip/T_Military_Pouches1_Skin%d_color.png", "normal": "Equip/T_Military_Pouches1_nmap.png",
		"rough": "Equip/T_Military_Pouches1_rough.png", "ao": "Equip/T_Military_Pouches1_ao.png", "metal": "Equip/T_Military_Pouches1_metalness.png"},
	"Mat_Military_Backpack_1": {"part": "Backpack", "albedo": "Equip/T_Military_Backpack1_color_skin%d.png", "normal": "Equip/T_Military_Backpack1_nmap.png",
		"rough": "Equip/T_Military_Backpack1_rough.png", "ao": "Equip/T_Military_Backpack1_ao.png", "metal": "Equip/T_Military_Backpack1_metalness.png"},
}

## Doku dosyası bulunamazsa kullanılacak renk
const FALLBACK_COLORS: Dictionary = {
	"Mat_Military_Head_1": Color(0.62, 0.47, 0.38), "Mat_Military_Eyes_1": Color(0.12, 0.10, 0.09),
	"Mat_Military_Hands_1": Color(0.62, 0.47, 0.38), "Mat_Military_Gloves_1": Color(0.11, 0.11, 0.10),
	"Mat_Military_Shirt_3": Color(0.29, 0.31, 0.22), "Mat_Military_Pants_2": Color(0.20, 0.21, 0.17),
	"Mat_Military_Vest_1": Color(0.40, 0.36, 0.26), "Mat_Military_Pouches_1": Color(0.36, 0.33, 0.24),
	"Mat_Military_Backpack_1": Color(0.27, 0.29, 0.21), "Mat_Military_Boots_3": Color(0.15, 0.12, 0.10),
	"Mat_Military_Cap_1": Color(0.26, 0.28, 0.20),
}

## "malzeme:skin" → StandardMaterial3D (tüm oyuncular paylaşır)
static var _material_cache: Dictionary = {}

var _outfit_applied := false


func _ready() -> void:
	for part in ALWAYS_HIDDEN:
		var n := find_child(part, true, false) as Node3D
		if n:
			n.visible = false
	_setup_idle()
	# Kimse apply_outfit çağırmazsa bir sonraki karede varsayılan kıyafet
	_apply_default_outfit.call_deferred()


## CrouchWalk'ın tek karesinden 1 sn'lik durağan döngü üretir (tüm oyuncular paylaşır).
## Ayrı klip gerekli: speed_scale=0 ile dondurmak AnimationPlayer geçişini de durduruyordu.
static func _get_crouch_idle(src: Animation) -> Animation:
	if _crouch_idle_cache:
		return _crouch_idle_cache
	var a := Animation.new()
	a.length = 1.0
	a.loop_mode = Animation.LOOP_LINEAR
	var t0 := clampf(CROUCH_IDLE_FRAME, 0.0, src.length)
	for i in src.get_track_count():
		var type := src.track_get_type(i)
		if type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D:
			continue
		var t := a.add_track(type)
		a.track_set_path(t, src.track_get_path(i))
		if type == Animation.TYPE_ROTATION_3D:
			var q := src.rotation_track_interpolate(i, t0)
			a.rotation_track_insert_key(t, 0.0, q)
			a.rotation_track_insert_key(t, 1.0, q)
		else:
			var p := src.position_track_interpolate(i, t0)
			a.position_track_insert_key(t, 0.0, p)
			a.position_track_insert_key(t, 1.0, p)
	_crouch_idle_cache = a
	return a


func _apply_default_outfit() -> void:
	if not _outfit_applied:
		apply_outfit(DEFAULT_OUTFIT)


## Karaktere göre parçaları açıp kapatır ve doku varyantlarını uygular
func apply_outfit(character: String) -> void:
	_outfit_applied = true
	var o: Dictionary = OUTFITS.get(character, OUTFITS[DEFAULT_OUTFIT])
	var vest: String = o["vest"]
	var has_vest := vest != "none"
	_set_part("SK_Military_Vest1", vest == "plain")
	_set_part("SK_Military_Vest1_4", vest == "pouches")
	_set_part("SK_Military_Backpack1_vest", o["backpack"] and has_vest)
	_set_part("SK_Military_Backpack1", o["backpack"] and not has_vest)
	_set_part("SK_Military_Cap1", o["cap"])
	_set_part("SK_Military_Male_Arms1_Gloves1", o["gloves"])
	_set_part("SK_Military_Male_Arms1", not o["gloves"])

	var skins: Dictionary = o["skin"]
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src == null or not MATERIALS.has(src.resource_name):
				continue
			var key: String = src.resource_name
			var part: String = MATERIALS[key]["part"]
			mi.set_surface_override_material(i, _get_material(key, int(skins.get(part, 1))))


func _set_part(part_name: String, on: bool) -> void:
	var n := find_child(part_name, true, false) as Node3D
	if n:
		n.visible = on


## Kütüphanedeki tüm animasyonları (Idle/Walk/Run/CrouchWalk/Talk/Jump/Death + Breathing Idle)
## varsayılan kütüphaneye ekler → Player "Idle"/"Run"/"Death" diye çağırır.
func _setup_idle() -> void:
	var aps := find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		return
	var player := aps[0] as AnimationPlayer
	if not player.has_animation_library(&""):
		player.add_animation_library(&"", AnimationLibrary.new())
	var lib := player.get_animation_library(&"")
	for anim_name: StringName in ANIM_LIBRARY.get_animation_list():
		if not lib.has_animation(anim_name):
			lib.add_animation(anim_name, ANIM_LIBRARY.get_animation(anim_name))
	# Olduğu yerde çömelme pozu: CrouchWalk'ın ayakların bir arada olduğu karesinden durağan döngü
	if not lib.has_animation(CROUCH_IDLE_NAME) and lib.has_animation(&"CrouchWalk"):
		lib.add_animation(CROUCH_IDLE_NAME, _get_crouch_idle(lib.get_animation(&"CrouchWalk")))
	var idle := IDLE_NAME if lib.has_animation(IDLE_NAME) else FALLBACK_IDLE
	player.play(idle)  # (autoplay ağaca eklendikten sonra etkisiz — doğrudan oynat)


static func _get_material(key: String, skin: int) -> StandardMaterial3D:
	var cache_key := "%s:%d" % [key, skin]
	if _material_cache.has(cache_key):
		return _material_cache[cache_key]
	var spec: Dictionary = MATERIALS[key]
	var m := StandardMaterial3D.new()
	m.resource_name = cache_key
	m.roughness = 1.0
	var albedo_path: String = spec["albedo"]
	if albedo_path.contains("%d"):
		albedo_path = albedo_path % skin
	var albedo := _tex(albedo_path)
	if albedo:
		m.albedo_texture = albedo
	else:
		m.albedo_color = FALLBACK_COLORS.get(key, Color(0.5, 0.5, 0.5))
		m.roughness = 0.85
	var normal := _tex(spec.get("normal", ""))
	if normal:
		m.normal_enabled = true
		m.normal_texture = normal
	var rough := _tex(spec.get("rough", ""))
	if rough:
		m.roughness_texture = rough
	var ao := _tex(spec.get("ao", ""))
	if ao:
		m.ao_enabled = true
		m.ao_texture = ao
		m.ao_light_affect = 0.3
	var metal := _tex(spec.get("metal", ""))
	if metal:
		m.metallic = 1.0
		m.metallic_texture = metal
	_material_cache[cache_key] = m
	return m


static func _tex(rel: String) -> Texture2D:
	if rel.is_empty():
		return null
	var path := TEX + rel
	if not ResourceLoader.exists(path):
		push_warning("Survivalist dokusu bulunamadı: " + path)
		return null
	return load(path) as Texture2D

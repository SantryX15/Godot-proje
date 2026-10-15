## WallLamps.gd (Map.tscn → "WallLamps" Node3D, çocukları Lamp* Marker3D)
## Duvar tepelerine monte küçük lambalar: koridora loş ışık havuzu + hafif ışık huzmesi ("sızıntı").
## Marker'ın -Z'si koridora bakar (tools/maze_lamps.py üretir; editörde taşınabilir/silinebilir/eklenebilir).
## Tipler (lamba sırasına göre deterministik — her client'ta aynı lamba aynı tipte):
##   STEADY  sıcak sodyum, çok hafif dalgalanma
##   FLICKER soğuk floresan, ara ara hızlı söner-yanar (kısa patlamalar)
##   DYING   çoğunlukla sönük, arada cızırdayarak kısa süre yanar
## Tamamen yerel görsel — ağ/oyun mantığı yok. Gölge kapalı (performans; ışık duvardan biraz sızar).

extends Node3D

enum Kind { STEADY, FLICKER, DYING }

const KIND_WEIGHTS := [55, 30, 15]
const COLORS := {
	Kind.STEADY:  Color(1.0, 0.62, 0.3),    # sodyum
	Kind.FLICKER: Color(0.78, 0.92, 1.0),   # floresan
	Kind.DYING:   Color(1.0, 0.8, 0.55),
}
const ENERGY := 1.15
const RANGE := 6.5
const LIGHT_OFFSET := 0.55   # ışık kaynağı duvar yüzünden koridora doğru (m)
const SHAFT_INTENSITY := 0.16  # huzmenin tam parlaklıktaki yoğunluğu (LightShaft.gdshader)
const SHAFT_SHADER := preload("res://scenes/world/LightShaft.gdshader")

var _lamps: Array[Dictionary] = []   # {light, bulb_mat, shaft_mat, kind, rng, level, timer, state}


func _ready() -> void:
	var idx := 0
	for child in get_children():
		if child is Marker3D:
			_build_lamp(child as Marker3D, idx)
			idx += 1


func _build_lamp(marker: Marker3D, idx: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + idx * 7919
	var kind := _pick_kind(rng)
	var color: Color = COLORS[kind]

	# Armatür: duvar tepesine oturan koyu metal gövde + koridora uzanan kısa kol
	var housing := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.42, 0.12, 0.34)
	housing.mesh = hb
	housing.position = Vector3(0, 0.12, -0.12)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.13, 0.13, 0.14)
	metal.metallic = 0.6
	metal.roughness = 0.5
	housing.material_override = metal
	housing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(housing)

	# Ampul: ışığa göre parlayan emissive küçük silindir (sarkık)
	var bulb := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.09
	cm.height = 0.14
	bulb.mesh = cm
	bulb.position = Vector3(0, 0.0, -LIGHT_OFFSET * 0.55)
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = color
	bulb_mat.emission_enabled = true
	bulb_mat.emission = color
	bulb_mat.emission_energy_multiplier = 3.0
	bulb.material_override = bulb_mat
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(bulb)

	# Işık: koridor tarafında, duvar tepesinin biraz altında
	var light := OmniLight3D.new()
	light.position = Vector3(0, -0.2, -LIGHT_OFFSET)
	light.light_color = color
	light.light_energy = ENERGY
	light.omni_range = RANGE
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	marker.add_child(light)

	# Sızıntı huzmesi: aşağı doğru genişleyen, toplamalı (additive) saydam koni
	var shaft := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.08
	sm.bottom_radius = 1.25
	sm.height = 2.6
	sm.cap_top = false
	sm.cap_bottom = false
	shaft.mesh = sm
	shaft.position = Vector3(0, -1.35, -LIGHT_OFFSET - 0.25)
	var shaft_mat := ShaderMaterial.new()
	shaft_mat.shader = SHAFT_SHADER
	shaft_mat.set_shader_parameter("color", color)
	shaft_mat.set_shader_parameter("intensity", SHAFT_INTENSITY)
	shaft.material_override = shaft_mat
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(shaft)

	_lamps.append({
		"light": light, "bulb_mat": bulb_mat, "shaft_mat": shaft_mat, "color": color,
		"kind": kind, "rng": rng, "level": 1.0, "target": 1.0, "timer": rng.randf_range(0.5, 4.0), "burst": 0,
	})


func _pick_kind(rng: RandomNumberGenerator) -> int:
	var roll := rng.randi_range(0, 99)
	if roll < KIND_WEIGHTS[0]:
		return Kind.STEADY
	if roll < KIND_WEIGHTS[0] + KIND_WEIGHTS[1]:
		return Kind.FLICKER
	return Kind.DYING


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for L: Dictionary in _lamps:
		var rng: RandomNumberGenerator = L["rng"]
		var level: float
		match L["kind"]:
			Kind.STEADY:
				# Şebeke dalgalanması gibi çok hafif nefes
				level = 0.92 + 0.06 * sin(t * 1.3 + float(L["timer"])) + rng.randf_range(-0.015, 0.015)
			Kind.FLICKER:
				# Çoğunlukla açık; zamanlayıcı dolunca 2-5 hızlı söndür-yak patlaması
				L["timer"] -= delta
				if L["timer"] <= 0.0:
					if L["burst"] > 0:
						L["burst"] -= 1
						L["target"] = 0.05 if L["target"] > 0.5 else 1.0
						L["timer"] = rng.randf_range(0.03, 0.12)
					else:
						L["burst"] = rng.randi_range(3, 9)
						L["target"] = 1.0
						L["timer"] = rng.randf_range(1.5, 6.0)
				if L["burst"] == 0:
					L["target"] = 1.0
				level = L["target"] + rng.randf_range(-0.03, 0.03)
			_:
				# Ölmek üzere: çoğunlukla sönük, arada kısa cızırtılı yanma
				L["timer"] -= delta
				if L["timer"] <= 0.0:
					if L["target"] > 0.5:
						L["target"] = rng.randf_range(0.0, 0.08)
						L["timer"] = rng.randf_range(1.0, 4.0)
					else:
						L["target"] = rng.randf_range(0.6, 1.0)
						L["timer"] = rng.randf_range(0.08, 0.5)
				level = L["target"] * (1.0 if L["target"] < 0.5 else rng.randf_range(0.7, 1.0))
		# Floresan anlık söner; diğerleri hafif yumuşak geçiş (ampul filamanı)
		var smooth := 1.0 if L["kind"] == Kind.FLICKER else 1.0 - exp(-25.0 * delta)
		L["level"] = lerpf(L["level"], clampf(level, 0.0, 1.0), smooth)
		var lv: float = L["level"]
		(L["light"] as OmniLight3D).light_energy = ENERGY * lv
		(L["bulb_mat"] as StandardMaterial3D).emission_energy_multiplier = 0.2 + 3.0 * lv
		(L["shaft_mat"] as ShaderMaterial).set_shader_parameter("intensity", SHAFT_INTENSITY * lv)

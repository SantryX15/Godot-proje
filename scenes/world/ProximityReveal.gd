## ProximityReveal.gd
## Kart/Kapı gibi objelerin ışığını, etiketini ve mesh'ini SADECE yerel oyuncu yaklaşınca gösterir.
## Parent'ın altındaki OmniLight3D / Label3D / MeshInstance3D'leri bulur, mesafeye göre yumuşakça açar.
## Tamamen yerel görsel — ağ/oyun mantığına dokunmaz (her client kendi oyuncusuna göre hesaplar).
##   reveal_far  : bu mesafeden itibaren belirmeye başlar
##   reveal_near : bu mesafede ve daha yakında tam görünür
## Not: mesh, oyuncunun el feneri ona değerse yine aydınlanır (doğal görüş) — burada sadece objenin
## kendi ışığı/etiketi kısılır; mesh_hidden_when_far=true ise uzaktayken mesh tamamen gizlenir.

extends Node

@export var reveal_far: float = 12.0
@export var reveal_near: float = 5.0
@export var mesh_hidden_when_far: bool = true
@export var fade_speed: float = 6.0

var _target: Node3D
var _lights: Array[Light3D] = []
var _light_energy: Array[float] = []
var _labels: Array[Label3D] = []
var _label_alpha: Array[float] = []
var _meshes: Array[MeshInstance3D] = []
var _factor := 0.0


func _ready() -> void:
	_target = get_parent() as Node3D
	# Tüm alt ağaç (iç içe görseller de — ör. Powerup'ın dönen sembolü)
	for child in _target.find_children("*", "Node3D", true, false):
		if child is Light3D:
			_lights.append(child)
			_light_energy.append((child as Light3D).light_energy)
		elif child is Label3D:
			_labels.append(child)
			_label_alpha.append((child as Label3D).modulate.a)
		elif child is MeshInstance3D:
			_meshes.append(child)
	_apply(0.0)


func _process(delta: float) -> void:
	var target := 0.0
	var player := _get_local_player()
	if player and _target.is_visible_in_tree():
		var d := player.global_position.distance_to(_target.global_position)
		target = clampf((reveal_far - d) / maxf(reveal_far - reveal_near, 0.01), 0.0, 1.0)
		target = target * target * (3.0 - 2.0 * target)  # smoothstep
	_factor = lerpf(_factor, target, 1.0 - exp(-fade_speed * delta))
	_apply(_factor)


func _apply(f: float) -> void:
	for i in range(_lights.size()):
		_lights[i].light_energy = _light_energy[i] * f
		_lights[i].visible = f > 0.01
	for i in range(_labels.size()):
		_labels[i].modulate.a = _label_alpha[i] * f
		_labels[i].outline_modulate.a = f
		_labels[i].visible = f > 0.01
	if mesh_hidden_when_far:
		for m in _meshes:
			m.visible = f > 0.01


func _get_local_player() -> Node3D:
	var p: Variant = GameManager.active_players.get(NetworkManager.get_local_id())
	if p == null or not is_instance_valid(p):
		return null
	return p as Node3D

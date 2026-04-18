## TeamManager.gd
## 4 takımı, renklerini, puanlarını ve spawn noktalarını yönetir.

extends Node

signal score_updated(team_id: int, new_score: int)
signal team_won(team_id: int)

const TEAM_COUNT := 4
const MAX_SCORE := 30  # Artık kazanma koşulu değil, sadece referans

## Takım renkleri
const TEAM_COLORS: Array[Color] = [
	Color(0.2, 0.6, 1.0),   # Takım 0 - Mavi
	Color(1.0, 0.3, 0.3),   # Takım 1 - Kırmızı
	Color(0.3, 0.9, 0.3),   # Takım 2 - Yeşil
	Color(1.0, 0.85, 0.1),  # Takım 3 - Sarı
]

const TEAM_NAMES: Array[String] = ["Mavi", "Kırmızı", "Yeşil", "Sarı"]

## team_id -> puan
var scores: Dictionary = { 0: 0, 1: 0, 2: 0, 3: 0 }

## Spawn noktaları — Vector3 listesi, Map.gd tarafından doldurulur
var spawn_points: Dictionary = { 0: [], 1: [], 2: [], 3: [] }


func reset() -> void:
	scores = { 0: 0, 1: 0, 2: 0, 3: 0 }


func add_kill(killing_team: int) -> void:
	if not scores.has(killing_team):
		return
	scores[killing_team] += 1
	_sync_score_rpc.rpc(killing_team, scores[killing_team])


@rpc("authority", "call_local", "reliable")
func _sync_score_rpc(team_id: int, new_score: int) -> void:
	scores[team_id] = new_score
	emit_signal("score_updated", team_id, new_score)


func get_spawn_position(team_id: int) -> Vector3:
	var points: Array = spawn_points.get(team_id, [])
	if points.is_empty():
		push_warning("Takım %d için spawn noktası yok!" % team_id)
		return Vector3.ZERO
	var base: Vector3 = points[randi() % points.size()]
	return base + Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))


func get_color(team_id: int) -> Color:
	if team_id < 0 or team_id >= TEAM_COLORS.size():
		return Color.WHITE
	return TEAM_COLORS[team_id]


func get_team_name(team_id: int) -> String:
	if team_id < 0 or team_id >= TEAM_NAMES.size():
		return "Bilinmiyor"
	return TEAM_NAMES[team_id]


func register_spawn_points(team_id: int, points: Array) -> void:
	spawn_points[team_id] = points

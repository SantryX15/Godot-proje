## Map.gd (3D)
## Spawn noktalarını TeamManager'a kaydeder. Haritanın geri kalanı editörde yapılır.

extends Node3D

@onready var spawn_root: Node3D = $SpawnPoints


func _ready() -> void:
	_register_spawn_points()


func _register_spawn_points() -> void:
	for team_id in range(4):
		var team_node: Node = spawn_root.get_node_or_null("Team%d" % team_id)
		if team_node == null:
			push_warning("Spawn noktası bulunamadı: Team%d" % team_id)
			continue
		var points: Array[Vector3] = []
		for child in team_node.get_children():
			if child is Marker3D:
				points.append(child.global_position)
		TeamManager.register_spawn_points(team_id, points)

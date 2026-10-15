## Map.gd (3D)
## Spawn noktalarını TeamManager'a kaydeder ve labirent duvarlarının çarpışmasını kurar.
## Labirent: Maze/MazeMesh (asset model/Maze_walls.obj — Maze.obj'den ortalanmış, XZ ×0.5, 3 m yükseklik).
## Kart/kapı aday noktaları CardPoints / DoorPoints altında (GameManager._spawn_card_and_door okur).

extends Node3D

@onready var spawn_root: Node3D = $SpawnPoints


func _ready() -> void:
	_build_maze_collision()
	_register_spawn_points()


## Duvar mesh'inden çarpışma şekli üretir (oyuncular + mermiler duvara takılır, layer 1)
func _build_maze_collision() -> void:
	var mesh_inst := get_node_or_null("Maze/MazeMesh") as MeshInstance3D
	if mesh_inst == null or mesh_inst.mesh == null:
		push_warning("Labirent mesh'i bulunamadı (Maze/MazeMesh)")
		return
	var shape := CollisionShape3D.new()
	shape.shape = mesh_inst.mesh.create_trimesh_shape()
	shape.transform = mesh_inst.transform
	$Maze.add_child(shape)


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

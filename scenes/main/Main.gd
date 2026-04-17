## Main.gd
## Giriş noktası – ana menüyü yükler.

extends Node

func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/ui/MainMenu.tscn")

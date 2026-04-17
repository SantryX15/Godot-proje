## StreetLamp.gd (3D)
## Sokak lambası — OmniLight3D ile isteğe bağlı titreme efekti.

extends Node3D

@export var flicker: bool = false
@export var flicker_speed: float = 0.1

@onready var light: OmniLight3D = $OmniLight3D


func _ready() -> void:
	if flicker:
		_start_flicker()


func _start_flicker() -> void:
	while true:
		await get_tree().create_timer(flicker_speed + randf() * 0.2).timeout
		light.light_energy = randf_range(0.6, 1.2) * 4.0

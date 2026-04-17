## StreetLamp.gd
## Sokak lambası – texture programatik oluşturulur.

extends Node2D

@export var flicker: bool = false
@export var flicker_speed: float = 0.1

@onready var light: PointLight2D = $PointLight2D


func _ready() -> void:
	light.texture = _make_light_texture()
	if flicker:
		_start_flicker()


func _start_flicker() -> void:
	while true:
		await get_tree().create_timer(flicker_speed + randf() * 0.2).timeout
		light.energy = randf_range(0.6, 1.2)


static func _make_light_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(1.0, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex

extends Area2D

@onready var sprite: Sprite2D = $Sprite2D

@export var next_level_reference: PackedScene
@export var rotation_speed: float = 135.0  # degrees per second

func _physics_process(delta: float) -> void:
	rotation_degrees += rotation_speed * delta

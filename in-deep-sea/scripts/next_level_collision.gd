extends Area2D

@onready var sprite: Sprite2D = $Sprite2D

@export var next_level_reference: String
@export var rotation_speed: float = 135.0  # degrees per second

func _physics_process(delta: float) -> void:
	rotation_degrees += rotation_speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		GlobalSignals.go_to_next_level_reached.emit(next_level_reference)

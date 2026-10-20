extends Area2D

@onready var jump_collision: CollisionShape2D = $"Jump collision"

@export var jump_force: float = 1500

func _on_jump_area_body_entered(body: Node2D) -> void:
	if body is Player:
		GlobalSignals.trampoline_collided.emit(jump_force)

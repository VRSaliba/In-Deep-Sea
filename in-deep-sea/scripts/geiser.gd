extends Area2D

@onready var jump_collision: CollisionShape2D = $"Jump collision"
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

@export var jump_force: float = 1500

func _on_jump_area_body_entered(body: Node2D) -> void:
	if body is Player:
		GlobalSignals.trampoline_collided.emit(jump_force)
		animated_sprite.play("default")

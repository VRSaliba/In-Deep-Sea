extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready():
	animated_sprite.animation = "default"
	var frame_count = animated_sprite.sprite_frames.get_frame_count("default")
	animated_sprite.frame = randi_range(0, frame_count - 1)

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		GlobalSignals.player_died.emit()

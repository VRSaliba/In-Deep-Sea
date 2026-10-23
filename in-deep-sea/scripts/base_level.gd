extends Node2D
class_name BaseLevel

@onready var world_boundary: Area2D = $WorldBoundary
@onready var next_level_collision: Area2D = $NextLevelCollision

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	next_level_collision.body_entered.connect(_on_next_level_collision_body_entered)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_next_level_collision_body_entered(body: Node2D) -> void:
	if body is Player:
		print("go to next level")
		GlobalSignals.go_to_next_level_reached.emit(next_level_collision.next_level_reference)

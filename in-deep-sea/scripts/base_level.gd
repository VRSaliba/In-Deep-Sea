extends Node2D
class_name BaseLevel

const LEVEL_PATHS := [
	"uid://esv4e8s4h3q6",
	"uid://1w83hqlrkygx",
	"uid://g7err3hw88kq",
	"uid://bfibno4vuqco2",
	"uid://ku4kt6dr4tfq",
]

@onready var world_boundary: Area2D = $WorldBoundary
@onready var next_level_collision: Area2D = $NextLevelCollision

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	next_level_collision.body_entered.connect(_on_next_level_collision_body_entered)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _on_next_level_collision_body_entered(body: Node2D) -> void:
	if body is Player:
		GlobalSignals.go_to_next_level_reached.emit(next_level_collision.next_level_reference)

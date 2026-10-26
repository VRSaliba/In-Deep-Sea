extends BaseLevel

func _ready() -> void:
	super()
	next_level_collision.next_level_reference = LEVEL_PATHS[3]

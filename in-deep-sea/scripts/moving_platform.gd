extends AnimatableBody2D


# You need to create Marker2d's per instance and assign them to this array via inspector for this code to work
@export var points: Array[Marker2D] = []   # Waypoints, in order
@export var speed := 150.0
@export var pause_time := 0.5
@export var loop := false                  # false = ping-pong, true = jump back to first point

@onready var tiles: TileMapLayer = $TileMapLayer

var positions: Array[Vector2] = []
var index := 0
var step := 1
var pause_left := 0.0

func _ready() -> void:
	tiles.collision_enabled = false
	_build_collision()

	if points.size() < 2:
		push_warning("Moving platform needs at least 2 markers.")
		set_physics_process(false)
		return

	# Cache positions so the path stays fixed even if a marker is moved later
	for p in points:
		positions.append(p.global_position)

	global_position = positions[0]
	index = 0
	_advance()

func _advance() -> void:
	var next := index + step
	if next >= positions.size() or next < 0:
		if loop:
			next = 0
		else:
			step = -step
			next = index + step
	index = next

func _physics_process(delta: float) -> void:
	if pause_left > 0.0:
		pause_left -= delta
		return

	var goal := positions[index]
	global_position = global_position.move_toward(goal, speed * delta)

	if global_position.is_equal_approx(goal):
		# Only pause at the first and last marker
		var is_end := index == 0 or index == positions.size() - 1
		if is_end:
			pause_left = pause_time
		_advance()

func _build_collision() -> void:
	for cell in tiles.get_used_cells():
		var data := tiles.get_cell_tile_data(cell)
		if data == null:
			continue
		var center := tiles.position + tiles.map_to_local(cell)
		for i in data.get_collision_polygons_count(0):
			var poly := CollisionPolygon2D.new()
			poly.polygon = data.get_collision_polygon_points(0, i)
			poly.position = center
			poly.one_way_collision = data.is_collision_polygon_one_way(0, i)
			add_child(poly)

extends CharacterBody2D
class_name Player

@onready var camera: Camera2D = $Camera2D

# ============================================================
#  MOVEMENT
# ============================================================
@export var speed := 640.0
@export var jump_speed := 800.0
@export var gravity := 1400.0

# Horizontal feel
@export var ground_accel := 3200.0
@export var ground_friction := 3500.0
@export var ground_brake := 2500.0
@export var air_accel := 1400.0
@export var air_friction := 200.0
@export var air_brake := 2000.0
@export var swing_coast_friction := 300.0

# Variable jump
@export var jump_release_gravity := 4.0
@export var jump_release_duration := 0.15

# Coyote & buffer
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.1

# ============================================================
#  DASH
# ============================================================
@export var dash_speed := 1200.0
@export var dash_duration := 0.2
@export var dash_push_factor := 0.8
@export var dash_falloff_speed := 1500.0
@onready var dash_cooldown: Timer = $"Dash Cooldown"

# ============================================================
#  GRAPPLE / SWING
# ============================================================
@onready var ray: RayCast2D = $RayCast2D
@onready var rope: Line2D = $Line2D

@export var rope_max_length := 1000.0
@export var rope_min_length := 20.0       # Shortest the rope can get
@export var reel_speed := 400.0   # Pixels per second when holding W/S
@export var spring_stiffness := 150.0
@export var spring_damping := 12
@export var swing_gravity_scale := 1.5
@export var swing_input_influence := 1.25
@export var swing_max_speed := 4000.0
@export var wall_drag_rate := 5.0
@export var swing_air_drag := 0.015   # Higher = swing loses speed faster

var grapple_target: Node2D = null        # The body the hook stuck to
var grapple_local_offset := Vector2.ZERO # Hit point in the body's local space

# ============================================================
#  CAMERA ZOOM
# ============================================================
@export var zoom_max_speed := 2000.0
@export var min_zoom := 0.45 # When char is fast
@export var max_zoom := 0.65 # When char is slow
@export var zoom_smooth := 3.5
@export var grapple_pan_factor := 0.5   # How much the camera leans toward the hook
@export var pan_smooth := 8.0           # How fast the pan eases in/out

# ============================================================
#  STATE
# ============================================================
var can_dash := true
var dash_timer := 0.0
var dash_direction := Vector2.ZERO

var release_timer := 0.0
var jump_was_pressed := false
var coyote_timer := 0.0
var jump_buffer_timer := 0.0

var is_grappling := false
var grapple_anchor := Vector2.ZERO
var rope_length := 0.0

# Used to draw the rope at the same interpolated position as the player
var prev_pos := Vector2.ZERO
var curr_pos := Vector2.ZERO

func _ready() -> void:
	GlobalSignals.player_died.connect(die)
	GlobalSignals.trampoline_collided.connect(step_on_trampoline)

	camera.make_current()
	ray.enabled = true

	rope.top_level = true
	rope.global_position = Vector2.ZERO
	rope.add_point(Vector2.ZERO)
	rope.add_point(Vector2.ZERO)
	rope.width = 2.0

	prev_pos = global_position
	curr_pos = global_position

func die() -> void:
	_release_grapple()
	visible = false
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	await get_tree().create_timer(1).timeout
	# Player death animation
	GlobalSignals.restart_level_signal.emit()

func _process(_delta: float) -> void:
	if is_grappling:
		var t := Engine.get_physics_interpolation_fraction()
		rope.set_point_position(0, prev_pos.lerp(curr_pos, t))
		rope.set_point_position(1, grapple_anchor)

func _physics_process(delta: float) -> void:
	_handle_grapple_input()

	if is_grappling:
		_update_grapple_anchor()
		_update_grapple_movement(delta)
	else:
		_update_walking_movement(delta)

	move_and_slide()
	_handle_collisions()
	_update_camera(delta)

	prev_pos = curr_pos
	curr_pos = global_position

# ============================================================
#  WALKING SYSTEM (unhooked)
# ============================================================

func _update_walking_movement(delta: float) -> void:
	# --- Coyote & buffer timers ---
	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer -= delta

	if jump_buffer_timer > 0.0:
		jump_buffer_timer -= delta

	# --- Gravity ---
	if not is_on_floor():
		var g := gravity
		if release_timer > 0.0 and velocity.y < 0:
			g *= jump_release_gravity
			release_timer -= delta
		velocity.y += g * delta

	# Detect release
	if jump_was_pressed and not Input.is_action_pressed("jump") and velocity.y < 0:
		release_timer = jump_release_duration
	jump_was_pressed = Input.is_action_pressed("jump")

	# --- Dash ---
	_try_dash()

	# --- Horizontal movement ---
	if dash_timer > 0.0:
		dash_timer -= delta
	else:
		var direction := Input.get_axis("move_left", "move_right")
		var current_speed := absf(velocity.x)

		if direction != 0.0 and signf(direction) != signf(velocity.x) and velocity.x != 0.0:
			var rate = ground_brake if is_on_floor() else air_brake
			velocity.x = move_toward(velocity.x, 0.0, rate * delta)
		elif direction != 0.0 and current_speed > speed:
			# Above max, same direction → slowly decay back to max walking speed
			var coast_rate = ground_friction if is_on_floor() else swing_coast_friction
			velocity.x = move_toward(velocity.x, direction * speed, coast_rate * delta)
		elif direction != 0.0:
			var rate = ground_accel if is_on_floor() else air_accel
			velocity.x = move_toward(velocity.x, direction * speed, rate * delta)
		elif current_speed > speed:
			# No input, above max → coast down
			var coast_rate = ground_friction if is_on_floor() else swing_coast_friction
			velocity.x = move_toward(velocity.x, 0.0, coast_rate * delta)
		else:
			var rate = ground_friction if is_on_floor() else air_friction
			velocity.x = move_toward(velocity.x, 0.0, rate * delta)

	# --- Jump (buffered + coyote) ---
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time

	if coyote_timer > 0.0 and jump_buffer_timer > 0.0:
		velocity.y = -jump_speed
		release_timer = 0.0
		jump_was_pressed = true
		coyote_timer = 0.0
		jump_buffer_timer = 0.0

# ============================================================
#  GRAPPLE / SWING SYSTEM (hooked)
# ============================================================

# Keeps the anchor glued to the object the hook stuck to (e.g. moving platform)
func _update_grapple_anchor() -> void:
	if grapple_target == null:
		return
	if not is_instance_valid(grapple_target):
		# The thing we hooked was freed, so let go
		_release_grapple()
		return
	grapple_anchor = grapple_target.to_global(grapple_local_offset)

func _update_grapple_movement(delta: float) -> void:
	# --- Dash ---
	_try_dash()

	if dash_timer > 0.0:
		dash_timer -= delta
		return

	# --- Gravity while swinging ---
	velocity.y += gravity * swing_gravity_scale * delta

	# --- Rope length control + elastic rope ---
	var adjust := Input.get_axis("reel_in", "reel_out")   # W = -1, S = +1
	var to_anchor := grapple_anchor - global_position
	var dist := to_anchor.length()
	var rope_dir := to_anchor / dist if dist > 0.001 else Vector2.ZERO
	var rigid := false

	if adjust != 0.0:
		if dist >= rope_length - 2.0:
			# Rope is taut: base the new length on the real distance, so no slack or stretch builds up
			var new_len := clampf(dist + adjust * reel_speed * delta, rope_min_length, rope_max_length)
			rigid = (adjust < 0.0 and new_len < dist) or (adjust > 0.0 and new_len > dist)
			rope_length = new_len
		else:
			# Rope is slack: just change the length and let gravity do the rest
			rope_length = clampf(rope_length + adjust * reel_speed * delta, rope_min_length, rope_max_length)

	if rigid:
		# Move along the rope at reel speed (toward the anchor is positive), keep the sideways swing speed
		var radial := velocity.dot(rope_dir)
		velocity += rope_dir * (-adjust * reel_speed - radial)
	else:
		# Normal elastic rope
		var stretch := dist - rope_length
		if stretch > 0.0:
			velocity += rope_dir * stretch * spring_stiffness * delta
			var radial_vel := velocity.dot(-rope_dir)
			if radial_vel > 0.0:
				velocity += rope_dir * radial_vel * spring_damping * delta

	# --- Player input influence (pump the swing) / drag when no input ---
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x += direction * swing_input_influence * speed * delta
	else:
		velocity *= exp(-swing_air_drag * delta)

	# --- Wall / floor / ceiling drag ---
	if is_on_wall() or is_on_floor() or is_on_ceiling():
		velocity *= exp(-wall_drag_rate * delta)

	# --- Speed clamp ---
	if velocity.length() > swing_max_speed:
		velocity = velocity.normalized() * swing_max_speed

	# --- Auto-release if too close ---
	if dist < 10.0:
		_release_grapple()

# ============================================================
#  DASH
# ============================================================

func _try_dash() -> void:
	if Input.is_action_just_pressed("dash") and dash_timer <= 0.0 and can_dash:
		can_dash = false
		dash_cooldown.start()
		var dir := Input.get_vector("move_left", "move_right", "up", "down")
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		dash_direction = dir
		dash_timer = dash_duration
		_perform_dash()

func _perform_dash() -> void:
	var current_speed := absf(velocity.x)
	var dash_factor := 1.0 - (current_speed / dash_falloff_speed) * 0.8
	velocity.x += dash_direction.x * dash_speed * maxf(dash_factor, 0.0)
	velocity.x = clampf(velocity.x, -swing_max_speed, swing_max_speed)

# ============================================================
#  SHARED
# ============================================================

func _handle_grapple_input() -> void:
	if Input.is_action_just_pressed("grapple"):
		if is_grappling:
			_release_grapple()
		else:
			_try_grapple()

func _try_grapple() -> void:
	var aim_dir := (get_global_mouse_position() - global_position).normalized()
	ray.rotation = aim_dir.angle()
	ray.target_position = Vector2(rope_max_length, 0)
	ray.force_raycast_update()

	if ray.is_colliding():
		is_grappling = true
		grapple_anchor = ray.get_collision_point()

		# Remember what we hit and where, relative to it
		grapple_target = ray.get_collider() as Node2D
		if grapple_target:
			grapple_local_offset = grapple_target.to_local(grapple_anchor)

		rope_length = global_position.distance_to(grapple_anchor)
		rope_length = minf(rope_length, rope_max_length)
		dash_timer = 0.0
		rope.show()

func _release_grapple() -> void:
	is_grappling = false
	rope_length = 0.0
	grapple_target = null
	rope.hide()

func _handle_collisions() -> void:
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		var collider = c.get_collider()
		if collider is RigidBody2D:
			collider.apply_central_impulse(-c.get_normal() * velocity.length() * dash_push_factor)

func _update_camera(delta: float) -> void:
	# --- Zoom (speed-based) ---
	var current_speed := velocity.length()
	var t := clampf(current_speed / zoom_max_speed, 0.0, 1.0)
	var target_zoom := lerpf(max_zoom, min_zoom, t)
	var new_zoom := lerpf(camera.zoom.x, target_zoom, 1.0 - exp(-zoom_smooth * delta))
	camera.zoom = Vector2(new_zoom, new_zoom)

	# --- Pan toward grapple anchor ---
	var target_offset := Vector2.ZERO
	if is_grappling:
		target_offset = (grapple_anchor - global_position) * grapple_pan_factor

	camera.offset = camera.offset.lerp(target_offset, 1.0 - exp(-pan_smooth * delta))

func _on_dash_cooldown_timeout() -> void:
	can_dash = true

func step_on_trampoline(jump_force: float) -> void:
	velocity.y = -jump_force

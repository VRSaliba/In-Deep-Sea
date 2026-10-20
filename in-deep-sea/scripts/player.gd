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
@export var ground_friction := 5000.0
@export var ground_brake := 6000.0
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
@export var dash_speed := 1100.0
@export var dash_duration := 0.15
@export var dash_push_factor := 0.8
@export var dash_falloff_speed := 1500.0
@onready var dash_cooldown: Timer = $"Dash Cooldown"

# ============================================================
#  GRAPPLE / SWING
# ============================================================
@onready var ray: RayCast2D = $RayCast2D
@onready var rope: Line2D = $Line2D
@export var rope_max_length := 10000.0
@export var spring_stiffness := 150.0
@export var spring_damping := 12
@export var reel_speed := 400.0
@export var swing_gravity_scale := 1
@export var swing_input_influence := 0.85
@export var swing_max_speed := 4000.0
@export var wall_drag_rate := 5.0

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

func _ready() -> void:
	GlobalSignals.trampoline_collided.connect(step_on_trampoline)
	
	camera.make_current()
	ray.enabled = true
	rope.add_point(Vector2.ZERO)
	rope.add_point(Vector2.ZERO)
	rope.width = 2.0

func _physics_process(delta: float) -> void:
	_handle_grapple_input()

	if is_grappling:
		_update_grapple_movement(delta)
	else:
		_update_walking_movement(delta)

	move_and_slide()
	_handle_collisions()

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
			# Above max, same direction → coast
			var coast_rate = ground_friction if is_on_floor() else swing_coast_friction
			velocity.x = move_toward(velocity.x, direction * current_speed, coast_rate * delta)
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

func _update_grapple_movement(delta: float) -> void:
	# --- Dash ---
	_try_dash()

	if dash_timer > 0.0:
		dash_timer -= delta
		_update_rope_visual()
		return

	# --- Reduced gravity while swinging ---
	velocity.y += gravity * swing_gravity_scale * delta

	# --- Reel in ---
	if Input.is_action_pressed("reel") and rope_length > 1.0:
		var reel_step := reel_speed * delta
		rope_length = maxf(rope_length - reel_step, 20.0)
		var to_anchor := grapple_anchor - global_position
		if to_anchor.length() > 1.0:
			velocity += to_anchor.normalized() * reel_speed * delta

	# --- Elastic rope ---
	var to_anchor := grapple_anchor - global_position
	var dist := to_anchor.length()
	var stretch := dist - rope_length
	if stretch > 0.0:
		var rope_dir := to_anchor.normalized()
		velocity += rope_dir * stretch * spring_stiffness * delta
		var radial_vel := velocity.dot(-rope_dir)
		if radial_vel > 0.0:
			velocity += rope_dir * radial_vel * spring_damping * delta

	# --- Player input influence (pump the swing) ---
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x += direction * swing_input_influence * speed * delta

	# --- Wall / floor / ceiling drag ---
	if is_on_wall() or is_on_floor() or is_on_ceiling():
		velocity *= exp(-wall_drag_rate * delta)

	# --- Speed clamp ---
	if velocity.length() > swing_max_speed:
		velocity = velocity.normalized() * swing_max_speed

	# --- Rope visual ---
	_update_rope_visual()

	# --- Auto-release if too close ---
	if dist < 10.0:
		_release_grapple()

func _update_rope_visual() -> void:
	var to_anchor := grapple_anchor - global_position
	rope.set_point_position(0, global_position - rope.global_position)
	rope.set_point_position(1, to_local(grapple_anchor))

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
		rope_length = global_position.distance_to(grapple_anchor)
		rope_length = minf(rope_length, rope_max_length)
		dash_timer = 0.0
		rope.show()

func _release_grapple() -> void:
	is_grappling = false
	rope_length = 0.0
	rope.hide()

func _handle_collisions() -> void:
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		var collider = c.get_collider()
		if collider is RigidBody2D:
			collider.apply_central_impulse(-c.get_normal() * velocity.length() * dash_push_factor)

func _on_dash_cooldown_timeout() -> void:
	can_dash = true   

func step_on_trampoline(jump_force: float) -> void:
	velocity.y = -jump_force

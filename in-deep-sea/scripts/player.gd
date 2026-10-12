extends CharacterBody2D

@export var speed := 640.0
@export var jump_speed := 800.0
@export var gravity := 1400.0

# Horizontal feel
@export var ground_accel := 3200.0       # how fast you speed up
@export var ground_friction := 3200.0   # how fast you slide to a stop
@export var air_accel := 1400.0          # ~half of ground (Mario halves it)
@export var air_friction := 200.0       # very little air drag

# Variable jump
@export var jump_release_velocity_factor := 0.2  # on release, multiply current upward velocity by this
@export var jump_release_gravity := 4   # extra gravity multiplier during the release window
@export var jump_release_duration := 0.15  # how long the extra gravity lasts (seconds)

var release_timer := 0.0
var jump_was_pressed := false
var is_jumping := false

# Coyete jump
@export var coyote_time := 0.1      # grace period after leaving the ground

var coyote_timer := 0.0

# Jumping buffer before landing
@export var jump_buffer_time := 0.1 # grace period before landing

var jump_buffer_timer := 0.0

# --- Dash ---
@export var dash_speed := 1500.0
@export var dash_duration := 0.15
@export var dash_push_factor := 0.8
@onready var dash_cooldown: Timer = $"Dash Cooldown"

# --- Grapple / swing ---
@onready var ray: RayCast2D = $RayCast2D
@onready var rope: Line2D = $Line2D
@export var rope_max_length := 10000.0
@export var spring_stiffness := 40.0
@export var spring_damping := 1.75
@export var reel_speed := 400.0
@export var swing_gravity_scale := 0.6      # gravity multiplier while hooked
@export var swing_input_influence := 0.4     # how much left/right input affects swing
@export var swing_max_speed := 2000.0        # clamp to prevent oscillation blowup


var can_dash := true
var can_jump := true

var dash_timer := 0.0
var dash_direction := Vector2.ZERO

var is_grappling := false
var grapple_anchor := Vector2.ZERO
var rope_length := 0.0


func _ready() -> void:
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
#  WALKING SYSTEM (unhooked) — Mario-style
# ============================================================

func _update_walking_movement(delta: float) -> void:
	# --- Coyote & buffer timers ---
	if is_on_floor():
		coyote_timer = coyote_time
		is_jumping = false
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
		velocity.x = dash_direction.x * dash_speed
		dash_timer -= delta
	else:
		var direction := Input.get_axis("move_left", "move_right")
		var target := direction * speed
		var rate: float
		if direction != 0.0:
			rate = ground_accel if is_on_floor() else air_accel
		else:
			rate = ground_friction if is_on_floor() else air_friction
		velocity.x = move_toward(velocity.x, target, rate * delta)

	# --- Jump (buffered + coyote) ---
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time

	if coyote_timer > 0.0 and jump_buffer_timer > 0.0:
		velocity.y = -jump_speed
		release_timer = 0.0
		jump_was_pressed = true
		coyote_timer = 0.0
		jump_buffer_timer = 0.0   


func _try_dash() -> void:
	if Input.is_action_just_pressed("dash") and dash_timer <= 0.0 and can_dash:
		can_dash = false
		dash_cooldown.start()
		var dir := Input.get_vector("move_left", "move_right", "up", "down")
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		dash_direction = dir
		dash_timer = dash_duration   

# ============================================================
#  GRAPPLE / SWING SYSTEM (hooked)
# ============================================================

func _update_grapple_movement(delta: float) -> void:
	# Reduced gravity while swinging
	velocity.y += gravity * swing_gravity_scale * delta

	# Reel in
	if Input.is_action_pressed("reel") and rope_length > 1.0:
		var reel_step := reel_speed * delta
		rope_length = maxf(rope_length - reel_step, 20.0)
		var to_anchor := grapple_anchor - global_position
		if to_anchor.length() > 1.0:
			velocity += to_anchor.normalized() * reel_speed * delta

	# Elastic rope
	var to_anchor := grapple_anchor - global_position
	var dist := to_anchor.length()
	var stretch := dist - rope_length
	if stretch > 0.0:
		var rope_dir := to_anchor.normalized()
		velocity += rope_dir * stretch * spring_stiffness * delta
		var radial_vel := velocity.dot(-rope_dir)
		if radial_vel > 0.0:
			velocity += rope_dir * radial_vel * spring_damping * delta

	# Player input influence (pump the swing)
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x += direction * swing_input_influence * speed * delta

	# Speed clamp
	if velocity.length() > swing_max_speed:
		velocity = velocity.normalized() * swing_max_speed

	# Rope visual
	rope.set_point_position(0, global_position - rope.global_position)
	rope.set_point_position(1, to_local(grapple_anchor))

	# Auto-release if too close
	if dist < 10.0:
		_release_grapple()


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

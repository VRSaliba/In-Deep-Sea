extends CharacterBody2D

@onready var dash_cooldown: Timer = $"Dash Cooldown"
@onready var ray: RayCast2D = $RayCast2D
@onready var rope: Line2D = $Line2D

@export var speed := 520.0
@export var jump_speed := 500.0
@export var gravity := 1200.0

# Acceleration / deceleration (pixels per second²)
@export var ground_accel := 1400.0
@export var ground_decel := 3800.0
@export var air_accel := 1200.0
@export var air_decel := 10.0

@export var dash_speed := 1500.0
@export var dash_duration := 0.15
@export var dash_push_factor := 0.8

# --- Grapple ---
@export var rope_max_length := 10000.0
@export var spring_stiffness := 40.0
@export var spring_damping := 1.75
@export var reel_speed := 400.0

var can_dash := true
var can_air_dash := true
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
	# --- Gravity ---
	if not is_on_floor():
		velocity.y += gravity * delta

	# --- Reset air dash on landing ---
	if is_on_floor():
		can_air_dash = true

	# --- Dash input ---
	if Input.is_action_just_pressed("dash") and dash_timer <= 0.0 and can_dash and (is_on_floor() or can_air_dash):
		can_dash = false
		dash_cooldown.start()
		if not is_on_floor():
			can_air_dash = false
		var dir := Input.get_vector("move_left", "move_right", "up", "down")
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		dash_direction = dir
		dash_timer = dash_duration

	# --- Grapple input ---
	_handle_grapple_input()

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
			rate = ground_decel if is_on_floor() else air_decel
		velocity.x = move_toward(velocity.x, target, rate * delta)

	# --- Jump ---
	if is_on_floor() or dash_timer > 0.0:
		can_jump = true
	else:
		can_jump = false

	if Input.is_action_just_pressed("jump") and can_jump:
		velocity.y = -jump_speed

	# --- Grapple physics ---
	if is_grappling:
		_apply_grapple_physics(delta)

	# --- Move & push ---
	move_and_slide()

	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		var collider = c.get_collider()
		if collider is RigidBody2D:
			collider.apply_central_impulse(-c.get_normal() * velocity.length() * dash_push_factor)


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


func _apply_grapple_physics(delta: float) -> void:
	var to_anchor := grapple_anchor - global_position
	var dist := to_anchor.length()

	# --- Reel in ---
	if Input.is_action_pressed("reel") and dist > 1.0:
		var reel_step := reel_speed * delta
		rope_length = maxf(rope_length - reel_step, 20.0)
		velocity += to_anchor.normalized() * reel_speed * delta

	# --- Elastic rope (spring) ---
	var stretch := dist - rope_length
	if stretch > 0.0:
		var rope_dir := to_anchor.normalized()
		velocity += rope_dir * stretch * spring_stiffness * delta
		var radial_vel := velocity.dot(-rope_dir)
		if radial_vel > 0.0:
			velocity += rope_dir * radial_vel * spring_damping * delta

	# --- Update rope visual ---
	rope.set_point_position(0, global_position - rope.global_position)
	rope.set_point_position(1, to_local(grapple_anchor))

	# Auto-release if too close
	if dist < 10.0:
		_release_grapple()


func _on_dash_cooldown_timeout() -> void:
	can_dash = true   

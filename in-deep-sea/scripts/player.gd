extends CharacterBody2D
class_name Player

@onready var camera: Camera2D = $Camera2D

@onready var end_level_ui: CanvasLayer = $Camera2D/CanvasLayer
@onready var label: Label = $Camera2D/CanvasLayer/MarginContainer/VBoxContainer/Label

var level_completed: bool = false
var level_time: float = 0

# Spine character. Adjust the path to match your scene tree.
@onready var spine: SpineSprite = $CleitinhoInDeepSea

@onready var harpoon: Sprite2D = $Harpoon

# ============================================================
#  MOVEMENT
# ============================================================
@export var speed := 640.0
@export var jump_speed := 800.0
@export var gravity := 1400.0

# Horizontal feel
@export var ground_accel := 3200.0
@export var ground_friction := 4750.0
@export var ground_brake := 6500.0
@export var air_accel := 1400.0
@export var air_friction := 200.0
@export var air_brake := 2000.0
@export var swing_coast_friction := 300.0

# Variable jump
@export var jump_release_gravity := 4.0
@export var jump_release_duration := 0.15

# Coyote & buffer
@export var coyote_time := 0.125
@export var jump_buffer_time := 0.1

# ============================================================
#  DASH
# ============================================================
@export var dash_speed := 1200.0
@export var dash_duration := 0.2
@export var dash_push_factor := 0.8
@export var dash_falloff_speed := 1500.0
@onready var dash_cooldown: Timer = $"Dash Cooldown"
@export var dash_cooldown_ground := 0.35
@export var dash_cooldown_air := 1.0

# ============================================================
#  GRAPPLE / SWING
# ============================================================
@onready var ray: RayCast2D = $RayCast2D
@onready var rope: Line2D = $Line2D

@export var rope_max_length := 1250.0
@export var rope_min_length := 20.0       # Shortest the rope can get
@export var reel_speed := 400.0   # Pixels per second when holding the reel keys
@export var spring_stiffness := 150.0
@export var spring_damping := 12
@export var swing_gravity_scale := 1.5
@export var swing_input_influence := 1.25
@export var swing_max_speed := 4000.0
@export var wall_drag_rate := 5.0
@export var swing_air_drag := 0.015   # Higher = swing loses speed faster

@export var dash_rope_stiffness_scale := 3.0   # Multiplies spring_stiffness during a dash
@export var dash_rope_damping_scale := 3.0     # Multiplies spring_damping during a dash

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
#  ANIMATION
# ============================================================
# Track 0 = body (idle / run / air / dash), track 1 = harpoon arm
const TRACK_BODY := 0
const TRACK_HARPOON := 1
const ANIM_MIX := 0.15   # Seconds used to blend between animations
const HOOK_MIX := 0.05           # Fast blend when the hook is fired
const HARPOON_OUT_TIME := 0.5    # Length of the out_arpao animation, in seconds

enum AnimState { NONE, IDLE, RUN, AIR, DASH, HOOKED }
var anim_state := AnimState.NONE
var harpoon_anim_active := false
var hook_release_timer := 0.0
var base_scale := Vector2.ONE   # Skeleton scale without the left/right flip

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

var was_on_floor := false

var can_cut_jump := false

# Used to draw the rope at the same interpolated position as the player
var prev_pos := Vector2.ZERO
var curr_pos := Vector2.ZERO

func _ready() -> void:
	end_level_ui.hide()
	
	GlobalSignals.player_died.connect(die)
	GlobalSignals.trampoline_collided.connect(step_on_trampoline)
	GlobalSignals.go_to_next_level_reached.connect(collided_with_next_level_portal)

	camera.make_current()
	ray.enabled = true

	rope.top_level = true
	rope.global_position = Vector2.ZERO
	rope.add_point(Vector2.ZERO)
	rope.add_point(Vector2.ZERO)
	rope.width = 2.0

	prev_pos = global_position
	curr_pos = global_position

	harpoon.top_level = true
	harpoon.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	harpoon.hide()

	base_scale = Vector2(absf(spine.scale.x), spine.scale.y)

func die() -> void:
	_release_grapple()
	visible = false
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	await get_tree().create_timer(1).timeout
	# Player death animation
	GlobalSignals.restart_level_signal.emit()

func _process(delta: float) -> void:
	if !level_completed:
		level_time += delta
	
	var t := Engine.get_physics_interpolation_fraction()
	var draw_pos := prev_pos.lerp(curr_pos, t)

	if is_grappling:
		rope.set_point_position(0, draw_pos)
		rope.set_point_position(1, grapple_anchor)
		harpoon.global_position = grapple_anchor

	_update_facing()

func _physics_process(delta: float) -> void:
	_handle_grapple_input()

	if is_grappling:
		_update_grapple_anchor()
		_update_grapple_movement(delta)
	else:
		_update_walking_movement(delta)

	move_and_slide()

	# Reset the dash on the tick the player lands
	var landed := is_on_floor() and not was_on_floor
	was_on_floor = is_on_floor()
	if landed and not can_dash:
		dash_cooldown.stop()
		can_dash = true

	_handle_collisions()
	_update_camera(delta)
	_update_animation(delta)

	prev_pos = curr_pos
	curr_pos = global_position

# ============================================================
#  FACING (Spine has no flip_h, so we flip the node's scale)
# ============================================================

func _face_left(left: bool) -> void:
	spine.scale.x = -base_scale.x if left else base_scale.x

func _is_facing_left() -> bool:
	return spine.scale.x < 0.0

func _update_facing() -> void:
	# While hooked, the facing stays as it was when the harpoon was shot
	if is_grappling:
		return

	# Only change direction when there is movement input,
	# otherwise keep the last facing
	var move_input := Input.get_axis("move_left", "move_right")
	if move_input != 0.0:
		_face_left(move_input < 0.0)

# ============================================================
#  ANIMATION
# ============================================================

func _update_animation(delta: float) -> void:
	var state := spine.get_animation_state()
	if state == null:
		return

	if hook_release_timer > 0.0:
		hook_release_timer -= delta

	# --- Track 1: harpoon arm ---
	if is_grappling and not harpoon_anim_active:
		harpoon_anim_active = true
		hook_release_timer = 0.0
		state.set_animation("in_arpao", false, TRACK_HARPOON)
		state.add_animation("loop_arpao", 0.0, true, TRACK_HARPOON)
	elif not is_grappling and harpoon_anim_active:
		harpoon_anim_active = false
		hook_release_timer = HARPOON_OUT_TIME
		state.set_animation("out_arpao", false, TRACK_HARPOON)
		state.add_empty_animation(TRACK_HARPOON, ANIM_MIX, 0.0)

	# --- Track 0: body ---
	var desired := AnimState.IDLE
	if is_grappling or hook_release_timer > 0.0:
		# run / jump / dash switch the arm-aiming constraints off, so while the
		# harpoon arm is in use the body track stays in the setup pose
		desired = AnimState.HOOKED
	elif dash_timer > 0.0:
		desired = AnimState.DASH
	elif not is_on_floor():
		desired = AnimState.AIR
	elif Input.get_axis("move_left", "move_right") != 0.0:
		desired = AnimState.RUN

	if desired == anim_state:
		return

	var previous := anim_state
	anim_state = desired

	match desired:
		AnimState.HOOKED:
			state.set_empty_animation(TRACK_BODY, HOOK_MIX)
		AnimState.IDLE:
			if previous == AnimState.RUN:
				# Play the stop animation, then blend back to the setup pose
				state.set_animation("out_run", false, TRACK_BODY)
				state.add_empty_animation(TRACK_BODY, ANIM_MIX, 0.0)
			else:
				state.set_empty_animation(TRACK_BODY, ANIM_MIX)
		AnimState.RUN:
			state.set_animation("in_run", false, TRACK_BODY)
			state.add_animation("loop_run", 0.0, true, TRACK_BODY)
		AnimState.AIR:
			state.set_animation("jump", false, TRACK_BODY)
		AnimState.DASH:
			state.set_animation("dash", false, TRACK_BODY)

# ============================================================
#  WALKING SYSTEM (unhooked)
# ============================================================

func _update_walking_movement(delta: float) -> void:
	# --- Coyote & buffer timers ---
	if is_on_floor() and velocity.y >= 0.0:
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
	if can_cut_jump and jump_was_pressed and not Input.is_action_pressed("jump") and velocity.y < 0:
		release_timer = jump_release_duration
	jump_was_pressed = Input.is_action_pressed("jump")

	# Jump can no longer be cut once the player starts falling
	if velocity.y >= 0.0:
		can_cut_jump = false

	# --- Dash ---
	_try_dash()

	# --- Horizontal movement ---
	if dash_timer > 0.0:
		dash_timer -= delta
	else:
		var direction := Input.get_axis("move_left", "move_right")
		var current_speed := absf(velocity.x)

		if direction != 0.0 and signf(direction) != signf(velocity.x) and velocity.x != 0.0:
			# Reversing: brake hard and carry straight through into the new direction
			var rate = ground_brake if is_on_floor() else air_brake
			velocity.x = move_toward(velocity.x, direction * speed, rate * delta)
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
		can_cut_jump = true
		coyote_timer = 0.0
		jump_buffer_timer = 0.0

		# Reset the dash on the frame the jump happens
		if not can_dash:
			dash_cooldown.stop()
			can_dash = true

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

		# Stiffer rope while dashing: less stretch, less elastic
		var dash_to_anchor := grapple_anchor - global_position
		var dash_dist := dash_to_anchor.length()
		var dash_stretch := dash_dist - rope_length
		if dash_stretch > 0.0 and dash_dist > 0.001:
			var dash_rope_dir := dash_to_anchor / dash_dist
			velocity += dash_rope_dir * dash_stretch * spring_stiffness * dash_rope_stiffness_scale * delta
			var dash_radial := velocity.dot(-dash_rope_dir)
			if dash_radial > 0.0:
				velocity += dash_rope_dir * dash_radial * spring_damping * dash_rope_damping_scale * delta
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
		dash_cooldown.start(dash_cooldown_ground if is_on_floor() else dash_cooldown_air)
		var dir := Vector2(Input.get_axis("move_left", "move_right"), 0.0)
		if dir == Vector2.ZERO:
			dir = Vector2.LEFT if _is_facing_left() else Vector2.RIGHT
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
		# Face the direction the harpoon was shot
		if absf(aim_dir.x) > 0.01:
			_face_left(aim_dir.x < 0.0)

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
		harpoon.global_position = grapple_anchor
		harpoon.global_rotation = (grapple_anchor - global_position).angle()
		harpoon.show()

func _release_grapple() -> void:
	is_grappling = false
	rope_length = 0.0
	grapple_target = null
	rope.hide()
	harpoon.hide()

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
	can_cut_jump = false
	release_timer = 0.0
	coyote_timer = 0.0
	jump_buffer_timer = 0.0

func collided_with_next_level_portal(_next_level_reference: String) -> void:
	level_completed = true
	velocity = Vector2.ZERO
	set_physics_process(false)
	spine.hide()
	harpoon.hide()
	rope.hide()

	var m = int(level_time) / 60
	var s = int(level_time) % 60
	var ms = int(level_time * 1000) % 1000
	label.text = "Time spent on this level: " + "%02d:%02d.%03d" % [m, s, ms]
	end_level_ui.show()
	

func _on_restart_button_pressed() -> void:
	GlobalSignals.restart_level_signal.emit()

func _on_continue_button_pressed() -> void:
	GlobalSignals.go_to_next_level_button_pressed.emit()

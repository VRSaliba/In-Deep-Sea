extends CharacterBody2D
class_name Player

@onready var camera: Camera2D = $Camera2D

@onready var end_level_ui: CanvasLayer = $Camera2D/CanvasLayer
@onready var label: Label = $Camera2D/CanvasLayer/MarginContainer/VBoxContainer/Label
@onready var buttons_box_container: HBoxContainer = $Camera2D/CanvasLayer/MarginContainer/VBoxContainer/HBoxContainer

var level_completed: bool = false
var level_time: float = 0

# The body and the arm are two separate Spine skeletons.
# Adjust the paths to match your scene tree.
@onready var spine: SpineSprite = $CleitinhoInDeepSea      # The body
@onready var arm_pivot: Node2D = $ArmPivot                  # Place this node on the shoulder
@onready var arm: SpineSprite = $ArmPivot/Arm               # The arm skeleton; its origin sits on the pivot

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
@onready var dash_bar: ProgressBar = $Camera2D/CanvasLayer/MarginContainer/VBoxContainer/HBoxContainer2/VBoxContainer/ProgressBar
@export var dash_cooldown_ground := 0.35
@export var dash_cooldown_air := 1.0

var dash_cooldown_total: float = 1.0

# ============================================================
#  GRAPPLE / SWING
# ============================================================
@onready var ray: RayCast2D = $RayCast2D
@onready var rope: Line2D = $Line2D

@export var rope_max_length := 1250.0
@export var rope_min_length := 20.0
@export var reel_speed := 400.0
@export var spring_stiffness := 150.0
@export var spring_damping := 12
@export var swing_gravity_scale := 1.5
@export var swing_input_influence := 1.25
@export var swing_max_speed := 4000.0
@export var wall_drag_rate := 5.0
@export var swing_air_drag := 0.015

@export var dash_rope_stiffness_scale := 3.0
@export var dash_rope_damping_scale := 3.0

var grapple_target: Node2D = null
var grapple_local_offset := Vector2.ZERO

# Rope look. "Tension" = how close the rope is to its stretch limit (0 = loose, 1 = stretched)
@export var rope_color_loose := Color(1.0, 1.0, 1.0)
@export var rope_color_taut := Color(1.0, 0.1, 0.1)
@export var rope_width_loose := 5.0
@export var rope_width_taut := 2.0
@export var rope_slack_ratio := 0.95     # distance / rope_length at or below this = fully loose
@export var rope_stretch_ratio := 1.1    # distance / rope_length at or above this = fully stretched
@export var rope_visual_smooth := 12.0   # How fast the color and width follow the tension
var rope_tension := 0.0

# ============================================================
#  CAMERA ZOOM
# ============================================================
@export var zoom_max_speed := 2000.0
@export var min_zoom := 0.45
@export var max_zoom := 0.65
@export var zoom_smooth := 3.5
@export var grapple_pan_factor := 0.5
@export var pan_smooth := 8.0

# ============================================================
#  ARM AIMING
# ============================================================
# The arm skeleton is rotated as a whole around the pivot.
# Rotation 0 must make the arm point to the right in the arm's own art;
# if it points somewhere else, set this offset (radians, e.g. deg_to_rad(90)).
const ARM_ROTATION_OFFSET := 0.0

# ============================================================
#  ANIMATION
# ============================================================
# Both skeletons (body and arm) use the same animation names.
# Blending between animations uses the default mix set on each SpineSkeletonDataResource.
const ANIM_IDLE := "idle"
const ANIM_RUN := "loop_run"
const ANIM_RUN_OUT := "out_run"
const ANIM_AIR := "jump"
const ANIM_HOOK_IN := "in_arpao"
const ANIM_HOOK_LOOP := "loop_arpao"
const ANIM_HOOK_OUT := "out_arpao"

enum AnimState { NONE, IDLE, RUN, AIR, HOOKED }
var anim_state := AnimState.NONE

var base_scale := Vector2.ONE        # Body scale without the left/right flip
var arm_base_scale := Vector2.ONE    # Arm scale without the up/down flip
var arm_pivot_base_x := 0.0          # Pivot x while facing right
var arm_base_position := Vector2.ZERO  # Arm position inside the pivot while pointing right
var jump_anim_active := false        # True after a real jump, until the player lands

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

var prev_pos := Vector2.ZERO
var curr_pos := Vector2.ZERO

var dead := false

func _ready() -> void:
	hide_end_level_ui()

	GlobalSignals.player_died.connect(die)
	GlobalSignals.trampoline_collided.connect(step_on_trampoline)
	GlobalSignals.go_to_next_level_reached.connect(collided_with_next_level_portal)

	camera.make_current()
	ray.enabled = true

	rope.top_level = true
	rope.global_position = Vector2.ZERO
	rope.add_point(Vector2.ZERO)
	rope.add_point(Vector2.ZERO)
	rope.width = rope_width_loose

	prev_pos = global_position
	curr_pos = global_position

	harpoon.top_level = true
	harpoon.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	harpoon.hide()

	base_scale = Vector2(absf(spine.scale.x), spine.scale.y)
	arm_base_scale = Vector2(arm.scale.x, absf(arm.scale.y))
	arm_pivot_base_x = arm_pivot.position.x
	arm_base_position = arm.position

	# The arm is rotated and flipped from _process, so physics interpolation must not smooth it
	arm_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	dash_bar.max_value = 1.0
	dash_bar.value = 1.0
	_update_dash_bar_color()

func hide_end_level_ui() -> void:
	label.hide()
	buttons_box_container.hide()

func show_end_level_ui() -> void:
	end_level_ui.show()
	label.show()
	buttons_box_container.show()

func die() -> void:
	if dead:
		return
	dead = true
	_release_grapple()
	visible = false
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	await get_tree().create_timer(1).timeout
	get_tree().reload_current_scene()

func _process(delta: float) -> void:
	if not level_completed:
		level_time += delta

	var t := Engine.get_physics_interpolation_fraction()
	var draw_pos := prev_pos.lerp(curr_pos, t)

	if is_grappling:
		rope.set_point_position(0, draw_pos)
		rope.set_point_position(1, grapple_anchor)
		harpoon.global_position = grapple_anchor
		_update_rope_look(draw_pos, delta)

	# --- Dash cooldown bar ---
	if not can_dash and not dash_cooldown.is_stopped():
		dash_bar.value = 1.0 - (dash_cooldown.time_left / dash_cooldown_total)
	_update_dash_bar_color()

	_update_facing()
	_update_arm_aim(draw_pos)

func _update_rope_look(draw_pos: Vector2, delta: float) -> void:
	var target := 0.0
	if rope_length > 0.0:
		var ratio := draw_pos.distance_to(grapple_anchor) / rope_length
		target = clampf(inverse_lerp(rope_slack_ratio, rope_stretch_ratio, ratio), 0.0, 1.0)

	# Smooth it so the rope doesn't flicker between physics ticks
	rope_tension = lerpf(rope_tension, target, 1.0 - exp(-rope_visual_smooth * delta))

	rope.default_color = rope_color_loose.lerp(rope_color_taut, rope_tension)
	rope.width = lerpf(rope_width_loose, rope_width_taut, rope_tension)

func _physics_process(delta: float) -> void:
	_handle_grapple_input()

	if is_grappling:
		_update_grapple_anchor()
		_update_grapple_movement(delta)
	else:
		_update_walking_movement(delta)

	move_and_slide()

	var landed := is_on_floor() and not was_on_floor
	was_on_floor = is_on_floor()
	if landed and not can_dash:
		dash_cooldown.stop()
		can_dash = true
		dash_bar.value = 1.0

	_handle_collisions()
	_update_camera(delta)
	_update_animation()

	prev_pos = curr_pos
	curr_pos = global_position

# ============================================================
#  DASH BAR
# ============================================================

func _update_dash_bar_color() -> void:
	var ratio := dash_bar.value
	var fill_style := dash_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style:
		fill_style.bg_color = Color.RED.lerp(Color.GREEN, ratio)

# ============================================================
#  FACING (Spine has no flip_h, so we flip the body's scale)
# ============================================================

func _face_left(left: bool) -> void:
	spine.scale.x = -base_scale.x if left else base_scale.x
	# The arm isn't a child of the body, so move its pivot to the other shoulder
	arm_pivot.position.x = -arm_pivot_base_x if left else arm_pivot_base_x

func _is_facing_left() -> bool:
	return spine.scale.x < 0.0

func _update_facing() -> void:
	if is_grappling:
		return
	var move_input := Input.get_axis("move_left", "move_right")
	if move_input != 0.0:
		_face_left(move_input < 0.0)
	else:
		# No input (on the ground or in the air): face the side the mouse is on
		var to_mouse := get_global_mouse_position() - global_position
		if absf(to_mouse.x) > 1.0:
			_face_left(to_mouse.x < 0.0)

# ============================================================
#  ARM AIMING (the whole arm node rotates around its pivot)
# ============================================================

func _update_arm_aim(draw_pos: Vector2) -> void:
	# Pivot position in the interpolated frame, so the arm doesn't jitter
	var origin := draw_pos + (arm_pivot.global_position - global_position)
	var target := grapple_anchor if is_grappling else get_global_mouse_position()
	var aim := target - origin
	if aim.length() < 1.0:
		return

	var angle := aim.angle()

	# While walking (not hooked), the arm can't point backwards
	if not is_grappling:
		var move_input := Input.get_axis("move_left", "move_right")
		if move_input > 0.0:
			angle = clampf(angle, -PI / 2.0, PI / 2.0)
		elif move_input < 0.0:
			var mirrored := wrapf(PI - angle, -PI, PI)
			mirrored = clampf(mirrored, -PI / 2.0, PI / 2.0)
			angle = PI - mirrored

	arm_pivot.global_rotation = angle + ARM_ROTATION_OFFSET

	# Keep the arm upright when it points to the left. The art is mirrored, so its
	# offset has to be mirrored too, or the shoulder would drift away from the pivot.
	var pointing_left := cos(angle) < 0.0
	arm.scale.y = -arm_base_scale.y if pointing_left else arm_base_scale.y
	arm.position = Vector2(arm_base_position.x, -arm_base_position.y if pointing_left else arm_base_position.y)

# ============================================================
#  ANIMATION
# ============================================================

# One state machine drives both skeletons, so the body and the arm stay in sync
func _update_animation() -> void:
	# The jump flag only lasts until the player lands or hooks onto something
	if is_grappling or (is_on_floor() and velocity.y >= 0.0):
		jump_anim_active = false

	var desired := AnimState.IDLE
	if is_grappling:
		desired = AnimState.HOOKED
	elif not is_on_floor():
		# Only play the jump animation after a real jump (not when falling off a ledge)
		desired = AnimState.AIR if jump_anim_active else AnimState.IDLE
	elif Input.get_axis("move_left", "move_right") != 0.0:
		desired = AnimState.RUN

	if desired == anim_state:
		return

	var previous := anim_state
	anim_state = desired
	_play_state_animation(spine, desired, previous)
	_play_state_animation(arm, desired, previous)

func _play_state_animation(sprite: SpineSprite, desired: AnimState, previous: AnimState) -> void:
	var state = sprite.get_animation_state()
	if state == null:
		return

	# The animation that plays for the new state (after any "out" animation)
	var next_name := ANIM_IDLE
	var next_loop := true
	match desired:
		AnimState.RUN:
			next_name = ANIM_RUN
		AnimState.AIR:
			next_name = ANIM_AIR
			next_loop = false

	if desired == AnimState.HOOKED:
		state.set_animation(ANIM_HOOK_IN, false, 0)
		state.add_animation(ANIM_HOOK_LOOP, 0.0, true, 0)
	elif previous == AnimState.HOOKED:
		# Retract the harpoon, then continue with the new state
		state.set_animation(ANIM_HOOK_OUT, false, 0)
		state.add_animation(next_name, 0.0, next_loop, 0)
	elif previous == AnimState.RUN and desired == AnimState.IDLE:
		# Stop running, then idle
		state.set_animation(ANIM_RUN_OUT, false, 0)
		state.add_animation(next_name, 0.0, next_loop, 0)
	else:
		state.set_animation(next_name, next_loop, 0)

# ============================================================
#  WALKING SYSTEM
# ============================================================

func _update_walking_movement(delta: float) -> void:
	if is_on_floor() and velocity.y >= 0.0:
		coyote_timer = coyote_time
	else:
		coyote_timer -= delta

	if jump_buffer_timer > 0.0:
		jump_buffer_timer -= delta

	if not is_on_floor():
		var g := gravity
		if release_timer > 0.0 and velocity.y < 0:
			g *= jump_release_gravity
			release_timer -= delta
		velocity.y += g * delta

	if can_cut_jump and jump_was_pressed and not Input.is_action_pressed("jump") and velocity.y < 0:
		release_timer = jump_release_duration
	jump_was_pressed = Input.is_action_pressed("jump")

	if velocity.y >= 0.0:
		can_cut_jump = false

	_try_dash()

	if dash_timer > 0.0:
		dash_timer -= delta
	else:
		var direction := Input.get_axis("move_left", "move_right")
		var current_speed := absf(velocity.x)

		if direction != 0.0 and signf(direction) != signf(velocity.x) and velocity.x != 0.0:
			var rate = ground_brake if is_on_floor() else air_brake
			velocity.x = move_toward(velocity.x, direction * speed, rate * delta)
		elif direction != 0.0 and current_speed > speed:
			var coast_rate = ground_friction if is_on_floor() else swing_coast_friction
			velocity.x = move_toward(velocity.x, direction * speed, coast_rate * delta)
		elif direction != 0.0:
			var rate = ground_accel if is_on_floor() else air_accel
			velocity.x = move_toward(velocity.x, direction * speed, rate * delta)
		elif current_speed > speed:
			var coast_rate = ground_friction if is_on_floor() else swing_coast_friction
			velocity.x = move_toward(velocity.x, 0.0, coast_rate * delta)
		else:
			var rate = ground_friction if is_on_floor() else air_friction
			velocity.x = move_toward(velocity.x, 0.0, rate * delta)

	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time

	if coyote_timer > 0.0 and jump_buffer_timer > 0.0:
		velocity.y = -jump_speed
		release_timer = 0.0
		jump_was_pressed = true
		can_cut_jump = true
		jump_anim_active = true
		coyote_timer = 0.0
		jump_buffer_timer = 0.0

		if not can_dash:
			dash_cooldown.stop()
			can_dash = true
			dash_bar.value = 1.0

# ============================================================
#  GRAPPLE / SWING SYSTEM
# ============================================================

func _update_grapple_anchor() -> void:
	if grapple_target == null:
		return
	if not is_instance_valid(grapple_target):
		_release_grapple()
		return
	grapple_anchor = grapple_target.to_global(grapple_local_offset)

func _update_grapple_movement(delta: float) -> void:
	_try_dash()

	if dash_timer > 0.0:
		dash_timer -= delta

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

	velocity.y += gravity * swing_gravity_scale * delta

	var adjust := Input.get_axis("reel_in", "reel_out")
	var to_anchor := grapple_anchor - global_position
	var dist := to_anchor.length()
	var rope_dir := to_anchor / dist if dist > 0.001 else Vector2.ZERO
	var rigid := false

	if adjust != 0.0:
		if dist >= rope_length - 2.0:
			var new_len := clampf(dist + adjust * reel_speed * delta, rope_min_length, rope_max_length)
			rigid = (adjust < 0.0 and new_len < dist) or (adjust > 0.0 and new_len > dist)
			rope_length = new_len
		else:
			rope_length = clampf(rope_length + adjust * reel_speed * delta, rope_min_length, rope_max_length)

	if rigid:
		var radial := velocity.dot(rope_dir)
		velocity += rope_dir * (-adjust * reel_speed - radial)
	else:
		var stretch := dist - rope_length
		if stretch > 0.0:
			velocity += rope_dir * stretch * spring_stiffness * delta
			var radial_vel := velocity.dot(-rope_dir)
			if radial_vel > 0.0:
				velocity += rope_dir * radial_vel * spring_damping * delta

	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x += direction * swing_input_influence * speed * delta
	else:
		velocity *= exp(-swing_air_drag * delta)

	if is_on_wall() or is_on_floor() or is_on_ceiling():
		velocity *= exp(-wall_drag_rate * delta)

	if velocity.length() > swing_max_speed:
		velocity = velocity.normalized() * swing_max_speed

	if dist < 10.0:
		_release_grapple()

# ============================================================
#  DASH
# ============================================================

func _try_dash() -> void:
	if Input.is_action_just_pressed("dash") and dash_timer <= 0.0 and can_dash:
		can_dash = false
		dash_cooldown_total = dash_cooldown_ground if is_on_floor() else dash_cooldown_air
		dash_cooldown.start(dash_cooldown_total)
		dash_bar.value = 0.0
		_update_dash_bar_color()
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
		if absf(aim_dir.x) > 0.01:
			_face_left(aim_dir.x < 0.0)

		is_grappling = true
		grapple_anchor = ray.get_collision_point()

		grapple_target = ray.get_collider() as Node2D
		if grapple_target:
			grapple_local_offset = grapple_target.to_local(grapple_anchor)

		rope_length = global_position.distance_to(grapple_anchor)
		rope_length = minf(rope_length, rope_max_length)
		dash_timer = 0.0
		rope_tension = 0.0
		rope.default_color = rope_color_loose
		rope.width = rope_width_loose
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
	var current_speed := velocity.length()
	var t := clampf(current_speed / zoom_max_speed, 0.0, 1.0)
	var target_zoom := lerpf(max_zoom, min_zoom, t)
	var new_zoom := lerpf(camera.zoom.x, target_zoom, 1.0 - exp(-zoom_smooth * delta))
	camera.zoom = Vector2(new_zoom, new_zoom)

	var target_offset := Vector2.ZERO
	if is_grappling:
		target_offset = (grapple_anchor - global_position) * grapple_pan_factor

	camera.offset = camera.offset.lerp(target_offset, 1.0 - exp(-pan_smooth * delta))

func _on_dash_cooldown_timeout() -> void:
	can_dash = true
	if visible:
		dash_bar.value = 1.0
		_update_dash_bar_color()

func step_on_trampoline(jump_force: float) -> void:
	velocity.y = -jump_force
	jump_anim_active = true
	can_cut_jump = false
	release_timer = 0.0
	coyote_timer = 0.0
	jump_buffer_timer = 0.0

func collided_with_next_level_portal(_next_level_reference: String) -> void:
	level_completed = true
	velocity = Vector2.ZERO
	set_physics_process(false)
	spine.hide()
	arm_pivot.hide()
	harpoon.hide()
	rope.hide()

	@warning_ignore("integer_division")
	var minutes = int(level_time) / 60
	var seconds = int(level_time) % 60
	var milliseconds = int(level_time * 1000) % 1000
	label.text = "Time spent on this level: " + "%02d:%02d.%03d" % [minutes, seconds, milliseconds]
	show_end_level_ui()

func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()

func _on_continue_button_pressed() -> void:
	GlobalSignals.go_to_next_level_button_pressed.emit()

func _on_map_selection_button_pressed() -> void:
	get_tree().change_scene_to_file("uid://ks4llyj7r8e0")

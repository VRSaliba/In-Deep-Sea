extends CharacterBody2D
class_name Player

@onready var camera: Camera2D = $Camera2D

@onready var end_level_ui: CanvasLayer = $Camera2D/CanvasLayer
@onready var label: Label = $Camera2D/CanvasLayer/MarginContainer/VBoxContainer/Label
@onready var buttons_box_container: HBoxContainer = $Camera2D/CanvasLayer/MarginContainer/VBoxContainer/HBoxContainer

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
#  ANIMATION
# ============================================================
const TRACK_BODY := 0
const TRACK_HARPOON := 1
const ANIM_MIX := 0.15
const HOOK_MIX := 0.05
const HARPOON_OUT_TIME := 0.5

enum AnimState { NONE, IDLE, RUN, AIR, DASH, HOOKED }
var anim_state := AnimState.NONE
var harpoon_anim_active := false
var hook_release_timer := 0.0
var base_scale := Vector2.ONE

# Aiming the harpoon arm and gun at the hook anchor while hooked
const SHOULDER_BONE := "upperarm_l"   # Where the arm starts
const WRIST_BONE := "wrist_ik_l"      # IK target the arm reaches for
const GUN_BONE := "arpao"             # Its +X axis is the direction the harpoon points
const HAND_IK_NAME := "hand_ik_L"     # IK constraint that bends the hand toward its default spot
const AIM_BLEND_SPEED := 10.0         # Higher = the arm snaps to the aim faster
@export var arm_reach := 480.0        # Shoulder-to-wrist distance while aiming, in skeleton units
var aim_mix_dirty := false
var aim_warned := false

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

	# Bones can only be modified manually just before the skeleton's world transforms update
	spine.before_world_transforms_change.connect(_aim_gun_at_anchor)
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
	_update_animation(delta)

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
#  FACING
# ============================================================

func _face_left(left: bool) -> void:
	spine.scale.x = -base_scale.x if left else base_scale.x

func _is_facing_left() -> bool:
	return spine.scale.x < 0.0

func _update_facing() -> void:
	if is_grappling:
		return
	var move_input := Input.get_axis("move_left", "move_right")
	if move_input != 0.0:
		_face_left(move_input < 0.0)

# ============================================================
#  ANIMATION
# ============================================================

# Moves the arm's IK target and the gun so they point at where the harpoon landed.
# Called by the SpineSprite right before it updates its world transforms.
func _aim_gun_at_anchor(_sprite = null) -> void:
	if not is_grappling:
		if aim_mix_dirty:
			aim_mix_dirty = false
			_set_hand_ik_mix(1.0)   # Give the hand back to the rig
		return

	aim_mix_dirty = true
	_set_hand_ik_mix(0.0)           # The hand follows the forearm instead of bending toward its default spot

	var k := 1.0 - exp(-AIM_BLEND_SPEED * get_process_delta_time())
	var shoulder: Vector2 = spine.get_global_bone_transform(SHOULDER_BONE).origin
	var wrist: Transform2D = spine.get_global_bone_transform(WRIST_BONE)
	var gun: Transform2D = spine.get_global_bone_transform(GUN_BONE)

	# 1) Put the wrist target on the shoulder -> anchor line, so the arm reaches toward the rope
	var dir := (grapple_anchor - shoulder).normalized()
	var wanted := shoulder + dir * arm_reach * absf(spine.global_scale.y)
	var wrist_pos := wrist.origin.lerp(wanted, k)
	spine.set_global_bone_transform(WRIST_BONE, Transform2D(wrist.x, wrist.y, wrist_pos))

	# 2) Hold the gun at the wrist and point it at the anchor
	var gun_pos := gun.origin.lerp(wrist_pos, k)
	var turn := wrapf((grapple_anchor - gun_pos).angle() - gun.x.angle(), -PI, PI) * k
	var rotated := Transform2D(turn, Vector2.ZERO) * Transform2D(gun.x, gun.y, Vector2.ZERO)
	spine.set_global_bone_transform(GUN_BONE, Transform2D(rotated.x, rotated.y, gun_pos))

# Sets the mix of the one-bone IK that points the hand at hand_ik_L (1.0 = on, 0.0 = off)
func _set_hand_ik_mix(mix: float) -> void:
	var skeleton = spine.get_skeleton()
	if skeleton == null:
		return
	if not skeleton.has_method("find_ik_constraint"):
		if not aim_warned:
			aim_warned = true
			push_warning("SpineSkeleton has no find_ik_constraint(); the hand can't be released from its IK")
		return
	var constraint = skeleton.find_ik_constraint(HAND_IK_NAME)
	if constraint != null and constraint.has_method("set_mix"):
		constraint.set_mix(mix)

func _update_animation(delta: float) -> void:
	var state := spine.get_animation_state()
	if state == null:
		return

	if hook_release_timer > 0.0:
		hook_release_timer -= delta

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

	var desired := AnimState.IDLE
	if is_grappling or hook_release_timer > 0.0:
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

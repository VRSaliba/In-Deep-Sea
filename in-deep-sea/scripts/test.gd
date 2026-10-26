extends SpineSprite

func _ready() -> void:
	# The skeleton is large (about 1240 x 1815 units), so scale it down to see it all
	scale = Vector2(0.2, 0.2)
	position = Vector2(576, 500)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	var state := get_animation_state()
	match event.keycode:
		KEY_1:
			# Start running: in_run plays once, then loop_run repeats
			state.set_animation("in_run", false, 0)
			state.add_animation("loop_run", 0.0, true, 0)
		KEY_2:
			# Stop running: out_run plays once
			state.set_animation("out_run", false, 0)
		KEY_3:
			state.set_animation("jump", false, 0)
		KEY_4:
			state.set_animation("dash", false, 0)
		KEY_5:
			# Harpoon: in_arpao once, then loop_arpao repeats
			state.set_animation("in_arpao", false, 0)
			state.add_animation("loop_arpao", 0.0, true, 0)
		KEY_6:
			state.set_animation("out_arpao", false, 0)
		KEY_0:
			# Back to the setup pose
			state.clear_tracks()
			get_skeleton().set_to_setup_pose()

extends RefCounted
## Keyboard/gamepad source. Reads project [input] actions and reports raw intents only
## (interpretation happens in InputRouter). Headlights report `lights_cycle` edge; InputRouter
## owns the OFF->CLEARANCE->LOW->HIGH state. Keys pinned equal to InputRouter.merge_local by
## tests/test_action_registry.gd.


func poll(_delta: float) -> Dictionary[StringName, Variant]:
	# R/F drive one vertical axis shared by both aircraft (plane elevator / drone climb);
	# the families are mutually exclusive so each reads only its own field. + = up.
	var vert := Input.get_action_strength("aircraft_up") - Input.get_action_strength("aircraft_down")
	return {
		&"accel": Input.get_action_strength("accel"),
		&"brake_reverse": Input.get_action_strength("brake_reverse"),
		&"steer": Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left"),
		&"handbrake": Input.get_action_strength("handbrake"),
		&"horn": Input.is_action_pressed("horn"),
		&"lights_cycle": Input.is_action_just_pressed("headlights"),
		&"hitch_toggle": Input.is_action_just_pressed("hitch"),
		&"pto_toggle": Input.is_action_just_pressed("pto"),
		&"pto_mode_toggle": Input.is_action_just_pressed("pto_mode"),
		&"scv_toggle": Input.is_action_just_pressed("scv"),
		&"diff_lock_toggle": Input.is_action_just_pressed("diff_lock"),
		&"fwd_drive_toggle": Input.is_action_just_pressed("fwd_drive"),
		&"elevator": vert,
		&"climb": vert,
		&"arm_toggle": Input.is_action_just_pressed("arm"),
		&"node_fail_cycle": Input.is_action_just_pressed("node_fail"),
		&"flight_mode_cycle": Input.is_action_just_pressed("flight_mode"),
		&"flaps_toggle": Input.is_action_just_pressed("flaps"),
		&"hardpoint_toggle": Input.is_action_just_pressed("hardpoint"),
		&"pantograph_toggle": Input.is_action_just_pressed("pantograph"),
		&"doors_toggle": Input.is_action_just_pressed("doors"),
		&"body_cmd_toggle": Input.is_action_just_pressed("body_cmd"),
	}

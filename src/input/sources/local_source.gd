extends RefCounted
## Keyboard source. Reads project [input] actions and reports raw intents only
## (interpretation happens in InputRouter). The analog fields read each action's KEY events only,
## since InputRouter shapes them as keys; the same actions' joypad events are pad_source.gd's.
## Edges and the horn read the action, so they come from either device. Headlights report
## `lights_cycle` edge; InputRouter owns the OFF->CLEARANCE->LOW->HIGH state. Keys pinned equal
## to InputRouter.merge_local by tests/test_action_registry.gd.


func poll(_delta: float) -> Dictionary[StringName, Variant]:
	# R/F drive one vertical axis shared by both aircraft (plane elevator / drone climb);
	# the families are mutually exclusive so each reads only its own field. + = up.
	var vert := key_strength("aircraft_up") - key_strength("aircraft_down")
	return {
		&"accel": key_strength("accel"),
		&"brake_reverse": key_strength("brake_reverse"),
		&"steer": key_strength("steer_right") - key_strength("steer_left"),
		&"handbrake": key_strength("handbrake"),
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
		&"nav_mode_cycle": Input.is_action_just_pressed("nav_mode"),
		&"sheet_cycle": Input.is_action_just_pressed("sheet"),
		&"flaps_toggle": Input.is_action_just_pressed("flaps"),
		&"hardpoint_toggle": Input.is_action_just_pressed("hardpoint"),
		&"pantograph_toggle": Input.is_action_just_pressed("pantograph"),
		&"doors_toggle": Input.is_action_just_pressed("doors"),
		&"body_cmd_toggle": Input.is_action_just_pressed("body_cmd"),
	}


## 1.0 while any key bound to `action` is held, else 0.0. Each binding is tested the way the engine
## matches it: keycode first, then physical keycode, then key label.
static func key_strength(action: StringName) -> float:
	for ev in InputMap.action_get_events(action):
		var key := ev as InputEventKey
		if key == null:
			continue
		var held := false
		if key.keycode != KEY_NONE:
			held = Input.is_key_pressed(key.keycode)
		elif key.physical_keycode != KEY_NONE:
			held = Input.is_physical_key_pressed(key.physical_keycode)
		elif key.key_label != KEY_NONE:
			held = Input.is_key_label_pressed(key.key_label)
		if held:
			return 1.0
	return 0.0

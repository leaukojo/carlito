extends RefCounted
## Gamepad source: the analog fields of the same project [input] actions LocalSource reads, from
## their joypad events only. InputRouter merges it after the key shaping, so a stick and a trigger
## drive exactly as held. Edges and the horn stay in LocalSource (they read the action, either
## device). Reports only the analog keys: merge_local reads the rest at their defaults, and
## tests/test_action_registry.gd pins every key here as one merge_local carries.


func poll() -> Dictionary[StringName, Variant]:
	# One vertical axis under two keys, as in LocalSource. + = up.
	var vert := pad_strength("aircraft_up") - pad_strength("aircraft_down")
	return {
		&"accel": pad_strength("accel"),
		&"brake_reverse": pad_strength("brake_reverse"),
		&"steer": pad_strength("steer_right") - pad_strength("steer_left"),
		&"handbrake": pad_strength("handbrake"),
		&"elevator": vert,
		&"climb": vert,
	}


## The strongest of `action`'s joypad bindings across the pads it names (device -1 = every
## connected pad), 0..1. An axis reads `axis_strength`; a button reads 1.0.
static func pad_strength(action: StringName) -> float:
	var deadzone := InputMap.action_get_deadzone(action)
	var best := 0.0
	for ev in InputMap.action_get_events(action):
		if not (ev is InputEventJoypadMotion or ev is InputEventJoypadButton):
			continue
		var devices: Array[int] = Input.get_connected_joypads()
		if ev.device >= 0:
			devices = [ev.device]
		for dev in devices:
			var motion := ev as InputEventJoypadMotion
			if motion != null:
				best = maxf(best, axis_strength(Input.get_joy_axis(dev, motion.axis),
						motion.axis_value, deadzone))
			elif Input.is_joy_button_pressed(dev, (ev as InputEventJoypadButton).button_index):
				best = 1.0
	return best


## An axis at `value` against a binding toward `bound` (its sign is the direction), 0..1, as
## `Input.get_action_strength` reads it: 0 the other way or inside the deadzone, then rescaled to
## start at 0 on the deadzone's edge. A deadzone of 1 reads full at full travel.
static func axis_strength(value: float, bound: float, deadzone: float) -> float:
	if signf(value) != signf(bound) or absf(value) < deadzone:
		return 0.0
	if deadzone >= 1.0:
		return 1.0
	return clampf(inverse_lerp(deadzone, 1.0, absf(value)), 0.0, 1.0)

extends RefCounted
## Gamepad source: the analog fields of the same project [input] actions LocalSource reads, from
## their joypad axes only. InputRouter merges it after the key shaping, so a stick and a trigger
## drive exactly as held. Pad buttons are PadLayer's: it injects their actions, so edges and the
## horn reach LocalSource, and the handbrake is read here off the action. Reports only the analog
## keys, and tests/test_action_registry.gd pins each one as an axis merge_local carries (any other
## key it would OR as a bit).


func poll() -> Dictionary[StringName, Variant]:
	# Left stick Y is read here, not through an action pair: the two aircraft take it with opposite
	# signs. Same stick as the steer, so the steer's deadzone. Stick back is +.
	var y := stick(JOY_AXIS_LEFT_Y, InputMap.action_get_deadzone(&"steer_right"))
	return {
		&"accel": pad_strength("accel"),
		&"brake_reverse": pad_strength("brake_reverse"),
		&"steer": pad_strength("steer_right") - pad_strength("steer_left"),
		# PadLayer's injected action; it also reads the handbrake key, harmless under MERGE_MAX
		# (that key is not shaped).
		&"handbrake": Input.get_action_strength(&"handbrake"),
		&"elevator": y,  # plane: pull back, nose up
		&"climb": -y,  # drone: push up, climb
	}


## `axis` on whichever connected pad pushes it furthest, signed, -1..1 (`signed_axis`).
static func stick(axis: JoyAxis, deadzone: float) -> float:
	var best := 0.0
	for dev in Input.get_connected_joypads():
		var v := signed_axis(Input.get_joy_axis(dev, axis), deadzone)
		if absf(v) > absf(best):
			best = v
	return best


## A raw axis reading as a signed strength: `axis_strength` either way, so zero inside the deadzone.
static func signed_axis(value: float, deadzone: float) -> float:
	return axis_strength(value, 1.0, deadzone) - axis_strength(value, -1.0, deadzone)


## The strongest of `action`'s joypad axis bindings across the pads it names (device -1 = every
## connected pad), 0..1, each read as `axis_strength`. No action binds a pad button (PadLayer's).
static func pad_strength(action: StringName) -> float:
	var deadzone := InputMap.action_get_deadzone(action)
	var best := 0.0
	for ev in InputMap.action_get_events(action):
		var motion := ev as InputEventJoypadMotion
		if motion == null:
			continue
		var devices: Array[int] = Input.get_connected_joypads()
		if motion.device >= 0:
			devices = [motion.device]
		for dev in devices:
			best = maxf(best, axis_strength(Input.get_joy_axis(dev, motion.axis),
					motion.axis_value, deadzone))
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

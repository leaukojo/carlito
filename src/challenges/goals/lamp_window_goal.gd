class_name LampWindowGoal
extends WindowGoal
## A lamp bit through a checkpoint window. With `expect_on`, the lamp must be seen lit inside
## `zone` and never dark for longer than `max_gap_s`; leaving settles it (see WindowGoal for the
## exit rule). The gap is what lets a source that BLINKS the bit pass a steady check: a lamp is
## lit only while its bit is set, and there is no local blink timer to smooth it
## (`VehicleInput.LampInput`). Without `expect_on`, the lamp seen lit anywhere inside fails.

@export var lamp: StringName = &"turn_left"   ## a bool LampInput field
@export var expect_on := true
## The longest dark stretch a legal flasher has: a 1 Hz period (LampFrequencyGoal's slowest) plus
## its sampling tolerance, so any indicator that passes the blink check passes this one too.
@export var max_gap_s := 1.05

var _seen := false
var _off_for := 0.0


func reset() -> void:
	super()
	_seen = false
	_off_for = 0.0


func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if not ChallengeFrame.lamp_bits().has(lamp):
		out.append("'%s' is not an on/off LampInput bit" % lamp)
	if max_gap_s <= 0.0:
		out.append("max_gap_s must be positive")
	return out


func input_refs() -> PackedStringArray:
	return PackedStringArray([lamp])


func step(frame: ChallengeFrame, delta: float) -> Status:
	var lit := bool(frame.input_value(lamp))
	match _where(frame):
		Where.BEFORE:
			return Status.RUNNING
		Where.STRAYED:
			return _strayed()
		Where.LEFT:
			if expect_on and not _seen:
				message = "%s never lit in %s" % [lamp, zone]
				return Status.FAIL
			return Status.PASS
	if not expect_on:
		if lit:
			message = "%s lit in %s" % [lamp, zone]
			return Status.FAIL
		return Status.RUNNING
	if lit:
		_seen = true
		_off_for = 0.0
		return Status.RUNNING
	_off_for += delta
	if _off_for > max_gap_s + HOLD_EPS:
		message = "%s dark for over %s s in %s" % [lamp, String.num(max_gap_s, 2), zone]
		return Status.FAIL
	return Status.RUNNING

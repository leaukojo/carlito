class_name LampFrequencyGoal
extends WindowGoal
## Flash a lamp at [min_hz, max_hz] through `zone`, like an indicator relay (UN R6/R48: 90 +/- 30
## flashes a minute). Timed from RISING edges, so the duty cycle is free. Inside the zone every
## period between two rising edges must be in band, and a stretch with no rising edge longer than
## the slowest legal period fails, which is what fails a steady bit. Leaving settles it (see
## WindowGoal for the exit rule) with at least one full period measured.

@export var lamp: StringName = &"turn_left"   ## a bool LampInput field
@export var min_hz := 1.0
@export var max_hz := 2.0
## Sampling tolerance on each period, both ways. An inbound bit can only change between rendered
## frames (the web main loop runs one frame's physics ticks back to back), so a period is only
## measurable to a frame. 50 ms covers a render rate down to 20 fps.
@export var tolerance_s := 0.05

var _timing := false
var _was_lit := false
var _since_rise := 0.0   ## s since the last rising edge, or since entry before the first
var _rises := 0


func reset() -> void:
	super()
	_timing = false
	_was_lit = false
	_since_rise = 0.0
	_rises = 0


func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if not ChallengeFrame.lamp_bits().has(lamp):
		out.append("'%s' is not an on/off LampInput bit" % lamp)
	if min_hz <= 0.0 or max_hz < min_hz:
		out.append("needs 0 < min_hz <= max_hz")
	if tolerance_s < 0.0:
		out.append("negative tolerance")
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
			if _rises < 2:
				message = "%s: too few flashes in %s to time" % [lamp, zone]
				return Status.FAIL
			return Status.PASS
	if not _timing:
		# A lamp already lit on entry is not an edge this window saw rise.
		_timing = true
		_was_lit = lit
		return Status.RUNNING
	_since_rise += delta
	if lit and not _was_lit:
		if _rises > 0 and not period_in_band(_since_rise, min_hz, max_hz, tolerance_s):
			message = "%s flashing at %s Hz, needed %s to %s Hz" % [lamp,
					String.num(1.0 / _since_rise, 2), String.num(min_hz, 2), String.num(max_hz, 2)]
			return Status.FAIL
		_rises += 1
		_since_rise = 0.0
	elif _since_rise > 1.0 / min_hz + tolerance_s + HOLD_EPS:
		message = "%s: no flash for %s s in %s" % [lamp, String.num(_since_rise, 2), zone]
		return Status.FAIL
	_was_lit = lit
	return Status.RUNNING


## Whether a measured period is in [1/max_hz, 1/min_hz], widened by `tol` seconds either way.
static func period_in_band(period: float, p_min_hz: float, p_max_hz: float, tol: float) -> bool:
	return period >= 1.0 / p_max_hz - tol - HOLD_EPS and period <= 1.0 / p_min_hz + tol + HOLD_EPS

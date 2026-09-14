class_name LampFlashHoldGoal
extends ChallengeGoal
## Hazard lights: a list of lamps must flash TOGETHER at [min_hz, max_hz] — no zone, this runs
## wherever the body is. Each lamp's rising edge must land within `tolerance_s` of the others',
## and every period between two common rising edges must pass LampFrequencyGoal.period_in_band.
## PASSes once that has held for `hold_s`, measured from the first common rising edge; before it,
## RUNNING with no timeout — but a lamp rising alone starts the clock, so one lamp flashing
## without the rest still times out, the same rule that fails a steady bit in LampFrequencyGoal.

@export var lamps: Array[StringName] = [&"turn_left", &"turn_right"]
@export var min_hz := 1.0
@export var max_hz := 2.0
@export var tolerance_s := 0.05
@export var hold_s := 5.0

var _seeded := false        ## the first tick only records each lamp's state, never an edge
var _was_lit: Dictionary[StringName, bool] = {}
var _since_rise: Dictionary[StringName, float] = {}   ## per lamp, INF until its first rise
var _started := false       ## any lamp has risen at least once
var _since_group := 0.0     ## time since the last confirmed common rising edge (or since _started)
var _group_ever := false    ## a common rising edge has happened at least once
var _held_time := 0.0       ## elapsed since the first common rising edge


func reset() -> void:
	super()
	_seeded = false
	_was_lit.clear()
	_since_rise.clear()
	_started = false
	_since_group = 0.0
	_group_ever = false
	_held_time = 0.0


func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if lamps.size() < 2:
		out.append("needs at least two lamps to flash together")
	for lamp in lamps:
		if not ChallengeFrame.lamp_bits().has(lamp):
			out.append("'%s' is not an on/off LampInput bit" % lamp)
	if min_hz <= 0.0 or max_hz < min_hz:
		out.append("needs 0 < min_hz <= max_hz")
	if tolerance_s < 0.0:
		out.append("negative tolerance")
	out.append_array(_hold_problems(hold_s))
	if min_hz > 0.0 and hold_s <= 1.0 / min_hz + tolerance_s:
		# Within one slowest period the no-flash timeout cannot fire, so one flash would pass.
		out.append("hold_s must outlast the slowest legal period")
	return out


func input_refs() -> PackedStringArray:
	var out := PackedStringArray()
	for lamp in lamps:
		out.append(lamp)
	return out


func step(frame: ChallengeFrame, delta: float) -> Status:
	if not _seeded:
		# A lamp already lit on the first tick is not an edge this goal saw rise.
		_seeded = true
		for lamp in lamps:
			_was_lit[lamp] = bool(frame.input_value(lamp))
		return Status.RUNNING

	var rose := false
	for lamp in lamps:
		var lit := bool(frame.input_value(lamp))
		var rose_lamp: bool = lit and not bool(_was_lit.get(lamp, false))
		_was_lit[lamp] = lit
		if rose_lamp:
			_since_rise[lamp] = 0.0
			rose = true
		elif _since_rise.get(lamp, INF) < INF:
			_since_rise[lamp] += delta

	if _started:
		_since_group += delta
		if _group_ever:
			_held_time += delta
	elif rose:
		_started = true
		_since_group = 0.0

	if not _started:
		return Status.RUNNING

	if rose and _grouped():
		if _group_ever:
			if not LampFrequencyGoal.period_in_band(_since_group, min_hz, max_hz, tolerance_s):
				message = "flashing at %s Hz, needed %s to %s Hz" % [String.num(1.0 / _since_group, 2),
						String.num(min_hz, 2), String.num(max_hz, 2)]
				return Status.FAIL
		else:
			_group_ever = true
			_held_time = 0.0
		_since_group = 0.0
	elif _since_group > 1.0 / min_hz + tolerance_s + HOLD_EPS:
		message = "no synced flash for %s s" % String.num(_since_group, 2)
		return Status.FAIL

	return Status.PASS if _group_ever and _held_time + HOLD_EPS >= hold_s else Status.RUNNING


## Every listed lamp rose within `tolerance_s` of the others.
func _grouped() -> bool:
	for lamp in lamps:
		if _since_rise.get(lamp, INF) > tolerance_s + HOLD_EPS:
			return false
	return true

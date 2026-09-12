class_name SignalLimitConstraint
extends ChallengeConstraint
## Fail the tick a signal leaves [low, high] (inclusive): a comfort limit on `accLat`, a floor on
## `air_primary`. With `absolute`, |value| is judged, so one `high` bounds both directions.

@export var signal_name := ""
@export var low := -INF
@export var high := INF
@export var absolute := false


func problems() -> PackedStringArray:
	return _band_problems(low, high)


func signal_refs() -> PackedStringArray:
	return PackedStringArray([signal_name])


func step(frame: ChallengeFrame, _delta: float) -> Status:
	var v := frame.num(signal_name)
	if absolute:
		v = absf(v)
	if v < low or v > high:
		message = "%s reached %s, limit %s" % [signal_name, String.num(v, 2), band_text(low, high)]
		return Status.FAIL
	return Status.RUNNING

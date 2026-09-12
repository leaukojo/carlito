class_name SignalBandGoal
extends WindowGoal
## Hold a signal inside [low, high] the whole way through `zone`: out of band while inside fails,
## and leaving settles it (see WindowGoal for the exit rule). On a thin zone across the road this
## is the entry-speed gate (`kmh`, `low` only); on a long one the speed trap; along a corridor, a
## band held along a path (`agl`, `engine_load`). The band is inclusive.

@export var signal_name := ""
@export var low := -INF
@export var high := INF
@export var absolute := false   ## judge |value|


func problems() -> PackedStringArray:
	return _band_problems(low, high)


func signal_refs() -> PackedStringArray:
	return PackedStringArray([signal_name])


func step(frame: ChallengeFrame, _delta: float) -> Status:
	match _where(frame):
		Where.BEFORE:
			return Status.RUNNING
		Where.LEFT:
			return Status.PASS
		Where.STRAYED:
			return _strayed()
	var v := frame.num(signal_name)
	if absolute:
		v = absf(v)
	if v < low or v > high:
		message = "%s read %s in %s, needed %s" % [signal_name, String.num(v, 2), zone,
				band_text(low, high)]
		return Status.FAIL
	return Status.RUNNING

class_name RingLapGoal
extends ChallengeGoal
## One lap inside a RING zone: after the body first enters, the angle it sweeps about the centre
## is summed tick by tick, and 360 degrees either way passes. Leaving the ring after entering
## fails. Driving back cancels the sweep, so a lap is net rotation, not distance.

@export var zone: StringName   ## a RING with an inner radius

var _zone: ZoneShape
var _entered := false
var _last_angle := 0.0
var _swept := 0.0


func reset() -> void:
	super()
	_entered = false
	_last_angle = 0.0
	_swept = 0.0


func bind(zones: Dictionary[StringName, ZoneShape]) -> PackedStringArray:
	_zone = zones.get(zone) as ZoneShape
	var out := _missing(zone, _zone)
	if _zone != null and (_zone.kind != ZoneShape.Kind.RING or _zone.inner_r <= 0.0):
		# Through a solid cylinder's centre the angle jumps and the sweep means nothing.
		out.append("zone '%s' must be a RING with an inner radius for a lap" % zone)
	return out


func step(frame: ChallengeFrame, _delta: float) -> Status:
	var p := frame.pose.origin
	if not _zone.contains(p):
		if _entered:
			message = "left the ring %s" % zone
			return Status.FAIL
		return Status.RUNNING
	var a := _zone.angle_of(p)
	if not _entered:
		_entered = true
		_last_angle = a
		return Status.RUNNING
	_swept += angle_difference(_last_angle, a)
	_last_angle = a
	return Status.PASS if absf(_swept) >= TAU - HOLD_EPS else Status.RUNNING


## Net angle swept so far, radians (signed), for the objective line.
func swept() -> float:
	return _swept

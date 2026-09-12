class_name FailZoneConstraint
extends ChallengeConstraint
## The body's origin inside `zone` returns RESET: the runner respawns the vehicle with `warning`
## as the notice, and the attempt starts over rather than ending. Off a causeway's edge, into a
## ditch the challenge is not about.

@export var zone: StringName
@export var warning := "Off the course"

var _zone: ZoneShape


func bind(zones: Dictionary[StringName, ZoneShape]) -> PackedStringArray:
	_zone = zones.get(zone) as ZoneShape
	return _missing(zone, _zone)


func step(frame: ChallengeFrame, _delta: float) -> Status:
	if _zone.contains(frame.pose.origin):
		message = warning
		return Status.RESET
	return Status.RUNNING

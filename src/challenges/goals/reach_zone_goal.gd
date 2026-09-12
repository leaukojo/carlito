class_name ReachZoneGoal
extends ChallengeGoal
## Pass when the body reaches `zone`: its origin inside, or its path since last tick through it,
## so a thin finish line cannot be skipped at speed. Ordered waypoints are a chain of these on
## RING zones: the attempt already steps its goals in order, so a waypoint reached early does not
## count.

@export var zone: StringName

var _zone: ZoneShape


func bind(zones: Dictionary[StringName, ZoneShape]) -> PackedStringArray:
	_zone = zones.get(zone) as ZoneShape
	return _missing(zone, _zone)


func step(frame: ChallengeFrame, _delta: float) -> Status:
	return Status.PASS if _touched(_zone, frame) else Status.RUNNING

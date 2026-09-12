class_name PayloadInZoneGoal
extends ChallengeGoal
## Pass once a payload that is off the hook has stayed inside `zone` for `hold_s`, so a crate
## that bounces through the zone does not count as delivered.

@export var zone: StringName
@export var hold_s := 1.0

var _zone: ZoneShape


func bind(zones: Dictionary[StringName, ZoneShape]) -> PackedStringArray:
	_zone = zones.get(zone) as ZoneShape
	return _missing(zone, _zone)


func problems() -> PackedStringArray:
	return _hold_problems(hold_s)


func step(frame: ChallengeFrame, delta: float) -> Status:
	var inside := false
	for p in frame.payloads:
		if _zone.contains(p):
			inside = true
			break
	return Status.PASS if _held_for(inside, delta, hold_s) else Status.RUNNING

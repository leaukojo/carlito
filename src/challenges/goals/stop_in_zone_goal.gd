class_name StopInZoneGoal
extends ChallengeGoal
## Pass once the vehicle has stood still inside `zone` for `hold_s`:
## - Still: the body's |velocity| at or below `stop_speed`. That is the velocity, not the signed
##   forward `speed`, so a drone or boat drifting sideways is not still.
## - Inside: every wheel on the ground with its contact inside. A wheel-less body is judged by its
##   origin.
## - Heading: when a tolerance is set, the heading must be within it. This is what forces a
##   reverse entry into a parking bay.
## Never fails; the par time closes a crawl.

@export var zone: StringName
@export var stop_speed := 0.1         ## m/s
@export var hold_s := 1.0
@export var heading_deg := 0.0        ## compass, 0 = north
@export var heading_tol_deg := -1.0   ## below 0: any heading

var _zone: ZoneShape


func bind(zones: Dictionary[StringName, ZoneShape]) -> PackedStringArray:
	_zone = zones.get(zone) as ZoneShape
	return _missing(zone, _zone)


func problems() -> PackedStringArray:
	var out := _hold_problems(hold_s)
	if stop_speed <= 0.0:
		out.append("stop_speed must be positive")
	return out


func signal_refs() -> PackedStringArray:
	return PackedStringArray(["heading"]) if heading_tol_deg >= 0.0 else PackedStringArray()


func step(frame: ChallengeFrame, delta: float) -> Status:
	var ok := frame.velocity.length() <= stop_speed and _inside(frame) \
			and (heading_tol_deg < 0.0
				or heading_error_deg(frame.num("heading"), heading_deg) <= heading_tol_deg + ZoneShape.EPS)
	return Status.PASS if _held_for(ok, delta, hold_s) else Status.RUNNING


func _inside(frame: ChallengeFrame) -> bool:
	if frame.wheel_count == 0:
		return _zone.contains(frame.pose.origin)
	if frame.wheel_contacts.size() < frame.wheel_count:
		return false
	for p in frame.wheel_contacts:
		if not _zone.contains(p):
			return false
	return true


## Unsigned difference between two compass headings, degrees, across the 0/360 wrap.
static func heading_error_deg(a: float, b: float) -> float:
	return absf(fposmod(a - b + 180.0, 360.0) - 180.0)

class_name SignalReachGoal
extends ChallengeGoal
## Pass once a signal has sat inside [low, high] for `hold_s`, inside `zone` when one is named.
## Covers a value at a point (`axle_load` on the scale, `pto_rpm`) and a state reached (`armed`,
## `trailer_connected` as 1..1: a bool reads 0/1). Never fails. The band is inclusive.

@export var signal_name := ""
@export var low := -INF
@export var high := INF
@export var zone: StringName = &""   ## empty: anywhere
@export var hold_s := 0.0

var _zone: ZoneShape


func bind(zones: Dictionary[StringName, ZoneShape]) -> PackedStringArray:
	if zone == &"":
		_zone = null
		return PackedStringArray()
	_zone = zones.get(zone) as ZoneShape
	return _missing(zone, _zone)


func problems() -> PackedStringArray:
	var out := _band_problems(low, high)
	out.append_array(_hold_problems(hold_s))
	return out


func signal_refs() -> PackedStringArray:
	return PackedStringArray([signal_name])


func step(frame: ChallengeFrame, delta: float) -> Status:
	var v := frame.num(signal_name)
	var ok := v >= low and v <= high and (_zone == null or _zone.contains(frame.pose.origin))
	return Status.PASS if _held_for(ok, delta, hold_s) else Status.RUNNING

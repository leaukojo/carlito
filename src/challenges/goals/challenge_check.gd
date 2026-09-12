class_name ChallengeCheck
extends Resource
## Base of every goal and constraint: a stateful evaluator over ChallengeFrames. Parameters are
## exports; per-attempt state is plain vars that `reset()` restores. ChallengeAttempt runs
## `duplicate()` copies, so the def's cached resource never carries state from one attempt into
## the next.

enum Status { RUNNING, PASS, FAIL, RESET }

## Hold slack: N ticks of 1/60 s sum to a hair either side of N/60, and a hold of exactly N ticks
## must be met on tick N.
const HOLD_EPS := 1e-4

## Why the check failed or reset, for the result panel and the respawn notice.
var message := ""

var _held := 0.0


## Back to the state an attempt starts in. Subclasses with state of their own extend it.
func reset() -> void:
	message = ""
	_held = 0.0


func step(_frame: ChallengeFrame, _delta: float) -> Status:
	return Status.RUNNING


## Resolve the course zones this check names; returns what is wrong. The attempt and registry
## validation share this one path.
func bind(_zones: Dictionary[StringName, ZoneShape]) -> PackedStringArray:
	return PackedStringArray()


## Parameters that can never work (an inverted band, a negative hold), for registry validation.
func problems() -> PackedStringArray:
	return PackedStringArray()


## Contract "out" signals this check reads, for registry validation.
func signal_refs() -> PackedStringArray:
	return PackedStringArray()


## VehicleInput / LampInput fields this check reads, for registry validation.
func input_refs() -> PackedStringArray:
	return PackedStringArray()


## True once `cond` has held for `hold_s` without a break. Any tick without it restarts the run;
## a `hold_s` of 0 needs one tick with it.
func _held_for(cond: bool, delta: float, hold_s: float) -> bool:
	_held = _held + delta if cond else 0.0
	return cond and _held + HOLD_EPS >= hold_s


## Whether `zone` holds the body this tick, or the body's path since last tick crossed it.
static func _touched(zone: ZoneShape, frame: ChallengeFrame) -> bool:
	var p := frame.pose.origin
	return zone.contains(p) or (frame.prev_origin.is_finite() and zone.crosses(frame.prev_origin, p))


static func _missing(zone_name: StringName, shape: ZoneShape) -> PackedStringArray:
	if shape != null:
		return PackedStringArray()
	return PackedStringArray(["zone '%s' is not in the course" % zone_name])


static func _band_problems(low: float, high: float) -> PackedStringArray:
	if low > high:
		return PackedStringArray(["band low %s is above high %s" % [low, high]])
	return PackedStringArray()


static func _hold_problems(hold_s: float) -> PackedStringArray:
	if hold_s < 0.0:
		return PackedStringArray(["negative hold time"])
	return PackedStringArray()


## "40 to 60", "at least 40", "at most 60": a band as the result panel says it.
static func band_text(low: float, high: float) -> String:
	if is_inf(low):
		return "at most %s" % String.num(high, 3)
	if is_inf(high):
		return "at least %s" % String.num(low, 3)
	return "%s to %s" % [String.num(low, 3), String.num(high, 3)]

class_name RollbackGoal
extends ChallengeGoal
## A hill start. Standing still (|velocity| at or below `stop_speed`) inside `zone` for `hold_s`
## latches an anchor and the body's forward axis at that moment. After that, rolling back more
## than `max_rollback_m` along it fails, and pulling `pull_away_m` forward passes. The game
## measures this along the slope, because `posX`/`posZ` are whole metres on the wire. It cannot
## tell whether the car was held by the brake or the handbrake.

@export var zone: StringName
@export var stop_speed := 0.1      ## m/s
@export var hold_s := 3.0
@export var max_rollback_m := 0.10
@export var pull_away_m := 2.0

var _zone: ZoneShape
var _anchored := false
var _anchor := Vector3.ZERO
var _forward := Vector3.FORWARD


func reset() -> void:
	super()
	_anchored = false
	_anchor = Vector3.ZERO
	_forward = Vector3.FORWARD


func bind(zones: Dictionary[StringName, ZoneShape]) -> PackedStringArray:
	_zone = zones.get(zone) as ZoneShape
	return _missing(zone, _zone)


func problems() -> PackedStringArray:
	var out := _hold_problems(hold_s)
	if stop_speed <= 0.0 or max_rollback_m < 0.0 or pull_away_m <= 0.0:
		out.append("needs stop_speed > 0, max_rollback_m >= 0 and pull_away_m > 0")
	return out


func step(frame: ChallengeFrame, delta: float) -> Status:
	var p := frame.pose.origin
	if not _anchored:
		var stopped := frame.velocity.length() <= stop_speed and _zone.contains(p)
		if _held_for(stopped, delta, hold_s):
			_anchored = true
			_anchor = p
			_forward = -frame.pose.basis.z.normalized()
		return Status.RUNNING
	var along := (p - _anchor).dot(_forward)
	if along < -max_rollback_m - ZoneShape.EPS:
		message = "rolled back %d cm, allowed %d" % [roundi(-along * 100.0),
				roundi(max_rollback_m * 100.0)]
		return Status.FAIL
	return Status.PASS if along >= pull_away_m else Status.RUNNING

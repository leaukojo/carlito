class_name ManualGearConstraint
extends ChallengeConstraint
## Fail while the gearbox is automatic and the vehicle is moving. Gear byte 0 is "no gear
## opinion", which engages D1 and auto-shifts (`InputRouter.arbitrate_bridge`), so a
## gear-teaching challenge demands an exact byte. Standing still on byte 0 is allowed: nothing
## has been driven on it yet. "Moving" is the sim's own `ST_MOVING` bit.


func signal_refs() -> PackedStringArray:
	return PackedStringArray(["status"])


func step(frame: ChallengeFrame, _delta: float) -> Status:
	var moving := (roundi(frame.num("status")) & VehicleTelemetry.ST_MOVING) != 0
	if frame.input.gear_auto and moving:
		message = "moving on gear byte 0 (automatic): send an exact gear"
		return Status.FAIL
	return Status.RUNNING

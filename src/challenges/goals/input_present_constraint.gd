class_name InputPresentConstraint
extends ChallengeConstraint
## Fail while a VehicleInput field sits at its "absent" presence-rule sentinel — the pattern
## `heading_cmd` (HEADING_CMD_NONE) and `guidance_curvature` (GUIDANCE_CURVATURE_NONE) both use
## to mean "nobody sent this command this tick". Built for Tractor 4 (`tractor_auto_steer`):
## the row is only a guidance lesson if hand-steering — which never sets `guidance_curvature` —
## actually fails the attempt.

@export var field: StringName = &"guidance_curvature"
@export var sentinel := VehicleInput.GUIDANCE_CURVATURE_NONE


func input_refs() -> PackedStringArray:
	return PackedStringArray([field])


func step(frame: ChallengeFrame, _delta: float) -> Status:
	if float(frame.input_value(field)) == sentinel:
		message = "%s is absent — hand steering doesn't pass this one" % field
		return Status.FAIL
	return Status.RUNNING

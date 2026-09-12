class_name ForbiddenValueConstraint
extends ChallengeConstraint
## Fail the tick a discrete signal takes one of `values`: a flag that must never be set
## (`trailer_abs` [1] — a bool reads 0/1) or a mode that must never be entered (`mode_actual`
## [LOITER, RTL], `nav_mode_actual`).

@export var signal_name := ""
@export var values := PackedInt32Array()


func problems() -> PackedStringArray:
	if values.is_empty():
		return PackedStringArray(["no forbidden values"])
	return PackedStringArray()


func signal_refs() -> PackedStringArray:
	return PackedStringArray([signal_name])


func step(frame: ChallengeFrame, _delta: float) -> Status:
	var v := roundi(frame.num(signal_name))
	if values.has(v):
		message = "%s went to %d" % [signal_name, v]
		return Status.FAIL
	return Status.RUNNING

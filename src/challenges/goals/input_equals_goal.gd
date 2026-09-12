class_name InputEqualsGoal
extends ChallengeGoal
## Pass once an input field has matched any of `values` (under `mask`) for `hold_s`. The goal
## reads the input, not the telemetry, for commands that have no echo. Examples: `led` is a packed
## RGB565 colour in its low 16 bits (mask 0xFFFF), and `lights` LOW or HIGH is [3, 4].

@export var field: StringName = &"led"   ## a VehicleInput or LampInput field
@export var values := PackedInt32Array()
@export var mask := -1                   ## all bits
@export var hold_s := 0.5


func problems() -> PackedStringArray:
	var out := _hold_problems(hold_s)
	if values.is_empty():
		out.append("no values to match")
	return out


func input_refs() -> PackedStringArray:
	return PackedStringArray([field])


func step(frame: ChallengeFrame, delta: float) -> Status:
	var v := int(frame.input_value(field)) & mask
	var ok := false
	for want in values:
		if (want & mask) == v:
			ok = true
			break
	return Status.PASS if _held_for(ok, delta, hold_s) else Status.RUNNING

class_name ChallengeFrame
extends RefCounted
## One physics tick as a challenge sees it: the only input every goal and constraint reads. Goals
## judge the PUBLISHED wire value under its contract name (`accLat`, not `acc_lat`), because that
## is what the player's tooling receives and what a briefing quotes. Lamp bits, `gear_auto` and
## `led` come from the `VehicleInput` (rule 5's struct, never a side channel). Geometry comes from
## the body itself: pose, velocity, wheel contacts. The game judges those, as it judges a finish
## line.

## One `telemetry.to_bridge_dict()` for this tick: contract name -> wire value.
var signals: Dictionary = {}
var input := VehicleInput.new()
var pose := Transform3D.IDENTITY          ## the vehicle body's world transform
## The body's world linear velocity, m/s. "Stopped" is judged on its length, not the signed
## forward `speed`, so a drone or boat drifting sideways is not stopped.
var velocity := Vector3.ZERO
## The body's origin on the previous tick, or INF when there is none: the first tick of an
## attempt, and the first tick after ANY respawn, so a teleport is never read as a path through
## every zone in between.
var prev_origin := Vector3.INF
## World contact points of the wheels touching the ground this tick.
var wheel_contacts := PackedVector3Array()
## Wheels the rig has; 0 is a wheel-less body (drone, boat), judged by `pose.origin` instead.
var wheel_count := 0
## World positions of every payload that is NOT on the hook.
var payloads := PackedVector3Array()


## A signal as a number: a bool reads 0/1, and an absent name reads 0. Registry validation holds
## every name a def uses against the contract, so absence here is a vehicle that lacks it.
func num(signal_name: String) -> float:
	var v: Variant = signals.get(signal_name, 0.0)
	match typeof(v):
		TYPE_BOOL:
			return 1.0 if v else 0.0
		TYPE_INT, TYPE_FLOAT:
			return float(v)
	return 0.0


## A `VehicleInput` field, or a lamp bit from its `LampInput` by the lamp's own field name.
func input_value(field: StringName) -> Variant:
	if field in input.lamps:
		return input.lamps.get(field)
	return input.get(field)


## Every name `input_value` answers: the script fields of `VehicleInput` and `LampInput`, minus
## `lamps` itself.
static func input_fields() -> PackedStringArray:
	var out := PackedStringArray()
	for obj: Object in [VehicleInput.new(), VehicleInput.LampInput.new()]:
		for prop in obj.get_property_list():
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.name != "lamps":
				out.append(prop.name)
	return out


## The on/off lamp bits a lamp goal may time: the bool fields of `LampInput`.
static func lamp_bits() -> PackedStringArray:
	var out := PackedStringArray()
	for prop in VehicleInput.LampInput.new().get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.type == TYPE_BOOL:
			out.append(prop.name)
	return out

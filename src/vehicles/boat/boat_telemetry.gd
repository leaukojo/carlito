class_name BoatTelemetry
extends VehicleTelemetry
## Boat telemetry. Adds the four boat "out" fields on top of the shared
## VehicleTelemetry. Field names are EXACTLY the contract names (pitch/roll/
## rudder_actual/trim) so the Bridge's name-keyed marshaling and the dashboard's
## t.get(name) reads work unchanged.
##
## pitch / roll / rudder_actual are read straight out of the buoyancy sim (real
## values, extracted from the body basis / the applied rudder);
## trim is a modeled honest value (same latitude as fuel/coolant/engine_load): the
## outdrive trims up toward the throttle demand, computed by the pure trim_step below.

const TRIM_RATE := 40.0            ## %/s the trim chases its target

var pitch := 0.0                   ## deg, contract 'pitch' (+ = bow up)
var roll := 0.0                    ## deg, contract 'roll' (+ = starboard down)
var rudder_actual := 0            ## %, contract 'rudder_actual' (- = port/left)
var trim := 0                      ## %, contract 'trim'


## Modeled engine trim (honest-model latitude, like engine_load): the outdrive
## trims up with forward throttle demand and returns to zero off-throttle / in reverse,
## slewing at `rate` %/s. Pure -> unit-tested.
static func trim_step(current: float, throttle_demand: float, rate: float, delta: float) -> float:
	var target := clampf(throttle_demand, 0.0, 1.0) * 100.0
	return move_toward(current, target, rate * delta)


func to_bridge_dict() -> Dictionary:
	var d := super()
	d["pitch"] = pitch
	d["roll"] = roll
	d["rudder_actual"] = rudder_actual
	d["trim"] = trim
	return d

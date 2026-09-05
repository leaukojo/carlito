class_name BoatTelemetry
extends VehicleTelemetry
## Boat telemetry. Adds the two boat-only fields; names match the contract signals exactly
## (rudder_actual/trim). pitch/roll are shared VehicleTelemetry fields written by the base.
## rudder_actual is read straight from the sim; trim is a modeled honest value (same
## latitude as fuel/coolant/engine_load).

const TRIM_RATE := 40.0            ## %/s the trim chases its target

var rudder_actual := 0            ## %, contract 'rudder_actual' (- = port/left)
var trim := 0                      ## %, contract 'trim'


## Modeled engine trim: trims up with forward throttle demand, returns to zero
## off-throttle/in reverse, slewing at `rate` %/s.
static func trim_step(current: float, throttle_demand: float, rate: float, delta: float) -> float:
	var target := clampf(throttle_demand, 0.0, 1.0) * 100.0
	return move_toward(current, target, rate * delta)

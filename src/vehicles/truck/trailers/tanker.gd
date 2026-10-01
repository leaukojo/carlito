extends TowedBody
## Tanker semi-trailer. `_surge` is a labelled honest model of a shifting centre of mass, not fluid
## dynamics: one number chasing longitudinal acceleration with a lag; no free surface or baffles.
## `set_load_offset` moves the real centre of mass, so trailer_axle_load / axle_load follow as
## consequences; never add a tanker term to either signal. Braking throws the load forward;
## accelerating slumps it onto the bogie. Declares no consumers: its discharge pump is its own.

## Metres the load slides each way from rest: ~1/10 of the 5.80 m barrel.
const SURGE_TRAVEL := 0.55

## Longitudinal accel (m/s^2) for full travel: a firm but ordinary brake application.
const SURGE_ACCEL_REF := 2.5

## Seconds to cross full travel. The lag is the model: slower than the brake that causes it.
const SURGE_TIME := 1.1

var _surge := 0.0  ## metres the load has slid rearward (negative = forward)


func consumers() -> int:
	return 0


func tick_body(delta: float) -> void:
	_surge = surge_step(_surge, surge_target(accel_fwd), delta)
	set_load_offset(_surge)


func reset_body() -> void:
	# The base resets the offset; the model's own state must follow or the next tick slews back out.
	_surge = 0.0


func body_pos01() -> float:
	# No body to raise; the surge is not a position.
	return 0.0


## Where the load wants to be (metres rearward) for a longitudinal accel (+ = speeding up). +z is
## rearward in the kingpin-origin frame. Saturates at the barrel's ends.
static func surge_target(accel_long: float) -> float:
	return clampf(accel_long / SURGE_ACCEL_REF, -1.0, 1.0) * SURGE_TRAVEL


## Constant-rate step, not exponential (a slug travels rather than decays); move_toward cannot
## overshoot.
static func surge_step(current: float, target: float, delta: float) -> float:
	return move_toward(current, target, SURGE_TRAVEL / SURGE_TIME * delta)

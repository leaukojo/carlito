extends TowedBody
## Tanker semi-trailer. `_surge` is a labelled honest model of a shifting centre of mass, not
## fluid dynamics: one number chasing longitudinal acceleration with a first-order lag, no free
## surface, no baffles, no waves (same non-goal as the boat's visual-only water).
## `set_load_offset_z` moves the real centre of mass, so trailer_axle_load / axle_load report the
## surge as a consequence — never add a tanker term to either signal directly.
## Braking throws the load forward (nosing the tractor down); accelerating slumps it onto the
## bogie; the lag means it's still arriving after the rig has stopped.
## Declares no consumers: a tanker's discharge pump is its own, not chassis PTO/hydraulics.

## Metres the load slides each way from rest. Barrel is 5.80 m; 0.55 m is ~1/10 of its length,
## enough to move axle loads by ~2 t.
const SURGE_TRAVEL := 0.55

## Longitudinal accel (m/s^2) for full travel. 2.5 is a firm but ordinary brake application, so
## normal driving reaches the model's ends.
const SURGE_ACCEL_REF := 2.5

## Seconds to cross full travel. The lag is the model: liquid doesn't arrive with the pedal,
## deliberately slower than the brake application that causes it.
const SURGE_TIME := 1.1

var _surge := 0.0  ## metres the load has slid rearward (negative = forward)


func consumers() -> int:
	return 0


func tick_body(delta: float) -> void:
	_surge = surge_step(_surge, surge_target(accel_fwd), delta)
	set_load_offset_z(_surge)


func reset_body() -> void:
	# Base already resets the offset; keep the model's own state in sync or the next tick slews
	# back out.
	_surge = 0.0


func body_pos01() -> float:
	# No body to raise, so nothing for the raise interlock to clamp; the surge is not a position.
	return 0.0


## Where the load wants to be (metres rearward) for a longitudinal accel (+ = speeding up).
## +z is rearward in the trailer's kingpin-origin frame. Saturates because the load runs out of
## barrel.
static func surge_target(accel_long: float) -> float:
	return clampf(accel_long / SURGE_ACCEL_REF, -1.0, 1.0) * SURGE_TRAVEL


## Constant-rate step, not exponential: a slug of liquid travels rather than decays. move_toward
## cannot overshoot the target, so no separate clamp is needed.
static func surge_step(current: float, target: float, delta: float) -> float:
	return move_toward(current, target, SURGE_TRAVEL / SURGE_TIME * delta)

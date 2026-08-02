extends TowedBody
## Tanker semi-trailer — a barrel of liquid whose centre of mass will not hold still.
##
## THIS IS A LABELLED HONEST MODEL OF A SHIFTING CENTRE OF MASS. IT IS NOT FLUID DYNAMICS, AND IT
## IS NOT PRETENDING TO BE. There is no fluid, no free surface, no baffle, no sloshing mode and no
## wave: there is one number, `_surge`, that says how far the load has slid along the barrel, and
## it chases the trailer's own longitudinal acceleration with a first-order lag. Real wave physics
## is a project non-goal, and the same rule already governs the boat — its shader waves are visual
## only and must never feed physics. Say the model out loud, keep it small, and let the
## CONSEQUENCES be real.
##
## What is real, then, is everything downstream of the number. `set_load_offset_z` moves this
## RigidBody3D's actual centre of mass, so gravity really acts somewhere else: the bogie's springs
## really carry more or less, the fifth wheel really takes the remainder, the rig really pitches on
## the joint. trailer_axle_load (summed off those springs) and the tractor's axle_load then report
## the surge because it happened, not because a term was added to them. Nothing anywhere adds a
## tanker term to a signal.
##
## WHAT IT FEELS LIKE, so it can be recognised rather than looked for: brake hard and the load runs
## FORWARD, which shoves weight onto the fifth wheel and noses the tractor down — the "push" a
## tanker driver gets at the end of every stop, and the reason you come off the brake before you
## stop. Accelerate and it slumps to the rear onto the bogie. The lag is what makes it readable:
## the load is still arriving when the rig has already stopped.
##
## Declares NO consumers, and that is honest: a tank trailer's discharge pump is its own, so there
## is nothing on the towing unit's PTO or hydraulics. The surge needs no connection at all — it is
## the payload, not a function.

## Metres the load slides each way from rest. Sized off the barrel: it is 5.80 m long, so half a
## metre is the load moving about a tenth of its own length, which is what a part-filled
## compartment can really do and is enough to move the axle loads by ~2 t.
const SURGE_TRAVEL := 0.55

## Longitudinal acceleration (m/s^2) that puts the load at full travel. 2.5 m/s^2 is a firm brake
## application rather than an emergency one, so ordinary driving reaches the ends of the model and
## the driver sees the whole range instead of a permanently centred load.
const SURGE_ACCEL_REF := 2.5

## Seconds for the load to cross its full travel. THE LAG IS THE MODEL: a mass of liquid does not
## arrive with the pedal, and this is the one property of a real surge that matters at the
## dashboard. Deliberately slower than the brake application that causes it.
const SURGE_TIME := 1.1

var _surge := 0.0  ## metres the load has slid rearward (negative = forward)


func consumers() -> int:
	return 0


func tick_body(delta: float) -> void:
	_surge = surge_step(_surge, surge_target(accel_fwd), delta)
	set_load_offset_z(_surge)


func reset_body() -> void:
	# The base already put the offset back; this keeps the model's own state with it, or the next
	# tick would slew back out from a number the respawn never cleared.
	_surge = 0.0


func body_pos01() -> float:
	# A tanker has no body to raise, so the raise interlock has nothing to clamp here. Stated
	# rather than inherited because the surge could look like a body position and is not one.
	return 0.0


## Where the load wants to be, in metres rearward, for a longitudinal acceleration (+ = speeding
## up). Speeding up throws the load BACK (+z is rearward in the trailer's own frame, which is
## authored with the origin at the kingpin); braking throws it forward. Saturating rather than
## linear, because the load runs out of barrel.
static func surge_target(accel_long: float) -> float:
	return clampf(accel_long / SURGE_ACCEL_REF, -1.0, 1.0) * SURGE_TRAVEL


## One step of the lag, at a constant rate rather than an exponential: a slug of liquid crossing a
## barrel travels, it does not decay, and a constant rate is what makes the arrival late enough to
## feel. move_toward can only approach the target, so the model cannot overshoot its own travel and
## needs no clamp of its own.
static func surge_step(current: float, target: float, delta: float) -> float:
	return move_toward(current, target, SURGE_TRAVEL / SURGE_TIME * delta)

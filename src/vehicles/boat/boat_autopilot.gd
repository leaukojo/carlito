class_name BoatAutopilot
extends RefCounted
## The boat's autopilot (contract 'nav_mode' / 'heading_cmd', PGN 127237 Heading/Track Control):
## pure static logic, no node state. BoatVehicle keeps the per-tick state and calls in here for
## every law, the DroneModes shape. Tested in tests/test_boat_autopilot.gd.
##
## `nav_mode` is what was requested (bridge / the 2 key); `nav_mode_actual` is what the pilot is
## doing. `resolve_mode` is the only place a mode is decided.
##
## HEADING HOLD AND NOTHING MORE: no routes, no cross-track error.

const SubsystemCounts := preload("res://src/input/subsystem_counts.gd")

## Ordinals are the contract's `nav_mode` / `nav_mode_actual` enum verbatim — FROZEN, growing or
## reordering this silently desyncs the wire; test_boat_autopilot.gd pins both.
enum { STANDBY = 0, HEADING_HOLD = 1 }

## How many positions the 2 key walks; from the leaf-counts module so the router (which must not
## depend on a vehicle class) sees the same number.
const COUNT := SubsystemCounts.NAV_MODES

## |steer| above which the helmsman has the helm and the pilot stands by. Above a joystick's rest
## slop, below a deliberate nudge.
const HELM_DEADBAND := 0.05

## Rudder fraction per DEGREE of heading error: full rudder at 28.6 deg off course.
const KP := 0.035
## Rudder fraction per deg/s of turn rate (damping): full rudder against a 50 deg/s swing.
const KD := 0.02

## Why those two numbers, so a re-tune starts from the derivation. Linearize the hull about its
## heading: `I * theta_dd = rudder_torque * A * u - drag_yaw * theta_d`, with `I` from
## `VehicleMath.inertia_of(mass, probe span)` and `A` the rudder authority. With
## `u = KP * e - KD * e_d` (per-radian units): `wn = sqrt(rudder_torque * A * KP / I)` and
## `zeta = (drag_yaw + rudder_torque * A * KD) / (2 * wn * I)`. Over authorities 0.4 to 1.0:
##
##     boat-speed-a  I  685   wn 2.8-4.4   zeta 1.79-1.88
##     boat-speed-j  I 2338   wn 1.9-3.1   zeta 1.71-1.88
##     boat-sail-a   I  681   wn 2.2-3.5   zeta 1.64-1.69
##
## Overdamped on every hull (wn * dt under 0.08 at 60 Hz), and `drag_yaw` alone carries zeta
## 0.6-1.3, so one gain pair suits all three hulls with no per-variant knob.
##
## The linear plant IS the shipped one: rudder torque is applied raw, and the yaw damper's one-tick
## clamp (`VehicleMath.damped_force`) binds only when `drag_yaw > I / delta` (41 kN*m/(rad/s) on
## boat-speed-a against its 3800; every hull clears it by 11-13x). Raising `drag_yaw` (or cutting
## mass or probe span) toward `I / delta` would put the clamp in the loop and invalidate the zetas.

# --- the mode ------------------------------------------------------------------

## Is `mode` one this pilot has? An out-of-range byte is a peer describing a different boat, not
## an error: it lands on STANDBY.
static func is_valid(mode: int) -> bool:
	return mode >= 0 and mode < COUNT


## A hand on the helm outranks the request: `steer` past HELM_DEADBAND stands the pilot by while
## held. Not latched: releasing re-engages, and BoatVehicle captures the new heading on that edge.
static func resolve_mode(requested: int, helm: float) -> int:
	if not is_valid(requested):
		return STANDBY
	if absf(helm) > HELM_DEADBAND:
		return STANDBY
	return requested


## 2-key walk: STANDBY -> HEADING HOLD -> STANDBY. Mirrors InputRouter.cycle_nav_mode;
## tests/test_boat_autopilot.gd pins the two equal.
static func cycle(mode: int) -> int:
	return posmod(mode + 1, COUNT)


# --- the loop ------------------------------------------------------------------

## Heading error in degrees, wrapped to +-180 (359 -> 1 is +2). Positive means "come right".
static func heading_error(target_deg: float, actual_deg: float) -> float:
	return fposmod(target_deg - actual_deg + 180.0, 360.0) - 180.0


## Compass turn rate (deg/s, + = swinging to starboard) from the published `yaw` rate:
## `VehicleTelemetry.yaw` is angular velocity about the BODY UP axis, and +Y rotation in Godot
## swings the bow to PORT, hence the negation.
static func turn_rate_deg(yaw_rate_rads: float) -> float:
	return -rad_to_deg(yaw_rate_rads)


## PD: proportional on the heading error, derivative on the turn rate (the error's rate, negated),
## clamped to the rudder's travel. The caller feeds the result through the same slew as a hand.
static func autopilot_rudder(error_deg: float, turn_rate_deg_s: float,
		kp: float, kd: float) -> float:
	return clampf(kp * error_deg - kd * turn_rate_deg_s, -1.0, 1.0)

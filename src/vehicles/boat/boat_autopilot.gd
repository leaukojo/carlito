class_name BoatAutopilot
extends RefCounted
## The boat's autopilot (contract 'nav_mode' / 'heading_cmd', PGN 127237 Heading/Track Control) —
## pure static logic, no node state. BoatVehicle keeps the per-tick state (the resolved mode, the
## captured target, last tick's rudder) and calls in here for every law, the DroneModes shape.
## Tested in tests/test_boat_autopilot.gd.
##
## `nav_mode` is what was requested (bridge / the 2 key); `nav_mode_actual` is what the pilot is
## actually doing. `resolve_mode` is the only place a mode is decided; nothing else may re-derive
## one.
##
## HEADING HOLD AND NOTHING MORE. No routes, no cross-track error — a route is a whole waypoint
## system and heading hold is the teaching object.

const SubsystemCounts := preload("res://src/input/subsystem_counts.gd")

## Ordinals are the contract's `nav_mode` / `nav_mode_actual` enum verbatim — FROZEN, growing or
## reordering this silently desyncs the wire; test_boat_autopilot.gd pins both.
enum { STANDBY = 0, HEADING_HOLD = 1 }

## How many positions the 2 key walks; read from the leaf-counts module so the router (which must
## not depend on a vehicle class) sees the same number.
const COUNT := SubsystemCounts.NAV_MODES

## |steer| above which the helmsman has the helm and the pilot stands by. Small enough that a
## joystick's rest slop does not knock the pilot out, large enough that a deliberate nudge does.
const HELM_DEADBAND := 0.05

## Rudder fraction per DEGREE of heading error: full rudder at 28.6 deg off course.
const KP := 0.035
## Rudder fraction per deg/s of turn rate — the damping term. Full rudder against a 50 deg/s
## swing, which is about the fastest any shipped hull turns.
const KD := 0.02

## Why those two numbers, so a re-tune starts from the derivation rather than from feel. Linearize
## the hull about its heading: `I * theta_dd = rudder_torque * A * u - drag_yaw * theta_d`, with
## `I` the same `VehicleMath.inertia_of(mass, probe span)` BoatVehicle already computes and `A` the
## speed/wash rudder authority. Substituting `u = KP * e - KD * e_d` (in per-radian units) gives
## `wn = sqrt(rudder_torque * A * KP / I)` and `zeta = (drag_yaw + rudder_torque * A * KD) / (2 *
## wn * I)`. Against the three shipped hulls' own numbers, over authorities 0.4 to 1.0:
##
##     boat-speed-a  I  685   wn 2.8-4.4   zeta 1.79-1.88
##     boat-speed-j  I 2338   wn 1.9-3.1   zeta 1.71-1.88
##     boat-sail-a   I  681   wn 2.2-3.5   zeta 1.64-1.69
##
## Comfortably overdamped on every hull, so there is no limit cycle to find at 60 Hz (wn * dt is
## under 0.08 at the worst), and the hull's own `drag_yaw` is already carrying zeta 0.6-1.3 of
## that before the D term is added — which is why one gain pair suits three very different boats
## and no per-variant knob is exported.
##
## That linear plant IS the shipped one, not an approximation of it. The rudder torque is applied
## raw, and the yaw damper's one-tick clamp (`VehicleMath.damped_force`) binds when
## `drag_yaw > I / delta`, a condition the yaw rate CANCELS out of — so it either never binds or
## always does. At 60 Hz that threshold is 41 kN*m/(rad/s) on boat-speed-a against its 3800, and
## every hull clears it by 11-13x. Raising a `drag_yaw` (or cutting a hull's mass or probe span)
## toward `I / delta` is what would put the clamp in the loop and invalidate the zetas above.

# --- the mode ------------------------------------------------------------------

## Is `mode` one this pilot has? An out-of-range byte is a peer describing a different boat, not
## an error — it lands on the safe position, the `flight_mode` / `body_cmd` rule.
static func is_valid(mode: int) -> bool:
	return mode >= 0 and mode < COUNT


## The ONE place the mode is decided. A hand on the helm outranks the request: deflecting `steer`
## past HELM_DEADBAND hands the rudder straight back for as long as it is held. Not latched, so
## releasing the helm re-engages — and BoatVehicle captures the new heading on that edge, which is
## what makes "nudge the helm to change course" the way you steer under the pilot.
static func resolve_mode(requested: int, helm: float) -> int:
	if not is_valid(requested):
		return STANDBY
	if absf(helm) > HELM_DEADBAND:
		return STANDBY
	return requested


## 2-key walk: STANDBY -> HEADING HOLD -> STANDBY. `posmod` (not `%`) so a negative starting mode
## still lands inside the ladder. Named static fn for the reason DroneModes.cycle is: it mirrors
## InputRouter.cycle_nav_mode, and tests/test_boat_autopilot.gd pins the two equal by calling both.
static func cycle(mode: int) -> int:
	return posmod(mode + 1, COUNT)


# --- the loop ------------------------------------------------------------------

## Heading error in degrees, wrapped to +-180 so 359 -> 1 is a 2 degree turn to starboard rather
## than a 358 degree one to port. Positive means "come right".
static func heading_error(target_deg: float, actual_deg: float) -> float:
	return fposmod(target_deg - actual_deg + 180.0, 360.0) - 180.0


## Compass turn rate (deg/s, + = swinging to starboard) from the published `yaw` rate. The one
## place the sign convention is stated: `VehicleTelemetry.yaw` is angular velocity about the BODY
## UP axis, and a positive rotation about +Y in Godot swings the bow to PORT — the same sign the
## hull's own `apply_torque(up * -_steer * rudder_torque * authority)` already encodes.
static func turn_rate_deg(yaw_rate_rads: float) -> float:
	return -rad_to_deg(yaw_rate_rads)


## The PD itself: proportional on the heading error, derivative on the turn rate (which is the
## error's own rate, negated), clamped to the rudder's travel. Saturating is normal and correct —
## a rudder hard over is what a real pilot does 30 degrees off course. The caller feeds the result
## through the SAME slew a hand's request goes through, so the pilot cannot move the rudder faster
## than a helmsman can.
static func autopilot_rudder(error_deg: float, turn_rate_deg_s: float,
		kp: float, kd: float) -> float:
	return clampf(kp * error_deg - kd * turn_rate_deg_s, -1.0, 1.0)

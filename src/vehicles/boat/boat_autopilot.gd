class_name BoatAutopilot
extends RefCounted
## The boat's autopilot (contract 'nav_mode' / 'heading_cmd', PGN 127237 Heading/Track Control):
## pure static logic, no node state. BoatVehicle keeps the per-tick state and calls in here for
## every law, the DroneModes shape. `resolve_mode` is the only place a mode is decided.
## Heading hold and nothing more: no routes, no cross-track error.

const SubsystemCounts := preload("res://src/input/subsystem_counts.gd")

## Ordinals are the contract's `nav_mode` / `nav_mode_actual` enum verbatim — FROZEN, growing or
## reordering this silently desyncs the wire; test_boat_autopilot.gd pins both.
enum { STANDBY = 0, HEADING_HOLD = 1 }

## From the leaf-counts module so the router, which must not depend on a vehicle class, agrees.
const COUNT := SubsystemCounts.NAV_MODES

## |steer| above which the helmsman has the helm and the pilot stands by. Above a joystick's rest
## slop, below a deliberate nudge.
const HELM_DEADBAND := 0.05

## Rudder fraction per DEGREE of heading error: full rudder at 28.6 deg off course.
const KP := 0.035
## Rudder fraction per deg/s of turn rate (damping): full rudder against a 50 deg/s swing.
## Derivation (zeta 1.6-1.9 on every hull; raising `drag_yaw` toward `I / delta` voids it):
## docs/vehicles.md § Autopilot gains.
const KD := 0.02

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

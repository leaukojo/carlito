class_name HillHold
extends RefCounted
## A foot-brake hold that keeps a grade pull-away from rolling back while the coupling takes up
## (`GroundDriveSpec.hill_hold`); pure statics run by `WheelDrive.hold_step`. Brake equipment like
## ABS, so it acts on every input path. Lets go once the drive holds the grade (Bosch EP 2 203 334).
## The grade is the wheels' contact plane, never body pitch: a squatting body stands on no grade.

## ASSIST latches the released foot brake at rest, until the drive holds or `hill_hold_s` runs
## out. STANDSTILL (Valtra HillHold) holds fully at rest with the pedal up, no timeout.
enum Kind { NONE, ASSIST, STANDSTILL }

## Road speed (m/s) under which the body reads as at rest.
const REST_SPEED := 0.1


## Whether the drive (`drive_axle_t`, N·m at the axle, last tick) beats gravity's `pull_axle_t` in
## direction `dir` (+1 D, -1 R). Rolling resistance is left out: the hold lets go late, never early.
static func drive_holds(dir: float, drive_axle_t: float, pull_axle_t: float) -> bool:
	return dir != 0.0 and dir * (drive_axle_t + pull_axle_t) >= 0.0


## Gravity's torque (N·m) at the axle along the heading, + = pulling forward, in the ground plane
## of `normal`; `mass_lever` is the rig's mass times the wheel radius.
static func pull_torque(gravity: Vector3, normal: Vector3, forward: Vector3,
		mass_lever: float) -> float:
	var along := gravity - normal * gravity.dot(normal)
	var heading := forward - normal * forward.dot(normal)
	if heading.length_squared() < 1e-12:
		return 0.0
	return along.dot(heading.normalized()) * mass_lever


## One tick: the next `(held application 0..1, seconds held)`. `in_gear` = a running engine in a
## drive gear with wheels down. The caller applies `max(pedal, held)`.
static func step(kind: Kind, timeout_s: float, held: float, held_s: float, pedal: float,
		throttle: float, at_rest: bool, in_gear: bool, drives: bool, delta: float) -> Vector2:
	if kind == Kind.NONE or not in_gear:
		return Vector2.ZERO
	if kind == Kind.ASSIST:
		if pedal > 0.0:
			# The driver's own brake: latched while at rest, what the hold keeps after the release.
			return Vector2(pedal if at_rest else 0.0, 0.0)
		if held <= 0.0 or drives or held_s >= timeout_s:
			return Vector2.ZERO
		return Vector2(held, held_s + delta)
	# STANDSTILL: arms at rest with the drive pedal up; the pedal alone never lets it go.
	if held <= 0.0 and (not at_rest or throttle > 0.0):
		return Vector2.ZERO
	if throttle > 0.0 and drives:
		return Vector2.ZERO
	return Vector2(1.0, held_s + delta)

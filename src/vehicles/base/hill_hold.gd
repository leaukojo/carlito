class_name HillHold
extends RefCounted
## A hold on the foot brake that keeps a pull-away on a grade from rolling back while the coupling
## takes up: pure statics, run by `WheelDrive.hold_step` before the drivetrain each tick, which
## applies the larger of the driver's pedal and the held application
## (`GroundDriveSpec.hill_hold`). Brake equipment like ABS, so it acts on every input path.
##
## It lets go once the drive the coupling passed the wheels last tick holds the grade
## (`drive_holds`), as hill-start assist releases on the intention to start once the engine torque
## passes the torque that holds the vehicle on the grade, computed from its load (Bosch EP 2 203 334;
## Volvo VN). The grade is read off the wheels' contact plane, never the body's pitch: a body
## squatting on flat ground stands on no grade.

## ASSIST: hill-start assist. It latches the foot brake's application while the body is at rest in
## a drive gear, keeps it after the release, and lets go when the drive holds the grade or after
## `GroundDriveSpec.hill_hold_s`. STANDSTILL: a powershift tractor's hill hold (Valtra HillHold). It
## holds at full application at any rest in a drive gear with the drive pedal up, with no timeout,
## and lets go once the pedal is down and the drive holds the grade, so the powershift clutch's
## ramp takes the body over.
enum Kind { NONE, ASSIST, STANDSTILL }

## Road speed (m/s) under which the body reads as at rest.
const REST_SPEED := 0.1


## Whether the drive holds the grade: `drive_axle_t` (N·m at the axle, + = pushing the wheels
## forward, the coupling's last tick) against `pull_axle_t` (`pull_torque`), in the engaged gear's
## direction `dir` (+1 D, -1 R). Rolling resistance is left out, so the hold lets go a little late,
## never early. False out of gear.
static func drive_holds(dir: float, drive_axle_t: float, pull_axle_t: float) -> bool:
	return dir != 0.0 and dir * (drive_axle_t + pull_axle_t) >= 0.0


## Gravity's torque (N·m) at the axle along the heading, + = pulling the body forward: `gravity`
## projected onto the ground plane of unit normal `normal`, dotted with `forward` projected onto the
## same plane, times `mass_lever` (the rig's mass times the wheel radius). 0 on level ground however
## the body pitches on its springs.
static func pull_torque(gravity: Vector3, normal: Vector3, forward: Vector3,
		mass_lever: float) -> float:
	var along := gravity - normal * gravity.dot(normal)
	var heading := forward - normal * forward.dot(normal)
	if heading.length_squared() < 1e-12:
		return 0.0
	return along.dot(heading.normalized()) * mass_lever


## One tick of the hold: the next `(held application 0..1, seconds held)` from this tick's. `pedal`
## is the driver's foot brake, `throttle` the drive pedal (unsigned), `in_gear` a running engine in
## a drive gear with wheels on the ground, `drives` this tick's `drive_holds`. The caller applies
## `max(pedal, held)`.
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

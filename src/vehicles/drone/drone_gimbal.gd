class_name DroneGimbal
extends RefCounted
## The camera gimbal: a slew-rate-limited mount between the airframe and the HoodCam marker. Pure
## static logic. A gimbal is a motor moving a mass, so it cannot step: the slew limit is the whole
## model, and why `gimbal_pitch`/`gimbal_pitch_actual` are two signals. Stops come from the
## contract ranges, passed in. A command past a stop sits on the stop.

## Slew rate (deg/s), both axes.
const SLEW_DEG_S := 60.0

## Where the mount sits with nothing commanded and after a respawn: pitch level, yaw straight
## ahead. Not the bottom of pitch travel, so switching into HOOD agrees with every other view.
const REST_PITCH := 0.0
const REST_YAW := 0.0


## Steps one axis toward its command: at most `rate * delta` degrees, never outside [lo, hi]. The
## command is clamped to the stops, so one far past a stop still walks at the mount's rate.
static func slew(actual: float, commanded: float, rate: float, delta: float,
		lo: float, hi: float) -> float:
	var target := clampf(commanded, lo, hi)
	var step := maxf(rate, 0.0) * maxf(delta, 0.0)
	return clampf(actual + clampf(target - actual, -step, step), lo, hi)


## The mount's local basis: yaw first (about the body's up axis), then pitch about the yawed right
## axis. The reverse order tilts the pan axis with the camera and the horizon rolls.
static func basis_of(pitch_deg: float, yaw_deg: float) -> Basis:
	# Negated: +Y rotation swings forward toward left, but the contract says + = right seen from above.
	return Basis(Vector3.UP, -deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))

class_name DroneGimbal
extends RefCounted
## The camera gimbal: a slew-rate-limited mount between the airframe and the HoodCam marker. Pure
## static logic, no node state, no scene. Tested in tests/test_drone_gimbal.gd.
##
## A gimbal is a motor moving a mass, so it can't step — the slew limit is the whole model, and is
## why `gimbal_pitch`/`gimbal_pitch_actual` are two signals. Stops come from the contract ranges,
## read and passed in by DroneVehicle, not typed here. A command past a stop sits on the stop.

## Slew rate, degrees per second, for both axes. One rate since both axes are the same size motor
## moving the same camera.
const SLEW_DEG_S := 60.0

## Where the mount sits with nothing commanded, and where a respawn puts it back: pitch level with
## the airframe, yaw straight ahead. Not the bottom of pitch travel (a delivery drone flies camera
## down), so the neutral pose agrees with every other view and switching into HOOD is not
## disorienting.
const REST_PITCH := 0.0
const REST_YAW := 0.0


## Step one axis toward its command: at most `rate * delta` degrees this tick, never outside
## [lo, hi]. The command is clamped to the stops rather than the result, so a command far past a
## stop still walks at the mount's own rate and stops there instead of arriving early.
static func slew(actual: float, commanded: float, rate: float, delta: float,
		lo: float, hi: float) -> float:
	var target := clampf(commanded, lo, hi)
	var step := maxf(rate, 0.0) * maxf(delta, 0.0)
	return clampf(actual + clampf(target - actual, -step, step), lo, hi)


## The mount's local basis from its two angles: yaw first (about the body's own up axis), then
## pitch about the yawed right axis. The reverse order tilts the pan axis with the camera and the
## horizon rolls.
static func basis_of(pitch_deg: float, yaw_deg: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))

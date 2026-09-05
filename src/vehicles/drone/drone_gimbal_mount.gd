class_name DroneGimbalMount
extends RefCounted
## The camera mount: the marker it aims, the two angles that chase the command, and the mechanical
## stops. Owned and ticked by `DroneVehicle`. `DroneGimbal` holds the slew step and basis math.
##
## Writing a slew-limited basis onto the `HoodCam` marker each tick is the whole FPV feed —
## `ChaseCamera`'s HOOD view composes that marker's whole transform, so no camera code is needed.
## The stops are read from the contract ranges of `gimbal_pitch`/`gimbal_yaw`, never typed twice.
## Only the basis is written; the marker's position stays scene-authored.

## The scene's HoodCam marker, or null on an airframe that has none — everything here still runs
## and simply aims nothing.
var _cam: Node3D = null

## Where the mount HAS reached — what gets published, never what was asked for.
var pitch := DroneGimbal.REST_PITCH
var yaw := DroneGimbal.REST_YAW

## The stops, overwritten from the contract in `_init`.
var _pitch_lo := -90.0
var _pitch_hi := 30.0
var _yaw_lo := -120.0
var _yaw_hi := 120.0


func _init(body: Node) -> void:
	_cam = body.get_node_or_null(^"HoodCam") as Node3D
	_read_stops()
	aim()


## The mechanical stops, taken from the contract ranges of the two command signals.
func _read_stops() -> void:
	var p: RefCounted = Contract.data.get_signal_def("gimbal_pitch", "in")
	if p != null and p.range.size() == 2:
		_pitch_lo = float(p.range[0])
		_pitch_hi = float(p.range[1])
	var y: RefCounted = Contract.data.get_signal_def("gimbal_yaw", "in")
	if y != null and y.range.size() == 2:
		_yaw_lo = float(y.range[0])
		_yaw_hi = float(y.range[1])


## Step both axes toward their commands at the mount's own rate and aim the marker. Commands are
## bridge-only and in degrees — framing a shot isn't a flight control.
func tick(pitch_cmd: float, yaw_cmd: float, delta: float) -> void:
	pitch = DroneGimbal.slew(pitch, pitch_cmd, DroneGimbal.SLEW_DEG_S, delta, _pitch_lo, _pitch_hi)
	yaw = DroneGimbal.slew(yaw, yaw_cmd, DroneGimbal.SLEW_DEG_S, delta, _yaw_lo, _yaw_hi)
	aim()


## Point the marker where the mount has slewed to.
func aim() -> void:
	if _cam != null:
		_cam.transform.basis = DroneGimbal.basis_of(pitch, yaw)


## Back to the rest pose, like every other sensor on a respawn.
func reset() -> void:
	pitch = DroneGimbal.REST_PITCH
	yaw = DroneGimbal.REST_YAW
	aim()

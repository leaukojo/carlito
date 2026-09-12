class_name GimbalAimGoal
extends ChallengeGoal
## Hold the drone's camera on a target (the centre of `zone`) within `tol_deg` for `hold_s`,
## judged on the `_actual` readbacks — where the mount has slewed to, not what was asked. The look
## direction goes through `DroneGimbal.basis_of`, the basis the HOOD view is composed from, so the
## goal and the picture cannot disagree.

@export var zone: StringName
@export var tol_deg := 5.0
@export var hold_s := 1.0

var _zone: ZoneShape


func bind(zones: Dictionary[StringName, ZoneShape]) -> PackedStringArray:
	_zone = zones.get(zone) as ZoneShape
	return _missing(zone, _zone)


func problems() -> PackedStringArray:
	var out := _hold_problems(hold_s)
	if tol_deg < 0.0:
		out.append("negative aim tolerance")
	return out


func signal_refs() -> PackedStringArray:
	return PackedStringArray(["gimbal_pitch_actual", "gimbal_yaw_actual"])


func step(frame: ChallengeFrame, delta: float) -> Status:
	var err := aim_error_deg(frame.pose, frame.num("gimbal_pitch_actual"),
			frame.num("gimbal_yaw_actual"), _zone.xform.origin)
	return Status.PASS if _held_for(err <= tol_deg, delta, hold_s) else Status.RUNNING


## Degrees between the camera's look direction and the line from the body to `target`. The
## camera sits at the body origin here: its mount offset is centimetres against a target metres
## away.
static func aim_error_deg(body: Transform3D, pitch_deg: float, yaw_deg: float, target: Vector3) -> float:
	var to_target := target - body.origin
	if to_target.length_squared() < 1e-9:
		return 0.0
	var look := body.basis.orthonormalized() * DroneGimbal.basis_of(pitch_deg, yaw_deg) * Vector3.FORWARD
	return rad_to_deg(look.angle_to(to_target))

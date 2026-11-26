class_name Articulation
extends RefCounted
## Fifth-wheel geometry: pure math for a tractor unit and one semi-trailer, no nodes, no state.
## `phi` is positive with the trailer to the tractor's right. The trailer's origin is the kingpin.

## Articulation stop (deg): a labelled model of trailer-against-cab contact (real artics fold at
## 70-90); this geometry touches only at ~140, and the bodies must not collide regardless.
const JACKKNIFE_MAX_DEG := 75.0


## Signed articulation angle between two body transforms. Flattened onto the horizontal plane,
## so a pitched tractor on a ramp does not read as articulated.
static func articulation_angle(tractor: Transform3D, trailer: Transform3D) -> float:
	# Trailer forward in the tractor's frame: forward is -Z, right is +X, so the angle from
	# forward toward right is atan2(local.x, -local.z).
	var local := tractor.basis.inverse() * (-trailer.basis.z)
	var flat := Vector2(local.x, -local.z)
	if flat.length_squared() < 1e-12:
		return 0.0
	return atan2(flat.x, flat.y)


## Where a coupled trailer belongs right now: on the kingpin, with the tractor's whole basis (on a
## slope the bogie sits briefly off the ground until its RayWheels settle it).
static func coupled_pose(tractor: Transform3D, kingpin_local: Vector3) -> Transform3D:
	return Transform3D(tractor.basis, tractor * kingpin_local)


## Plate friction torque (N*m) on the towed body: the coupling law's moment `friction_nm` at this
## rate (`CouplingProfile.yaw_friction_moment`), opposing the RELATIVE yaw rate; the caller applies
## the opposite on the chassis. It damps sway without re-centring. Clamped to the one-tick stop on
## `moment`, the pair's free-body figure (`pair_moment`), the 60 Hz guard: the joint swings the
## trailer about its kingpin as well, so the relative yaw meets a larger moment, and this stop and
## the towed tyres' caps together take only part of it in a tick.
static func yaw_friction_torque(rel_yaw_rate: float, friction_nm: float, moment: float,
		delta: float) -> float:
	if friction_nm <= 0.0 or delta <= 0.0:
		return 0.0
	var cap := maxf(moment, 0.0) * absf(rel_yaw_rate) / delta
	return -signf(rel_yaw_rate) * minf(friction_nm, cap)


## The moment a torque pair meets, off the two bodies' inverse moments about its axis: in series,
## `1 / (inv_a + inv_b)`. 0 when neither body can turn.
static func pair_moment(inv_a: float, inv_b: float) -> float:
	var inv := maxf(inv_a, 0.0) + maxf(inv_b, 0.0)
	return 1.0 / inv if inv > 0.0 else 0.0


## Fraction of a semi-trailer's weight resting on the fifth wheel rather than its own bogie:
## moments about the bogie centre, kingpin at z = 0. Sizes both spring rates: a trailer sprung for
## its full mass rides its bump stops.
static func kingpin_share(com_z: float, bogie_z: float) -> float:
	if bogie_z <= 0.0:
		return 0.0
	return clampf((bogie_z - com_z) / bogie_z, 0.0, 1.0)


## Fraction of a vertical load at body-space `load_z` the rear axle carries (front z negative,
## forward = -Z).
static func rear_axle_share(load_z: float, front_z: float, rear_z: float) -> float:
	var wheelbase := rear_z - front_z
	if wheelbase <= 0.0:
		return 0.0
	return clampf((load_z - front_z) / wheelbase, 0.0, 1.0)

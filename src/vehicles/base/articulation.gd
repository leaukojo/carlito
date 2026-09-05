class_name Articulation
extends RefCounted
## Fifth-wheel geometry: pure math for a tractor unit and one semi-trailer, no nodes, no state.
## The shipped rig uses `coupled_pose` and the load split (`kingpin_share` / `rear_axle_share`),
## which sizes both specs' springs. `jackknife_step` and `pose_at_angle` are a tested but unused
## fallback for a Jolt joint that fails to hold at 60 Hz, and would be deaf to trailer-side forces.
##
## `phi` is the articulation angle about world up, tractor forward to trailer forward, positive =
## trailer to the tractor's right. The trailer's origin is the kingpin, so trailer-space z is
## measured back from the coupling.

## The rig's articulation stop, degrees: a labelled model of trailer-against-cab contact, not a
## measurement of this geometry, where nothing would touch until ~140 deg. A real artic folds to
## 70-90 deg before steel meets steel. Shared by the shipped joint's yaw limit and the fallback's
## clamp so there is one number; the two bodies must not collide regardless, since the gooseneck
## sweeps through the tractor's frame.
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


## Where a coupled trailer belongs right now: origin on the tractor's kingpin, aligned with the
## tractor. Spawn, coupling and respawn all re-lay it rather than merely stopping it, since
## zeroing velocity alone leaves it halted wherever it drifted. It inherits the tractor's whole
## basis, pitch included, so on a slope the bogie sits briefly off the ground until its own
## RayWheels settle it, which the joint's pitch limit allows.
static func coupled_pose(tractor: Transform3D, kingpin_local: Vector3) -> Transform3D:
	return Transform3D(tractor.basis, tractor * kingpin_local)


## Fallback pose: where the trailer sits at articulation angle `phi`, hung off the tractor's
## kingpin. Reuses TrainPlacement.pose_from_bogies for the basis, which already solves the det=-1
## handedness trap, and re-anchors the origin to the kingpin rather than the bogie midpoint.
static func pose_at_angle(tractor: Transform3D, kingpin_local: Vector3, phi: float,
		bogie_z: float) -> Transform3D:
	var kingpin := tractor * kingpin_local
	# Flattened tractor forward, yawed by -phi: positive phi puts the trailer right (clockwise
	# from above), and Basis(UP, +x) turns a body left.
	var fwd := -tractor.basis.z
	fwd = Vector3(fwd.x, 0.0, fwd.z)
	if fwd.length_squared() < 1e-12:
		fwd = Vector3.FORWARD
	var trailer_fwd := (Basis(Vector3.UP, -phi) * fwd.normalized())
	var pose := TrainPlacement.pose_from_bogies(kingpin, kingpin - trailer_fwd * bogie_z)
	return Transform3D(pose.basis, kingpin)


## Fallback integration: one 60 Hz step of the single-articulation kinematic model, from the
## rolling constraint that the trailer's bogie cannot move sideways.
##
##   phi_dot = yaw_rate * (1 - (kingpin_ahead / bogie_z) * cos phi) - (v / bogie_z) * sin phi
##
## `v_fwd` and `yaw_rate` are the tractor's signed forward speed and yaw about world up, and
## `kingpin_ahead` is how far the kingpin sits ahead of the drive axle. The sin term is negative
## feedback while pulling and positive while reversing, where the angle runs away into a
## jackknife. Clamped at JACKKNIFE_MAX_DEG.
static func jackknife_step(phi: float, v_fwd: float, yaw_rate: float, delta: float,
		bogie_z: float, kingpin_ahead: float) -> float:
	if bogie_z <= 0.0:
		return phi
	var phi_dot := yaw_rate * (1.0 - (kingpin_ahead / bogie_z) * cos(phi)) \
			- (v_fwd / bogie_z) * sin(phi)
	var limit := deg_to_rad(JACKKNIFE_MAX_DEG)
	return clampf(phi + phi_dot * delta, -limit, limit)


## Fraction of a semi-trailer's weight resting on the fifth wheel rather than its own bogie:
## moments about the bogie centre, kingpin at trailer-space z = 0. This sizes both spring rates,
## since the trailer's own springs carry only (1 - share) of its mass and that share lands on the
## tractor's drive axle; a trailer sprung for its full mass rides its bump stops.
static func kingpin_share(com_z: float, bogie_z: float) -> float:
	if bogie_z <= 0.0:
		return 0.0
	return clampf((bogie_z - com_z) / bogie_z, 0.0, 1.0)


## Fraction of a vertical load at body-space `load_z` the rear axle carries (front z negative,
## forward = -Z). Used for the chassis' own weight and for the kingpin load at the fifth wheel.
static func rear_axle_share(load_z: float, front_z: float, rear_z: float) -> float:
	var wheelbase := rear_z - front_z
	if wheelbase <= 0.0:
		return 0.0
	return clampf((load_z - front_z) / wheelbase, 0.0, 1.0)

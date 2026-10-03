class_name Articulation
extends RefCounted
## Fifth-wheel geometry: pure math for a tractor unit and one semi-trailer, no nodes, no state.
## The rig uses `coupled_pose` and the load split (`kingpin_share` / `rear_axle_share`), which
## sizes both specs' springs.
##
## `phi` is the articulation angle about world up, tractor forward to trailer forward, positive =
## trailer to the tractor's right. The trailer's origin is the kingpin, so trailer-space z is
## measured back from the coupling.

## The rig's articulation stop, degrees: a labelled model of trailer-against-cab contact (a real
## artic folds to 70-90 deg), not this geometry's, where nothing touches until ~140 deg. The
## joint's yaw limit; the bodies must not collide regardless, since the gooseneck sweeps through
## the tractor's frame.
const JACKKNIFE_MAX_DEG := 75.0

## Share of the one-tick stop the plate friction may take (`yaw_friction_torque`). The towed tyres'
## one-tick lateral caps already stop the same relative yaw in the same tick, so a plate taking the
## whole stop reverses it every tick and a standing rig buzzes for ever; at 0.5 the reversal halves
## each tick and dies out. Guard: `test_tow_host` `test_a_coupled_rig_standing_still_stays_mirror_symmetric`.
const YAW_CAP_SHARE := 0.5


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
## tractor. Spawn, coupling and respawn re-lay it rather than just zeroing its velocity. It
## inherits the tractor's whole basis, pitch included, so on a slope the bogie sits briefly off the
## ground until its own RayWheels settle it, which the joint's pitch limit allows.
static func coupled_pose(tractor: Transform3D, kingpin_local: Vector3) -> Transform3D:
	return Transform3D(tractor.basis, tractor * kingpin_local)


## Coulomb friction torque (N*m) a coupling plate puts on the towed body about the articulation
## axis, given the RELATIVE yaw rate across the joint. Signed to oppose the rate; the caller
## applies the equal and opposite on the chassis.
##
## Coulomb, not viscous: the magnitude is `friction_nm` at any rate, so it damps trailer sway
## without re-centring the trailer. `moment * |rate| / delta` is the one-tick rule in torque
## form (60 Hz clamp: src/vehicles/CLAUDE.md § The 60 Hz tick), of which the plate takes
## `YAW_CAP_SHARE`, so a rig at a standstill cannot buzz across zero. `moment` is the PAIR's
## (`pair_moment`): the torque turns both bodies, so either body's own moment alone overshoots.
static func yaw_friction_torque(rel_yaw_rate: float, friction_nm: float, moment: float,
		delta: float) -> float:
	if friction_nm <= 0.0 or delta <= 0.0:
		return 0.0
	var cap := YAW_CAP_SHARE * maxf(moment, 0.0) * absf(rel_yaw_rate) / delta
	return -signf(rel_yaw_rate) * minf(friction_nm, cap)


## The moment a torque pair meets, off the two bodies' inverse moments about its axis: in series,
## `1 / (inv_a + inv_b)`. 0 when neither body can turn.
static func pair_moment(inv_a: float, inv_b: float) -> float:
	var inv := maxf(inv_a, 0.0) + maxf(inv_b, 0.0)
	return 1.0 / inv if inv > 0.0 else 0.0


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

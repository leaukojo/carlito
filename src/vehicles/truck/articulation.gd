class_name Articulation
extends RefCounted
## Fifth-wheel geometry: the pure math behind a tractor unit and one semi-trailer. No nodes, no
## physics, no state -> all of it unit-tested in tests/test_trailer.gd.
##
## Two DIFFERENT jobs live here, and keeping them apart matters:
##
##   - What the SHIPPED rig uses: coupled_pose (spawn / coupling / respawn) and the static load
##     split (kingpin_share / rear_axle_share), which is what sizes both specs' springs.
##   - The NAMED FALLBACK from the plan, in case the Jolt joint had not held at 60 Hz: solve the
##     articulation angle kinematically (jackknife_step) and pose the trailer from it
##     (pose_at_angle) as an AnimatableBody3D follower. It is written and tested either way, so
##     taking it would be a decision rather than a rewrite. Its honest cost, if it is ever taken:
##     it is DEAF TO TRAILER-SIDE FORCES — a tanker's surge and the trailer's own tipping stop
##     being physical, because nothing on the trailer can push back.
##
## Angle convention, used by every function here: `phi` is the articulation angle in radians,
## measured about world up from the TRACTOR's forward to the TRAILER's forward, and POSITIVE
## means the trailer points to the tractor's RIGHT. That matches the engine's own yaw sign
## (a positive angular velocity about +Y turns a body left, so a left turn makes phi grow as the
## trailer lags behind on the right).
##
## Length convention: the trailer is authored with its ORIGIN AT THE KINGPIN, so a trailer-space
## z is a distance measured back from the coupling — `bogie_z` is the bogie centre, and the
## kingpin itself is 0. That is the implements' "origin on the lower pin line" rule in the same
## shape: the datum is the joint, so the coupled pose is one transform multiply.

## The rig's articulation stop, DEGREES — a LABELLED MODEL of trailer-against-cab contact, used by
## both the shipped joint (SemiTractor's yaw limit) and the fallback's clamp, so there is one number
## and not two.
##
## It is a model rather than a measurement, and the measurement is why: the flatbed's front corners
## swing on a 1.02 m radius (0.96 half-width, 0.33 m overhang) against 1.15 m from the kingpin to the
## cab's rear face, so on THIS geometry nothing would touch until about 140 deg, where the trailer's
## flank finally reaches the cab. A real artic is built much tighter — the trailer's swing radius
## very nearly fills the gap — and folds to roughly 70-90 deg before steel meets steel. 75 deg is
## that real stop. It cannot be left to the collision system either way: the trailer's gooseneck
## sweeps through the tractor's own frame partway round, so the two bodies must not collide at all
## (see SemiTractor._build_joint).
const JACKKNIFE_MAX_DEG := 75.0


## Signed articulation angle between two body transforms (see the convention above). Flattened
## onto the horizontal plane, so a pitched tractor on a ramp does not read as articulated.
static func articulation_angle(tractor: Transform3D, trailer: Transform3D) -> float:
	# The trailer's forward, expressed in the tractor's own frame: forward is -Z and right is +X,
	# so the angle from forward toward the right is atan2(local.x, -local.z).
	var local := tractor.basis.inverse() * (-trailer.basis.z)
	var flat := Vector2(local.x, -local.z)
	if flat.length_squared() < 1e-12:
		return 0.0
	return atan2(flat.x, flat.y)


## Where a coupled trailer belongs right now: origin on the tractor's kingpin, aligned with the
## tractor. Used at spawn, when V couples one, and by respawn — the trailer is re-LAID here, not
## merely stopped, because zeroing velocity alone leaves a body halted wherever it drifted (the
## train's lesson).
##
## It inherits the tractor's whole basis, pitch included: on a slope the bogie 5.45 m behind is
## therefore a little off the ground for the few ticks its own RayWheels need to settle it, and
## the joint's pitch limit allows exactly that. Level ground (every spawn marker) is flat.
static func coupled_pose(tractor: Transform3D, kingpin_local: Vector3) -> Transform3D:
	return Transform3D(tractor.basis, tractor * kingpin_local)


## FALLBACK pose: where the trailer sits at articulation angle `phi`, hung off the tractor's
## kingpin. Reuses TrainPlacement.pose_from_bogies for the BASIS — that is where the det = -1
## handedness trap is already solved once — and then re-anchors the origin, because a semi's pose
## datum is its kingpin and not the midpoint between two bogies the train's cars are posed from.
static func pose_at_angle(tractor: Transform3D, kingpin_local: Vector3, phi: float,
		bogie_z: float) -> Transform3D:
	var kingpin := tractor * kingpin_local
	# Flattened tractor forward, yawed by -phi: a positive phi puts the trailer to the RIGHT,
	# which is a clockwise turn from above, and Basis(UP, +x) turns a body left.
	var fwd := -tractor.basis.z
	fwd = Vector3(fwd.x, 0.0, fwd.z)
	if fwd.length_squared() < 1e-12:
		fwd = Vector3.FORWARD
	var trailer_fwd := (Basis(Vector3.UP, -phi) * fwd.normalized())
	var pose := TrainPlacement.pose_from_bogies(kingpin, kingpin - trailer_fwd * bogie_z)
	return Transform3D(pose.basis, kingpin)


## FALLBACK integration: one 60 Hz step of the single-articulation kinematic model, from the
## rolling constraint that the trailer's bogie cannot move sideways.
##
##   phi_dot = yaw_rate * (1 - (kingpin_ahead / bogie_z) * cos phi) - (v / bogie_z) * sin phi
##
## `v_fwd` is the tractor's signed forward speed and `yaw_rate` its yaw about world up (both
## straight off the sim); `kingpin_ahead` is how far the kingpin sits AHEAD of the drive axle.
## The shape of it is the whole reason a towed body is interesting: the sin term is NEGATIVE
## feedback while pulling (any angle straightens itself out) and POSITIVE while reversing (the
## angle runs away — a jackknife), which is why reversing a trailer is a skill and driving one
## forward is not. Clamped at JACKKNIFE_MAX, where the trailer would be against the cab.
static func jackknife_step(phi: float, v_fwd: float, yaw_rate: float, delta: float,
		bogie_z: float, kingpin_ahead: float) -> float:
	if bogie_z <= 0.0:
		return phi
	var phi_dot := yaw_rate * (1.0 - (kingpin_ahead / bogie_z) * cos(phi)) \
			- (v_fwd / bogie_z) * sin(phi)
	var limit := deg_to_rad(JACKKNIFE_MAX_DEG)
	return clampf(phi + phi_dot * delta, -limit, limit)


## Fraction of a semi-trailer's weight that rests on the FIFTH WHEEL rather than on its own
## bogie: moments about the bogie centre, with the kingpin at trailer-space z = 0.
##
## This is not decoration — it is what sizes both spring rates. The trailer's own springs carry
## only (1 - share) of its mass, and that same share lands on the tractor's drive axle, where it
## has to fit inside the rest of the suspension travel. A trailer whose springs are sized for its
## full mass rides on its bump stops, which is the "sinking" failure, and the shipped Kenney
## trucks already do it (their rear static load is above what their springs can make).
static func kingpin_share(com_z: float, bogie_z: float) -> float:
	if bogie_z <= 0.0:
		return 0.0
	return clampf((bogie_z - com_z) / bogie_z, 0.0, 1.0)


## Fraction of a vertical load applied at body-space `load_z` that the REAR axle carries, from
## the two axle positions (front z is negative, forward = -Z). Used twice: for the chassis' own
## weight at its centre of mass, and for the kingpin load at the fifth wheel — a load ahead of
## the drive axle is shared with the steer axle, which is why the plate sits where it does.
static func rear_axle_share(load_z: float, front_z: float, rear_z: float) -> float:
	var wheelbase := rear_z - front_z
	if wheelbase <= 0.0:
		return 0.0
	return clampf((load_z - front_z) / wheelbase, 0.0, 1.0)

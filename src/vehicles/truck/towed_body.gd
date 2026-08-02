class_name TowedBody
extends RigidBody3D
## A semi-trailer: a real RigidBody3D on the end of a real joint, carrying its OWN unmodified
## RayWheels — undriven, braked.
##
## Not a BaseVehicle, and deliberately so. It has no drivetrain, no steering and no telemetry of
## its own, and it must never register with InputRouter (there is one vehicle per tick and the
## tractor is it). What it reuses instead is RayWheel exactly as shipped: no fork, no subclass,
## no softened clamp. That is what makes it honest rather than convenient — the trailer's
## suspension loads and its wheel slip are then measurements of a real trailer, which is what
## Phase 5's trailer_axle_load and trailer_abs are read out of instead of invented.
##
## Two rules about who drives it:
##
##   - It is ticked BY THE TRACTOR, from SemiTractor._tick_extras — not from its own
##     _physics_process. That fixes the order (the trailer's wheels always integrate after the
##     tractor's, once per physics frame) and keeps the gating on the coupling side: a towed body
##     is never trusted to gate itself, the same rule ThreePointHitch follows for the implements.
##   - It reads no input. The brake demand arrives as a number the tractor computed.
##
## Geometry convention: authored with the ORIGIN AT THE KINGPIN, ground at y = -1.05 (measured
## off the tractor unit's fifth-wheel plate). So the coupling datum is the origin, every
## trailer-space z is a distance back from the kingpin, and Articulation.coupled_pose is one
## transform multiply. Wheel anchors therefore sit at NEGATIVE y, and the bogie is the only axle
## group there is.
##
## `spec` is a VehicleSpec because that is what RayWheel consumes (mass, wheel geometry,
## suspension, tires) — reuse over a second half-copied resource type. Its drivetrain, steering
## and lamp fields are unused here and stay at their defaults; `brake_torque` IS used, and is
## load-apportioned off this trailer's own axle loads rather than copied from the tractor.
##
## WHAT A TRAILER CONSUMES IS DECLARED IN CODE (`consumers()`), never in exported data — the
## ImplementBase rule, and for the same reason: a scene edit must not be able to claim a
## connection the machine does not physically have. And the GATING lives on the coupling side
## (SemiTractor), never in the subclass: a towed body is never trusted to ignore drive or flow it
## never plugged in, exactly as ThreePointHitch is never willing to trust an implement to.
##
## The two load models a subclass can carry (a tipping body's payload sliding rearward, a tanker's
## surge) both reach the world through ONE mechanism: `set_load_offset_z` moves this body's centre
## of mass. Nothing is added to a signal. The bogie's springs then really carry more or less, so
## `trailer_axle_load` (summed off those springs) and the tractor's own `axle_load` move as
## CONSEQUENCES — the draft-force discipline, and the hopper_load discipline before it.

## What a towed body can plug into on the towing unit. Both are non-visual plumbing — no hoses or
## shafts are modelled, exactly as the tractor's SCV is not — and both are gated by SemiTractor.
##
## There is deliberately no data-bus entry here: ISO 11992 belongs to the TOWING unit's ISO 7638
## connector (VehicleSpec.trailer_bus_equipped), and the standard carries nothing about the body,
## so a trailer has nothing to declare about the bus. Which trailer is on the back shows through
## MASS and through which tractor-side signals it moves — never through a trailer_type.
enum Consumer {
	PTO = 1,        ## driven off the towing unit's chassis PTO (a tipper's hydraulic pump)
	HYDRAULIC = 2,  ## fed by a proportional hydraulic valve on the towing unit
}

## Road speed (m/s) below which a body raise is permitted — a genuine STANDSTILL, not the walking
## pace RefuseBody's arm is allowed to work at. A refuse round is driven between bins with the arm
## cycling; a tipping body goes up with the rig parked and nothing else, because a raised body is
## several metres of leverage on a trailer that is about to be four metres tall.
const RAISE_SPEED_MS := 0.15
## Parking-brake application the raise interlock demands (RefuseBody.PARK_BRAKE_MIN's rule, and the
## local handbrake is still the only parking brake this project has).
const RAISE_PARK_BRAKE_MIN := 0.5

## Contacts the body reports at once. `body_is_colliding` only asks whether the list is EMPTY, so
## one would do — a couple more only make the answer robust if the engine reports them in an odd
## order, and there is no per-contact work behind it.
const MAX_CONTACTS_REPORTED := 4

## Scene node whose Node3D children are the wheel visuals, IN THE SAME ORDER as
## spec.wheel_positions. One ordering in one place: a count mismatch is an authoring error and
## says so, rather than silently leaving a wheel invisible.
@export var wheel_root: NodePath = ^"Wheels"
@export var spec: VehicleSpec

var wheels: Array[RayWheel] = []

## PTO drive as the towing unit last handed it down (see set_pto). Held on the base for the same
## reason ImplementBase holds it: a trailer that declares no PTO is gated off at the coupling and
## simply reads a dead shaft here, rather than being trusted to ignore one.
var pto_on := false
var pto_rpm := 0
## Proportional valve opening as the towing unit last handed it down, 0..1 (see set_valve). Gated
## at the coupling exactly like the PTO.
var valve_flow := 0.0

## Longitudinal acceleration along this body's OWN forward axis (m/s^2, + = speeding up),
## differentiated from its own velocity each tick. Read out of the sim that produced the motion —
## the tanker's surge model is driven off this rather than off anything the tractor reports.
var accel_fwd := 0.0

var _last_fwd_speed := 0.0
var _load_offset_z := 0.0  ## metres the payload has slid back from the spec's centre of mass


func _ready() -> void:
	# Everything below reads the spec, and a trailer scene that shipped without one would otherwise
	# fail as a null dereference two lines in. Say what is missing instead — the same shape as the
	# wheel-count mismatch below, which is the other authoring error this scene can carry.
	if spec == null:
		push_error("%s: no VehicleSpec — the trailer has no mass, wheels or brakes" % name)
		return
	mass = spec.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# The centre of mass is load-bearing on a trailer in a way it is not on a car: where it sits
	# between the kingpin and the bogie IS the load split (see Articulation.kingpin_share), so it
	# decides how much weight the tractor's drive axle picks up.
	center_of_mass = spec.center_of_mass
	can_sleep = false
	# Same reason as BaseVehicle: 14 t coming down off a kerb can cross the thin terrain collision
	# in one 60 Hz tick.
	continuous_cd = true
	# Report body contacts, which is what SemiTractor's fit check reads (see body_is_colliding).
	# Cheap here precisely because there are normally none at all: this body stands on raycasts.
	contact_monitor = true
	max_contacts_reported = MAX_CONTACTS_REPORTED
	var visuals: Array[Node3D] = []
	var root := get_node_or_null(wheel_root)
	if root != null:
		for child in root.get_children():
			if child is Node3D:
				visuals.append(child as Node3D)
	if visuals.size() != spec.wheel_positions.size():
		push_error("%s: %d wheel visuals for %d spec wheel positions" % [
				name, visuals.size(), spec.wheel_positions.size()])
	for i in spec.wheel_positions.size():
		var visual: Node3D = visuals[i] if i < visuals.size() else null
		# Undriven and unsteered: a semi-trailer axle is neither. It only ever brakes.
		wheels.append(RayWheel.new(spec.wheel_positions[i], false, false, visual))


## One physics tick of the trailer's running gear, called by the tractor. `brake01` is the service
## demand and `handbrake01` the parking-brake demand, both computed by the TRACTOR and sent as
## numbers (0..1) — the trailer applies them through RayWheel's own brake path like every other
## braked wheel in the project, so nothing here integrates a force of its own.
##
## THE PARKING BRAKE IS ON EVERY AXLE OF THE BOGIE, not on a "rear" pair the way BaseVehicle applies
## it, and that is the trailer's anatomy rather than an inconsistency: spring brake chambers sit on
## all three axles of a tri-axle bogie, because a semi-trailer has no other way to be held. It is
## also the whole of the rig's parking brake in practice — the tractor's two driven wheels cannot
## hold 32 t on a grade, which is exactly what a trailer with no park brake at all felt like.
func tick_towed(brake01: float, handbrake01: float, delta: float,
		grip_terrains: Array[Node]) -> void:
	# Empty is the state _ready leaves behind when the spec was missing: it has already said so, so
	# roll along as dead weight on the joint rather than repeating the error sixty times a second.
	if wheels.is_empty():
		return
	# This body's own longitudinal acceleration, off its own velocity. Measured BEFORE the wheels
	# integrate, so it is the motion the last tick actually produced rather than half of this one.
	if delta > 0.0:
		var fwd_speed := -global_transform.basis.z.dot(linear_velocity)
		accel_fwd = (fwd_speed - _last_fwd_speed) / delta
		_last_fwd_speed = fwd_speed
	# The body model runs BEFORE the wheels, so a load that moved this tick is under the springs
	# the same tick they report it — the tractor's pose-the-linkage-then-read-it ordering.
	tick_body(delta)
	var space := get_world_3d().direct_space_state
	var brake_t := clampf(brake01, 0.0, 1.0) * spec.brake_torque \
			+ clampf(handbrake01, 0.0, 1.0) * spec.handbrake_torque
	for w in wheels:
		w.tick(self, spec, space, 0.0, brake_t, delta, grip_terrains)


## Re-lay the trailer at `pose`, stopped. Both halves matter: the pose, because zeroing velocity
## alone leaves a body halted wherever it had drifted to (the train's lesson), and the wheel
## reset, because a RayWheel that keeps last frame's compression and spin across a teleport
## reports a suspension spike — which is this body's equivalent of the accel history BaseVehicle
## clears on the tractor. The trailer publishes no accel/impact of its own yet (its telemetry
## arrives with the Phase 5 bus); when it does, it is reset here beside the wheels.
func reset_at(pose: Transform3D) -> void:
	global_transform = pose
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	for w in wheels:
		w.reset()
	# The acceleration history goes with the velocity, for the same reason the base clears the
	# tractor's: a teleport differentiates into a colossal acceleration, and on this body that
	# would throw the tanker's load the length of the barrel on the frame after a respawn.
	accel_fwd = 0.0
	_last_fwd_speed = 0.0
	# The payload comes home too — a re-laid rig is a rig that has stood, and leaving a shifted
	# load behind would make respawn a way to keep weight where the driver never put it.
	set_load_offset_z(0.0)
	reset_body()
	reset_physics_interpolation()


## Which of the towing unit's connections this trailer plugs into — a bitwise OR of Consumer
## (subclass override). LOAD-BEARING, not documentation: SemiTractor gates real drive and real
## flow on it, so claiming a connection you do not have is a lie the machine will act on.
func consumers() -> int:
	return 0


## True when this trailer uses `c` (readability helper over the bitmask).
func uses(c: Consumer) -> bool:
	return (consumers() & int(c)) != 0


## PTO seam: `on` is the engaged state, `rpm` the shaft speed. A trailer that does not declare
## Consumer.PTO never sees drive here — SemiTractor gates it off at the coupling, so it reads a
## dead shaft rather than being trusted to ignore one. Override only to react to the change.
func set_pto(on: bool, rpm: int) -> void:
	pto_on = on
	pto_rpm = rpm


## Valve seam: `flow01` is the towing unit's proportional hydraulic opening, 0..1. Gated at the
## coupling exactly like the PTO — a trailer with no plumbing reads a shut valve however far the
## spool is opened, and the raise INTERLOCK is applied there too, never here.
func set_valve(flow01: float) -> void:
	valve_flow = flow01


## One tick of whatever body this trailer carries, called by tick_towed before the wheels
## integrate. Public rather than an underscore seam so the load models can be stepped in a test
## without a physics world, which is how the rest of this family's pure logic is asserted.
func tick_body(_delta: float) -> void:
	pass


## Put the body back in its parked pose (subclass override), called from reset_at.
func reset_body() -> void:
	pass


## How far this body's payload has slid BACK from the spec's authored centre of mass, 0..1 for a
## body position (subclass override). SemiTractor reads it to clamp the raise interlock without
## having to know what kind of body it is talking to.
func body_pos01() -> float:
	return 0.0


## Slide this trailer's centre of mass `offset_z` metres rearward of where the spec put it. THE
## ONE MECHANISM both load models use, and the reason neither of them is a fiction: gravity acts
## at the centre of mass, so moving it really does change what the bogie's springs hold up and
## what is left on the fifth wheel. trailer_axle_load, axle_load and the rig's pitch then follow
## from the sim rather than from a term added to any of them.
##
## Written only when it actually moves: `center_of_mass` is a physics-server property, and the
## slew settles at both ends of its travel.
func set_load_offset_z(offset_z: float) -> void:
	if spec == null or is_equal_approx(offset_z, _load_offset_z):
		return
	_load_offset_z = offset_z
	# The custom mode is what makes `center_of_mass` writable at all — _ready already sets it, but a
	# load model must not depend on having been readied first: RigidBody3D REJECTS the write in any
	# other mode with an engine error rather than a wrong number, so the failure is loud in a test
	# and silent nowhere.
	if center_of_mass_mode != RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = spec.center_of_mass + Vector3(0.0, 0.0, offset_z)


## Metres the payload is currently displaced rearward (negative = forward). 0 on a trailer whose
## load cannot move, which is three of the four.
func load_shift_z() -> float:
	return _load_offset_z


## IS THIS TRAILER'S BODY TOUCHING ANYTHING? The one question SemiTractor's fit check asks, and it
## is a good question precisely because the honest answer is almost always no: a semi-trailer stands
## on RayWheels, which are RAYCASTS rather than shapes, so its collision body has nothing to rest on
## and touches nothing in normal towing. The tractor does not count — the fifth-wheel joint excludes
## the pair, because the plate and this body's nose deliberately overlap while coupled.
##
## So a `true` here right after a coupling means the trailer was laid inside the world. No threshold,
## no penetration depth, no guess about what the engine would do: it has already done it.
func body_is_colliding() -> bool:
	return not get_colliding_bodies().is_empty()


## Every CollisionShape3D in this trailer as `{ "shape": Shape3D, "xf": Transform3D }`, the
## transform accumulated down to TRAILER space. Walked recursively and usable on a scene that is NOT
## in the tree.
##
## AUTHORING ACCESSOR: nothing at runtime reads this any more (the fit check above asks the physics
## engine instead of re-deriving the shapes). It stays because `test_trailer` uses it to assert that
## each trailer's authored collision clears the ground and does not reach forward into the tractor,
## which is a real invariant of the scenes and has nothing to do with how coupling works.
func collision_probes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_gather_probes(self, Transform3D.IDENTITY, out)
	return out


func _gather_probes(node: Node, xf: Transform3D, out: Array[Dictionary]) -> void:
	for child in node.get_children():
		var n3 := child as Node3D
		if n3 == null:
			continue
		var here := xf * n3.transform
		var col := n3 as CollisionShape3D
		if col != null and col.shape != null and not col.disabled:
			out.append({"shape": col.shape, "xf": here})
		_gather_probes(n3, here, out)


## THE BODY-RAISE INTERLOCK, and it belongs to the COUPLING rather than to any one trailer: every
## argument is TOWING-UNIT state and SemiTractor is what evaluates it, the same crossing
## RefuseBody.is_inhibited makes from the chassis to the body network. A trailer is never asked
## whether it may lift itself.
##
## Both conditions are real hardware practice: a tipping body goes up with the parking brake set
## and the rig stopped, because raising one on the move is how a trailer ends up on its side or
## through a bridge. Note it is STRICTER than the refuse arm's, which is allowed to work at
## walking pace — see RAISE_SPEED_MS.
static func body_raise_allowed(speed_ms: float, parking_brake: float) -> bool:
	return parking_brake >= RAISE_PARK_BRAKE_MIN and absf(speed_ms) <= RAISE_SPEED_MS


## Bogie centre, as a distance back from the kingpin (m) — MEASURED off the spec's own wheel
## anchors rather than restated as a constant, so a re-authored bogie cannot disagree with it.
func bogie_z() -> float:
	if spec.wheel_positions.is_empty():
		return 0.0
	var total := 0.0
	for p in spec.wheel_positions:
		total += p.z
	return total / float(spec.wheel_positions.size())


## STATIC share of this trailer's weight that rests on the fifth wheel (0..1) — the load the
## tractor's drive axle picks up when you couple, which is why axle_load rises the moment it does.
## Off the SPEC, so it is the parked figure both spring rates are sized from and it does not move
## when a load model does.
func kingpin_share() -> float:
	return Articulation.kingpin_share(spec.center_of_mass.z, bogie_z())


## The share RIGHT NOW, with whatever the load model has done to the centre of mass folded in.
## Tipping a body rearward drops it toward zero: the bogie takes the payload and the tractor's
## drive axle gives it back, which is the pair of consequences the tipper exists to show.
func live_kingpin_share() -> float:
	return Articulation.kingpin_share(spec.center_of_mass.z + _load_offset_z, bogie_z())


## Total suspension force the bogie is carrying this tick (N), straight off the wheels. This is
## what trailer_axle_load is read out of — a weight the springs were really holding, never a mass
## lookup — and it is also what the "does it sink" check measures.
func bogie_suspension_force() -> float:
	var total := 0.0
	for w in wheels:
		total += w.suspension_force
	return total


## Worst |longitudinal slip| across the bogie this tick — what trailer_abs (EBS21) is read out of.
## These wheels are undriven, so a slip here is only ever a wheel being braked toward a lock, and
## RayWheel already reports 0 for an airborne wheel. The MAX rather than a mean, because ABS is a
## per-wheel device: one locking wheel is the event.
func max_wheel_slip() -> float:
	var worst := 0.0
	for w in wheels:
		worst = maxf(worst, w.slip)
	return worst

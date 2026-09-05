class_name TowedBody
extends RigidBody3D
## A semi-trailer: a RigidBody3D on a joint carrying unmodified RayWheels, undriven and braked.
## Not a BaseVehicle and never registers with InputRouter; brake demand arrives as a number, and
## the tractor ticks it (SemiTractor._tick_extras) to fix integration order.
##
## Geometry: origin at the kingpin, ground at y = -1.05, trailer-space z is distance back from
## the kingpin, wheel anchors at negative y. `consumers()` is declared in code, never exported
## data, so a scene edit cannot claim a connection the machine lacks. Payload load models reach
## the world only through `set_load_offset_z`, so axle loads follow as consequences.

## What a towed body can plug into on the towing unit, gated by SemiTractor. No data-bus entry:
## ISO 11992 belongs to the towing unit's ISO 7638 connector (VehicleSpec.trailer_bus_equipped).
## Which trailer is on the back shows through mass and moved signals, never a trailer_type.
## NOT ImplementBase.Connection, whose bits deliberately differ (PTO is 1 here, 4 there) and whose
## PTO and SCV are a different shaft and different plumbing. The only fact stated in both is the
## hose (HYDRAULIC here <-> Connection.SCV there), on FarmTipper alone, pinned by
## test_drawbar_trailer. Never mask one enum's value against the other's uses().
enum Consumer {
	PTO = 1,        ## driven off the towing unit's chassis PTO (a tipper's hydraulic pump)
	HYDRAULIC = 2,  ## fed by a proportional hydraulic valve on the towing unit
}

## Road speed (m/s) below which a body raise is permitted: a genuine standstill, stricter than
## RefuseBody's walking-pace arm, because a raised body is several metres of leverage.
const Layers := preload("res://src/physics/collision_layers.gd")
const RAISE_SPEED_MS := 0.15
## Parking-brake application the raise interlock demands (RefuseBody.PARK_BRAKE_MIN's rule).
const RAISE_PARK_BRAKE_MIN := 0.5

## Contacts reported at once. `body_is_colliding` only checks emptiness, so one would do.
const MAX_CONTACTS_REPORTED := 4

## Scene node whose Node3D children are the wheel visuals, in the ground drive's wheel_positions
## order. A count mismatch is an authoring error and says so.
@export var wheel_root: NodePath = ^"Wheels"
@export var spec: VehicleSpec

var wheels: Array[RayWheel] = []

## The trailer's own lamps, resolved off its own spec and root, driven by the tractor off lamp
## bits already riding VehicleInput. No side channel, no local blink timer.
var _lamps := LampSet.new()

## PTO drive as the towing unit last handed it down; a trailer declaring no PTO reads a dead shaft.
var pto_on := false
var pto_rpm := 0
## Proportional valve opening as last handed down, 0..1. Gated at the coupling like the PTO.
var valve_flow := 0.0

## Longitudinal acceleration along this body's own forward axis (m/s^2, + = speeding up),
## differentiated from its velocity each tick. The tanker's surge model reads it.
var accel_fwd := 0.0

var _last_fwd_speed := 0.0
var _load_offset_z := 0.0  ## metres the payload has slid back from the spec's centre of mass


func _ready() -> void:
	# Same layer as the towing vehicle, and set above the spec guards below, which return early
	# even though a trailer with an authoring error still has to collide.
	collision_layer = Layers.VEHICLE
	collision_mask = Layers.WORLD
	# Everything below reads the spec, so say what is missing rather than null-deref two lines in.
	if spec == null:
		push_error("%s: no VehicleSpec — the trailer has no mass, wheels or brakes" % name)
		return
	if spec.ground_drive == null:
		push_error("%s: VehicleSpec declares no ground_drive — no wheels, suspension or brakes"
				% name)
		return
	mass = spec.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# Where it sits between kingpin and bogie is the load split (Articulation.kingpin_share).
	center_of_mass = spec.center_of_mass
	can_sleep = false
	# Not a BaseVehicle, so nothing else clears the per-mass `physics/3d/default_linear_damp`;
	# at 0.1 on 24 t it plateaus the semi at 32.7 km/h.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	# 14 t off a kerb can cross thin terrain collision in one tick.
	continuous_cd = true
	# What SemiTractor's fit check reads (body_is_colliding). Cheap: normally no contacts at all.
	contact_monitor = true
	max_contacts_reported = MAX_CONTACTS_REPORTED
	var visuals: Array[Node3D] = []
	var root := get_node_or_null(wheel_root)
	if root != null:
		for child in root.get_children():
			if child is Node3D:
				visuals.append(child as Node3D)
	var gd := spec.ground_drive
	if visuals.size() != gd.wheel_positions.size():
		push_error("%s: %d wheel visuals for %d spec wheel positions" % [
				name, visuals.size(), gd.wheel_positions.size()])
	# Static per-corner share of this trailer's own mass — see RayWheel.corner_mass.
	var corner_mass := spec.mass / maxf(1.0, gd.wheel_positions.size())
	for i in gd.wheel_positions.size():
		var visual: Node3D = visuals[i] if i < visuals.size() else null
		# Undriven and unsteered: a semi-trailer axle only ever brakes.
		wheels.append(RayWheel.new(gd.wheel_positions[i], false, false, visual, corner_mass))
	# LampSet tolerates every path missing, so a lampless trailer binds nothing and apply_lamps
	# is a no-op rather than a crash.
	_lamps.setup(self, spec)


## Mirror the rig's lamp state onto this trailer, called by the tractor. Not physics, so it runs
## even on a frozen showroom trailer. The contract has no trailer lamp signal: brake_lamp is one
## bit shown at both ends of the combination.
func apply_lamps(brake_on: bool, headlights: int, turn_left: bool, turn_right: bool) -> void:
	_lamps.apply(brake_on, headlights, turn_left, turn_right)


## One physics tick of the trailer's running gear. `brake01` and `handbrake01` are computed by
## the tractor and applied through RayWheel's own brake path. The parking brake is on every axle
## of the bogie, not a rear pair: the tractor's two driven wheels cannot hold 32 t on a grade.
func tick_towed(brake01: float, handbrake01: float, delta: float,
		grip_terrains: Array[Node]) -> void:
	# Empty means _ready found no spec, so roll along as dead weight rather than erroring at 60 Hz.
	if wheels.is_empty():
		return
	# Measured before the wheels integrate, so it is last tick's motion.
	if delta > 0.0:
		var fwd_speed := -global_transform.basis.z.dot(linear_velocity)
		accel_fwd = (fwd_speed - _last_fwd_speed) / delta
		_last_fwd_speed = fwd_speed
	# The body model runs before the wheels, so a load shift this tick is under the springs now.
	tick_body(delta)
	var space := get_world_3d().direct_space_state
	var gd := spec.ground_drive
	var brake_t := clampf(brake01, 0.0, 1.0) * gd.brake_torque \
			+ clampf(handbrake01, 0.0, 1.0) * gd.handbrake_torque
	for w in wheels:
		w.tick(self, gd, space, 0.0, brake_t, delta, grip_terrains)
	# Resistance is a sum, not a multiple: this trailer's own drag area plus its bogie load.
	apply_central_force(VehicleMath.road_resistance(linear_velocity, gd.drag_area,
			gd.rolling_resistance, bogie_suspension_force(), mass, delta))


## Re-lay the trailer at `pose`, stopped. Zeroing velocity alone leaves it wherever it drifted,
## and stale wheel compression or spin reads as a suspension spike.
func reset_at(pose: Transform3D) -> void:
	global_transform = pose
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	for w in wheels:
		w.reset()
	# A teleport differentiates into a colossal acceleration otherwise.
	accel_fwd = 0.0
	_last_fwd_speed = 0.0
	# Payload comes home too, or respawn becomes a way to keep weight the driver never put.
	set_load_offset_z(0.0)
	reset_body()
	reset_physics_interpolation()


## Which of the towing unit's connections this trailer plugs into, a bitwise OR of Consumer.
## SemiTractor gates real drive and flow on it.
func consumers() -> int:
	return 0


## True when this trailer uses `c`.
func uses(c: Consumer) -> bool:
	return (consumers() & int(c)) != 0


## PTO seam: `on` is engaged state, `rpm` the shaft speed. A trailer not declaring Consumer.PTO
## never sees drive, since SemiTractor gates it off at the coupling.
func set_pto(on: bool, rpm: int) -> void:
	pto_on = on
	pto_rpm = rpm


## Valve seam: `flow01` is the towing unit's proportional hydraulic opening, 0..1. The raise
## interlock is applied at the coupling, never here.
func set_valve(flow01: float) -> void:
	valve_flow = flow01


## One tick of whatever body this trailer carries, called by tick_towed before the wheels
## integrate. Public so a load model can be stepped in a test with no physics world.
func tick_body(_delta: float) -> void:
	pass


## Put the body back in its parked pose (subclass override), called from reset_at.
func reset_body() -> void:
	pass


## How far the payload has slid back from the spec's centre of mass, 0..1. SemiTractor reads it
## to clamp the raise interlock.
func body_pos01() -> float:
	return 0.0


## Slide this trailer's centre of mass `offset_z` metres rearward. The one mechanism both load
## models use: gravity acts at the centre of mass, so the springs really feel it.
func set_load_offset_z(offset_z: float) -> void:
	if spec == null or is_equal_approx(offset_z, _load_offset_z):
		return
	_load_offset_z = offset_z
	# A load model must not depend on _ready having run first; RigidBody3D rejects this write in
	# any other mode.
	if center_of_mass_mode != RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = spec.center_of_mass + Vector3(0.0, 0.0, offset_z)


## Metres the payload is displaced rearward (negative = forward), 0 where the load cannot move.
func load_shift_z() -> float:
	return _load_offset_z


## Is this trailer's body touching anything? It normally touches nothing (RayWheels are raycasts,
## the tractor is excluded by the joint), so `true` right after coupling means the trailer was
## laid inside the world.
func body_is_colliding() -> bool:
	return not get_colliding_bodies().is_empty()


## Every CollisionShape3D in this trailer as `{ "shape": Shape3D, "xf": Transform3D }`, transform
## accumulated to trailer space, usable on a scene not in the tree. An authoring accessor only;
## test_trailer is its consumer.
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


## The body-raise interlock. Every argument is towing-unit state, evaluated by SemiTractor: a
## trailer is never asked whether it may lift itself. Raising a tipping body on the move is how a
## trailer ends up on its side or through a bridge.
static func body_raise_allowed(speed_ms: float, parking_brake: float) -> bool:
	return parking_brake >= RAISE_PARK_BRAKE_MIN and absf(speed_ms) <= RAISE_SPEED_MS


## Bogie centre, distance back from the kingpin (m), measured off the spec's own wheel anchors.
func bogie_z() -> float:
	if spec.ground_drive.wheel_positions.is_empty():
		return 0.0
	var total := 0.0
	for p in spec.ground_drive.wheel_positions:
		total += p.z
	return total / float(spec.ground_drive.wheel_positions.size())


## Static share of this trailer's weight resting on the fifth wheel (0..1): the load the drive
## axle picks up on coupling. Read off the spec, so it is the parked figure the spring rates are
## sized from and does not move when a load model does.
func kingpin_share() -> float:
	return Articulation.kingpin_share(spec.center_of_mass.z, bogie_z())


## The share right now, with the load model's centre-of-mass shift folded in. Tipping a body
## rearward drops it toward zero: the bogie takes the payload back off the drive axle.
func live_kingpin_share() -> float:
	return Articulation.kingpin_share(spec.center_of_mass.z + _load_offset_z, bogie_z())


## Total suspension force the bogie carries this tick (N), straight off the wheels; this is what
## trailer_axle_load is read out of.
func bogie_suspension_force() -> float:
	var total := 0.0
	for w in wheels:
		total += w.suspension_force
	return total


## Worst |longitudinal slip| across the bogie this tick, which trailer_abs (EBS21) reads. These
## wheels are undriven, so slip only means braking toward a lock. Max, not mean: ABS is a
## per-wheel device, so one locking wheel is the event.
func max_wheel_slip() -> float:
	var worst := 0.0
	for w in wheels:
		worst = maxf(worst, w.slip)
	return worst

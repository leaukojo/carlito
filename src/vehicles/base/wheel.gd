class_name RayWheel
extends RefCounted
## One raycast-suspension wheel (one ray/wheel, slip-based grip).
##
## Ticked by BaseVehicle each physics frame: casts the suspension ray, applies
## spring/damper force plus longitudinal/lateral slip friction at the contact, and
## integrates wheel spin from drive/brake/road-reaction torque. Tuned for the locked
## 60 Hz tick — the guardrails below (damper clamp, force clamp, low-speed slip
## clamps) plus the semi-implicit spin step in _integrate_spin are what keep explicit
## integration stable there.
## DO NOT remove or weaken any clamp, and DO NOT raise the physics tick to "fix"
## instability — retune VehicleSpec values instead.
## Approach informed by Dechode/Godot-Advanced-Vehicle and
## Tobalation/GDCustomRaycastVehicle (both MIT, credited in README); no code copied.

## Slip-ratio denominator floor (m/s): keeps slip finite as speed -> 0.
const LOW_SPEED_FLOOR := 1.5

## How far above/below a terrain's surface a contact may sit and still pick up its painted
## grip (m). Generous enough for anything welded onto the ground — a conformed road's deck
## sits AT the flattened terrain height (the profile's skirt drops below it, never above) —
## and tight enough that a bridge, ramp or platform crossing over a painted patch keeps its
## own neutral grip instead of inheriting ice from the ground below.
const SURFACE_GRIP_REACH := 1.0

var anchor: Vector3     ## hub anchor, body space
var steered: bool
var driven: bool
var is_rear: bool

var steer_angle := 0.0  ## rad, set by BaseVehicle before tick
var lat_grip_scale := 1.0  ## rear side-grip cut while handbraking (spec.handbrake_grip)
var omega := 0.0        ## wheel spin, rad/s, + = rolling forward
var compression := 0.0
var in_contact := false
var suspension_force := 0.0
var slip := 0.0         ## |longitudinal slip ratio|, for telemetry
var contact_point := Vector3.ZERO  ## world-space hit position while in_contact (read by the dust emitter)
var surface_grip := 1.0  ## grip multiplier from the painted terrain under the contact (F3 readout)
## m the visual centre rides above the physics hub = visual radius - spec.wheel_radius. Keeps
## an over/undersized wheel VISUAL meeting the ground while physics stays single-radius. Lives
## on the root transform, not the visual's children — a child offset would orbit with the spin.
var visual_lift := 0.0

var _prev_compression := 0.0
var _spin_angle := 0.0
var _visual: Node3D


func _init(p_anchor: Vector3, p_steered: bool, p_driven: bool, p_visual: Node3D) -> void:
	anchor = p_anchor
	steered = p_steered
	driven = p_driven
	is_rear = p_anchor.z > 0.0
	_visual = p_visual


func reset() -> void:
	omega = 0.0
	compression = 0.0
	_prev_compression = 0.0
	in_contact = false
	suspension_force = 0.0
	slip = 0.0
	surface_grip = 1.0


## Which of the level's painted terrains `point` is ON, or null when none is. The lookup is
## collider-independent (XZ + height), so it also works where a wheel rests on a conformed road
## welded over the terrain — but it is NOT XZ alone: the point must be within SURFACE_GRIP_REACH
## of the terrain surface, else a bridge deck or ramp passing over a painted patch would inherit
## its paint. With several terrains in reach (a detail terrain inset in a big one) the NEAREST
## surface wins, not scene-tree order. Duck-typed (contains_xz/height_at) — no type dep.
##
## Lives here with the reach constant because the tire-grip query is what it exists for; the
## tractor's draft force asks the same question about the hitch point, and the rule is written
## down once.
static func terrain_at(point: Vector3, terrains: Array[Node]) -> Node:
	var found: Node = null
	var nearest := SURFACE_GRIP_REACH
	for terrain in terrains:
		if not is_instance_valid(terrain) or not terrain.contains_xz(point):
			continue
		var drop: float = absf(point.y - terrain.height_at(point))
		if drop < nearest:
			nearest = drop
			found = terrain
	return found


func tick(body: RigidBody3D, spec: VehicleSpec, space: PhysicsDirectSpaceState3D,
		drive_torque: float, brake_torque: float, delta: float,
		grip_terrains: Array[Node]) -> void:
	var xform := body.global_transform
	var up := xform.basis.y
	var ray_from := xform * anchor
	var ray_len := spec.rest_length + spec.wheel_radius
	var query := PhysicsRayQueryParameters3D.create(
			ray_from, ray_from - up * ray_len, 0xFFFFFFFF, [body.get_rid()])
	var hit := space.intersect_ray(query)

	in_contact = not hit.is_empty()
	if not in_contact:
		compression = 0.0
		_prev_compression = 0.0
		suspension_force = 0.0
		slip = 0.0
		surface_grip = 1.0
		# Airborne: no contact, so no road reaction and no contact slip — the spin step below
		# degenerates to the plain explicit one.
		_integrate_spin(drive_torque, 0.0, brake_torque, spec, delta, 0.0)
		_update_visual(spec, delta)
		return

	contact_point = hit.position
	var normal: Vector3 = hit.normal
	var corner_mass := spec.mass / maxf(1.0, spec.wheel_positions.size())

	# Painted-terrain grip under the contact: scales the tire mu below (see terrain_at for the
	# surface-reach rule). Unpainted, off-map or up on a deck above the ground = neutral 1.0.
	var terrain := terrain_at(contact_point, grip_terrains)
	surface_grip = terrain.grip_at(contact_point) if terrain != null else 1.0

	# Suspension: spring + damper along the body's up axis at the contact point.
	compression = clampf(ray_len - ray_from.distance_to(contact_point), 0.0, spec.rest_length)
	var comp_vel := (compression - _prev_compression) / delta
	_prev_compression = compression
	var damper := spec.damper_bump if comp_vel > 0.0 else spec.damper_rebound
	# 60 Hz guardrail: damping may never exceed the force that would reverse the
	# compression velocity within one tick.
	var damper_force := clampf(damper * comp_vel,
			-corner_mass * absf(comp_vel) / delta, corner_mass * absf(comp_vel) / delta)
	suspension_force = clampf(spec.spring_rate * compression + damper_force,
			0.0, spec.max_suspension_force)
	body.apply_force(up * suspension_force, contact_point - body.global_position)

	# Tire frame on the contact plane: forward = steered wheel forward, side completes it.
	var wheel_forward := (Basis(up, steer_angle) * -xform.basis.z)
	var forward := (wheel_forward - normal * wheel_forward.dot(normal)).normalized()
	var side := forward.cross(normal)

	var vel := body.linear_velocity \
			+ body.angular_velocity.cross(contact_point - body.global_position)
	var v_long := vel.dot(forward)
	var v_lat := vel.dot(side)

	# Effective tire coefficients: spec grip scaled by the painted-surface grip. Scaling mu
	# only shrinks force (always stabilizing) — the one-tick velocity clamps below cap by
	# momentum, independent of mu, so they stay fully in force.
	var mu_long := spec.mu_long * surface_grip
	var mu_lat := spec.mu_lat * lat_grip_scale * surface_grip

	# Longitudinal: slip ratio vs the grip curve, capped by the force that would
	# cancel the slip velocity in one tick (low-speed stability).
	var slip_vel := omega * spec.wheel_radius - v_long
	var slip_ratio := slip_vel / maxf(absf(v_long), LOW_SPEED_FLOOR)
	slip = absf(slip_ratio)
	var f_long := signf(slip_ratio) * mu_long * suspension_force \
			* VehicleSpec.sample_curve(spec.grip_curve, absf(slip_ratio))
	f_long = clampf(f_long,
			-corner_mass * absf(slip_vel) / delta, corner_mass * absf(slip_vel) / delta)

	# Lateral: slip angle vs the same curve, capped by the force that would zero
	# lateral velocity in one tick (kills parked-car jitter, the classic 60 Hz failure).
	var slip_angle := atan2(absf(v_lat), maxf(absf(v_long), LOW_SPEED_FLOOR))
	var f_lat := -signf(v_lat) * mu_lat * suspension_force \
			* VehicleSpec.sample_curve(spec.grip_curve, slip_angle)
	f_lat = clampf(f_lat,
			-corner_mass * absf(v_lat) / delta, corner_mass * absf(v_lat) / delta)

	# Friction circle: combined demand cannot exceed the grip budget.
	var budget_long := mu_long * suspension_force
	var budget_lat := mu_lat * suspension_force
	if budget_long > 0.0 and budget_lat > 0.0:
		var demand := sqrt(pow(f_long / budget_long, 2.0) + pow(f_lat / budget_lat, 2.0))
		if demand > 1.0:
			f_long /= demand
			f_lat /= demand

	body.apply_force(forward * f_long + side * f_lat, contact_point - body.global_position)

	_integrate_spin(drive_torque, -f_long * spec.wheel_radius, brake_torque, spec, delta, slip_vel)
	_update_visual(spec, delta)


## Wheel spin from drive + road-reaction torque; brakes decelerate toward zero and
## never reverse the spin (braking force on the body then emerges from negative slip).
##
## 60 Hz guardrail, SEMI-IMPLICIT: tire force is enormous next to the wheel's OWN inertia,
## so explicit integration of the road reaction over-corrects every tick and `omega` rings at
## the tick rate — invisible until something publishes it (`wheel_speed` / `wheel_slip`), then
## unmissable. The corner-mass clamp on `f_long` above sizes force for the BODY and is far too
## loose to settle the wheel.
##
## The fix is a damped (backward-Euler) step, NOT a clamp on the reaction. `reaction_stiffness`
## is the secant slope of the tire's reaction against contact slip, expressed as the ratio of
## one explicit tick's reaction to the reaction that would just null the slip; dividing the NET
## torque by (1 + that) is the linearized implicit update. Two properties matter:
##
##  - the divisor is >= 1, so this only ever SHRINKS a correction — no ringing, and it relaxes
##    to the plain explicit step as delta -> 0 (measured: matches a 480 Hz reference run);
##  - it divides the WHOLE net torque, so a wheel already in equilibrium (drive balancing
##    reaction) does not move. Clamping the reaction alone instead leaves `drive_torque -
##    max_reaction` pushing at equilibrium, which walks the wheel to a different steady slip
##    and hands the body traction the driveline never paid for — measured as +20 % top speed
##    on the car and +41 % on the tractor against the same reference. Don't go back to a clamp.
func _integrate_spin(drive_torque: float, reaction_torque: float, brake_torque: float,
		spec: VehicleSpec, delta: float, slip_vel: float) -> void:
	var null_slip_torque := spec.wheel_inertia * absf(slip_vel) / (delta * spec.wheel_radius)
	var reaction_stiffness := absf(reaction_torque) / maxf(null_slip_torque, 1e-6)
	omega += (drive_torque + reaction_torque) / (1.0 + reaction_stiffness) \
			/ spec.wheel_inertia * delta
	omega = move_toward(omega, 0.0, brake_torque / spec.wheel_inertia * delta)


func _update_visual(spec: VehicleSpec, delta: float) -> void:
	if _visual == null:
		return
	_spin_angle = wrapf(_spin_angle + omega * delta, -TAU, TAU)
	var center := anchor + Vector3.DOWN * (spec.rest_length - compression) \
			+ Vector3.UP * visual_lift
	_visual.transform = Transform3D(
			Basis(Vector3.UP, steer_angle) * Basis(Vector3.RIGHT, -_spin_angle)
			* Basis(Vector3.BACK, PI / 2.0),
			center)

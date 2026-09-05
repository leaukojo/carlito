class_name RayWheel
extends RefCounted
## One raycast-suspension wheel: one ray per wheel, slip-based grip. Ticked by WheelDrive each
## physics frame, casting the suspension ray, applying spring and damper force plus slip friction
## at the contact, and integrating spin from drive, brake and road-reaction torque.
##
## Tuned for the locked 60 Hz tick: the clamps below plus the semi-implicit spin step in
## _integrate_spin keep it stable. Do not remove or weaken a clamp or raise the tick to fix
## instability; retune GroundDriveSpec instead.

const Layers := preload("res://src/physics/collision_layers.gd")

## Slip-ratio denominator floor (m/s): keeps slip finite as speed -> 0.
const LOW_SPEED_FLOOR := 1.5

## How far above or below a terrain surface a contact may sit and still pick up its painted grip
## (m). Keeps a bridge or ramp over a painted patch from inheriting that grip.
const SURFACE_GRIP_REACH := 1.0

var anchor: Vector3     ## hub anchor, body space
var steered: bool
var driven: bool
var is_rear: bool

var steer_angle := 0.0  ## rad, set by WheelDrive before tick
var lat_grip_scale := 1.0  ## rear side-grip cut while handbraking (`handbrake_grip`)
var omega := 0.0        ## wheel spin, rad/s, + = rolling forward
var compression := 0.0
var in_contact := false
var suspension_force := 0.0
var slip := 0.0         ## |longitudinal slip ratio|, for telemetry
var force_long := 0.0   ## last tick's longitudinal tire force (N, +=forward); diagnostic only
var contact_point := Vector3.ZERO  ## world-space hit position while in_contact (read by the dust emitter)
var contact_normal := Vector3.UP  ## world-space contact normal while in_contact; diagnostic only
var surface_grip := 1.0  ## grip multiplier from the painted terrain under the contact (F3 readout)
## Visual radius minus wheel_radius, which keeps an over- or undersized wheel visual meeting the
## ground while physics stays single-radius. Rides the root transform, not the visual's children.
var visual_lift := 0.0
## Body mass share this corner carries (kg): `mass / wheel count`, a static build-time quantity
## that sizes the three 60 Hz clamps below. Constructor-required, since a wheel built with zero
## applies no damping or tire force and just slides.
var corner_mass: float

var _prev_compression := 0.0
var _spin_angle := 0.0
var _visual: Node3D
var _query := PhysicsRayQueryParameters3D.new()  ## built once, refilled per tick (hot allocation)
var _query_body := RID()  ## body `_query.exclude` was built for


func _init(p_anchor: Vector3, p_steered: bool, p_driven: bool, p_visual: Node3D,
		p_corner_mass: float) -> void:
	anchor = p_anchor
	steered = p_steered
	driven = p_driven
	is_rear = p_anchor.z > 0.0
	_visual = p_visual
	corner_mass = p_corner_mass
	_query.collision_mask = Layers.SOLID  ## Containment left out — see collision_layers.gd


func reset() -> void:
	omega = 0.0
	compression = 0.0
	_prev_compression = 0.0
	in_contact = false
	suspension_force = 0.0
	slip = 0.0
	surface_grip = 1.0


## Which of the level's painted terrains `point` is on, or null. XZ plus height, not XZ alone, so
## a road welded over terrain works but a bridge above a painted patch does not inherit it. The
## nearest surface wins when several are in reach. Duck-typed on contains_xz / height_at.
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


func tick(body: RigidBody3D, drive_spec: GroundDriveSpec, space: PhysicsDirectSpaceState3D,
		drive_torque: float, brake_torque: float, delta: float,
		grip_terrains: Array[Node]) -> void:
	var xform := body.global_transform
	var up := xform.basis.y
	var ray_from := xform * anchor
	var ray_len := drive_spec.rest_length + drive_spec.wheel_radius
	# Self-exclusion still needed: this body is on VEHICLE, which SOLID includes.
	if _query_body != body.get_rid():
		_query_body = body.get_rid()
		_query.exclude = [_query_body]
	_query.from = ray_from
	_query.to = ray_from - up * ray_len
	var hit := space.intersect_ray(_query)

	in_contact = not hit.is_empty()
	if not in_contact:
		compression = 0.0
		_prev_compression = 0.0
		suspension_force = 0.0
		slip = 0.0
		force_long = 0.0
		contact_normal = Vector3.UP
		surface_grip = 1.0
		_integrate_spin(drive_torque, 0.0, brake_torque, drive_spec, delta, 0.0)  ## airborne
		_update_visual(drive_spec, delta)
		return

	contact_point = hit.position
	var normal: Vector3 = hit.normal
	contact_normal = normal
	var terrain := terrain_at(contact_point, grip_terrains)
	surface_grip = terrain.grip_at(contact_point) if terrain != null else 1.0

	# Applied along the contact normal, never the chassis up axis, which tips part of the
	# vertical load into the direction of travel whenever the body pitches.
	compression = clampf(ray_len - ray_from.distance_to(contact_point), 0.0, drive_spec.rest_length)
	var comp_vel := (compression - _prev_compression) / delta
	_prev_compression = compression
	var damper := drive_spec.damper_bump if comp_vel > 0.0 else drive_spec.damper_rebound
	# 60 Hz clamp: never exceed the force that reverses compression velocity in one tick.
	var damper_force := clampf(damper * comp_vel,
			-corner_mass * absf(comp_vel) / delta, corner_mass * absf(comp_vel) / delta)
	suspension_force = clampf(drive_spec.spring_rate * compression + damper_force,
			0.0, drive_spec.max_suspension_force)
	body.apply_force(normal * suspension_force, contact_point - body.global_position)

	var wheel_forward := (Basis(up, steer_angle) * -xform.basis.z)
	var forward := (wheel_forward - normal * wheel_forward.dot(normal)).normalized()
	var side := forward.cross(normal)

	var vel := body.linear_velocity \
			+ body.angular_velocity.cross(contact_point - body.global_position)
	var v_long := vel.dot(forward)
	var v_lat := vel.dot(side)

	var mu_long := drive_spec.mu_long * surface_grip
	var mu_lat := drive_spec.mu_lat * lat_grip_scale * surface_grip

	# Capped by the force that would cancel slip velocity in one tick.
	var slip_vel := omega * drive_spec.wheel_radius - v_long
	var slip_ratio := slip_vel / maxf(absf(v_long), LOW_SPEED_FLOOR)
	slip = absf(slip_ratio)
	var f_long := signf(slip_ratio) * mu_long * suspension_force \
			* VehicleSpec.sample_curve(drive_spec.grip_curve, absf(slip_ratio))
	f_long = clampf(f_long,
			-corner_mass * absf(slip_vel) / delta, corner_mass * absf(slip_vel) / delta)

	# Capped by the force that would zero lateral velocity in one tick (kills parked-car jitter).
	var slip_angle := atan2(absf(v_lat), maxf(absf(v_long), LOW_SPEED_FLOOR))
	var f_lat := -signf(v_lat) * mu_lat * suspension_force \
			* VehicleSpec.sample_curve(drive_spec.grip_curve, slip_angle)
	f_lat = clampf(f_lat,
			-corner_mass * absf(v_lat) / delta, corner_mass * absf(v_lat) / delta)

	var budget_long := mu_long * suspension_force  ## friction circle: combined demand <= budget
	var budget_lat := mu_lat * suspension_force
	if budget_long > 0.0 and budget_lat > 0.0:
		var demand := sqrt(pow(f_long / budget_long, 2.0) + pow(f_lat / budget_lat, 2.0))
		if demand > 1.0:
			f_long /= demand
			f_lat /= demand

	body.apply_force(forward * f_long + side * f_lat, contact_point - body.global_position)
	force_long = f_long

	_integrate_spin(drive_torque, -f_long * drive_spec.wheel_radius, brake_torque, drive_spec,
			delta, slip_vel)
	_update_visual(drive_spec, delta)


## Wheel spin from drive plus road-reaction torque; brakes decelerate toward zero and never
## reverse it. Semi-implicit on purpose: tire force is huge next to the wheel's own inertia, so an
## explicit step over-corrects and `omega` rings at the tick rate. `reaction_stiffness` is the
## secant slope of tire reaction against contact slip, and dividing the net torque by (1 + that)
## is the linearized implicit update, a divisor >= 1 that only shrinks a correction and relaxes to
## the explicit step as delta -> 0. Clamping the reaction alone leaves the wheel pushing at
## equilibrium and walking to a steady slip the driveline never paid for (+20% top speed on the
## car, +41% on the tractor against a 480 Hz reference). Do not go back to a clamp.
func _integrate_spin(drive_torque: float, reaction_torque: float, brake_torque: float,
		drive_spec: GroundDriveSpec, delta: float, slip_vel: float) -> void:
	var null_slip_torque := drive_spec.wheel_inertia * absf(slip_vel) \
			/ (delta * drive_spec.wheel_radius)
	var reaction_stiffness := absf(reaction_torque) / maxf(null_slip_torque, 1e-6)
	omega += (drive_torque + reaction_torque) / (1.0 + reaction_stiffness) \
			/ drive_spec.wheel_inertia * delta
	omega = move_toward(omega, 0.0, brake_torque / drive_spec.wheel_inertia * delta)


func _update_visual(drive_spec: GroundDriveSpec, delta: float) -> void:
	if _visual == null:
		return
	_spin_angle = wrapf(_spin_angle + omega * delta, -TAU, TAU)
	var center := anchor + Vector3.DOWN * (drive_spec.rest_length - compression) \
			+ Vector3.UP * visual_lift
	_visual.transform = Transform3D(
			Basis(Vector3.UP, steer_angle) * Basis(Vector3.RIGHT, -_spin_angle)
			* Basis(Vector3.BACK, PI / 2.0),
			center)

class_name RayWheel
extends RefCounted
## One raycast-suspension wheel: one ray per wheel, slip-based grip. Ticked by WheelDrive each
## physics frame, casting the suspension ray, applying spring and damper force plus slip friction
## at the contact, and integrating spin from drive, brake and road-reaction torque.
##
## Tuned for the locked 60 Hz tick: the clamps below plus the semi-implicit spin step in
## _integrate_spin keep it stable (src/vehicles/CLAUDE.md § The 60 Hz tick). Retune
## GroundDriveSpec, never a clamp.

const Layers := preload("res://src/physics/collision_layers.gd")

## Slip-ratio denominator floor (m/s): keeps slip finite as speed -> 0.
const LOW_SPEED_FLOOR := 1.5

## How far above or below a terrain surface a contact may sit and still pick up its painted grip
## (m). Keeps a bridge or ramp over a painted patch from inheriting that grip.
const SURFACE_GRIP_REACH := 1.0

## Braking slip an anti-lock wheel holds at most (`GroundDriveSpec.abs_equipped`): the grip curve's
## peak, where the tyre brakes hardest; a locked wheel slides at the curve's tail, 0.8 of it. An
## honest model of an ideal ABS: it knows the true road speed and holds the slip without cycling.
## It buys steering too: a locked wheel's force opposes its whole slide (`combined_slip_force`).
const ABS_SLIP := 0.12

## Drive slip a traction-controlled wheel holds at most (`GroundDriveSpec.tcs_equipped`): ABS_SLIP's
## drive-side twin, the same peak. An ideal TC: it knows the true road speed, holds the slip without
## cycling, and only ever removes drive (`_integrate_spin`).
const TCS_SLIP := 0.12

## Rate (1/s) at which a wheel off the ground sheds spin to bearing, tyre and driveline losses (an
## honest model). Without it a lifted wheel has no resisting torque once the limiter cuts the
## throttle (`Drivetrain.overrun_torque` reads the still-down pedal), so `omega` freezes at the
## tripping value and the cut never clears. Well under a jump's air time, so landing spin-up is
## unaffected.
const FREE_SPIN_DECAY := 0.25

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
var abs_active := false ## the anti-lock held this wheel's brake back this tick
var tcs_active := false ## traction control held this wheel's drive back this tick
var force_long := 0.0   ## last tick's longitudinal tire force (N, +=forward); diagnostic only
var force_lat := 0.0    ## last tick's lateral tire force (N, post friction circle); diagnostic only
var contact_point := Vector3.ZERO  ## world-space hit position while in_contact (read by the dust emitter)
var contact_normal := Vector3.UP  ## world-space contact normal while in_contact; diagnostic only
var surface_grip := 1.0  ## grip multiplier from the painted terrain under the contact (F3 readout)
var surface_drag := 0.0  ## added rolling-resistance coefficient of the painted terrain under the contact (F3 readout)
## Spin change per N·m of extra torque in this tick's step, `delta / (I * (1 + reaction_stiffness))`
## (rad/s per N·m), latched by `_integrate_spin`. The step is linear in the applied torque, so a
## coupling torque `T` applied after it as `omega -= T * spin_compliance` equals adding `T` to
## `drive_torque` inside it: how `Differential` couples wheels. A gripping wheel is stiff (small), a
## spinning or airborne one soft (`delta / I`).
var spin_compliance := 0.0
## Visual radius minus wheel_radius, which keeps an over- or undersized wheel visual meeting the
## ground while physics stays single-radius. Rides the root transform, not the visual's children.
var visual_lift := 0.0
## The other wheel of this axle, paired by `pair_axles` when the spec asks for a bar; null means no
## bar on this body. The bar reads the snapshot `_bar_compression`, never the live `compression`,
## and the body's tick (`WheelDrive.tick`, `TowedBody.tick_towed`) latches it for EVERY wheel
## before any wheel ticks.
## Wheels tick in array order, so a latch inside `tick` gives the first wheel of a pair a partner
## value one tick staler than the second's: a phantom damper on the left wheels only
## (docs/vehicles.md has the figures).
var anti_roll_partner: RayWheel = null
## Body mass share this corner carries (kg): `mass / wheel count`, sizing the three 60 Hz clamps
## below. Constructor-required: a wheel built with zero applies no damping or tire force and just
## slides. It tracks the body's LIVE mass (every runtime `mass` write is `BaseVehicle.set_live_mass`).
## COMPROMISE: a semi tractor's kingpin load is NOT folded in (it rides the rear axle without
## touching `mass`), so this corner mass is understated there. That is the safe way round, since a
## clamp sized under the true load can only be tighter; widening it to chase the load undoes the
## stability (src/vehicles/truck/CLAUDE.md § Fifth wheel, mass, axle loads).
var corner_mass: float
## Tightens the one-tick lateral cap below `corner_mass` where the body's own tensor says the
## contact moves less mass sideways (`lateral_mass_at`); INF leaves `corner_mass` alone. Only
## `TowedBody` sizes it (see `TowedBody._size_lateral_caps`).
var lateral_cap_mass := INF
## This corner's spring and dampers, picked per axle from the spec by `apply_suspension`
## (`GroundDriveSpec.rear_spring_rate` and friends). Every builder calls it; a wheel left at 0
## carries nothing.
var spring_rate := 0.0
var damper_bump := 0.0
var damper_rebound := 0.0

var _prev_compression := 0.0
## The body's velocity at its centre of mass last tick, valid only while this wheel was on the
## ground: its change is the next step's predictor of how far the road moves under the wheel
## (`_integrate_spin`). The centre of mass, not the contact: the contact also carries the pitch the
## tyre's own force rocks in one tick, and following that rings the body at the tick rate.
var _prev_body_vel := Vector3.ZERO
var _prev_vel_valid := false
## Last tick's `compression`, latched by `latch_bar` for the whole body before any wheel ticks, so
## both wheels of an axle read the same snapshot. See `anti_roll_partner`.
var _bar_compression := 0.0
var _spin_angle := 0.0
var _visual: Node3D
var _query := PhysicsRayQueryParameters3D.new()  ## built once, refilled per tick (hot allocation)
var _query_body := RID()  ## body `_query.exclude` was built for


func _init(p_anchor: Vector3, p_steered: bool, p_driven: bool, p_visual: Node3D,
		p_corner_mass: float) -> void:
	anchor = p_anchor
	steered = p_steered
	driven = p_driven
	is_rear = is_rear_z(p_anchor.z)
	_visual = p_visual
	corner_mass = p_corner_mass
	_query.collision_mask = Layers.SOLID  ## Containment left out — see collision_layers.gd


## Pick this axle's spring and dampers off the spec: the rear accessors fall back to the front
## values at 0, so a spec with no rear fields is one rate for every corner.
func apply_suspension(gd: GroundDriveSpec) -> void:
	spring_rate = gd.rear_spring_rate() if is_rear else gd.spring_rate
	damper_bump = gd.rear_damper_bump() if is_rear else gd.damper_bump
	damper_rebound = gd.rear_damper_rebound() if is_rear else gd.damper_rebound


func reset() -> void:
	omega = 0.0
	compression = 0.0
	_prev_compression = 0.0
	_prev_vel_valid = false
	_bar_compression = 0.0
	in_contact = false
	suspension_force = 0.0
	slip = 0.0
	abs_active = false
	tcs_active = false
	force_long = 0.0
	force_lat = 0.0
	surface_grip = 1.0
	surface_drag = 0.0
	spin_compliance = 0.0


## The one front/rear predicate: +Z is rearward in body space, so a station at exactly z == 0 is
## FRONT. Every axle split goes through this so no station is front to one site and rear to
## another. No shipped spec has one (`test_vehicle_catalog` sweeps for it).
static func is_rear_z(z: float) -> bool:
	return z > 0.0


## Which of the level's painted terrains `point` is on, or null. XZ plus height within
## SURFACE_GRIP_REACH, so a bridge above a painted patch does not inherit it; the nearest surface
## wins. Duck-typed on contains_xz / height_at.
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


## `abs_slip` > 0 caps the brake at that braking slip (anti-lock); the owner passes 0 for a wheel a
## mechanical hold (handbrake, spring brakes) is on, which no ABS modulates. `tcs_slip` > 0 caps the
## drive at that drive slip (traction control), on the ground and off it.
func tick(body: RigidBody3D, drive_spec: GroundDriveSpec, space: PhysicsDirectSpaceState3D,
		drive_torque: float, brake_torque: float, delta: float,
		grip_terrains: Array[Node], abs_slip := 0.0, tcs_slip := 0.0) -> void:
	var xform := body.global_transform
	var up := xform.basis.y
	var ray_from := xform * anchor
	var ray_len := drive_spec.rest_length + drive_spec.wheel_radius
	# Self-exclusion: this body is on VEHICLE, which SOLID includes.
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
		_prev_vel_valid = false
		suspension_force = 0.0
		slip = 0.0
		abs_active = false
		force_long = 0.0
		force_lat = 0.0
		contact_normal = Vector3.UP
		surface_grip = 1.0
		surface_drag = 0.0
		# A TC compares wheel speed with vehicle speed and cannot see contact: off the ground it reads
		# the hub's own forward velocity.
		var hub_vel := body.linear_velocity \
				+ body.angular_velocity.cross(ray_from - body.global_position)
		var hub_v_long := hub_vel.dot(Basis(up, steer_angle) * -xform.basis.z)
		_integrate_spin(drive_torque, 0.0, brake_torque, drive_spec, delta, 0.0,  ## airborne
				hub_v_long, 0.0, 0.0, tcs_slip)
		omega = free_spin_omega(omega, delta)
		_update_visual(drive_spec, delta)
		return

	contact_point = hit.position
	var normal: Vector3 = hit.normal
	contact_normal = normal
	var terrain := terrain_at(contact_point, grip_terrains)
	surface_grip = terrain.grip_at(contact_point) if terrain != null else 1.0
	surface_drag = terrain.drag_at(contact_point) if terrain != null else 0.0

	# Along the contact normal, never the chassis up axis, which would push a pitched body along.
	compression = clampf(ray_len - ray_from.distance_to(contact_point), 0.0, drive_spec.rest_length)
	var comp_vel := (compression - _prev_compression) / delta
	_prev_compression = compression
	var damper := damper_bump if comp_vel > 0.0 else damper_rebound
	# 60 Hz clamp: never exceed the force that reverses compression velocity in one tick.
	var damper_force := clampf(damper * comp_vel,
			-corner_mass * absf(comp_vel) / delta, corner_mass * absf(comp_vel) / delta)
	# The bar sits inside the same force cap as spring and damper.
	suspension_force = clampf(spring_rate * compression + damper_force
			+ bar_force(drive_spec.anti_roll_rate),
			0.0, drive_spec.max_suspension_force)
	body.apply_force(normal * suspension_force, contact_point - body.global_position)

	var wheel_forward := (Basis(up, steer_angle) * -xform.basis.z)
	var forward := (wheel_forward - normal * wheel_forward.dot(normal)).normalized()
	var side := forward.cross(normal)

	var vel := body.linear_velocity \
			+ body.angular_velocity.cross(contact_point - body.global_position)
	var v_long := vel.dot(forward)
	var v_lat := vel.dot(side)

	# Load-scaled BEFORE the tyre force below: its friction ellipse is drawn on this tick's budget.
	var ref_load := corner_mass * 9.81
	var mu_long := load_scaled_mu(drive_spec.mu_long * surface_grip,
			suspension_force, ref_load, drive_spec.load_sensitivity)
	var mu_lat := load_scaled_mu(drive_spec.mu_lat * lat_grip_scale * surface_grip,
			suspension_force, ref_load, drive_spec.load_sensitivity)

	# Both slips on one denominator, so the slip vector points along the patch's slide.
	var slip_denom := maxf(absf(v_long), LOW_SPEED_FLOOR)
	var slip_vel := omega * drive_spec.wheel_radius - v_long
	var slip_ratio := slip_vel / slip_denom
	slip = absf(slip_ratio)
	var tyre := combined_slip_force(slip_ratio, -v_lat / slip_denom,
			mu_long * suspension_force, mu_lat * suspension_force, drive_spec.grip_curve)

	# Each axis capped by the force that would cancel its slip velocity in one tick (the lateral cap
	# kills parked-car jitter).
	var f_long := clampf(tyre.x,
			-corner_mass * absf(slip_vel) / delta, corner_mass * absf(slip_vel) / delta)
	var lat_mass := minf(corner_mass, lateral_cap_mass)
	var f_lat := clampf(tyre.y, -lat_mass * absf(v_lat) / delta, lat_mass * absf(v_lat) / delta)

	body.apply_force(forward * f_long + side * f_lat, contact_point - body.global_position)
	force_long = f_long
	force_lat = f_lat

	# Surface drag is the ground deforming, not the tyre: outside the friction circle and the spin
	# step (a wheel in mud keeps rolling at road speed; the body slows).
	body.apply_force(forward * surface_drag_force(v_long, surface_drag, suspension_force,
			corner_mass, delta), contact_point - body.global_position)

	# Faded out from twice the slip floor down to it: below the floor slip is read against the floor,
	# the tyre's slope sits at the one-tick cap, and following the body rings it at the tick rate.
	var dv_long := (body.linear_velocity - _prev_body_vel).dot(forward) if _prev_vel_valid else 0.0
	dv_long *= clampf(absf(v_long) / LOW_SPEED_FLOOR - 1.0, 0.0, 1.0)
	_prev_body_vel = body.linear_velocity
	_prev_vel_valid = true
	_integrate_spin(drive_torque, -f_long * drive_spec.wheel_radius, brake_torque, drive_spec,
			delta, slip_vel, v_long, abs_slip, dv_long, tcs_slip)
	_update_visual(drive_spec, delta)


## Pair each wheel with the one across its axle (same z, opposite side) for the anti-roll bar. Every
## body with a bar builds its pairs here: the chassis (`WheelDrive`) and the towed bogie
## (`TowedBody`), whose three axles each get their own.
static func pair_axles(wheels: Array[RayWheel]) -> void:
	for w in wheels:
		for other in wheels:
			if other != w and is_equal_approx(other.anchor.z, w.anchor.z) \
					and signf(other.anchor.x) != signf(w.anchor.x):
				w.anti_roll_partner = other
				break


## Snapshot this wheel's compression for the anti-roll bar. The body's tick calls it on every
## wheel BEFORE any of them ticks (see `anti_roll_partner`).
func latch_bar() -> void:
	_bar_compression = compression


## This wheel's anti-roll bar force off the shared snapshot (N, + = pushes this corner up): equal
## and opposite to the partner's while both snapshots come from the same latch. 0 with no bar, or
## while the partner is airborne, where its zero compression would read as full droop and shove
## this corner up on a bar that is really just hanging.
func bar_force(rate: float) -> float:
	if anti_roll_partner == null or not anti_roll_partner.in_contact:
		return 0.0
	return VehicleMath.anti_roll_force(_bar_compression, anti_roll_partner._bar_compression, rate)


## Effective mass (kg) a force along body +X meets at body-space `arm` from the centre of mass:
## `1 / (1/m + (arm x X) . I^-1 (arm x X))`, the body's own mass plus the roll and yaw the lever
## adds. `inv_inertia` is the solver's inverse tensor in body axes. A free-body figure, so a joint
## on the body can only raise the real one. 0 for a massless body.
static func lateral_mass_at(arm: Vector3, body_mass: float, inv_inertia: Basis) -> float:
	if body_mass <= 0.0:
		return 0.0
	var lever := arm.cross(Vector3.RIGHT)
	return 1.0 / (1.0 / body_mass + lever.dot(inv_inertia * lever))


## Tyre mu at a load off the corner's static reference: `mu * (1 - sensitivity * log2(load / ref))`,
## so grip grows SLOWER than load above the reference. Identity at the reference and at
## sensitivity 0, so every brake number derived at the even static load (`_derive_brakes` in
## tools/gen_kenney_vehicles.gd, `test_vehicle_catalog`) holds. Capacity `mu(L) * L` still RISES
## with load; what a heavier wheel loses is its share per newton, which lets transfer move the
## balance. The [0.5, 1.25] clamp and the ref*0.25 load floor bind on nothing shipped (0.12 at the
## floor reaches 1.24); they bound a suspension spike or a runtime mass rewrite.
static func load_scaled_mu(mu: float, normal_load: float, ref_load: float,
		sensitivity: float) -> float:
	if sensitivity <= 0.0 or ref_load <= 0.0 or mu <= 0.0:
		return mu
	var ratio := maxf(normal_load, ref_load * 0.25) / ref_load
	return clampf(mu * (1.0 - sensitivity * log(ratio) / log(2.0)), mu * 0.5, mu * 1.25)


## Tyre force (N; x along the wheel's forward, y along its side) for the slip vector
## (`slip_long`, `slip_lat`), both slips over one speed denominator so the vector points along the
## contact patch's slide. The grip curve reads its LENGTH and the force points along it, scaled per
## axis by the budgets (`mu * N`), so it never leaves their ellipse. A locked wheel's slip is almost
## all longitudinal: its force opposes the slide and it stops steering. On the curve's linear rise
## each axis is exactly what it would be alone.
static func combined_slip_force(slip_long: float, slip_lat: float, budget_long: float,
		budget_lat: float, grip_curve: PackedVector2Array) -> Vector2:
	var s := Vector2(slip_long, slip_lat).length()
	if s <= 0.0:
		return Vector2.ZERO
	var grip := minf(VehicleSpec.sample_curve(grip_curve, s), 1.0) / s
	return Vector2(budget_long * slip_long * grip, budget_lat * slip_lat * grip)


## Spin a wheel off the ground keeps after one tick of `FREE_SPIN_DECAY` (rad/s): exponential
## toward zero, never reversing it. The one torque on a wheel out of contact.
static func free_spin_omega(omega_in: float, delta: float) -> float:
	return move_toward(omega_in, 0.0, absf(omega_in) * FREE_SPIN_DECAY * delta)


## Rolling-resistance force (N, along the wheel's forward) from a painted surface: `crr * load`
## opposing the contact's longitudinal velocity, capped at the force that would zero that
## velocity in one tick so it can stop the wheel and never push it backward. 0 at rest.
static func surface_drag_force(v_long: float, crr: float, normal_load: float, moment: float,
		delta: float) -> float:
	if crr <= 0.0 or normal_load <= 0.0:
		return 0.0
	var tick_cap := moment * absf(v_long) / delta
	return clampf(-signf(v_long) * crr * normal_load, -tick_cap, tick_cap)


## Wheel spin from drive plus road-reaction torque; brakes decelerate toward zero and never
## reverse it. Semi-implicit on purpose: tire force is huge next to the wheel's own inertia, so an
## explicit step makes `omega` ring at the tick rate. `reaction_stiffness` is the secant slope of
## tire reaction against contact slip; dividing the net torque by (1 + that) is the linearized
## implicit update (divisor >= 1, so it only shrinks a correction). Clamping the reaction instead
## leaves a steady slip the driveline never paid for (figures: docs/vehicles.md).
## The brake goes through the same step (`* spin_compliance`), only clamped at zero spin. Taken
## outside it, a held brake needs the tyre to carry `1 + reaction_stiffness` times its torque
## (figures: docs/vehicles.md). `abs_slip` > 0 then caps what the brake takes off at the spin
## that braking slip leaves (`abs_spin_room`), against the contact's `v_long` at the tick's end.
## The step solves for SLIP, not spin: `dv_long`, the road's change under the wheel over the tick
## (the body's last one, as the predictor), is followed in proportion to the grip (`k / (1 + k)`),
## and only the rest pays the divisor. Solved for spin alone, every tick the body accelerates costs
## the wheel `I * a * k / r` it never needed: ~12 % of a full brake mid-stop, 6-9 % on a launch.
## This lands within ~3 % of a 480 Hz reference (figures: docs/vehicles.md).
## `tcs_slip` > 0 then takes back the drive's own share of the step (`drive_torque *
## spin_compliance`) as far as the drive slip passes `tcs_slip` (`tcs_spin_room`), against the same
## end-of-tick road speed as ABS, and never more than that share: TC removes drive, never brakes. A
## negative drive (engine overrun) is held the same way on its own side.
func _integrate_spin(drive_torque: float, reaction_torque: float, brake_torque: float,
		drive_spec: GroundDriveSpec, delta: float, slip_vel: float, v_long := 0.0,
		abs_slip := 0.0, dv_long := 0.0, tcs_slip := 0.0) -> void:
	var null_slip_torque := drive_spec.wheel_inertia * absf(slip_vel) \
			/ (delta * drive_spec.wheel_radius)
	var reaction_stiffness := absf(reaction_torque) / maxf(null_slip_torque, 1e-6)
	spin_compliance = delta / (drive_spec.wheel_inertia * (1.0 + reaction_stiffness))
	omega += (drive_torque + reaction_torque) / (1.0 + reaction_stiffness) \
			/ drive_spec.wheel_inertia * delta \
			+ dv_long / drive_spec.wheel_radius * reaction_stiffness / (1.0 + reaction_stiffness)
	tcs_active = false
	if tcs_slip > 0.0 and drive_torque != 0.0:
		# COMPROMISE: the cap is per wheel. On an open diff it neither cuts the gripping wheel (an
		# engine-side TC would) nor sends the cut across (a brake-based TC would). A biasing diff
		# couples after this step and can lift a capped wheel past the peak for a tick, the same
		# order the ABS cap has. Exact needs the cap solved jointly with `Differential`.
		var dir := signf(drive_torque)
		var share := absf(drive_torque) * spin_compliance
		var room := tcs_spin_room(omega * dir - share, (v_long + dv_long) * dir,
				drive_spec.wheel_radius, tcs_slip)
		if share > room:
			omega -= dir * (share - room)
			tcs_active = true
	# What the brake alone takes off: never more than stops the wheel.
	var take := minf(brake_torque * spin_compliance, absf(omega))
	abs_active = false
	if abs_slip > 0.0 and take > 0.0:
		var room := abs_spin_room(omega, v_long + dv_long, drive_spec.wheel_radius, abs_slip)
		if take > room:
			take = room
			abs_active = true
	omega = move_toward(omega, 0.0, take)


## Spin (rad/s) a brake may still take off this wheel before its braking slip passes `abs_slip`,
## on RayWheel's own slip denominator (LOW_SPEED_FLOOR). Unlimited (all of `|spin|`) when the
## wheel already turns against the contact's travel, and near a standstill, where the floor lets
## it stop: a stopped vehicle must still be held.
static func abs_spin_room(spin: float, v_long: float, radius: float, abs_slip: float) -> float:
	if radius <= 0.0 or signf(spin) != signf(v_long):
		return absf(spin)
	var denom := maxf(absf(v_long), LOW_SPEED_FLOOR)
	var floor_spin := maxf(absf(v_long) - abs_slip * denom, 0.0) / radius
	return maxf(absf(spin) - floor_spin, 0.0)


## Spin (rad/s) the drive may still add to this wheel before its drive slip passes `tcs_slip`: the
## mirror of `abs_spin_room` on the same LOW_SPEED_FLOOR denominator. `spin` and `v_long` are signed
## along the drive (the caller multiplies both by the drive torque's sign), so reverse mirrors
## forward. A wheel turning slower than the road, or against the drive, has all the way back to the
## road speed plus the peak to spin up through.
static func tcs_spin_room(spin: float, v_long: float, radius: float, tcs_slip: float) -> float:
	if radius <= 0.0:
		return INF
	var ceiling := (v_long + tcs_slip * maxf(absf(v_long), LOW_SPEED_FLOOR)) / radius
	return maxf(ceiling - spin, 0.0)


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

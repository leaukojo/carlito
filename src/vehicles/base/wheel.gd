class_name RayWheel
extends RefCounted
## One cast-suspension wheel: the tyre's cylinder swept down its travel, slip-based grip. Ticked by
## WheelDrive each physics frame, casting the tyre, applying spring and damper force plus slip
## friction at the contact, and integrating spin from drive, brake and road-reaction torque.
##
## Tuned for the locked 60 Hz tick: the clamps below plus the semi-implicit spin step in
## _integrate_spin keep it stable (src/vehicles/CLAUDE.md § Physics). Retune
## GroundDriveSpec, never a clamp.

const Layers := preload("res://src/physics/collision_layers.gd")

## Slip-ratio denominator floor (m/s): keeps slip finite as speed -> 0. The least of a wheel's
## `slip_floor`.
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
## cycling, and only ever removes drive (`tcs_take`).
const TCS_SLIP := 0.12

## Rate (1/s) at which a wheel off the ground sheds spin to bearing, tyre and driveline losses (an
## honest model): what stops a lifted undriven wheel, or one in N. A driven wheel in gear turns
## with the crank through its coupling (`Drivetrain.couple`), so it never passes the limiter (the
## crank lands on the redline) and the engine's own overrun slows it. Well under a jump's air
## time, so landing spin-up is unaffected.
const FREE_SPIN_DECAY := 0.25

## Static friction (`stick_step`, `stick_stiffness`, `stick_saturate`): the contact patch's deflection (m) at which its
## spring carries the whole friction budget. ~2 cm puts a car corner near 175 kN/m, a real tyre's
## order. The slip force alone is viscous below LOW_SPEED_FLOOR (zero force at zero slide), so a
## held wheel would creep down any grade; this spring is what holds it.
const STICK_DEFLECTION := 0.02
## Ground speed (m/s) below which the patch spring fades in, full at rest. Above it the slip force
## is the whole tyre, so driving, braking and cornering figures never see the spring.
const STICK_SPEED := 0.5
## Relaxation length (m): a rolling patch takes in fresh, undeflected tread, so its deflection
## decays per metre rolled. Set so the rolling spring's steady force equals the grip curve's linear
## rise (budget / ABS_SLIP per unit slip), so blending the two leaves no step.
const STICK_RELAX := STICK_DEFLECTION / ABS_SLIP
## 60 Hz clamp on the patch spring: stiffness never above this fraction of `mass / delta^2`
## (omega * dt <= 0.5), so the spring cannot ring at the tick rate on the mass it moves.
const STICK_TICK_STIFFNESS := 0.25

## Contact casts that started inside something, read as full bump (`_contact_query`), process-wide:
## a diagnostic the measure tools read (an attachment under a hub shows here).
static var start_overlaps := 0

var anchor: Vector3     ## hub anchor, body space
var steered: bool
var driven: bool
var is_rear: bool

var steer_angle := 0.0  ## rad, set by WheelDrive before tick
var omega := 0.0        ## wheel spin, rad/s, + = rolling forward
var compression := 0.0
var in_contact := false
var suspension_force := 0.0
var slip := 0.0         ## |longitudinal slip ratio|, for telemetry
var long_slip := 0.0    ## signed longitudinal slip ratio this tick (+ = wheel faster than the road)
var abs_active := false ## the anti-lock held this wheel's brake back this tick
var tcs_active := false ## traction control held this wheel's drive back this tick
var force_long := 0.0   ## last tick's longitudinal tire force (N, +=forward); the next tick's link force reads it (`link_slope`)
var force_lat := 0.0    ## last tick's lateral tire force (N, post friction circle); diagnostic only
var long_cap := 0.0     ## last tick's one-tick cap on the longitudinal slip force (N); diagnostic only
## The body's slip-denominator floor (m/s): the highest of its wheels' own (`slip_floor_for`) last
## tick, shared by `size_cap_masses`. A slip ratio's denominator is the road speed, one per body:
## each wheel's own floor would put its grip peak at its own slip velocity, and a driveline that
## turns the wheels together (a centre diff, a TC on the light axle) would hold the heavy ones under
## theirs. A wheel reads at least its own floor this tick.
var slip_floor := LOW_SPEED_FLOOR
var _own_slip_floor := LOW_SPEED_FLOOR
var contact_point := Vector3.ZERO  ## world-space patch, under the hub (`patch_offset`), while in_contact
var contact_normal := Vector3.UP  ## world-space contact normal while in_contact (the hill hold's grade)
var surface_grip := 1.0  ## grip multiplier from the painted terrain under the contact (F3 readout)
var surface_drag := 0.0  ## added rolling-resistance coefficient of the painted terrain under the contact (F3 readout)
## Spin change per N·m of extra torque in this tick's step, `delta / (I * (1 + reaction_stiffness))`
## (rad/s per N·m), latched by `_integrate_spin`. The step is linear in the applied torque, so a
## coupling torque `T` applied after it as `omega -= T * spin_compliance` equals adding `T` to
## `drive_torque` inside it: how `Differential` couples wheels. A gripping wheel is stiff (small), a
## spinning or airborne one soft (`delta / I`).
var spin_compliance := 0.0
## This tick's brake, latched by `_integrate_spin` and applied by `settle_spin`: the spin (rad/s) it
## can take off (`brake_torque * spin_compliance`), and the signed spin ABS stops it at
## (`abs_floor_spin`; 0 = no floor, the brake may stop the wheel).
var brake_spin := 0.0
var abs_floor := 0.0
## This tick's traction-control hold, latched by `_integrate_spin` and applied by `settle_spin`
## before the brake: the drive's own share of the step (`drive_torque * spin_compliance`, rad/s,
## signed with the drive; 0 = no hold), the most it takes back, and the signed spin it holds the
## drive at (`tcs_ceiling_spin`; under overrun, the mirrored floor).
var tcs_spin := 0.0
var tcs_ceiling := 0.0
## The owner settles this wheel's spin in its differential solve (`WheelDrive._couple_differentials`
## calls `settle_spin` with the coupling torque), so the brake is solved with the diffs; false
## settles the brake alone at the end of the step (a trailer's wheels).
var coupled_spin := false
## Torque (N·m, + = with forward drive) the differentials passed this wheel at its last settle; the
## brake holds it as it holds the drive (`held_force_range`). 0 on a wheel nothing couples.
var coupled_torque := 0.0
## The park lock's rating (N·m) at this wheel this tick, set by the owner before `tick`
## (`WheelDrive.pawl_torque`; 0 = no lock): the case holds the wheel through the diffs, so a wheel
## the lock stopped (`hold_by_lock`) is held like a braked one, to that rating beyond the brake.
var lock_torque := 0.0
## The other wheel of this axle, paired by `pair_axles` when the spec asks for a bar; null means no
## bar on this body. The bar reads the snapshot `_bar_compression`, never the live `compression`,
## and the body's tick (`WheelDrive.tick`, `TowedBody.tick_towed`) latches it for EVERY wheel
## before any wheel ticks.
## Wheels tick in array order, so a latch inside `tick` gives the first wheel of a pair a partner
## value one tick staler than the second's: a phantom damper on the left wheels only
## (docs/vehicles.md has the figures).
## Held weakly: the pair refer to each other, and a RefCounted cycle is never freed (every spawn
## would leak its wheels). The owner's `wheels` array keeps both alive.
var anti_roll_partner: RayWheel:
	get:
		return _partner_ref.get_ref() as RayWheel if _partner_ref != null else null
	set(value):
		_partner_ref = weakref(value) if value != null else null
var _partner_ref: WeakRef = null
## Body mass share this corner carries (kg): `mass / wheel count`, sizing the three 60 Hz clamps
## below. Constructor-required: a wheel built with zero applies no damping or tire force and just
## slides. It tracks the body's LIVE mass (every runtime `mass` write is `BaseVehicle.set_live_mass`).
## COMPROMISE: a semi tractor's kingpin load is NOT folded in (it rides the rear axle without
## touching `mass`), so this corner mass is understated there. That is the safe way round, since a
## clamp sized under the true load can only be tighter; widening it to chase the load undoes the
## stability (src/vehicles/truck/CLAUDE.md).
var corner_mass: float
## Tighten the one-tick caps and the patch spring below `corner_mass` where the body's own tensor
## says the contacts move less mass, across the wheel (roll, yaw) and along it (pitch, yaw):
## `size_cap_masses`, every tick; INF leaves `corner_mass` alone. The patch velocity is read about
## the COM, which rides 0.7-1.7 m over the contacts, so `corner_mass` alone overruns the tick and
## the patch rings (a crawl reads slip 0.15 at a standstill; a parked rig winds its side spring up
## and slides off the hand brake). The long one also sizes the slip floor (`slip_floor_for`), so
## the cap it sets never cuts the grip curve.
var lateral_cap_mass := INF
var long_cap_mass := INF
## This corner's spring and dampers, picked per axle from the spec by `apply_suspension`
## (`GroundDriveSpec.rear_spring_rate` and friends). Every builder calls it; a wheel left at 0
## carries nothing.
var spring_rate := 0.0
var damper_bump := 0.0
var damper_rebound := 0.0
## This axle's anti-roll bar rate (`GroundDriveSpec.rear_anti_roll_rate` at the rear).
var bar_rate := 0.0
## This axle's link geometry, signed so `link_slope * force_long` is the link force along the
## contact normal: `GroundDriveSpec.anti_squat_slope` at the rear, `-anti_dive_slope` at the front.
var link_slope := 0.0
## This axle's side-grip multiple on `mu_lat`: `GroundDriveSpec.rear_lat_grip` at the rear, 1 at
## the front.
var axle_lat_grip := 1.0
## The share of this corner's load one of its tyres carries, which the side grip and the
## cornering-stiffness law read: 0.5 on a twin rear (`GroundDriveSpec.rear_twin_tyres`), else 1.
var tyre_share := 1.0
## This wheel's physics radius (m) and spin inertia (kg*m^2), picked per axle by `apply_suspension`
## (`GroundDriveSpec.axle_radius`, `axle_inertia`).
var wheel_radius := 0.0
var wheel_inertia := 0.0
## This axle's tread half-width (m), `GroundDriveSpec.axle_half_width`: the contact cylinder's.
var half_width := 0.0

var _prev_compression := 0.0
## Contact-patch deflection (m; x along the wheel's forward, y along its side), the static-friction
## spring's state: grows with the patch's slide, decays as it rolls, 0 above STICK_SPEED.
var _stick := Vector2.ZERO
## The brake held this wheel at zero spin at its last settle, the differentials' torque included:
## only then does the patch spring act along the wheel. A free wheel's spin carries a few kg of
## equivalent mass, which a spring would ring at 60 Hz; and an unbraked wheel should roll down a
## grade.
var _spin_held := false
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
## The contact cast, built by `apply_suspension` off this axle's radius and width, refilled per tick
## (hot allocation). Null until then.
var _query: PhysicsShapeQueryParameters3D = null
var _query_body := RID()  ## body `_query.exclude` was built for
## `_contact_query`'s result: the hub's drop below the anchor (m) and the contact normal.
var _contact_drop := 0.0
var _contact_normal := Vector3.UP


func _init(p_anchor: Vector3, p_steered: bool, p_driven: bool, p_visual: Node3D,
		p_corner_mass: float) -> void:
	anchor = p_anchor
	steered = p_steered
	driven = p_driven
	is_rear = is_rear_z(p_anchor.z)
	_visual = p_visual
	corner_mass = p_corner_mass


## Pick this axle's spring, dampers, links, side grip, radius and inertia off the spec, and build
## the contact cylinder: the rear accessors fall back to the front values at 0, so a spec with no
## rear fields is one rate for every corner.
func apply_suspension(gd: GroundDriveSpec) -> void:
	spring_rate = gd.rear_spring_rate() if is_rear else gd.spring_rate
	damper_bump = gd.rear_damper_bump() if is_rear else gd.damper_bump
	damper_rebound = gd.rear_damper_rebound() if is_rear else gd.damper_rebound
	bar_rate = gd.rear_anti_roll_rate() if is_rear else gd.anti_roll_rate
	link_slope = gd.anti_squat_slope if is_rear else -gd.anti_dive_slope
	axle_lat_grip = gd.rear_lat_grip if is_rear else 1.0
	tyre_share = 0.5 if is_rear and gd.rear_twin_tyres else 1.0
	wheel_radius = gd.axle_radius(is_rear)
	wheel_inertia = gd.axle_inertia(is_rear)
	half_width = gd.axle_half_width(is_rear)
	_query = null
	if half_width > 0.0 and wheel_radius > 0.0:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = wheel_radius
		cylinder.height = 2.0 * half_width
		_query = PhysicsShapeQueryParameters3D.new()
		_query.shape = cylinder
		_query.collision_mask = Layers.SOLID  ## Containment left out — see collision_layers.gd
		_query_body = RID()


func reset() -> void:
	omega = 0.0
	compression = 0.0
	_prev_compression = 0.0
	_prev_vel_valid = false
	_own_slip_floor = LOW_SPEED_FLOOR
	slip_floor = LOW_SPEED_FLOOR
	_bar_compression = 0.0
	in_contact = false
	suspension_force = 0.0
	slip = 0.0
	long_slip = 0.0
	abs_active = false
	tcs_active = false
	force_long = 0.0
	force_lat = 0.0
	surface_grip = 1.0
	surface_drag = 0.0
	spin_compliance = 0.0
	brake_spin = 0.0
	abs_floor = 0.0
	tcs_spin = 0.0
	tcs_ceiling = 0.0
	coupled_torque = 0.0
	lock_torque = 0.0
	_stick = Vector2.ZERO
	_spin_held = false


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
## drive at that drive slip (traction control), on the ground and off it; `tcs_drive` (N·m) is the
## drive the wheel's coupling may pass it this tick besides `drive_torque`, which bounds the hold.
func tick(body: RigidBody3D, drive_spec: GroundDriveSpec, space: PhysicsDirectSpaceState3D,
		drive_torque: float, brake_torque: float, delta: float,
		grip_terrains: Array[Node], abs_slip := 0.0, tcs_slip := 0.0, tcs_drive := 0.0) -> void:
	var xform := body.global_transform
	var up := xform.basis.y
	var ray_from := xform * anchor
	var ray_len := drive_spec.rest_length + wheel_radius
	# The contact query: whether the tyre touches, how far below the anchor its hub sits touching
	# plus the radius (`hit_dist`), and the contact normal.
	var hit_dist := 0.0
	var normal := Vector3.UP
	in_contact = _contact_query(space, body, ray_from, up, Basis(up, steer_angle) * xform.basis,
			drive_spec.rest_length)
	if in_contact:
		hit_dist = _contact_drop + wheel_radius
		normal = _contact_normal

	if not in_contact:
		compression = 0.0
		_prev_compression = 0.0
		_prev_vel_valid = false
		suspension_force = 0.0
		slip = 0.0
		long_slip = 0.0
		abs_active = false
		force_long = 0.0
		force_lat = 0.0
		contact_normal = Vector3.UP
		surface_grip = 1.0
		surface_drag = 0.0
		_stick = Vector2.ZERO
		# ABS and TC compare wheel speed with vehicle speed and cannot see contact: off the ground they
		# read the hub's own forward velocity. So a braked wheel that lifts (the rears in a hard stop)
		# keeps turning near road speed and lands gripping, where a brake alone stops it dead in the air
		# and it lands locked.
		var hub_vel := VehicleMath.point_velocity(body, ray_from)
		var hub_v_long := hub_vel.dot(Basis(up, steer_angle) * -xform.basis.z)
		_integrate_spin(drive_torque, 0.0, brake_torque, delta, 0.0,  ## airborne
				hub_v_long, abs_slip, 0.0, tcs_slip, tcs_drive)
		omega = free_spin_omega(omega, delta)
		if not coupled_spin:
			update_visual(drive_spec, delta)
		return

	contact_normal = normal
	# The spring travels along the cast (the body's down), so compression reads along it. The patch
	# is the hub's disk touching along the contact normal, on the wheel's mid-plane: Jolt's own rest
	# point wanders across the tread (9 cm on a steered wheel).
	var hub := ray_from - up * (hit_dist - wheel_radius)
	contact_point = hub + patch_offset(normal, up, Basis(up, steer_angle) * xform.basis.x,
			wheel_radius)
	var terrain := terrain_at(contact_point, grip_terrains)
	surface_grip = terrain.grip_at(contact_point) if terrain != null else 1.0
	surface_drag = terrain.drag_at(contact_point) if terrain != null else 0.0

	# Along the contact normal, never the chassis up axis, which would push a pitched body along.
	compression = clampf(ray_len - hit_dist, 0.0, drive_spec.rest_length)
	var comp_vel := (compression - _prev_compression) / delta
	_prev_compression = compression
	var damper := damper_bump if comp_vel > 0.0 else damper_rebound
	# 60 Hz clamp: never exceed the force that reverses compression velocity in one tick.
	var damper_force := clampf(damper * comp_vel,
			-corner_mass * absf(comp_vel) / delta, corner_mass * absf(comp_vel) / delta)
	# The bar sits inside the same force cap as spring and damper. So do the links, off last tick's
	# tyre force (this tick's needs the load being computed): `suspension_force` is the whole load
	# the corner carries, which the tyre budget below and every load readout take.
	suspension_force = clampf(spring_rate * compression + damper_force
			+ bar_force(bar_rate) + link_slope * force_long,
			0.0, drive_spec.max_suspension_force)
	body.apply_force(normal * suspension_force, contact_point - body.global_position)

	var wheel_forward := (Basis(up, steer_angle) * -xform.basis.z)
	var forward := (wheel_forward - normal * wheel_forward.dot(normal)).normalized()
	var side := forward.cross(normal)

	var vel := VehicleMath.point_velocity(body, contact_point)
	var v_long := vel.dot(forward)
	var v_lat := vel.dot(side)

	# Load-scaled BEFORE the tyre force below: its friction ellipse is drawn on this tick's budget.
	var ref_load := corner_mass * 9.81
	var mu_long := load_scaled_mu(drive_spec.mu_long * surface_grip,
			suspension_force, ref_load, drive_spec.load_sensitivity)
	var mu_lat := load_scaled_mu(drive_spec.mu_lat * axle_lat_grip * surface_grip,
			suspension_force * tyre_share, ref_load, drive_spec.load_sensitivity)

	# Both slips on one denominator, so the slip vector points along the patch's slide; its floor
	# keeps the curve's rise inside the one-tick cap below (`slip_floor_for`).
	var long_mass := minf(corner_mass, long_cap_mass)
	_own_slip_floor = slip_floor_for(mu_long * suspension_force, long_mass,
			drive_spec.grip_curve, delta)
	var floor_vel := maxf(slip_floor, _own_slip_floor)
	var slip_denom := maxf(absf(v_long), floor_vel)
	var slip_vel := omega * wheel_radius - v_long
	var slip_ratio := slip_vel / slip_denom
	long_slip = slip_ratio
	slip = absf(slip_ratio)
	# A twin pair at half load each: `mu(L / 2) * L` over `2 C(L / 2)` is this at `L / 2`.
	var lat_peak := lateral_peak_slip(suspension_force * tyre_share, ref_load,
			drive_spec.load_sensitivity, drive_spec.cornering_peak_load)
	var tyre := combined_slip_force(slip_ratio, -v_lat / slip_denom,
			mu_long * suspension_force, mu_lat * suspension_force, drive_spec.grip_curve, lat_peak)

	# Each axis capped by the force that would cancel its slip velocity in one tick (the lateral cap
	# kills parked-car jitter).
	long_cap = long_mass * absf(slip_vel) / delta
	var f_long := clampf(tyre.x, -long_cap, long_cap)
	var lat_mass := minf(corner_mass, lateral_cap_mass)
	var f_lat := clampf(tyre.y, -lat_mass * absf(v_lat) / delta, lat_mass * absf(v_lat) / delta)

	# Static friction: the patch spring beside the slip force, which is its damper. Along the wheel
	# only while the spin is held (`_spin_held`, last tick's settle).
	var f := Vector2(f_long, f_lat)
	var budget_long := mu_long * suspension_force
	var budget_lat := mu_lat * suspension_force
	var stick_w := clampf(1.0 - Vector2(v_long, v_lat).length() / STICK_SPEED, 0.0, 1.0)
	# What the brake holds besides the patch: the drive and what the differentials pass the wheel.
	var held_against := drive_torque + coupled_torque
	if stick_w > 0.0 and budget_long > 0.0 and budget_lat > 0.0:
		# A brake released (or out-driven) this tick holds nothing, whatever last tick latched.
		var hold_torque := brake_torque + lock_torque
		var held := _spin_held and hold_torque > absf(held_against)
		_stick = stick_step(_stick, Vector2(slip_vel if held else 0.0, -v_lat),
				absf(omega * wheel_radius), delta)
		if not held:
			_stick.x = 0.0
		var k := Vector2(stick_stiffness(budget_long, long_mass, delta),
				stick_stiffness(budget_lat, lat_mass, delta))
		_stick = stick_saturate(_stick, k, budget_long, budget_lat)
		f = friction_ellipse(f + stick_w * k * _stick, budget_long, budget_lat)
		if held:
			# Along the wheel only, so a brake-limited hold costs the patch no side grip.
			var hold := held_force_range(budget_long, hold_torque, held_against, wheel_radius)
			var stiffness := maxf(k.x, 1e-6)
			_stick.x = clampf(_stick.x, hold.x / stiffness, hold.y / stiffness)
			f.x = clampf(f.x, hold.x, hold.y)
	else:
		_stick = Vector2.ZERO

	body.apply_force(forward * f.x + side * f.y, contact_point - body.global_position)
	force_long = f.x
	force_lat = f.y

	# Surface drag is the ground deforming, not the tyre: outside the friction circle and the spin
	# step (a wheel in mud keeps rolling at road speed; the body slows).
	body.apply_force(forward * surface_drag_force(v_long, surface_drag, suspension_force,
			long_mass, delta), contact_point - body.global_position)

	# Faded out from twice the slip floor down to it: below the floor slip is read against the floor,
	# the tyre's slope sits at the one-tick cap, and following the body rings it at the tick rate.
	var dv_long := (body.linear_velocity - _prev_body_vel).dot(forward) if _prev_vel_valid else 0.0
	dv_long *= clampf(absf(v_long) / LOW_SPEED_FLOOR - 1.0, 0.0, 1.0)
	_prev_body_vel = body.linear_velocity
	_prev_vel_valid = true
	_integrate_spin(drive_torque, -f.x * wheel_radius, brake_torque, delta, slip_vel, v_long, abs_slip,
			dv_long, tcs_slip, tcs_drive, floor_vel)
	if not coupled_spin:
		update_visual(drive_spec, delta)


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
	var partner := anti_roll_partner
	if partner == null or not partner.in_contact:
		return 0.0
	return VehicleMath.anti_roll_force(_bar_compression, partner._bar_compression, rate)


## Effective mass (kg) each contact's force along body-space unit `axis` meets while every contact
## pushes along it: `1 / sum_j |1/m + (arm_i x axis) . I^-1 (arm_j x axis)|`, at body-space `arms`
## from the centre of mass. The row sum bounds every mode at once (Gershgorin: an even push, where
## the sides' yaw cancels, or the sides against each other), so caps sized off it cancel the slip
## velocities in one tick at most and never overshoot them. One arm is a lone contact's own figure,
## the body's mass plus the moments its lever turns. `inv_inertia` is the solver's inverse tensor
## in body axes. A free-body figure, so a joint on the body can only raise the real one. 0 for a
## massless body.
static func contact_masses(arms: PackedVector3Array, axis: Vector3, body_mass: float,
		inv_inertia: Basis) -> PackedFloat64Array:
	var masses := PackedFloat64Array()
	masses.resize(arms.size())
	if body_mass <= 0.0:
		return masses
	var levers := PackedVector3Array()
	var turned := PackedVector3Array()
	for arm in arms:
		levers.append(arm.cross(axis))
		turned.append(inv_inertia * levers[levers.size() - 1])
	for i in arms.size():
		var row := 0.0
		for j in arms.size():
			row += absf(1.0 / body_mass + levers[i].dot(turned[j]))
		masses[i] = 1.0 / row
	return masses


## Offset (m) from the hub to the patch: where a disk of `radius` in the wheel's plane (its spin
## axis `axle`) touches a plane of `normal`, `-radius` along the normal's part in that plane. Exact
## on a plane: straight under the hub in pitch, along the body's `up` in roll. Along `up` when the
## normal has no part pointing up in that plane (a back face, a face along the axle).
static func patch_offset(normal: Vector3, up: Vector3, axle: Vector3, radius: float) -> Vector3:
	var in_plane := normal - axle * normal.dot(axle)
	if in_plane.dot(up) <= 1e-3:
		return -up * radius
	return -in_plane.normalized() * radius


## Distance (m) from a cylinder's centre to its support plane of `normal`: radius `radius`, axis
## `axle`, `half_len` either side. Exact for Jolt's cylinder but where its convex radius rounds the
## rim (a normal with a part along the axle).
static func cylinder_support(normal: Vector3, axle: Vector3, radius: float, half_len: float) -> float:
	var along := absf(normal.dot(axle))
	return radius * sqrt(maxf(1.0 - along * along, 0.0)) + half_len * along


## The hub's drop (m) where the tyre just touches, between the sweep's last free stop `safe_drop`
## and its first touching one `unsafe_drop`: the touching stop backed out by `gap` (m, the
## centre's height over the contact's support plane less the cylinder's support; < 0 overlapping)
## along `up`, whose part along the normal is `normal_up`. Exact on a face, to first order over
## the step at an edge.
static func settled_drop(safe_drop: float, unsafe_drop: float, gap: float, normal_up: float) -> float:
	return clampf(unsafe_drop + gap / maxf(normal_up, 0.1), safe_drop, unsafe_drop)


## The contact: a cylinder of the wheel's radius and `2 half_width` across, its axis on the steered
## axle (`wheel_basis`'s x), swept from full bump (the hub at the anchor) down the travel; the
## normal is the rest contact's where the sweep stops, the face's on a face and radial at an edge.
## A start inside something reads full bump, the clamp's figure (`start_overlaps`). Sets
## `_contact_drop` and `_contact_normal`; false when nothing is under the tyre.
## COMPROMISE: `cast_motion` bisects to 1/256 of the motion (1.2 mm on a 0.3 m travel), a step
## the hub flickers across at rest and the dampers turn into load spikes (a semi's steer wheel
## lost ~1.1 kN at launch). `settled_drop` closes it off the touching stop's contact; reading the
## raw fraction instead costs that noise on every body.
func _contact_query(space: PhysicsDirectSpaceState3D, body: RigidBody3D, ray_from: Vector3,
		up: Vector3, wheel_basis: Basis, rest_length: float) -> bool:
	assert(_query != null, "the contact needs GroundDriveSpec.tyre_half_width and apply_suspension")
	# Self-exclusion: this body is on VEHICLE, which SOLID includes.
	if _query_body != body.get_rid():
		_query_body = body.get_rid()
		_query.exclude = [_query_body]
	var motion := -up * rest_length
	_query.transform = Transform3D(wheel_basis * Basis(Vector3.BACK, PI / 2.0), ray_from)
	_query.motion = motion
	var fractions := space.cast_motion(_query)
	_query.motion = Vector3.ZERO
	if fractions.size() < 2 or fractions[1] >= 1.0:
		# Jolt's sweep ignores what the shape already overlaps at its start, so "no hit" is either a
		# free wheel or one already past full bump: the rest test at the start tells them apart.
		var start := space.get_rest_info(_query)
		if start.is_empty():
			return false
		start_overlaps += 1
		_contact_drop = 0.0
		_contact_normal = start.get("normal", up)
		return true
	if fractions[1] <= 0.0:
		start_overlaps += 1
	var safe_drop := rest_length * fractions[0]
	var unsafe_drop := rest_length * fractions[1]
	_query.transform.origin = ray_from + motion * fractions[1]
	var rest := space.get_rest_info(_query)
	_contact_drop = safe_drop
	_contact_normal = up
	if not rest.is_empty():
		_contact_normal = rest["normal"]
		var gap := (_query.transform.origin - (rest["point"] as Vector3)).dot(_contact_normal) \
				- cylinder_support(_contact_normal, wheel_basis.x, wheel_radius, half_width)
		_contact_drop = settled_drop(safe_drop, unsafe_drop, gap, _contact_normal.dot(up))
	return true


## Each wheel's cap masses off what the wheels' contacts really move together (`contact_masses`),
## along the wheel and across it. Sized every tick, since the load models move the COM; the lever
## runs to full droop, the longest it gets, and on to last tick's patch (`patch_offset`). Also shares
## the body's slip floor (`slip_floor`).
static func size_cap_masses(wheels: Array[RayWheel], body: RigidBody3D,
		gd: GroundDriveSpec) -> void:
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	if state == null or wheels.is_empty():
		return
	var b := body.global_transform.basis
	var inv_inertia := b.transposed() * state.inverse_inertia_tensor * b
	var droop := Vector3(0.0, gd.rest_length, 0.0)
	var arms := PackedVector3Array()
	for w in wheels:
		var normal := b.transposed() * w.contact_normal if w.in_contact else Vector3.UP
		var patch := patch_offset(normal, Vector3.UP, Basis(Vector3.UP, w.steer_angle) * Vector3.RIGHT,
				w.wheel_radius)
		arms.append(w.anchor - droop + patch - body.center_of_mass)
	var along := contact_masses(arms, Vector3.BACK, body.mass, inv_inertia)
	var across := contact_masses(arms, Vector3.RIGHT, body.mass, inv_inertia)
	var floor_vel := LOW_SPEED_FLOOR
	for w in wheels:
		floor_vel = maxf(floor_vel, w._own_slip_floor if w.in_contact else LOW_SPEED_FLOOR)
	for i in wheels.size():
		wheels[i].long_cap_mass = along[i]
		wheels[i].lateral_cap_mass = across[i]
		wheels[i].slip_floor = floor_vel


## Tyre mu at a load off the corner's static reference: `mu * (1 - sensitivity * log2(load / ref))`,
## so grip grows SLOWER than load above the reference. Identity at the reference and at
## sensitivity 0, so every brake figure checked at the even static load (`BrakeSizing`,
## `test_vehicle_catalog`) holds. Capacity `mu(L) * L` still RISES
## with load; what a heavier wheel loses is its share per newton, which lets transfer move the
## balance. The [0.5, 1.25] clamp and the ref*0.25 load floor bind on nothing shipped (0.12 at the
## floor reaches 1.24); they bound a suspension spike or a runtime mass rewrite.
static func load_scaled_mu(mu: float, normal_load: float, ref_load: float,
		sensitivity: float) -> float:
	if sensitivity <= 0.0 or ref_load <= 0.0 or mu <= 0.0:
		return mu
	var ratio := maxf(normal_load, ref_load * 0.25) / ref_load
	return clampf(mu * (1.0 - sensitivity * log(ratio) / log(2.0)), mu * 0.5, mu * 1.25)


## A tyre's cornering stiffness at `normal_load` over its stiffness at `ref_load`, on the Magic
## Formula's load law `sin(2 atan(L / (peak_load * ref)))` (`PKY2`): it rises with load, flattens and
## peaks at `peak_load` times the reference, so a heavier wheel gives less stiffness per newton. 1 at
## the reference, and 1 at any load when `peak_load` <= 0 (off: the stiffness then follows `mu(L) * L`).
static func cornering_load_shape(normal_load: float, ref_load: float, peak_load: float) -> float:
	if peak_load <= 0.0 or ref_load <= 0.0:
		return 1.0
	var at_ref := sin(2.0 * atan(1.0 / peak_load))
	return sin(2.0 * atan(maxf(normal_load, 0.0) / (peak_load * ref_load))) / at_ref


## The side slip (a multiple of the grip curve's own peak slip) at which a tyre at `normal_load`
## reaches its peak side force: `mu(L) * L / C(L)`, its peak force over its cornering stiffness
## (`cornering_load_shape`), normalised to 1 at `ref_load`. 1 at any load when `peak_load` <= 0, the
## stiffness then following `mu(L) * L`. Surface grip and `axle_lat_grip` scale force and stiffness
## alike, so they drop out. The load is floored at `load_scaled_mu`'s, which keeps it finite at 0.
static func lateral_peak_slip(normal_load: float, ref_load: float, sensitivity: float,
		peak_load: float) -> float:
	if peak_load <= 0.0 or ref_load <= 0.0:
		return 1.0
	var n_load := maxf(normal_load, ref_load * 0.25)
	return load_scaled_mu(1.0, n_load, ref_load, sensitivity) * n_load \
			/ (ref_load * cornering_load_shape(n_load, ref_load, peak_load))


## Tyre force (N; x along the wheel's forward, y along its side) for the slip vector
## (`slip_long`, `slip_lat`), both slips over one speed denominator so the vector points along the
## contact patch's slide. The side slip is read against its own peak, `lat_peak` times the curve's
## (`lateral_peak_slip`; the longitudinal peak is the curve's). The grip curve reads the LENGTH of
## that normalised vector and the force points along it, scaled per axis by the budgets (`mu * N`),
## so it never leaves their ellipse and its peak is the budget whatever `lat_peak`. A locked wheel's
## slip is almost all longitudinal: its force opposes the slide, tilted by the budget ratio and
## `1 / lat_peak`, and it stops steering. On the curve's linear rise each axis is exactly what it
## would be alone.
static func combined_slip_force(slip_long: float, slip_lat: float, budget_long: float,
		budget_lat: float, grip_curve: PackedVector2Array, lat_peak := 1.0) -> Vector2:
	var sigma := Vector2(slip_long, slip_lat / lat_peak)
	var s := sigma.length()
	if s <= 0.0:
		return Vector2.ZERO
	var grip := minf(VehicleSpec.sample_curve(grip_curve, s), 1.0) / s
	return Vector2(budget_long * sigma.x * grip, budget_lat * sigma.y * grip)


## The patch deflection (m) after one tick: the old one decayed over the distance rolled
## (`roll_speed`, m/s, over STICK_RELAX; exact, so it never flips sign) plus the slide
## (`slide_vel`, m/s, the contact's velocity against the road along the tyre's force axes).
static func stick_step(stick: Vector2, slide_vel: Vector2, roll_speed: float,
		delta: float) -> Vector2:
	return stick * exp(-absf(roll_speed) * delta / STICK_RELAX) + slide_vel * delta


## The patch spring's stiffness (N/m) for one axis: the budget reached at STICK_DEFLECTION, under
## the 60 Hz clamp on the `mass` that axis moves (STICK_TICK_STIFFNESS).
static func stick_stiffness(budget: float, mass: float, delta: float) -> float:
	return minf(budget / STICK_DEFLECTION, STICK_TICK_STIFFNESS * mass / (delta * delta))


## `stick` pulled back onto the edge of the friction ellipse wherever its spring force
## (`k * stick` per axis) would leave it. That edge is the slide: the spring then carries the
## whole budget, whatever the tick clamp did to `k`.
static func stick_saturate(stick: Vector2, k: Vector2, budget_long: float,
		budget_lat: float) -> Vector2:
	if budget_long <= 0.0 or budget_lat <= 0.0:
		return Vector2.ZERO
	var reach := Vector2(k.x * stick.x / budget_long, k.y * stick.y / budget_lat).length()
	return stick / reach if reach > 1.0 else stick


## The longitudinal force range (N, x the most backward, y the most forward) a held wheel's patch
## carries: the tyre's budget either way, or where the brake slips first. The brake holds the wheel
## against its net torque, `held_against - f r` (`held_against` the drive plus what the
## differentials pass it, + = forward), so a drive working with the patch's force (a converter's
## creep up a grade) widens that side and one working against it narrows it. Past it the brake slips
## at its own Coulomb limit and the body slides there; letting the wheel turn at that edge instead
## flickers it held / free, rewinding the patch from zero on a moving body every catch. 2 % inside
## the brake, so the settle's own check (`brake >= |reaction|`) keeps it held. Empty (both 0) once
## the drive alone out-holds the brake.
static func held_force_range(budget_long: float, brake_torque: float, held_against: float,
		radius: float) -> Vector2:
	if radius <= 0.0:
		return Vector2(-budget_long, budget_long)
	if absf(held_against) >= brake_torque:
		return Vector2.ZERO
	var hold := 0.98 * brake_torque
	return Vector2(clampf((held_against - hold) / radius, -budget_long, 0.0),
			clampf((held_against + hold) / radius, 0.0, budget_long))


## `f` scaled back into the friction ellipse of the two budgets (N), direction kept.
static func friction_ellipse(f: Vector2, budget_long: float, budget_lat: float) -> Vector2:
	if budget_long <= 0.0 or budget_lat <= 0.0:
		return Vector2.ZERO
	var reach := Vector2(f.x / budget_long, f.y / budget_lat).length()
	return f / reach if reach > 1.0 else f


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


## Slip-ratio denominator floor (m/s) for a tyre of longitudinal budget `budget` (N) whose one-tick
## cap moves `mass`: LOW_SPEED_FLOOR, or higher where the grip curve's steepest rise, `budget * rise
## / floor` N per m/s of slip, would pass the cap's `mass / delta`. On that floor the curve sits
## inside the cap everywhere, so the cap binds only on an overshoot and a crawl still reaches the
## full budget, at its peak's slip ratio. A numerical floor like
## LOW_SPEED_FLOOR, not a tyre property: a heavy corner on a light cap mass (a drive axle under a
## fifth wheel) needs more slip velocity at a crawl for the same force.
## The longitudinal rise only: the side rise, `1 / lateral_peak_slip` steeper on a light wheel, is
## held by its own one-tick cap, deadbeat on `contact_masses`; a floor reading it would move every
## straight-line crawl figure through the shared denominator.
static func slip_floor_for(budget: float, mass: float, grip_curve: PackedVector2Array,
		delta: float) -> float:
	if mass <= 0.0:
		return LOW_SPEED_FLOOR
	var rise := 0.0  ## steepest secant from the origin, per unit slip: a vertex's, the curve linear
	for p in grip_curve:
		if p.x > 0.0:
			rise = maxf(rise, minf(p.y, 1.0) / p.x)
	return maxf(LOW_SPEED_FLOOR, budget * rise * delta / mass)


## Wheel spin from drive plus road-reaction torque, semi-implicit (an explicit step rings at the
## tick rate): the net torque is divided by (1 + `reaction_stiffness`), never the reaction clamped.
## It solves for SLIP: the road's change under the wheel is followed in proportion `k / (1 + k)`.
## The brake (`brake_spin`, ABS floor `abs_floor`) and the TC hold (`tcs_spin`, `tcs_ceiling`: TC
## removes drive, never brakes) are latched by the step and applied by `settle_spin`, after the
## differentials on a `coupled_spin` wheel. Derivation and figures: docs/vehicles.md, "Spin step".
func _integrate_spin(drive_torque: float, reaction_torque: float, brake_torque: float,
		delta: float, slip_vel: float, v_long := 0.0, abs_slip := 0.0, dv_long := 0.0,
		tcs_slip := 0.0, tcs_drive := 0.0, floor_vel := LOW_SPEED_FLOOR) -> void:
	var null_slip_torque := wheel_inertia * absf(slip_vel) / (delta * wheel_radius)
	var reaction_stiffness := absf(reaction_torque) / maxf(null_slip_torque, 1e-6)
	spin_compliance = delta / (wheel_inertia * (1.0 + reaction_stiffness))
	omega += (drive_torque + reaction_torque) / (1.0 + reaction_stiffness) / wheel_inertia * delta \
			+ dv_long / wheel_radius * reaction_stiffness / (1.0 + reaction_stiffness)
	tcs_spin = 0.0
	tcs_ceiling = 0.0
	var held_drive := drive_torque + tcs_drive
	if tcs_slip > 0.0 and held_drive != 0.0 and wheel_radius > 0.0:
		tcs_spin = held_drive * spin_compliance
		tcs_ceiling = tcs_ceiling_spin(v_long + dv_long, signf(held_drive), wheel_radius, tcs_slip,
				floor_vel)
	brake_spin = brake_torque * spin_compliance
	abs_floor = abs_floor_spin(v_long + dv_long, wheel_radius, abs_slip, floor_vel)
	abs_active = false
	if not coupled_spin:
		settle_spin(0.0)


## Settle this tick's spin: `torque` (N·m) from the differentials through the step
## (`* spin_compliance`), then the latched holds, the traction control's and then the brake's
## (`settled_spin`). The owner of a `coupled_spin` wheel calls it once per tick after solving its
## differentials with those holds inside (`Differential.braked_coupling_torque`); any other wheel
## settles at the end of its own step. `lock_part` is the park lock's share of `torque`: a hold like
## the brake's, so the patch is held against the rest (`coupled_torque`) and never against it.
func settle_spin(torque: float, lock_part := 0.0) -> void:
	coupled_torque = torque - lock_part
	omega += torque * spin_compliance
	var tcs := tcs_take(omega, tcs_spin, tcs_ceiling)
	tcs_active = tcs > 0.0
	omega -= signf(tcs_spin) * tcs
	abs_active = minf(brake_spin, absf(omega)) > brake_room(omega, abs_floor)
	omega = braked_spin(omega, brake_spin, abs_floor)
	# Held when the brake had the torque to stop the spin outright: through the secant step that is
	# `brake_torque >= |drive + reaction + coupling|`, a Coulomb check, so a weak brake lets the
	# wheel turn.
	_spin_held = brake_spin > 0.0 and omega == 0.0


## The park lock holds this wheel still (`WheelDrive._couple_differentials`): stopped and held as a
## brake holds it, after `settle_spin`.
func hold_by_lock() -> void:
	omega = 0.0
	_spin_held = true


## The brake law: `spin` (rad/s, before the brake) after a brake that can take off `can_take`,
## never past zero, and under ABS never below `stop_at` (`abs_floor_spin`). Monotone and piecewise
## linear in `spin`, which is what lets `Differential` solve a coupling with its brakes inside.
static func braked_spin(spin: float, can_take: float, stop_at: float) -> float:
	return move_toward(spin, 0.0, minf(can_take, brake_room(spin, stop_at)))


## Spin (rad/s) a brake may take off `spin` before reaching the ABS floor `stop_at`: all of it with
## no floor (0), or when the wheel already turns against the floor's (the contact's) direction.
static func brake_room(spin: float, stop_at: float) -> float:
	if stop_at == 0.0 or signf(spin) != signf(stop_at):
		return absf(spin)
	return maxf(absf(spin) - absf(stop_at), 0.0)


## Signed spin (rad/s) an anti-lock brake stops at: the spin whose braking slip is `abs_slip` at
## the contact's `v_long`, on RayWheel's own slip denominator (floored at `floor_vel`, the wheel's
## `slip_floor`). 0 (stop the wheel) with no ABS, and near a standstill, where the floor lets it
## stop: a stopped vehicle must still be held.
static func abs_floor_spin(v_long: float, radius: float, abs_slip: float,
		floor_vel := LOW_SPEED_FLOOR) -> float:
	if radius <= 0.0 or abs_slip <= 0.0:
		return 0.0
	var denom := maxf(absf(v_long), floor_vel)
	return signf(v_long) * maxf(absf(v_long) - abs_slip * denom, 0.0) / radius


## Signed spin (rad/s) a traction-controlled drive stops at: the spin whose drive slip is
## `tcs_slip` at the contact's `v_long`, on the drive's side `dir` (the drive torque's sign), so
## reverse mirrors forward. The mirror of `abs_floor_spin` on the same denominator (`floor_vel`).
## `radius` must be positive: the caller latches no hold at 0.
static func tcs_ceiling_spin(v_long: float, dir: float, radius: float, tcs_slip: float,
		floor_vel := LOW_SPEED_FLOOR) -> float:
	return dir * ((v_long * dir + tcs_slip * maxf(absf(v_long), floor_vel)) / radius)


## Spin (rad/s, >= 0, against the drive) the traction-control hold takes off `spin`: as far as it
## passes `ceiling` on the drive's side, and never more than `share`, the drive's own part of the
## step (`tcs_spin`, signed with the drive): TC removes drive, never brakes. A wheel turning slower
## than the road, or against the drive, loses nothing. 0 with no share.
static func tcs_take(spin: float, share: float, ceiling: float) -> float:
	if share == 0.0:
		return 0.0
	var dir := signf(share)
	var room := maxf(ceiling * dir - (spin * dir - absf(share)), 0.0)
	return maxf(absf(share) - room, 0.0)


## A wheel's settle law: `spin` (rad/s, before its holds) after the traction-control hold
## (`tcs_take`) and then the brake (`braked_spin`). Each is monotone and piecewise linear in `spin`,
## so their composition is too, which is what lets `Differential` solve a coupling with both inside.
static func settled_spin(spin: float, can_take: float, stop_at: float, tcs_share: float,
		tcs_at: float) -> float:
	return braked_spin(spin - signf(tcs_share) * tcs_take(spin, tcs_share, tcs_at), can_take,
			stop_at)


## Draw this tick's settled spin and suspension travel. A `coupled_spin` wheel's owner calls it
## after `settle_spin`, or a held wheel would draw the spin its brake then takes back.
func update_visual(drive_spec: GroundDriveSpec, delta: float) -> void:
	if _visual == null:
		return
	_spin_angle = wrapf(_spin_angle + omega * delta, -TAU, TAU)
	var center := anchor + Vector3.DOWN * (drive_spec.rest_length - compression)
	_visual.transform = Transform3D(
			Basis(Vector3.UP, steer_angle) * Basis(Vector3.RIGHT, -_spin_angle)
			* Basis(Vector3.BACK, PI / 2.0),
			center)

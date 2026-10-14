class_name WheelDrive
extends RefCounted
## The wheeled ground drive: RayWheels, visuals, torque split, brakes, diff lock, resistance,
## downforce, slip telemetry and wheel-slip dust. Owned and ticked by BaseVehicle like Drivetrain,
## a RefCounted rather than a child node since wheel positions are spec data. Data lives on
## `spec.ground_drive`; `steer_speed` stays on the core spec since it also slews a rudder and yaw.

const WHEEL_VISUAL_NAMES: PackedStringArray = ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]

## Wheel-slip dust emitter, built in code.
const DUST_SLIP_MIN := 0.2      ## rear slip ratio where dust starts
const DUST_SLIP_FULL := 0.6     ## rear slip ratio for full emission
const DUST_MOVING := 1.0        ## m/s below which dust is suppressed (idle burnout stays clean)

## Foot-brake application against pedal travel, anchored per body: half pedal asks
## BRAKE_HALF_PEDAL_G of deceleration on every body, full pedal the hardware's whole capacity
## (`BrakeSizing.capacity_g`, past the tyre: a lock, or ABS at the peak). So the feel per pedal
## travel is the same from the saloon to the semi, and only the last part of the travel reaches each
## body's reserve (`brake_application`).
const BRAKE_HALF_PEDAL_G := 0.5
## Road speed (m/s) under which a gearbox in P drops its pawl into the parking gear; above it the
## pawl ratchets over the teeth, so P holds nothing at speed.
const PAWL_ENGAGE_SPEED := 1.0
## Spin (rad/s) under which every wheel the pawl locks reads as stopped while the pawl holds: the
## pass solves the lock before the diffs, which then move the driven wheels' mean by the spread
## their compliances leave (7.5e-4 on `suv-luxury` parked on 16 %, 2026-10-08). 3.5 mm/s at a car's
## tread, inside a parking gear's backlash; a wheel an open diff counter-rotates off its lost grip
## turns rad/s.
const LOCK_STUCK_SPIN := 0.01

var wheels: Array[RayWheel] = []
## Rear diff state as actually run this tick, not the request bit; `diff_lock_state` reads this.
var rear_diff_locked := false
## Retarder torque actually applied this tick (Nm), summed over driven rear wheels.
var retarder_torque_applied := 0.0
## Spring-brake application on the rear wheels, 0..1, set by the owner for the next tick (a truck's
## air gate, `TruckVehicle`): `handbrake_torque`, applied like a pulled handbrake.
var spring_brake := 0.0
## The gearbox sits in P (`Drivetrain.GEAR_P`), set by the owner before each tick: the pawl locks
## the gearbox output to the case below PAWL_ENGAGE_SPEED (`_couple_differentials`).
var park_engaged := false

var _applied_steer := 0.0  ## steer angle applied to steered wheels this tick (rad)
var _driven_count := 0     ## driven wheels as drive_omega() counted them THIS tick
var _dust: GPUParticles3D  ## rear-slip dust; null until build_dust(), and on a drive with no wheels
## The wheels of each axle (indices into `wheels`), split once by `RayWheel.is_rear`: the
## differentials couple within and between these. Whether an axle is DRIVEN is read per tick (MFWD
## engages at runtime).
var _front := PackedInt32Array()
var _rear := PackedInt32Array()
## Torque (N·m) the differentials pass each wheel this tick, accumulated by `_couple_differentials`
## and handed to `RayWheel.settle_spin`.
var _coupling := PackedFloat64Array()
## The park pawl's part of `_coupling` (N·m), which the brake holds with, never against
## (`RayWheel.settle_spin`).
var _lock_coupling := PackedFloat64Array()
## Front-to-rear anchor distance (m), body space; 0 if the spec declares no front/rear pair
## (never happens for a real wheeled body). Cached once in _init since wheel_positions is data.
var _wheelbase := 0.0
## Full-pedal foot-brake torque at one front / rear wheel (`GroundDriveSpec.axle_brake_torque`),
## cached in _init like the wheelbase.
var _brake_front := 0.0
var _brake_rear := 0.0
var _retarder_rating := 0.0  ## Nm a driven wheel (`Drivetrain.retarder_rating`), cached in _init
## Load (kg) the pedal map anchors on (`pedal_application`), 0 = the body's live mass. A towing
## unit with EBS sets its coupled static load each tick (its mass plus what the trailer puts on the
## coupling): EBS load sensing, so half pedal asks the rig what it asks the bare unit.
var brake_load_kg := 0.0
var _brake_force := 0.0  ## full-pedal foot-brake force (N) over every wheel, cached in _init
var _live_mass := 0.0    ## the body's mass (kg), kept by `set_corner_mass_from`
## The hill hold applies more than the driver's pedal this tick (`hold_step`).
var hill_holding := false
## Mass (kg) a coupled trailer hangs on the body, set by the owner each tick like `brake_load_kg`
## (`TowHost.towed_mass_kg`): the hill hold and the gearbox's load weigh the grade with it.
var towed_kg := 0.0
## `HillHold.step`'s state: the held application and the seconds held.
var _hold := Vector2.ZERO
## Axle torque (N·m, + = forward) the engine passed the driven wheels last tick, which the hill hold
## weighs against the grade.
var _drive_torque := 0.0


## Build the wheels and their visuals.
func _init(body: Node3D, spec: VehicleSpec) -> void:
	var gd := spec.ground_drive
	# Per-corner mass share; a runtime `mass` write re-shares it (BaseVehicle.set_live_mass).
	var corner_mass := spec.mass / maxf(1.0, gd.wheel_positions.size())
	for i in gd.wheel_positions.size():
		var pos := gd.wheel_positions[i]
		var front := not RayWheel.is_rear_z(pos.z)
		var driven := (front and gd.driven_front) or (not front and gd.driven_rear)
		var visual: Node3D = null
		# Rendered radius for this corner; physics always uses gd.wheel_radius.
		var vis_radius := gd.wheel_radius
		if not front and gd.wheel_visual_radius_rear > 0.0:
			vis_radius = gd.wheel_visual_radius_rear
		elif gd.wheel_visual_radius > 0.0:
			vis_radius = gd.wheel_visual_radius
		if i < WHEEL_VISUAL_NAMES.size():
			visual = body.get_node_or_null(NodePath(WHEEL_VISUAL_NAMES[i]))
			# No authored wheel mesh; instance the spec's under the expected name.
			var scene: PackedScene = gd.wheel_scene
			if not front and gd.wheel_scene_rear != null:
				scene = gd.wheel_scene_rear
			if visual == null and scene != null:
				visual = scene.instantiate()
				visual.name = WHEEL_VISUAL_NAMES[i]
				# Radius-normalized model, scaled to vis_radius; right wheels flip to face out
				# (rim on one face). The flip is Vector3.RIGHT, not UP: local Y is the axle in
				# RayWheel's root basis. Flip and scale ride the child; RayWheel overwrites the root.
				for child in visual.get_children():
					if child is Node3D:
						var b := (child as Node3D).basis.scaled(Vector3.ONE * vis_radius)
						(child as Node3D).basis = Basis(Vector3.RIGHT, PI) * b if pos.x > 0.0 else b
				body.add_child(visual)
		var wheel := RayWheel.new(pos, front, driven, visual, corner_mass)
		wheel.visual_lift = vis_radius - gd.wheel_radius
		wheel.apply_suspension(gd)
		# Brakes are solved with the differentials (`_couple_differentials`).
		wheel.coupled_spin = true
		if wheel.is_rear:
			_rear.append(wheels.size())
		else:
			_front.append(wheels.size())
		wheels.append(wheel)
	_coupling.resize(wheels.size())
	_lock_coupling.resize(wheels.size())
	if gd.anti_roll_rate > 0.0:
		RayWheel.pair_axles(wheels)
	_wheelbase = _compute_wheelbase()
	_brake_front = gd.axle_brake_torque(false)
	_brake_rear = gd.axle_brake_torque(true)
	_retarder_rating = Drivetrain.retarder_rating(spec)
	_brake_force = gd.brake_torque * gd.wheel_positions.size() / maxf(gd.wheel_radius, 1e-6)
	_live_mass = spec.mass


## Share of the foot brake's capacity a pedal at `pedal` (0..1) applies on a body whose full pedal
## makes `capacity_g`: `pedal ^ k`, with `k` putting half pedal at BRAKE_HALF_PEDAL_G. A body with
## no more capacity than that is linear (k = 1), never regressive.
static func brake_application(pedal: float, capacity_g: float) -> float:
	var k := 1.0
	if capacity_g > BRAKE_HALF_PEDAL_G:
		k = log(BRAKE_HALF_PEDAL_G / capacity_g) / log(0.5)
	return pow(clampf(pedal, 0.0, 1.0), k)


## This body's `brake_application` of the foot pedal, its capacity read on `brake_load_kg` (or its
## live mass); what a towing unit also sends its trailer.
func pedal_application(pedal: float) -> float:
	var load_kg := brake_load_kg if brake_load_kg > 0.0 else _live_mass
	return brake_application(pedal, _brake_force / (maxf(load_kg, 1e-6) * BrakeSizing.G))


## The park pawl's rating (Nm) per driven wheel: `park_pawl_torque` while the gearbox is in P and
## the body under PAWL_ENGAGE_SPEED (above it a real pawl ratchets over the parking gear's teeth),
## else 0. The lock on the gearbox output holds that times the driven wheels, reaching each wheel
## through the diffs (`_couple_differentials`). A mechanical hold, never under ABS.
static func pawl_torque(in_park: bool, gd: GroundDriveSpec, ground_speed: float) -> float:
	if not in_park or absf(ground_speed) >= PAWL_ENGAGE_SPEED:
		return 0.0
	return maxf(gd.park_pawl_torque, 0.0)


## Parking-brake torque (Nm) at one rear wheel: the lever (`handbrake01`) or a truck's spring
## brakes (`spring01`), whichever applies more. Both act on the same hardware, `handbrake_torque`.
static func parking_torque(handbrake01: float, spring01: float, gd: GroundDriveSpec) -> float:
	return parking_application(handbrake01, spring01) * gd.handbrake_torque


## Parking-brake application, 0..1: the lever or the spring brakes, whichever applies more. What a
## towing unit also hands its trailer (`TowHost.tick_towing`'s `parking01`).
static func parking_application(handbrake01: float, spring01: float) -> float:
	return clampf(maxf(handbrake01, spring01), 0.0, 1.0)


## Re-share the body's LIVE mass over the corners. The three one-tick RayWheel clamps are sized
## off `corner_mass`, so BaseVehicle.set_live_mass (the refuse truck's hopper) calls this, or the
## clamps stay sized for the empty vehicle and bite on forces the laden body legitimately makes.
## The pedal map anchors on the same live mass (`pedal_application`).
func set_corner_mass_from(live_mass: float) -> void:
	_live_mass = live_mass
	var corner_mass := live_mass / maxf(1.0, wheels.size())
	for w in wheels:
		w.corner_mass = corner_mass


## Wheel-slip dust, built separately so the emitter keeps its place in the body's child order.
func build_dust(body: Node3D, gd: GroundDriveSpec) -> void:
	if gd.wheel_positions.is_empty():
		return
	_dust = _build_dust(gd)
	body.add_child(_dust)


## The foot pedal the brakes apply this tick, 0..1: the driver's, or the hill hold's application
## where that is more (`hold_step`). What a towing unit also sends its trailer
## (`pedal_application`), so the rig holds as one.
func foot_pedal(input: VehicleInput) -> float:
	return maxf(input.brake, _hold.x)


## The hill hold's tick (`GroundDriveSpec.hill_hold`, `HillHold`), before `drive_omega` and the
## drivetrain, which read `foot_pedal`. The grade is read off the mean contact normal of the wheels
## on the ground, the gear's direction off the byte the box engaged last tick, and the drive off
## what the coupling passed last tick. It also hands the gearbox the rig's mass and the load it
## stands under there (`Drivetrain.standing_load`: the grade, the tyres' rolling resistance and the
## soil's drag under them), what the shift policy's start gear and road load read.
func hold_step(body: RigidBody3D, gd: GroundDriveSpec, input: VehicleInput,
		drivetrain: Drivetrain, ground_speed: float, delta: float) -> void:
	var dir := signf(Drivetrain.ratio_for_byte(drivetrain.spec, drivetrain.gear_byte))
	var normal := Vector3.ZERO
	var soil := 0.0
	var touching := 0
	for w in wheels:
		if w.in_contact:
			normal += w.contact_normal
			soil += w.surface_drag
			touching += 1
	var in_gear := dir != 0.0 and drivetrain.running and normal != Vector3.ZERO
	var mass := _live_mass + towed_kg
	var pull := 0.0
	drivetrain.load_mass_kg = mass
	drivetrain.standing_load = 0.0
	if normal != Vector3.ZERO:
		var gravity := body.get_gravity()
		var forward := -body.global_transform.basis.z
		var lever := mass * gd.wheel_radius
		pull = HillHold.pull_torque(gravity, normal.normalized(), forward, lever)
		drivetrain.standing_load = ShiftPolicy.standing_load(gravity, normal.normalized(), forward,
				gd.rolling_resistance + soil / touching, lever)
	_hold = HillHold.step(gd.hill_hold, gd.hill_hold_s, _hold.x, _hold.y, input.brake,
			absf(input.throttle), absf(ground_speed) < HillHold.REST_SPEED, in_gear,
			HillHold.drive_holds(dir, _drive_torque, pull), delta)
	hill_holding = _hold.x > input.brake


## Mean spin speed of the driven wheels, which the drivetrain uses for gear pick and torque-curve
## placement. Called before Drivetrain.process; the driven count latched here is reused by tick()
## for the torque split.
func drive_omega(gd: GroundDriveSpec, input: VehicleInput) -> float:
	# MFWD: the tractor front axle engages at runtime, so `driven` is not fixed at _ready. The foot
	# brake engages it too where declared, the hill hold's included: the rigid shaft then carries the
	# rear brakes' torque to the front wheels (`_couple_differentials`).
	if gd.front_axle_engageable:
		var braking := gd.brake_engages_front_axle and foot_pedal(input) > 0.0
		for w in wheels:
			if not w.is_rear:
				w.driven = input.fwd_drive or gd.driven_front or braking  ## can only ADD drive

	_driven_count = 0
	var omega := 0.0
	for w in wheels:
		if w.driven:
			_driven_count += 1
			omega += w.omega
	return omega / maxf(1.0, _driven_count)


## Front axle to rear axle distance (m), from the built wheels' anchors. 0.0 with no front or no
## rear wheel (never a real wheeled body).
func _compute_wheelbase() -> float:
	var front_z := INF
	var rear_z := -INF
	for w in wheels:
		if w.is_rear:
			rear_z = maxf(rear_z, w.anchor.z)
		else:
			front_z = minf(front_z, w.anchor.z)
	if is_inf(front_z) or is_inf(rear_z):
		return 0.0
	return rear_z - front_z


## Pure: ISOBUS curvature (1/km, + = right) to wheel angle (rad, same sign; the caller negates it
## for `_applied_steer`'s convention, as the plain `steer` path does). One angle for both steered
## wheels (no Ackermann). `angle = atan(wheelbase * curvature)`, clamped to the mechanical lock,
## never the speed-tapered one.
static func steer_angle_from_curvature(curvature_per_km: float, wheelbase: float,
		max_steer_deg: float) -> float:
	var max_rad := deg_to_rad(max_steer_deg)
	var angle := atan(wheelbase * (curvature_per_km / 1000.0))
	return clampf(angle, -max_rad, max_rad)


## The guidance path's slew TARGET, in the unit of `input.steer` ([-1, 1], + = right): the
## untapered lock angle for the commanded curvature over that lock, so `BaseVehicle` slews it at
## `spec.steer_speed` like hand-steering. NAN with no guidance command or no wheelbase, so the
## caller falls back to `input.steer`.
func guidance_steer_unit(input: VehicleInput, gd: GroundDriveSpec) -> float:
	if input.guidance_curvature == VehicleInput.GUIDANCE_CURVATURE_NONE or _wheelbase <= 0.0:
		return NAN
	var max_rad := deg_to_rad(gd.max_steer_deg)
	return steer_angle_from_curvature(input.guidance_curvature, _wheelbase, gd.max_steer_deg) \
			/ max_rad


## Statement order is load-bearing: resistance reads this tick's spring load so it must follow
## the wheel loop; the differentials settle every wheel's spin and brake off its step, so they must
## follow spin integration. `axle_torque` is the rigid crank's (`Drivetrain.process`): 0 where the
## engine drives wheels, whose drive arrives through `drivetrain`'s coupling inside the solve.
func tick(body: RigidBody3D, spec: VehicleSpec, input: VehicleInput, steer: float,
		axle_torque: float, ground_speed: float, delta: float,
		grip_terrains: Array[Node], drivetrain: Drivetrain = null) -> void:
	var gd := spec.ground_drive
	if input.guidance_curvature != VehicleInput.GUIDANCE_CURVATURE_NONE and _wheelbase > 0.0:
		# `steer` (already slewed from guidance_steer_unit) is in mechanical-lock units: no speed
		# taper, so the driven radius tracks the command at any speed.
		_applied_steer = -steer * deg_to_rad(gd.max_steer_deg)
	else:
		# High-speed steering falloff (min_steer_frac == 1.0 disables it).
		var steer_falloff := 1.0
		if gd.steer_falloff_speed > 0.0:
			steer_falloff = lerpf(1.0, gd.min_steer_frac,
					clampf(absf(ground_speed) / gd.steer_falloff_speed, 0.0, 1.0))
		_applied_steer = -steer * deg_to_rad(gd.max_steer_deg * steer_falloff)

	var space := body.get_world_3d().direct_space_state
	retarder_torque_applied = 0.0
	var pawl := pawl_torque(park_engaged, gd, ground_speed)
	# The driven wheels, which the pawl locks while it is in.
	var locked := PackedInt32Array()
	for i in wheels.size():
		wheels[i].lock_torque = pawl if wheels[i].driven else 0.0
		if wheels[i].lock_torque > 0.0:
			locked.append(i)
	# One anti-roll snapshot for the whole body before any wheel ticks (`RayWheel.anti_roll_partner`).
	for w in wheels:
		w.latch_bar()
	# Traction control rides the drive alone, a hold each wheel latches and the differentials settle
	# with its brake, bounded by its share of what the coupling may pass; `tcs_off` (bridge or local
	# setting) switches it off.
	var tcs_slip := RayWheel.TCS_SLIP if gd.tcs_equipped and not input.tcs_off else 0.0
	var tcs_drive := drivetrain.tcs_drive_torque() / maxf(1.0, _driven_count) \
			if drivetrain != null and Drivetrain.drives_wheels(spec) else 0.0
	var pedal := pedal_application(foot_pedal(input))
	for w in wheels:
		w.steer_angle = _applied_steer if w.steered else 0.0
		# The nominal equal split (open-diff law); `_couple_differentials` adds what a biasing,
		# locked or rigid diff moves on top, once every wheel has integrated.
		var drive_t := axle_torque / _driven_count if w.driven else 0.0
		var brake_t := pedal * (_brake_rear if w.is_rear else _brake_front)
		# Anti-lock rides the foot brake and the retarder; a handbrake or spring brake is a
		# mechanical hold no ABS modulates, so a wheel under one brakes without.
		var abs_slip := RayWheel.ABS_SLIP if gd.abs_equipped else 0.0
		if w.is_rear:
			var parking := parking_torque(input.handbrake, spring_brake, gd)
			brake_t += parking
			if parking > 0.0:
				abs_slip = 0.0
			# Retarder (truck only): a brake on the driven axle, never a separate model. Its slip cap
			# reads last tick's compliance (a free wheel's `delta / I` before the first tick).
			# COMPROMISE: on the tick a gripping wheel leaves the ground the cap is up to
			# `1 + reaction_stiffness` too generous and the retarder can stop the lifted wheel; ABS
			# lets it spin back up on landing. Exact needs the cap solved inside RayWheel's step.
			if gd.retarder_equipped and w.driven:
				var compliance := w.spin_compliance if w.spin_compliance > 0.0 \
						else delta / gd.wheel_inertia
				var ret := Drivetrain.retarder_torque(
						input.retarder, ground_speed, w.omega, gd, compliance, _retarder_rating)
				brake_t += ret
				retarder_torque_applied += ret
		w.tick(body, gd, space, drive_t, brake_t, delta, grip_terrains, abs_slip,
				tcs_slip if w.driven else 0.0, tcs_drive if w.driven else 0.0)

	_couple_differentials(gd, input, axle_torque, locked, pawl * locked.size(),
			drivetrain if drivetrain != null and Drivetrain.drives_wheels(spec) else null)
	for w in wheels:
		w.update_visual(gd, delta)
	_apply_resistance(body, gd, delta)
	_apply_downforce(body, gd)


## The declared differentials, as coupling torques solved off each wheel's own spin step
## (`Differential`, `RayWheel.spin_compliance`) with every wheel's holds inside each solve
## (`Differential.braked_coupling_torque`), then every wheel settled (`RayWheel.settle_spin`): a
## braked wheel stays held unless the torque a diff must pass it beats its brake, and a TC-held one
## stays at its ceiling unless the diff passes it more than its drive share. One pass, the gearbox
## output first. In P, while the pawl is in (`locked`, the driven wheels; `lock_capacity` > 0): a
## lock of the gearbox output to the case, so a coupling of the driven wheels' mean spin to a ground
## of no compliance, its torque reaching them equally through the diffs; an open diff downstream
## still lets its outputs counter-rotate, as a real one does in P. In D or R on an engine that
## drives the wheels (`drivetrain`): the crank, an output with its own spin and compliance behind
## the controller's capacity, or behind a converter's law solved against the driven wheels' settled
## mean (`Drivetrain.couple`), its torque reaching the wheels the same way.
## Either torque sizes a biasing diff's capacity, as `axle_torque` (the rigid crank's) does. Then
## the centre, whenever both axles are driven (rigid for MFWD, else `centre_diff_bias`), its torque
## reaching an axle's wheels equally; then each axle, capacity sized off the torque it actually
## received, unbounded on the rear while the diff lock is held. All open, each wheel settles on its
## own holds.
## COMPROMISE: one pass. An axle coupling between wheels of unequal compliance moves that axle's
## mean after the centre balanced it (`race-future`'s rear LSD, the tractor's lock under MFWD).
## Exact needs each axle solved inside the centre's solve. Likewise the centre and axles move the
## driven wheels' mean after the gearbox output settled against it: under the pawl LOCK_STUCK_SPIN
## absorbs it, and a locked crank coupling stays locked (the state is the controller's, set when the
## solve carried less than its capacity), the crank a spread's worth off its wheels until the next
## tick's solve.
func _couple_differentials(gd: GroundDriveSpec, input: VehicleInput, axle_torque: float,
		locked := PackedInt32Array(), lock_capacity := 0.0, drivetrain: Drivetrain = null) -> void:
	_coupling.fill(0.0)
	_lock_coupling.fill(0.0)
	var front_driven := _axle_driven(_front)
	var rear_driven := _axle_driven(_rear)
	var shaft_torque := axle_torque
	_drive_torque = axle_torque
	var lock_holds := false
	if not locked.is_empty() and lock_capacity > 0.0:
		# Torque the case takes off the output, split over the driven wheels like a drive torque:
		# it is what the diffs carry in P, so it sizes a biasing diff's capacity too.
		var lock := -_coupling_torque(locked, PackedInt32Array(), lock_capacity, 0.0, 0.0)
		lock_holds = absf(lock) < lock_capacity
		_share(locked, lock)
		for i in locked:
			_lock_coupling[i] = lock / locked.size()
		shaft_torque += lock
	if drivetrain != null:
		# In N or P the crank settles free and passes nothing (`Drivetrain.couple`).
		var driven := PackedInt32Array()
		for i in wheels.size():
			if wheels[i].driven:
				driven.append(i)
		# The turbine's side, read only while a converter slips.
		var held: Array = _outputs(driven) if drivetrain.converting else []
		var drive := drivetrain.couple(
				func(spin: float, compliance: float, capacity: float) -> float:
					return -_coupling_torque(driven, PackedInt32Array(), capacity, spin, compliance),
				func(torque: float) -> float:
					return Differential.settled_mean_spin(held[0], held[1], held[2], held[3],
							held[4], held[5], torque))
		_drive_torque += drive
		if drive != 0.0:
			_share(driven, drive)
			shaft_torque += drive
	var per_wheel := shaft_torque / maxf(1.0, _driven_count)
	var front_in := per_wheel * _front.size() if front_driven else 0.0
	var rear_in := per_wheel * _rear.size() if rear_driven else 0.0
	if front_driven and rear_driven:
		var centre_cap := INF if gd.centre_diff_rigid \
				else Differential.bias_capacity(shaft_torque, gd.centre_diff_bias)
		# Positive moves torque from the rear axle to the front one.
		var t := _coupling_torque(_rear, _front, centre_cap)
		if t != 0.0:
			_share(_rear, -t)
			_share(_front, t)
			rear_in -= t
			front_in += t
	if front_driven:
		_couple_axle(_front, Differential.bias_capacity(front_in, gd.diff_bias_front))
	# A lock is one rigid shaft whether or not the axle is driven this tick.
	rear_diff_locked = gd.rear_diff_lockable and input.diff_lock and _rear.size() == 2
	if rear_diff_locked:
		_couple_axle(_rear, INF)
	elif rear_driven:
		_couple_axle(_rear, Differential.bias_capacity(rear_in, gd.diff_bias_rear))
	for i in wheels.size():
		wheels[i].settle_spin(_coupling[i], _lock_coupling[i])
	if drivetrain != null:
		_report_to_controller(gd, input, drivetrain)
	# The pawl holds the whole driveline still, or none of it: one wheel turning is the lock slipping
	# or an open diff counter-rotating off it.
	if lock_holds:
		for i in locked:
			if absf(wheels[i].omega) > LOCK_STUCK_SPIN:
				return
		for i in locked:
			wheels[i].hold_by_lock()


## What the transmission controller reads off the driven wheels for its next tick: ABS holding one
## of them (`Drivetrain.abs_release`), and engine braking slipping their mean past the traction
## control's floor (`Drivetrain.drag_control`, where TC is fitted and on).
func _report_to_controller(gd: GroundDriveSpec, input: VehicleInput,
		drivetrain: Drivetrain) -> void:
	var abs_held := false
	var slip_sum := 0.0
	var n := 0
	for w in wheels:
		if w.driven:
			abs_held = abs_held or w.abs_active
			slip_sum += w.long_slip
			n += 1
	drivetrain.abs_release = abs_held
	var dir := signf(Drivetrain.ratio_for_byte(drivetrain.spec, drivetrain.gear_byte))
	drivetrain.drag_control = gd.tcs_equipped and not input.tcs_off and drivetrain.overrun \
			and n > 0 and dir * slip_sum / n < -RayWheel.TCS_SLIP


## Couple the two wheels of one axle through a diff of `capacity`; only a two-wheel axle is a
## differential.
func _couple_axle(axle: PackedInt32Array, capacity: float) -> void:
	if axle.size() != 2 or capacity <= 0.0:
		return
	var t := _coupling_torque(axle.slice(0, 1), axle.slice(1, 2), capacity)
	_coupling[axle[0]] -= t
	_coupling[axle[1]] += t


## Torque (N·m) a coupling of `capacity` moves from `side_a`'s wheels to `side_b`'s, each wheel
## entering with what the diffs passed it so far this tick and its latched holds (brake, traction
## control). A `far_spin` adds to side b one more output with that spin (rad/s) and
## `far_compliance`, which holds nothing: the gearbox case under the pawl (0, 0), or the crank
## behind its coupling (`Drivetrain.couple`).
func _coupling_torque(side_a: PackedInt32Array, side_b: PackedInt32Array, capacity: float,
		far_spin := NAN, far_compliance := 0.0) -> float:
	if capacity <= 0.0:
		return 0.0
	var outputs := _outputs(side_a + side_b)
	var omega: PackedFloat64Array = outputs[0]
	var compliance: PackedFloat64Array = outputs[1]
	var can_take: PackedFloat64Array = outputs[2]
	var stop_at: PackedFloat64Array = outputs[3]
	var tcs_share: PackedFloat64Array = outputs[4]
	var tcs_at: PackedFloat64Array = outputs[5]
	if not is_nan(far_spin):
		omega.append(far_spin)
		compliance.append(far_compliance)
		can_take.append(0.0)
		stop_at.append(0.0)
		tcs_share.append(0.0)
		tcs_at.append(0.0)
	return Differential.braked_coupling_torque(omega, compliance, can_take, stop_at, tcs_share,
			tcs_at, side_a.size(), capacity)


## The wheels at `indices` as a solve's outputs, each entering with what the diffs passed it so far
## this tick: [spin, compliance, `brake_spin`, `abs_floor`, `tcs_spin`, `tcs_ceiling`].
func _outputs(indices: PackedInt32Array) -> Array[PackedFloat64Array]:
	var omega := PackedFloat64Array()
	var compliance := PackedFloat64Array()
	var can_take := PackedFloat64Array()
	var stop_at := PackedFloat64Array()
	var tcs_share := PackedFloat64Array()
	var tcs_at := PackedFloat64Array()
	for i in indices:
		var w := wheels[i]
		omega.append(w.omega + _coupling[i] * w.spin_compliance)
		compliance.append(w.spin_compliance)
		can_take.append(w.brake_spin)
		stop_at.append(w.abs_floor)
		tcs_share.append(w.tcs_spin)
		tcs_at.append(w.tcs_ceiling)
	return [omega, compliance, can_take, stop_at, tcs_share, tcs_at]


## Torque into an axle, split equally over its wheels (the open-diff law).
func _share(axle: PackedInt32Array, torque: float) -> void:
	var share := torque / maxf(1.0, axle.size())
	for i in axle:
		_coupling[i] += share


func _axle_driven(axle: PackedInt32Array) -> bool:
	for i in axle:
		if wheels[i].driven:
			return true
	return false


## Aero plus rolling resistance, which sets top speed. Runs after the wheels tick so the normal
## load is this tick's spring reading, not `mass * g`: an airborne car resists nothing and a laden
## truck resists more for free. Inert when neither is declared.
func _apply_resistance(body: RigidBody3D, gd: GroundDriveSpec, delta: float) -> void:
	if gd.drag_area <= 0.0 and gd.rolling_resistance <= 0.0:
		return
	var normal_load := 0.0
	for w in wheels:
		normal_load += w.suspension_force
	body.apply_central_force(VehicleMath.road_resistance(body.linear_velocity, gd.drag_area,
			gd.rolling_resistance, normal_load, body.mass, delta))


## Downforce down the body's own up axis so it follows roll and pitch; applied centrally to keep
## the body's weight split. Not gated on ground contact.
func _apply_downforce(body: RigidBody3D, gd: GroundDriveSpec) -> void:
	if gd.downforce_area <= 0.0:
		return
	body.apply_central_force(-body.global_basis.y * VehicleMath.aero_downforce(
			body.linear_velocity.length(), gd.downforce_area))


## Per-axle slip telemetry; clears `ground` if any wheel is off the road.
func fill_slip(t: VehicleTelemetry) -> void:
	var slip_sum := [0.0, 0.0]
	var count := [0, 0]
	for w in wheels:
		var axle := 1 if w.is_rear else 0
		slip_sum[axle] += w.slip
		count[axle] += 1
		if not w.in_contact:
			t.ground = false
	t.slip_front = slip_sum[0] / maxi(1, count[0])
	t.slip_rear = slip_sum[1] / maxi(1, count[1])


## Rear-slip dust, scaled by rear slip, world-space so the plume stays where kicked up.
func update_dust(t: VehicleTelemetry) -> void:
	if _dust == null:
		return
	var midpoint := Vector3.ZERO
	var rear_contacts := 0
	for w in wheels:
		if w.is_rear and w.in_contact:
			midpoint += w.contact_point
			rear_contacts += 1
	var intensity := 0.0
	if rear_contacts > 0 and absf(t.speed) > DUST_MOVING:
		_dust.global_position = midpoint / rear_contacts
		intensity = clampf(
				(t.slip_rear - DUST_SLIP_MIN) / (DUST_SLIP_FULL - DUST_SLIP_MIN), 0.0, 1.0)
	_dust.emitting = intensity > 0.01
	_dust.amount_ratio = intensity


## The wheel and dust half of BaseVehicle.respawn, avoiding a suspension spike and a dust streak.
func respawn() -> void:
	_hold = Vector2.ZERO
	hill_holding = false
	_drive_torque = 0.0
	for w in wheels:
		w.reset()
	if _dust != null:
		_dust.restart()
		_dust.emitting = false


func _build_dust(gd: GroundDriveSpec) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	var half_track := 0.6  ## spans rear track width so dust reads as coming from both wheels
	for pos in gd.wheel_positions:
		if RayWheel.is_rear_z(pos.z):
			half_track = maxf(half_track, absf(pos.x))
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(half_track, 0.1, 0.25)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0.0, -1.0, 0.0)
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.scale_min = 0.35
	pm.scale_max = 0.7
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.5))
	scale_curve.add_point(Vector2(1.0, 1.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	pm.scale_curve = scale_tex
	var grad := Gradient.new()
	grad.set_color(0, Color(0.92, 0.90, 0.85, 0.5))
	grad.set_color(1, Color(0.92, 0.90, 0.85, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	pm.color_ramp = grad_tex

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot_texture()
	quad.material = mat

	var p := GPUParticles3D.new()
	p.name = "DustEmitter"
	p.local_coords = false
	p.amount = 24
	p.lifetime = 0.9
	p.process_material = pm
	p.draw_pass_1 = quad
	p.emitting = false
	p.amount_ratio = 0.0
	return p


## Soft round alpha mask (radial white to transparent) so dust quads read as puffs, not squares.
func _soft_dot_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex

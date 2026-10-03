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

var wheels: Array[RayWheel] = []
## Rear diff state as actually run this tick, not the request bit; `diff_lock_state` reads this.
var rear_diff_locked := false
## Retarder torque actually applied this tick (Nm), summed over driven rear wheels.
var retarder_torque_applied := 0.0

var _applied_steer := 0.0  ## steer angle applied to steered wheels this tick (rad)
var _driven_count := 0     ## driven wheels as drive_omega() counted them THIS tick
var _dust: GPUParticles3D  ## rear-slip dust; null until build_dust(), and on a drive with no wheels
## The wheels of each axle, split once by `RayWheel.is_rear`: the differentials couple within and
## between these. Whether an axle is DRIVEN is read per tick (MFWD engages at runtime).
var _front: Array[RayWheel] = []
var _rear: Array[RayWheel] = []
## Front-to-rear anchor distance (m), body space; 0 if the spec declares no front/rear pair
## (never happens for a real wheeled body). Cached once in _init since wheel_positions is data.
var _wheelbase := 0.0
## Full-pedal foot-brake torque at one front / rear wheel (`GroundDriveSpec.axle_brake_torque`),
## cached in _init like the wheelbase.
var _brake_front := 0.0
var _brake_rear := 0.0


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
		wheels.append(wheel)
		if wheel.is_rear:
			_rear.append(wheel)
		else:
			_front.append(wheel)
	if gd.anti_roll_rate > 0.0:
		RayWheel.pair_axles(wheels)
	_wheelbase = _compute_wheelbase()
	_brake_front = gd.axle_brake_torque(false)
	_brake_rear = gd.axle_brake_torque(true)


## Re-share the body's LIVE mass over the corners. The three one-tick RayWheel clamps are sized
## off `corner_mass`, so BaseVehicle.set_live_mass (the refuse truck's hopper) calls this, or the
## clamps stay sized for the empty vehicle and bite on forces the laden body legitimately makes.
func set_corner_mass_from(live_mass: float) -> void:
	var corner_mass := live_mass / maxf(1.0, wheels.size())
	for w in wheels:
		w.corner_mass = corner_mass


## Wheel-slip dust, built separately so the emitter keeps its place in the body's child order.
func build_dust(body: Node3D, gd: GroundDriveSpec) -> void:
	if gd.wheel_positions.is_empty():
		return
	_dust = _build_dust(gd)
	body.add_child(_dust)


## Mean spin speed of the driven wheels, which the drivetrain uses for gear pick and torque-curve
## placement. Called before Drivetrain.process; the driven count latched here is reused by tick()
## for the torque split.
func drive_omega(gd: GroundDriveSpec, input: VehicleInput) -> float:
	# MFWD: the tractor front axle engages at runtime, so `driven` is not fixed at _ready. The foot
	# brake engages it too where declared: the rigid shaft then carries the rear brakes' torque to
	# the front wheels (`_couple_differentials`).
	if gd.front_axle_engageable:
		var braking := gd.brake_engages_front_axle and input.brake > 0.0
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
## the wheel loop; the differentials write omega off each wheel's step, so they must follow spin
## integration.
func tick(body: RigidBody3D, spec: VehicleSpec, input: VehicleInput, steer: float,
		axle_torque: float, ground_speed: float, delta: float,
		grip_terrains: Array[Node]) -> void:
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
	# One anti-roll snapshot for the whole body before any wheel ticks (`RayWheel.anti_roll_partner`).
	for w in wheels:
		w.latch_bar()
	# Traction control rides the drive alone; the bridge may switch it off (`tcs_off`).
	var tcs_slip := RayWheel.TCS_SLIP if gd.tcs_equipped and not input.tcs_off else 0.0
	for w in wheels:
		w.steer_angle = _applied_steer if w.steered else 0.0
		# The nominal equal split (open-diff law); `_couple_differentials` adds what a biasing,
		# locked or rigid diff moves on top, once every wheel has integrated.
		var drive_t := axle_torque / _driven_count if w.driven else 0.0
		var brake_t := input.brake * (_brake_rear if w.is_rear else _brake_front)
		# Anti-lock rides the foot brake and the retarder; a handbrake is a mechanical hold no ABS
		# modulates, so a rear wheel under it brakes without.
		var abs_slip := RayWheel.ABS_SLIP if gd.abs_equipped else 0.0
		if w.is_rear:
			brake_t += input.handbrake * gd.handbrake_torque
			w.lat_grip_scale = lerpf(1.0, gd.handbrake_grip, input.handbrake)
			if input.handbrake > 0.0:
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
						input.retarder, ground_speed, w.omega, gd, compliance)
				brake_t += ret
				retarder_torque_applied += ret
		w.tick(body, gd, space, drive_t, brake_t, delta, grip_terrains, abs_slip,
				tcs_slip if w.driven else 0.0)

	_couple_differentials(gd, input, axle_torque)
	_apply_resistance(body, gd, delta)
	_apply_downforce(body, gd)


## The declared differentials, as coupling torques solved off each wheel's own spin step
## (`Differential`, `RayWheel.spin_compliance`). One pass: the centre first, whenever both axles are
## driven (rigid for MFWD, else `centre_diff_bias`), its torque reaching an axle's wheels equally;
## then each axle, capacity sized off the torque it actually received, unbounded on the rear while
## the diff lock is held. All open is a no-op.
func _couple_differentials(gd: GroundDriveSpec, input: VehicleInput, axle_torque: float) -> void:
	var front_driven := _axle_driven(_front)
	var rear_driven := _axle_driven(_rear)
	var per_wheel := axle_torque / maxf(1.0, _driven_count)
	var front_in := per_wheel * _front.size() if front_driven else 0.0
	var rear_in := per_wheel * _rear.size() if rear_driven else 0.0
	if front_driven and rear_driven:
		var centre_cap := INF if gd.centre_diff_rigid \
				else Differential.bias_capacity(axle_torque, gd.centre_diff_bias)
		# Positive moves torque from the rear axle to the front one.
		var t := Differential.coupling_torque(_mean_omega(_rear), _mean_omega(_front),
				_axle_compliance(_rear), _axle_compliance(_front), centre_cap)
		if t != 0.0:
			_apply_axle_torque(_rear, -t)
			_apply_axle_torque(_front, t)
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


## Couple the two wheels of one axle through a diff of `capacity`; only a two-wheel axle is a
## differential.
static func _couple_axle(axle: Array[RayWheel], capacity: float) -> void:
	if axle.size() != 2 or capacity <= 0.0:
		return
	var a := axle[0]
	var b := axle[1]
	var t := Differential.coupling_torque(a.omega, b.omega, a.spin_compliance,
			b.spin_compliance, capacity)
	a.omega -= t * a.spin_compliance
	b.omega += t * b.spin_compliance


static func _axle_driven(axle: Array[RayWheel]) -> bool:
	for w in axle:
		if w.driven:
			return true
	return false


static func _mean_omega(axle: Array[RayWheel]) -> float:
	var sum := 0.0
	for w in axle:
		sum += w.omega
	return sum / maxf(1.0, axle.size())


## Change in the axle's MEAN spin per N·m into the axle: the torque splits equally over its wheels
## (`torque / n` each), so the mean moves by `torque * sum(compliance) / n^2`.
static func _axle_compliance(axle: Array[RayWheel]) -> float:
	var sum := 0.0
	for w in axle:
		sum += w.spin_compliance
	var n := maxf(1.0, axle.size())
	return sum / (n * n)


## Torque into an axle, split equally over its wheels and applied off each wheel's own step.
static func _apply_axle_torque(axle: Array[RayWheel], torque: float) -> void:
	var share := torque / maxf(1.0, axle.size())
	for w in axle:
		w.omega += share * w.spin_compliance


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

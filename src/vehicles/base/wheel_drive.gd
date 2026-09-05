class_name WheelDrive
extends RefCounted
## The wheeled ground drive: RayWheels, visuals, torque split, brakes, diff lock, resistance,
## downforce, slip telemetry and wheel-slip dust. Owned and ticked by BaseVehicle like Drivetrain,
## a RefCounted rather than a child node since wheel positions are spec data. Data lives on
## `spec.ground_drive`; `steer_speed` stays on the core spec since it also slews a rudder and yaw.

const WHEEL_VISUAL_NAMES: PackedStringArray = ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]

## Wheel-slip dust emitter, built in code (no scene, no re-bake).
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


## Build the wheels and their visuals.
func _init(body: Node3D, spec: VehicleSpec) -> void:
	var gd := spec.ground_drive
	# Static per-corner mass share, from the spec's mass rather than the body's laden mass.
	var corner_mass := spec.mass / maxf(1.0, gd.wheel_positions.size())
	for i in gd.wheel_positions.size():
		var pos := gd.wheel_positions[i]
		var front := pos.z < 0.0
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
				# Radius-normalized model, scaled to vis_radius; right wheels flip to face out,
				# since the rim is on one face. The flip is Vector3.RIGHT, not UP: local Y is the
				# axle in RayWheel's root basis, so a yaw there just spins the wheel about it.
				# Flip and scale ride the child; RayWheel overwrites the root transform each tick.
				for child in visual.get_children():
					if child is Node3D:
						var b := (child as Node3D).basis.scaled(Vector3.ONE * vis_radius)
						(child as Node3D).basis = Basis(Vector3.RIGHT, PI) * b if pos.x > 0.0 else b
				body.add_child(visual)
		var wheel := RayWheel.new(pos, front, driven, visual, corner_mass)
		wheel.visual_lift = vis_radius - gd.wheel_radius
		wheels.append(wheel)


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
	# MFWD: the tractor front axle engages at runtime, so `driven` is not fixed at _ready.
	if gd.front_axle_engageable:
		for w in wheels:
			if not w.is_rear:
				w.driven = input.fwd_drive or gd.driven_front  ## can only ADD drive

	_driven_count = 0
	var omega := 0.0
	for w in wheels:
		if w.driven:
			_driven_count += 1
			omega += w.omega
	return omega / maxf(1.0, _driven_count)


## Statement order is load-bearing: resistance reads this tick's spring load so it must follow
## the wheel loop; the diff lock writes omega so it must follow spin integration.
func tick(body: RigidBody3D, spec: VehicleSpec, input: VehicleInput, steer: float,
		axle_torque: float, ground_speed: float, delta: float,
		grip_terrains: Array[Node]) -> void:
	var gd := spec.ground_drive
	# High-speed steering falloff (min_steer_frac == 1.0 disables it).
	var steer_falloff := 1.0
	if gd.steer_falloff_speed > 0.0:
		steer_falloff = lerpf(1.0, gd.min_steer_frac,
				clampf(absf(ground_speed) / gd.steer_falloff_speed, 0.0, 1.0))
	_applied_steer = -steer * deg_to_rad(gd.max_steer_deg * steer_falloff)

	var space := body.get_world_3d().direct_space_state
	retarder_torque_applied = 0.0
	for w in wheels:
		w.steer_angle = _applied_steer if w.steered else 0.0
		var drive_t := axle_torque / _driven_count if w.driven else 0.0
		var brake_t := input.brake * gd.brake_torque
		if w.is_rear:
			brake_t += input.handbrake * gd.handbrake_torque
			w.lat_grip_scale = lerpf(1.0, gd.handbrake_grip, input.handbrake)
			# Retarder (truck only): a brake on the driven axle, never a separate model.
			if gd.retarder_equipped and w.driven:
				var ret := Drivetrain.retarder_torque(
						input.retarder, ground_speed, w.omega, gd, delta)
				brake_t += ret
				retarder_torque_applied += ret
		w.tick(body, gd, space, drive_t, brake_t, delta, grip_terrains)

	_lock_rear_diff(gd, input)
	_apply_resistance(body, gd, delta)
	_apply_downforce(body, gd)


## Rear diff lock (tractor only): a locked diff is one rigid shaft, so pull the rear pair onto a
## common omega after spin integration. Sharing a slip ratio, the grippy wheel pulls.
func _lock_rear_diff(gd: GroundDriveSpec, input: VehicleInput) -> void:
	rear_diff_locked = false
	if not (gd.rear_diff_lockable and input.diff_lock):
		return
	var rear: Array[RayWheel] = []
	for w in wheels:
		if w.is_rear:
			rear.append(w)
	if rear.size() != 2:  ## only a two-wheel axle is a differential
		return
	var shared := Drivetrain.locked_axle_omega(rear[0].omega, rear[1].omega)
	rear[0].omega = shared
	rear[1].omega = shared
	rear_diff_locked = true


## Aero plus rolling resistance, which sets top speed. Runs after the wheels tick so the normal
## load is this tick's spring reading. Rolling resistance reads off the springs, not `mass * g`,
## so a jumped car resists nothing airborne and a laden truck resists more for free. Aero ignores
## mass, so a towed body's own drag area is what a 32 t rig pays. Inert when neither is declared.
func _apply_resistance(body: RigidBody3D, gd: GroundDriveSpec, delta: float) -> void:
	if gd.drag_area <= 0.0 and gd.rolling_resistance <= 0.0:
		return
	var normal_load := 0.0
	for w in wheels:
		normal_load += w.suspension_force
	body.apply_central_force(VehicleMath.road_resistance(body.linear_velocity, gd.drag_area,
			gd.rolling_resistance, normal_load, body.mass, delta))


## Downforce, applied down the body's own up axis so it follows roll and pitch, and never a grip
## multiplier: it compresses the springs and grip follows, at the cost of ride height and
## resistance. Applied centrally so it keeps the body's existing weight split. Not gated on ground
## contact, since a wing pushes down in the air too.
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
		if pos.z > 0.0:
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

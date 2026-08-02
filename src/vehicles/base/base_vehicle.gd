class_name BaseVehicle
extends RigidBody3D
## Vehicle base: consumes one normalized VehicleInput from InputRouter
## (never reads input sources itself), runs the raycast wheels and
## drivetrain, and publishes VehicleTelemetry each physics tick. Spawn/respawn and
## the camera target are part of this base contract. All tuning lives in `spec`.

signal respawned

const WHEEL_VISUAL_NAMES: PackedStringArray = ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]
const FALL_RESPAWN_Y := -20.0

## Telemetry derivation tuning: kept out of VehicleSpec — these are the
## same for every vehicle, not feel knobs.
const ACCEL_SMOOTH := 10.0      ## 1/s exp rate the reported long/lat accel tracks raw
const COOLANT_RATE := 2.0       ## degC/s the coolant chases its steady-state target
const IMPACT_THRESHOLD := 25.0  ## m/s^2 acceleration spike that counts as an impact
const IMPACT_DECAY := 40.0      ## m/s^2 per s the held impact value bleeds off
const MOVING_SPEED := 0.3       ## m/s standstill epsilon for the status 'moving' bit

## Wheel-slip dust: one world-space GPUParticles3D emitter kicked up from the rear
## contact patch when the rear tires break traction (drift/burnout/hard accel). All feel-
## neutral cosmetics — built in code so it touches no scene and needs no re-bake.
const DUST_SLIP_MIN := 0.2      ## rear slip ratio where dust starts
const DUST_SLIP_FULL := 0.6     ## rear slip ratio for full emission
const DUST_MOVING := 1.0        ## m/s below which dust is suppressed (idle burnout stays clean)

## Stand-in road drag for wheel-driven chassis, replacing the engine default of 0.1 —
## see the DIRTY note in _ready and the aero item in docs/TODO.md. Chosen so the default
## car tops out around 230 km/h, which is past the 5th->6th upshift, rather than 128 km/h.
const ROAD_LINEAR_DAMP := 0.033

@export var spec: VehicleSpec

## This body exists to be LOOKED AT, not driven — the vehicle selector's preview viewport and
## the thumbnail tool. Set BEFORE it enters the tree (the Level.initial_variant pattern), since
## _ready is what acts on it. It does exactly one thing: skip InputRouter registration.
## `register_vehicle` is a plain assignment, so a preview body would silently take the driven
## body's slot in local reverse arbitration — and null it again on its way out.
var display_only := false

var drivetrain: Drivetrain
var wheels: Array[RayWheel] = []
var telemetry: VehicleTelemetry  ## built in _ready via _make_telemetry (subclasses override the type)
var spawn_transform: Transform3D
## Rear differential state as the DRIVELINE actually ran it this tick (not the request bit) —
## the tractor's diff_lock_state signal is read from here. Always false without
## spec.rear_diff_lockable, so every other vehicle publishes/behaves exactly as before.
var rear_diff_locked := false
## Auxiliary retarder torque the driveline actually applied this tick, summed over the driven
## rear wheels (Nm) — the truck's retarder_state signal is read from here, so it reports what
## ran rather than echoing the request. Always 0 without spec.retarder_equipped.
var retarder_torque_applied := 0.0

var _steer := 0.0
var _applied_steer := 0.0  ## steer angle applied to steered wheels this tick (rad); read by visual-only subclasses (bike)
var _grip_terrains: Array[Node] = []  ## painted terrains the wheels sample for surface grip
var _terrains_found := false           ## one-shot guard for the terrain scan below
var _prev_velocity := Vector3.ZERO  ## last tick's linear_velocity, for accel/impact
var _impact_hold := 0.0             ## decaying peak of the impact magnitude
var _lamps := LampSet.new()         ## drives the scene-authored §6 lamps from input
var _horn_player: AudioStreamPlayer ## procedural horn, played on the horn rising edge
var _prev_horn := false
var _dust: GPUParticles3D            ## rear-slip dust; null on wheel-less vehicles (boat, train)


func _ready() -> void:
	telemetry = _make_telemetry()
	mass = spec.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = spec.center_of_mass
	can_sleep = false
	# Continuous CD on every chassis: a body coming down hard (ramp jump, dive, free
	# fall) can otherwise cross the thin terrain collision in one 60 Hz tick and tunnel
	# through. The RayWheels are raycasts and unaffected; only one vehicle is active at a
	# time, so the CCD cost is negligible.
	continuous_cd = true
	# DIRTY, TEMPORARY — remove with the aero item in docs/TODO.md. There is no drag model
	# anywhere in this folder, so what actually sets every wheeled vehicle's top speed is
	# Godot's DEFAULT linear damp (physics/3d/default_linear_damp = 0.1), which nobody chose.
	# It is linear in v where real aero is quadratic, and ~8x too strong at 35 m/s: the car
	# stalls at 128 km/h in 4th at 4752 rpm, below shift_up_rpm, so gears 5 and 6 can never
	# engage. Until an honest aero + rolling-resistance model lands this is a flat reduced
	# constant. Only WHEEL-DRIVEN chassis (car / truck / tractor / bike) are touched — the
	# boat, drone and plane run their own drag through VehicleMath, and the train is railed.
	# The bikes are excluded, and `angular_damping > 0` is the bike discriminator (it is set
	# on nothing else — see the stability-assist block just below). At 260 kg they were the
	# one family the default damp was holding to a sane number: reducing it takes them from
	# 175 to 314 km/h. Another reason this whole block is a stand-in and not a model.
	if (spec.driven_front or spec.driven_rear) and spec.angular_damping <= 0.0:
		linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		linear_damp = ROAD_LINEAR_DAMP
	# Stability-assist yaw/roll bleed (bikes only; 0 leaves the engine default untouched).
	if spec.angular_damping > 0.0:
		angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		angular_damp = spec.angular_damping
	drivetrain = Drivetrain.new(spec)
	for i in spec.wheel_positions.size():
		var pos := spec.wheel_positions[i]
		var front := pos.z < 0.0
		var driven := (front and spec.driven_front) or (not front and spec.driven_rear)
		var visual: Node3D = null
		# Rendered radius for this corner (visual only — physics stays spec.wheel_radius).
		var vis_radius := spec.wheel_radius
		if not front and spec.wheel_visual_radius_rear > 0.0:
			vis_radius = spec.wheel_visual_radius_rear
		elif spec.wheel_visual_radius > 0.0:
			vis_radius = spec.wheel_visual_radius
		if i < WHEEL_VISUAL_NAMES.size():
			visual = get_node_or_null(NodePath(WHEEL_VISUAL_NAMES[i]))
			# No authored wheel mesh but the spec ships one (Kenney wheel wrapper): instance
			# it under the expected name at the anchor. RayWheel then drives its transform.
			var scene: PackedScene = spec.wheel_scene
			if not front and spec.wheel_scene_rear != null:
				scene = spec.wheel_scene_rear
			if visual == null and scene != null:
				visual = scene.instantiate()
				visual.name = WHEEL_VISUAL_NAMES[i]
				# Wheel scenes are radius-normalized, so the instance is scaled to vis_radius.
				# The model is also asymmetric (rim on one face, and unmirrored it faces body
				# -X): turn the RIGHT wheels around so every rim faces out. The flip axis is
				# Vector3.RIGHT, not UP — RayWheel's root basis maps the wheel's local X to
				# world up and its local Y to the AXLE, so a 180deg yaw here would just spin
				# the wheel about its own axle (invisible). Both the flip and the scale ride
				# the child: RayWheel overwrites the root transform every tick, not children.
				for child in visual.get_children():
					if child is Node3D:
						var b := (child as Node3D).basis.scaled(Vector3.ONE * vis_radius)
						(child as Node3D).basis = Basis(Vector3.RIGHT, PI) * b if pos.x > 0.0 else b
				add_child(visual)
		var wheel := RayWheel.new(pos, front, driven, visual)
		wheel.visual_lift = vis_radius - spec.wheel_radius
		wheels.append(wheel)
	spawn_transform = global_transform
	_prev_velocity = linear_velocity
	_lamps.setup(self, spec)
	_horn_player = AudioStreamPlayer.new()
	_horn_player.stream = Horn.make_stream()
	add_child(_horn_player)
	# Wheel-slip dust: only wheeled vehicles get an emitter (boat/train have no wheels).
	if not spec.wheel_positions.is_empty():
		_dust = _build_dust()
		add_child(_dust)
	if not display_only:
		InputRouter.register_vehicle(self)


func _exit_tree() -> void:
	InputRouter.unregister_vehicle(self)


func _physics_process(delta: float) -> void:
	var input := InputRouter.get_vehicle_input()
	_steer = move_toward(_steer, input.steer, spec.steer_speed * delta)

	# MFWD: the tractor's front axle is engaged at runtime, so `driven` is not fixed at _ready
	# the way spec.driven_front leaves it for everyone else. Done here, ahead of the count
	# below, so the torque split and the drivetrain's drive_omega both see this tick's axles.
	if spec.front_axle_engageable:
		for w in wheels:
			if not w.is_rear:
				# `or spec.driven_front` so engageability can only ADD drive: a spec that
				# declares a permanently driven front axle keeps it when MFWD is out.
				w.driven = input.fwd_drive or spec.driven_front

	var driven_count := 0
	var drive_omega := 0.0
	for w in wheels:
		if w.driven:
			driven_count += 1
			drive_omega += w.omega
	drive_omega /= maxf(1.0, driven_count)

	var ground_speed := linear_velocity.dot(-global_transform.basis.z)
	var axle_torque := drivetrain.process(
			delta, absf(input.throttle), drive_omega, ground_speed, input.gear_request, input.gear_auto)

	# Discover the level's painted terrains once — the level and its terrain siblings are
	# guaranteed in-tree by the first physics tick. Wheels sample these for surface grip.
	if not _terrains_found:
		_grip_terrains = _find_grip_terrains()
		_terrains_found = true

	# High-speed steering falloff: shrink usable lock as speed rises (min_steer_frac == 1.0
	# disables it — the default for every vehicle except the bikes).
	var steer_falloff := 1.0
	if spec.steer_falloff_speed > 0.0:
		steer_falloff = lerpf(1.0, spec.min_steer_frac,
				clampf(absf(ground_speed) / spec.steer_falloff_speed, 0.0, 1.0))
	_applied_steer = -_steer * deg_to_rad(spec.max_steer_deg * steer_falloff)

	var space := get_world_3d().direct_space_state
	retarder_torque_applied = 0.0
	for w in wheels:
		w.steer_angle = _applied_steer if w.steered else 0.0
		var drive_t := axle_torque / driven_count if w.driven else 0.0
		var brake_t := input.brake * spec.brake_torque
		if w.is_rear:
			brake_t += input.handbrake * spec.handbrake_torque
			w.lat_grip_scale = lerpf(1.0, spec.handbrake_grip, input.handbrake)
			# Auxiliary driveline retarder (truck only — spec.retarder_equipped is false
			# everywhere else, so the 'retarder' input bit is inert on every other vehicle).
			# It is a brake on the DRIVEN axle, so it goes in with the other brake torques and
			# RayWheel integrates it exactly like them: no second brake model, and no explicit
			# step outside the stabilized integrator. See Drivetrain's retarder block for why
			# that placement is load-bearing rather than tidy.
			if spec.retarder_equipped and w.driven:
				var ret := Drivetrain.retarder_torque(
						input.retarder, ground_speed, w.omega, spec, delta)
				brake_t += ret
				retarder_torque_applied += ret
		w.tick(self, spec, space, drive_t, brake_t, delta, _grip_terrains)

	_lock_rear_diff(input)
	_update_telemetry(input, delta)
	_lamps.apply(input.brake_lamp, input.lights, input.turn_left, input.turn_right)
	# Horn honks on the rising edge and holds while pressed — source-agnostic (the bit
	# is set by whichever source owns input this tick).
	if input.horn and not _prev_horn:
		_horn_player.play()
	elif not input.horn and _prev_horn:
		_horn_player.stop()
	_prev_horn = input.horn
	_update_dust()

	# Subsystem hook, run last so the drivetrain rpm and telemetry motion fields a
	# subclass reads are already current this tick (empty in the base — see below).
	_tick_extras(input, delta)

	if global_position.y < FALL_RESPAWN_Y:
		respawn()


## Rear differential lock (tractor only — spec.rear_diff_lockable is false everywhere else).
## A locked diff is one rigid shaft, so its wheels cannot turn at different speeds: run after
## the wheels have integrated their spin and pull the rear pair onto a common omega. Sharing a
## spin speed makes them share a SLIP RATIO, so each wheel's force falls out of its own
## mu * N — the wheel with grip does the pulling, which is the whole point of a diff lock.
## Unlocked, nothing happens here: the equal per-wheel torque split above is already the open
## differential's torque law, and the wheels are free to spin at their own speeds.
func _lock_rear_diff(input: InputRouter.VehicleInput) -> void:
	rear_diff_locked = false
	if not (spec.rear_diff_lockable and input.diff_lock):
		return
	var rear: Array[RayWheel] = []
	for w in wheels:
		if w.is_rear:
			rear.append(w)
	# Only a two-wheel axle is a differential; anything else has no pair to couple — and the
	# state flag stays false in that case, because nothing was actually locked. diff_lock_state
	# reports the driveline, so it may never be set before the coupling has happened.
	if rear.size() != 2:
		return
	var shared := Drivetrain.locked_axle_omega(rear[0].omega, rear[1].omega)
	rear[0].omega = shared
	rear[1].omega = shared
	rear_diff_locked = true


## Telemetry factory (subclass seam): the base publishes the plain struct; a subclass
## with extra "out" fields (e.g. the tractor's ISOBUS signals) returns its own subclass.
func _make_telemetry() -> VehicleTelemetry:
	return VehicleTelemetry.new()


## Per-tick subsystem hook (subclass seam): empty in the base, run at the end of
## _physics_process. Subclasses (tractor hitch/PTO) do their per-tick work here so they
## never fork _physics_process / _update_telemetry.
func _tick_extras(_input: InputRouter.VehicleInput, _delta: float) -> void:
	pass


## What this machine can do that not every machine can, for the shell's control gating — the
## touch overlay's buttons and the pause menu's CONTROLS sheet, both driven by ActionRegistry.
## Duck-typed like cycle_implement / attachment_controls, so boot.gd asks without knowing what
## kind of vehicle answered.
##
## Read off the SAME spec flags that gate the behaviour in _physics_process (diff lock at
## _lock_rear_diff, MFWD in the driven-wheel loop), never a second declaration beside them — a
## control must not be offered on a machine the flag makes inert. Subclasses add what their own
## anatomy declares; see TruckVehicle for the refuse body.
func vehicle_capabilities() -> Dictionary:
	return {
		"diff_lock": spec != null and spec.rear_diff_lockable,
		"fwd_drive": spec != null and spec.front_axle_engageable,
	}


## Drive the rear-slip dust emitter: emit from the rear contact patch, scaled by how hard
## the rear tires are slipping, while moving and grounded. World-space particles so the
## plume stays where it was kicked up. No-op on wheel-less vehicles (_dust is null).
func _update_dust() -> void:
	if _dust == null:
		return
	var midpoint := Vector3.ZERO
	var rear_contacts := 0
	for w in wheels:
		if w.is_rear and w.in_contact:
			midpoint += w.contact_point
			rear_contacts += 1
	var intensity := 0.0
	if rear_contacts > 0 and absf(telemetry.speed) > DUST_MOVING:
		_dust.global_position = midpoint / rear_contacts
		intensity = clampf(
				(telemetry.slip_rear - DUST_SLIP_MIN) / (DUST_SLIP_FULL - DUST_SLIP_MIN), 0.0, 1.0)
	_dust.emitting = intensity > 0.01
	_dust.amount_ratio = intensity


## Build the dust emitter entirely in code (no scene asset, so nothing to re-bake): a
## world-space GPUParticles3D drawing soft billboarded tan puffs that rise, grow and fade.
func _build_dust() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	# Spawn across the rear track width (not one central point) so the dust reads as coming
	# from both wheels. The emitter's basis follows the car, so local X = the car's lateral
	# axis; a little Z depth gives the wake some length instead of a razor line.
	var half_track := 0.6
	for pos in spec.wheel_positions:
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
	# Grow over life.
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.5))
	scale_curve.add_point(Vector2(1.0, 1.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	pm.scale_curve = scale_tex
	# Pale off-white dust, fading to transparent.
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


## Soft round alpha mask (radial white->transparent) so the dust quads read as puffs, not
## squares. Generated in code, no image asset.
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


## Collect the painted terrains under the owning level for the wheels' surface-grip query.
## Walks up to the level (duck-typed by set_vehicle) then scans its subtree for the terrain
## contract (grip_at + contains_xz + height_at) — no HeightmapTerrain / Level type dependency.
func _find_grip_terrains() -> Array[Node]:
	var out: Array[Node] = []
	var root := get_parent()
	while root != null and not root.has_method("set_vehicle"):
		root = root.get_parent()
	if root == null:
		# Not under a Level (a test rig / dev fixture): scan from the outermost ancestor below
		# the SceneTree root, so a terrain that is a SIBLING of the vehicle's parent — the
		# usual rig layout — is found rather than silently missed.
		root = self
		while root.get_parent() != null and root.get_parent() != get_tree().root:
			root = root.get_parent()
	_collect_grip_terrains(root, out)
	return out


static func _collect_grip_terrains(node: Node, out: Array[Node]) -> void:
	if node.has_method("grip_at") and node.has_method("contains_xz") \
			and node.has_method("height_at"):
		out.append(node)
	for child in node.get_children():
		_collect_grip_terrains(child, out)


func _update_telemetry(input: InputRouter.VehicleInput, delta: float) -> void:
	var xform := global_transform
	var forward := -xform.basis.z
	var up := xform.basis.y

	# Motion read straight out of the sim.
	telemetry.speed = linear_velocity.dot(forward)
	telemetry.kmh = absf(telemetry.speed) * 3.6
	telemetry.rpm = drivetrain.rpm
	telemetry.gear_byte = drivetrain.gear_byte
	telemetry.throttle = input.throttle
	telemetry.steer = _steer
	telemetry.yaw = angular_velocity.dot(up)

	var accel := VehicleTelemetry.body_accel(
			linear_velocity, _prev_velocity, delta, forward, xform.basis.x)
	var s := 1.0 - exp(-ACCEL_SMOOTH * delta)
	telemetry.acc_long = lerpf(telemetry.acc_long, accel.x, s)
	telemetry.acc_lat = lerpf(telemetry.acc_lat, accel.y, s)

	telemetry.ground = true
	var slip_sum := [0.0, 0.0]
	var count := [0, 0]
	for w in wheels:
		var axle := 1 if w.is_rear else 0
		slip_sum[axle] += w.slip
		count[axle] += 1
		if not w.in_contact:
			telemetry.ground = false
	telemetry.slip_front = slip_sum[0] / maxi(1, count[0])
	telemetry.slip_rear = slip_sum[1] / maxi(1, count[1])

	# Navigation: raw position, GPS mapping, compass heading, odometer.
	telemetry.pos_x = global_position.x
	telemetry.pos_z = global_position.z
	telemetry.lat = VehicleTelemetry.gps_lat(global_position.z)
	telemetry.lon = VehicleTelemetry.gps_lon(global_position.x)
	telemetry.heading = VehicleTelemetry.heading_from_forward(forward)
	telemetry.odo = VehicleTelemetry.odo_step(telemetry.odo, telemetry.speed, delta)

	# Auxiliary systems (modeled): fuel/coolant/battery keyed off ignition + load.
	var running := input.key == InputRouter.KEY_IGNITION
	var load_frac := clampf(absf(input.throttle), 0.0, 1.0)
	telemetry.fuel = VehicleTelemetry.fuel_step(telemetry.fuel, load_frac, running, delta)
	telemetry.coolant = VehicleTelemetry.coolant_step(
			telemetry.coolant, VehicleTelemetry.coolant_target(running, load_frac), COOLANT_RATE, delta)
	telemetry.battery = VehicleTelemetry.battery_volts(running, load_frac)

	# Impact: gate the raw acceleration spike, then peak-hold with decay so a
	# one-tick collision stays readable on the dash / bridge.
	var accel_mag := ((linear_velocity - _prev_velocity) / maxf(delta, 1e-5)).length()
	_impact_hold = maxf(
			VehicleTelemetry.impact_gate(accel_mag, IMPACT_THRESHOLD),
			move_toward(_impact_hold, 0.0, IMPACT_DECAY * delta))
	telemetry.impact = _impact_hold

	telemetry.status = VehicleTelemetry.pack_status(
			running, telemetry.ground, absf(telemetry.speed) > MOVING_SPEED,
			telemetry.gear_byte, input.handbrake > 0.0, input.lights >= 3)

	_prev_velocity = linear_velocity


## Reset to the last spawn transform with zeroed motion. Also fired automatically
## when the vehicle falls off the world.
func respawn() -> void:
	global_transform = spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_steer = 0.0
	# Zero the accel/impact history so the teleport isn't read as a huge Δv spike.
	_prev_velocity = Vector3.ZERO
	_impact_hold = 0.0
	telemetry.acc_long = 0.0
	telemetry.acc_lat = 0.0
	for w in wheels:
		w.reset()
	# Clear any live dust so the teleport doesn't streak a plume across the map.
	if _dust != null:
		_dust.restart()
		_dust.emitting = false
	reset_physics_interpolation()
	respawned.emit()


func get_camera_target() -> Node3D:
	return self


## Physics bodies the chase camera's occlusion ray must ignore — itself, plus any sub-bodies a
## multi-body vehicle owns (the train's wagons trail right behind the loco, so without this the
## occlusion pull-in slams the camera into the first wagon). Single-chassis vehicles are just self.
func get_camera_exclude_bodies() -> Array[RID]:
	return [get_rid()]


## Optional chase-camera framing override {distance, height, look_height, top_height, iso_size}.
## Empty = use the level camera's authored values (every wheeled vehicle). A long vehicle (the
## consist) returns bigger values so CHASE/ISO/TOP clear the whole train instead of burying the
## camera in a wagon. Read per frame by ChaseCamera, so a garage swap re-frames immediately.
func get_camera_framing() -> Dictionary:
	return {}


## Read by InputRouter for arbitration (local brake-vs-reverse); vehicles otherwise
## never talk to the router beyond register/consume.
func get_speed() -> float:
	return telemetry.speed


func get_gear_byte() -> int:
	return drivetrain.gear_byte if drivetrain != null else Drivetrain.GEAR_N

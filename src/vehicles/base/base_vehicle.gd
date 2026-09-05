class_name BaseVehicle
extends RigidBody3D
## Vehicle base, family-agnostic: consumes one normalized VehicleInput from InputRouter, slews
## the steer axis, runs the drivetrain, and publishes VehicleTelemetry each tick. Spawn/respawn
## and the camera target are part of this base contract. `spec` is not the whole of a vehicle's
## tuning: a free body (boat/drone/plane) declares hull, airframe and aero `@export`s on its own
## node.
##
## The wheeled ground drive is a composed sibling (`drive`, a WheelDrive). Drivetrain stays here
## because every family consumes its gear byte and applied_throttle.

signal respawned

const Groups := preload("res://src/levels/base/carlito_groups.gd")
const Layers := preload("res://src/physics/collision_layers.gd")
const FALL_RESPAWN_Y := -20.0

## Returned by `wheels` when there is no ground drive, so callers avoid a null check.
const EMPTY_WHEELS: Array[RayWheel] = []

## Telemetry derivation tuning, the same for every vehicle. Not feel knobs, so off VehicleSpec.
const ACCEL_SMOOTH := 10.0      ## 1/s exp rate the reported long/lat accel tracks raw
const COOLANT_RATE := 2.0       ## degC/s the coolant chases its steady-state target
const IMPACT_THRESHOLD := 25.0  ## m/s^2 acceleration spike that counts as an impact
const IMPACT_DECAY := 40.0      ## m/s^2 per s the held impact value bleeds off
const MOVING_SPEED := 0.3       ## m/s standstill epsilon for the status 'moving' bit

@export var spec: VehicleSpec

## Preview-only body (vehicle selector, thumbnail tool). Set before entering the tree, so _ready
## skips InputRouter registration; otherwise a preview steals the driven body's slot.
var display_only := false

var drivetrain: Drivetrain
var drive: WheelDrive            ## the wheeled ground drive, or null on a spec that declares none
var telemetry: VehicleTelemetry  ## built in _ready via _make_telemetry (subclasses override the type)
var spawn_transform: Transform3D

## Forwarding views of the ground drive's state; the truck retarder and spring brake, the
## tractor's diff lock and MFWD, the debug overlay and measure_vehicles all read them here.
var wheels: Array[RayWheel]:
	get: return drive.wheels if drive != null else EMPTY_WHEELS
var rear_diff_locked: bool:
	get: return drive.rear_diff_locked if drive != null else false
var retarder_torque_applied: float:
	get: return drive.retarder_torque_applied if drive != null else 0.0

var _steer := 0.0
## World gravity, read once at _ready. On the base like pitch/roll/altitude/vspeed: a fact about
## the world, not the family. Unread on a wheeled body, where weight arrives via the springs.
var _gravity := 9.8
var _grip_terrains: Array[Node] = []  ## painted terrains the wheels sample for surface grip
var _terrains_found := false           ## one-shot guard for the terrain scan below
var _prev_velocity := Vector3.ZERO  ## last tick's linear_velocity, for accel/impact
var _impact_hold := 0.0             ## decaying peak of the impact magnitude
var _lamps := LampSet.new()         ## drives the scene-authored lamps from input
var _horn_player: AudioStreamPlayer ## procedural horn, played on the horn rising edge
var _prev_horn := false


func _ready() -> void:
	# The vehicle mask carries Containment (gameplay rays use SOLID and omit it), and the water
	# kill volume depends on this layer being VEHICLE.
	collision_layer = Layers.VEHICLE
	collision_mask = Layers.WORLD
	telemetry = _make_telemetry()
	telemetry.speed_limit = roundi(spec.speed_limit_kmh)  # copied once, not republished per tick
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	mass = spec.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = spec.center_of_mass
	can_sleep = false
	# A hard fall can tunnel through thin terrain collision in one 60 Hz tick otherwise.
	continuous_cd = true
	# Nothing rides the engine's default_linear_damp (0.1), which would set every wheeled
	# vehicle's top speed. Resistance comes from WheelDrive._apply_resistance or the vehicle's
	# own declared drag, never a project setting.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	if spec.angular_damping > 0.0:  # stability-assist yaw/roll bleed
		angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		angular_damp = spec.angular_damping
	drivetrain = Drivetrain.new(spec)
	if spec.ground_drive != null:  # optional: boat/drone/train declare none
		drive = WheelDrive.new(self, spec)
	spawn_transform = global_transform
	_prev_velocity = linear_velocity
	_lamps.setup(self, spec)
	_horn_player = AudioStreamPlayer.new()
	_horn_player.stream = Horn.make_stream()
	add_child(_horn_player)
	if drive != null:
		drive.build_dust(self, spec.ground_drive)
	if not display_only:
		InputRouter.register_vehicle(self)


func _exit_tree() -> void:
	InputRouter.unregister_vehicle(self)
	if drive != null:  # stop dust emission before a garage/cycle swap frees the subtree
		drive.respawn()


func _physics_process(delta: float) -> void:
	var input := InputRouter.get_vehicle_input()
	_steer = move_toward(_steer, input.steer, spec.steer_speed * delta)

	var drive_omega := drive.drive_omega(spec.ground_drive, input) if drive != null else 0.0
	var ground_speed := linear_velocity.dot(-global_transform.basis.z)
	var axle_torque := drivetrain.process(
			delta, absf(input.throttle), drive_omega, ground_speed, input.gear_request, input.gear_auto)

	if not _terrains_found:  # discover the level's painted terrains once, wheels sample for grip
		_grip_terrains = _find_grip_terrains()
		_terrains_found = true

	# Order is load-bearing: resistance reads this tick's spring loads; diff lock's omega
	# write must follow spin integration.
	if drive != null:
		drive.tick(self, spec, input, _steer, axle_torque, ground_speed, delta, _grip_terrains)

	_update_telemetry(input, delta)
	var lamp_bits := input.lamps
	_lamps.apply(lamp_bits.brake_lamp, input.lights, lamp_bits.turn_left, lamp_bits.turn_right,
			lamp_bits.led, lamp_bits.beacon, lamp_bits.strobe)
	if input.horn and not _prev_horn:  # honks on rising edge, holds while pressed
		_horn_player.play()
	elif not input.horn and _prev_horn:
		_horn_player.stop()
	_prev_horn = input.horn
	if drive != null:
		drive.update_dust(telemetry)

	_tick_extras(input, delta)  # last, so drivetrain rpm/telemetry motion are current

	if global_position.y < FALL_RESPAWN_Y:
		respawn()


## Subclass seam: a subclass with extra "out" fields (the tractor's ISOBUS) returns its own
## VehicleTelemetry subclass.
func _make_telemetry() -> VehicleTelemetry:
	return VehicleTelemetry.new()


## The other subclass seam: a per-tick subsystem hook run at the end of _physics_process.
## Subclasses never fork _physics_process itself.
func _tick_extras(_input: VehicleInput, _delta: float) -> void:
	pass


## What this machine can do, for the shell's control gating. Duck-typed, and reading the same
## spec flags that gate the behaviour in _physics_process.
func vehicle_capabilities() -> Dictionary:
	var gd: GroundDriveSpec = spec.ground_drive if spec != null else null
	return {
		"diff_lock": gd != null and gd.rear_diff_lockable,
		"fwd_drive": gd != null and gd.front_axle_engageable,
	}


## The level this vehicle is under: a group lookup, not a Level type dependency, since a running
## game holds exactly one level. Every "what is in my world" scan starts here.
func _level_root() -> Node:
	for level in get_tree().get_nodes_in_group(Groups.LEVEL):
		if level.is_ancestor_of(self):
			return level
	# Test rig fallback: scan up so a terrain sibling of the vehicle's parent is found.
	var root: Node = self
	while root.get_parent() != null and root.get_parent() != get_tree().root:
		root = root.get_parent()
	return root


## Painted terrains under the owning level for the wheels' grip query. Scans for the terrain
## contract (grip_at + contains_xz + height_at), with no HeightmapTerrain type dependency.
func _find_grip_terrains() -> Array[Node]:
	var out: Array[Node] = []
	_collect_grip_terrains(_level_root(), out)
	return out


static func _collect_grip_terrains(node: Node, out: Array[Node]) -> void:
	if node.has_method("grip_at") and node.has_method("contains_xz") \
			and node.has_method("height_at"):
		out.append(node)
	for child in node.get_children():
		_collect_grip_terrains(child, out)


func _update_telemetry(input: VehicleInput, delta: float) -> void:
	var xform := global_transform
	var forward := -xform.basis.z
	var up := xform.basis.y

	telemetry.speed = linear_velocity.dot(forward)
	telemetry.kmh = absf(telemetry.speed) * 3.6
	telemetry.rpm = drivetrain.rpm
	telemetry.gear_byte = drivetrain.gear_byte
	telemetry.throttle = input.throttle
	telemetry.steer = _steer
	telemetry.yaw = angular_velocity.dot(up)
	# roll_rate is about the forward axis (-Z), matching published `roll`'s sign convention.
	telemetry.roll_rate = -angular_velocity.dot(xform.basis.z)
	telemetry.pitch_rate = angular_velocity.dot(xform.basis.x)
	# Written before _tick_extras, so a mid-tick reader (drone pre-arm check) sees this tick.
	telemetry.pitch = VehicleMath.pitch_deg(xform.basis)
	telemetry.roll = VehicleMath.roll_deg(xform.basis)
	telemetry.altitude = global_position.y
	telemetry.vspeed = linear_velocity.y

	var accel := VehicleTelemetry.body_accel(
			linear_velocity, _prev_velocity, delta, forward, xform.basis.x, up)
	var s := 1.0 - exp(-ACCEL_SMOOTH * delta)
	telemetry.acc_long = lerpf(telemetry.acc_long, accel.x, s)
	telemetry.acc_lat = lerpf(telemetry.acc_lat, accel.y, s)
	telemetry.acc_vert = lerpf(telemetry.acc_vert, accel.z, s)

	telemetry.ground = true  # train/boat/drone overwrite ST_GROUND in their own _tick_extras
	if drive != null:
		drive.fill_slip(telemetry)

	telemetry.pos_x = global_position.x
	telemetry.pos_z = global_position.z
	telemetry.lat = VehicleTelemetry.gps_lat(global_position.z)
	telemetry.lon = VehicleTelemetry.gps_lon(global_position.x)
	telemetry.heading = VehicleTelemetry.heading_from_forward(forward)
	telemetry.odo = VehicleTelemetry.odo_step(telemetry.odo, telemetry.speed, delta)

	var running := input.key == InputRouter.KEY_IGNITION
	# Governed throttle, not the pedal (telemetry.throttle stays the pedal): an engine held
	# back by the limiter is not burning fuel for a request it never made.
	var load_frac := clampf(drivetrain.applied_throttle, 0.0, 1.0)
	telemetry.fuel = VehicleTelemetry.fuel_step(telemetry.fuel, load_frac, running, delta)
	telemetry.coolant = VehicleTelemetry.coolant_step(
			telemetry.coolant, VehicleTelemetry.coolant_target(running, load_frac), COOLANT_RATE, delta)
	telemetry.battery = VehicleTelemetry.battery_volts(running, load_frac)
	telemetry.engine_hours = VehicleTelemetry.hours_step(telemetry.engine_hours, running, delta)

	# Gate the raw acceleration spike, then peak-hold with decay so a one-tick collision stays
	# readable on the dash and the bridge.
	var accel_mag := ((linear_velocity - _prev_velocity) / maxf(delta, 1e-5)).length()
	_impact_hold = maxf(
			VehicleTelemetry.impact_gate(accel_mag, IMPACT_THRESHOLD),
			move_toward(_impact_hold, 0.0, IMPACT_DECAY * delta))
	telemetry.impact = _impact_hold

	telemetry.status = VehicleTelemetry.pack_status(
			running, telemetry.ground, absf(telemetry.speed) > MOVING_SPEED,
			telemetry.gear_byte, input.handbrake > 0.0, input.lights >= 3)

	_prev_velocity = linear_velocity


## Reset to the last spawn transform with zeroed motion; also fired on a fall off the world.
func respawn() -> void:
	global_transform = spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_steer = 0.0
	_prev_velocity = Vector3.ZERO  # zero accel/impact history so the teleport isn't read as an impact
	_impact_hold = 0.0
	telemetry.acc_long = 0.0
	telemetry.acc_lat = 0.0
	telemetry.acc_vert = 0.0
	if drive != null:
		drive.respawn()
	reset_physics_interpolation()
	respawned.emit()


func get_camera_target() -> Node3D:
	return self


## Physics bodies the chase camera's occlusion ray must ignore: self, plus any sub-bodies. A
## train's wagons trail the loco, and without this the pull-in slams the camera into the first.
func get_camera_exclude_bodies() -> Array[RID]:
	return [get_rid()]


## Optional chase-camera framing override; empty means the level camera's authored values. A
## long vehicle (a train consist) returns bigger values to clear the whole thing.
func get_camera_framing() -> Dictionary:
	return {}


## Read by InputRouter for local brake-vs-reverse arbitration.
func get_speed() -> float:
	return telemetry.speed


func get_gear_byte() -> int:
	return drivetrain.gear_byte if drivetrain != null else Drivetrain.GEAR_N

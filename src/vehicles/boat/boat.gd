class_name BoatVehicle
extends BaseVehicle
## Boat, through the two BaseVehicle seams only. Float probes sample WaterSurface's flat height
## and push the hull up, thrust acts at the stern, the rudder makes yaw torque, the hull below the
## waterline drags against the level's CurrentField and the hull above it takes windage from the
## level's WindField: two frames on one body. Force magnitudes are static functions with one-tick
## clamps (`src/vehicles/CLAUDE.md` § The 60 Hz tick). Hull geometry is node knobs; engine tuning
## lives in the variant's spec. The autopilot (BoatAutopilot) steers through the helm slew; see
## _autopilot.

const RUDDER_SPEED_REF := 6.0   ## m/s of forward flow that gives full rudder authority
const RUDDER_PROP_WASH := 0.5   ## authority contributed by full throttle prop wash

@export_group("Buoyancy")
## Float probe positions, body space (bow = -Z). 4-6 probes.
@export var probe_points := PackedVector3Array([
	Vector3(-0.8, -0.2, -1.6), Vector3(0.8, -0.2, -1.6),
	Vector3(-0.8, -0.2, 1.8), Vector3(0.8, -0.2, 1.8),
])
## Rest submersion (m) of the probes when floating level. The per-probe spring rate is derived
## from it (k = m*g / (probes * float_depth)), so the boat floats by construction.
@export var float_depth := 0.35
@export var buoyancy_damp := 0.5          ## damper as a ratio of critical (per probe)
@export var max_probe_force_factor := 3.0 ## per-probe force cap, x the probe's weight share

@export_group("Propulsion")
@export var thrust_force := 5200.0        ## N at full forward throttle
@export var reverse_thrust_factor := 0.4  ## reverse thrust fraction
@export var prop_offset := Vector3(0, -0.5, 1.9)  ## body-space thrust point (outdrive: stern, below COM)
@export var rudder_torque := 7000.0       ## N*m yaw torque at full rudder + full authority

@export_group("Hull drag")
@export var drag_long := 380.0            ## N per m/s forward (sets top speed vs thrust)
@export var drag_lat := 2600.0            ## N per m/s sideways (the keel)
@export var drag_yaw := 5000.0            ## N*m per rad/s of yaw
@export var keel_offset := -0.65          ## body-space Y where lateral drag acts (roll in turns)

## Windage: the above-waterline hull in the AIR-relative flow, the mirror of the hull drag below.
## A labelled honest model: `0.5 * rho * Cd * A` linearized at ~6 m/s for a 4-5 m hull (side area
## ~3x the frontal). Air is 1/800 the density, so it costs only ~1-2 % of top speed against
## `drag_long`, and is not tuned away.
@export_group("Windage")
@export var windage_long := 6.0           ## N per m/s of air-relative fore-aft flow
@export var windage_lat := 18.0           ## N per m/s athwartships (the bigger side area)
## Body-space centre of windage from the waterline origin, like `prop_offset`: +Y above the COM
## heels the hull, +Z aft yaws the bow up into a beam wind.
@export var windage_offset := Vector3(0.0, 0.55, 0.45)

## The rig (contract `sheet` -> `sail_angle`). `sail_area` 0 means THIS HULL HAS NO RIG: the whole
## block is skipped. Declared per variant in `tools/gen_boat_variants.gd`, never derived from the
## mesh.
@export_group("Sail")
@export var sail_area := 0.0            ## m^2 of working sail; 0 = no rig
## Body-space centre of effort from the waterline origin: +Y above the COM so the rig heels the
## hull, a little +Z to put it abaft the mast.
@export var sail_center := Vector3.ZERO
## Boom travel at the sheet fully eased. 90 makes a dead run pure drag (boom square to the wind,
## zero angle of attack), so a shorter value is a rig the shrouds stop early, not a tuning knob.
@export var sheet_max_deg := 0.0
## The sail mesh, swung about its mast so the visible boom is the one the force uses. Visual and
## optional; empty on every hull with `sail_area` 0. Resolved once in `_ready`.
@export var sail_pivot: NodePath

## Depth sounder on the centreline, `transducer_station` aft of the origin. Its depth is not a
## knob: it rides the probe plane `-float_depth`, the same plane the aground predicate below
## measures, so `depth` and the ground bit are two readings of one seabed. A Y of its own would
## drift them apart per hull. The mesh's real keel is deeper (the generator's `draft`, which no
## runtime field carries).
@export_group("Sounder")
@export var transducer_station := 0.6   ## m aft of the origin, on the centreline

## Aground detection (contract `status` bit 1, ST_GROUND, which a wheel-less body answers for
## itself): the hull rests on the bed or beach. The buoyancy spring settles a floating hull's
## probes at ~float_depth on average, while a hull the bed holds up reads shallower. Read off the
## probe depths buoyancy already computes.
const AGROUND_SHALLOW_FRAC := 0.5 ## mean probe depth must be under this fraction of float_depth
const AGROUND_VSPEED := 0.2       ## m/s hull vertical speed below which it's settled, not falling
const AGROUND_DEBOUNCE := 1.0     ## seconds the shallow reading must hold — filters wave chop
								   ## at the shoreline and the near-zero apex of a wake jump

var _trim := 0.0        ## %, chases forward throttle (BoatTelemetry.trim_step)
var _aground_hold := 0.0  ## seconds the aground condition has held continuously
var _nav_mode: int = BoatAutopilot.STANDBY  ## what the pilot is DOING (contract 'nav_mode_actual')
var _heading_target := 0.0              ## deg the pilot steers to (contract 'heading_target')
## The rudder this hull applied last tick, which the autopilot re-slews from. See _autopilot.
var _helm := 0.0
var _yaw_inertia := 1000.0
var _waters: Array[WaterSurface] = []  ## the level's water bodies, collected once
var _waters_found := false             ## one-shot guard for the water scan
var _sail_node: Node3D = null          ## the mesh `sail_pivot` names, or null


func _make_telemetry() -> VehicleTelemetry:
	return BoatTelemetry.new()


func _ready() -> void:
	super._ready()
	# Yaw inertia proxy from the footprint the probes span; sizes the yaw-damper clamp.
	var length := 0.0
	var width := 0.0
	for p in probe_points:
		length = maxf(length, absf(p.z) * 2.0)
		width = maxf(width, absf(p.x) * 2.0)
	_yaw_inertia = VehicleMath.inertia_of(spec.mass, length, width)
	if not sail_pivot.is_empty():
		_sail_node = get_node_or_null(sail_pivot) as Node3D


func _tick_extras(input: VehicleInput, delta: float) -> void:
	var t := telemetry as BoatTelemetry
	# First, so the rudder torque below is this tick's.
	_autopilot(input, t, delta)
	if not _waters_found:
		_collect_waters()
		_waters_found = true
	var water := _find_water()
	# Wind and `aw` are read once: the windage, the sail force and the wind instruments share them.
	var wind := WindField.at(self)
	var aw := BoatTelemetry.apparent_wind(linear_velocity, wind, global_transform.basis)
	# `through_water` is the velocity the hull swims at: every hull force and the speed log are
	# measured against it. It equals `linear_velocity` on a level with no CurrentField.
	var current := CurrentField.at(self)
	var through_water := linear_velocity - current
	# The boom is read outside the buoyancy gate: it depends only on the sheet and the apparent
	# wind, and a boom frozen out of the water would be a stale reading. Only the FORCE is gated.
	# `sail_area` 0 leaves it on the centreline.
	var boom := 0.0
	if sail_area > 0.0:
		boom = BoatSail.boom_angle(input.sheet, aw.y, sheet_max_deg)
	var stern_wet := false
	var submerged := 0
	var depth_sum := 0.0

	if water != null:
		var probe_count := maxf(1.0, probe_points.size())
		var probe_mass := spec.mass / probe_count
		var k := spec.mass * _gravity / (probe_count * maxf(float_depth, 0.01))
		var damp := buoyancy_damp * 2.0 * sqrt(k * probe_mass)
		var max_f := max_probe_force_factor * probe_mass * _gravity
		var water_y := water.get_height(global_position)
		for p_local in probe_points:
			var p := global_transform * p_local
			var depth := water_y - p.y
			depth_sum += depth
			var vert_vel := (linear_velocity + angular_velocity.cross(p - global_position)).y
			var f := probe_force(depth, vert_vel, k, damp, probe_mass, delta, max_f)
			# Immersion is read off DEPTH, not the force, which caps at max_f.
			if depth > 0.0:
				submerged += 1
				if p_local.z > 0.0:
					stern_wet = true
			if f > 0.0:
				apply_force(Vector3.UP * f, p - global_position)

	if submerged > 0:
		var fwd := -global_transform.basis.z
		var right := global_transform.basis.x
		var up := global_transform.basis.y
		var v_long := through_water.dot(fwd)
		# Hull drag: forward resistance at the COM, the keel's lateral resistance at keel_offset
		# (the hull heels in turns). Both against the WATER, not the ground.
		apply_central_force(fwd * VehicleMath.damped_force(v_long, drag_long, spec.mass, delta))
		var v_lat := through_water.dot(right)
		apply_force(right * VehicleMath.damped_force(v_lat, drag_lat, spec.mass, delta),
				up * keel_offset)
		# Yaw stays on the RAW angular velocity: a uniform stream exerts no yaw moment.
		var yaw_rate := angular_velocity.dot(up)
		apply_torque(up * VehicleMath.damped_force(yaw_rate, drag_yaw, _yaw_inertia, delta))

		# Windage against the air; the lateral term acts at windage_offset. Not
		# VehicleMath.air_damper: its `axis` masks WORLD space, and this is a BODY-frame split.
		var air := linear_velocity - wind
		apply_central_force(fwd * VehicleMath.damped_force(
				air.dot(fwd), windage_long, spec.mass, delta))
		apply_force(right * VehicleMath.damped_force(air.dot(right), windage_lat,
				spec.mass, delta), global_transform.basis * windage_offset)

		# The rig, the only air term that DRIVES. Gated with the hull's drag: an ungated sail would
		# push a beached boat unopposed. `aw` is flattened to the water plane
		# (BoatTelemetry.apparent_wind), so the axes must be too, or a heeled hull gains a
		# vertical force nothing opposes.
		if sail_area > 0.0:
			var sail_axes := BoatSail.flatten_hull_axes(fwd, right)
			apply_force(BoatSail.force(aw, boom, sail_area, sail_axes[0], sail_axes[1]),
					global_transform.basis * sail_center)

		if stern_wet:
			# Thrust at the stern, below the COM, so the bow rises under throttle.
			apply_force(fwd * thrust_force * thrust_scale(input.throttle, reverse_thrust_factor),
					global_transform.basis * prop_offset)
			# Authority follows flow over the blade (water-relative v_long plus prop wash). Steer
			# negative is left and +Y torque yaws left, so the sign flips.
			var authority := rudder_authority(v_long, input.throttle)
			apply_torque(up * (-_steer * rudder_torque * authority))

	_trim = BoatTelemetry.trim_step(_trim, input.throttle, BoatTelemetry.TRIM_RATE, delta)
	t.rudder_actual = roundi(clampf(_steer, -1.0, 1.0) * 100.0)
	t.trim = roundi(_trim)

	# Engine room and instruments below are ungated by buoyancy: gauges read out of the water too.
	var running := input.key == InputRouter.KEY_IGNITION
	var load_frac := clampf(drivetrain.applied_throttle, 0.0, 1.0)
	t.fuel_rate = BoatTelemetry.fuel_rate_model(load_frac, running)
	t.oil_press = BoatTelemetry.oil_press_model(drivetrain.rpm, spec.idle_rpm, running)
	t.tank_level = BoatTelemetry.tank_step(t.tank_level, running, delta)

	t.aws = aw.x
	t.awa = aw.y
	var tw := BoatTelemetry.true_wind(wind)
	t.tws = tw.x
	t.twd = tw.y
	t.sail_angle = boom
	if _sail_node != null:
		# Godot's +Y yaw swings the bow to PORT (BoatAutopilot.turn_rate_deg) while the boom angle
		# is positive the other way, so it negates. A yaw commutes with the Model node's 180 deg
		# Y flip.
		_sail_node.rotation.y = -deg_to_rad(boom)

	var track := BoatTelemetry.flow_toward(linear_velocity)
	t.sog = track.x
	t.cog = track.y
	t.stw = BoatTelemetry.flow_toward(through_water).x
	var tide := BoatTelemetry.flow_toward(current)
	t.current_drift = tide.x
	t.current_set = tide.y

	# The sounder IS gated on the water, unlike the instruments above.
	t.depth = BoatTelemetry.DEPTH_INVALID
	if water != null:
		t.depth = seabed_sounding(
				global_transform * Vector3(0.0, -float_depth, transducer_station), _grip_terrains)

	var mean_depth := depth_sum / maxf(1.0, probe_points.size())
	var aground := aground_now(water != null, mean_depth, linear_velocity.y,
			float_depth, AGROUND_SHALLOW_FRAC, AGROUND_VSPEED)
	_aground_hold = aground_hold(_aground_hold, aground, delta)
	t.ground = _aground_hold >= AGROUND_DEBOUNCE
	t.status = VehicleTelemetry.with_status_bit(t.status, VehicleTelemetry.ST_GROUND, t.ground)


## The autopilot (contract 'nav_mode' -> 'nav_mode_actual' / 'heading_target'). Every law is a
## BoatAutopilot static; what lives here is the per-tick state.
##
## It slews from `_helm` (the rudder this hull last applied), never from `_steer`: BaseVehicle has
## already slewed `_steer` toward the hand's request, and re-slewing that value toward the pilot's
## demand cancels (move_toward(move_toward(x, 0, r), c, r) is x), so the rudder would drift to
## centre. The slew runs at the same spec.steer_speed as the hand's.
##
## `t.steer` is rewritten because _update_telemetry ran before this and published the pre-empted
## value.
func _autopilot(input: VehicleInput, t: BoatTelemetry, delta: float) -> void:
	var was := _nav_mode
	_nav_mode = BoatAutopilot.resolve_mode(input.nav_mode, input.steer)
	if _nav_mode == BoatAutopilot.HEADING_HOLD:
		if input.heading_cmd >= 0.0:
			_heading_target = input.heading_cmd  # the bus is steering (presence IS the command)
		elif was != BoatAutopilot.HEADING_HOLD:
			# Only the engage EDGE captures the current heading (also fires when a helm nudge is
			# released); an engaged pilot whose bus goes quiet keeps its course.
			_heading_target = t.heading
		var demand := BoatAutopilot.autopilot_rudder(
				BoatAutopilot.heading_error(_heading_target, t.heading),
				BoatAutopilot.turn_rate_deg(t.yaw), BoatAutopilot.KP, BoatAutopilot.KD)
		_steer = move_toward(_helm, demand, spec.steer_speed * delta)
	else:
		# Standing by echoes the course an engage WOULD capture; 0 would read as a real target.
		_heading_target = t.heading
	_helm = _steer
	t.nav_mode_actual = _nav_mode
	t.heading_target = _heading_target
	t.steer = _steer


## A rig is anatomy, not a family trait: only `boat-sail-a` carries one, so the SHEET control is
## capability-gated. Contract signals key on the family, so the powerboats publish a resting 0.
func vehicle_capabilities() -> Dictionary:
	var caps := super()
	caps["sail"] = sail_area > 0.0
	return caps


func reset_session_state() -> void:
	super.reset_session_state()
	_trim = 0.0
	_aground_hold = 0.0
	# The base zeroed `_steer`; `_helm` mirrors it. STANDBY makes the next engage a fresh capture.
	_helm = 0.0
	_nav_mode = BoatAutopilot.STANDBY
	_heading_target = 0.0


## First WaterSurface whose region contains the hull, null when ashore. The list is collected
## once, but `contains_xz` stays per tick, since that changes as the boat moves.
func _find_water() -> WaterSurface:
	for w in _waters:
		if not is_instance_valid(w):
			continue
		if w.contains_xz(global_position):
			return w
	return null


func _collect_waters() -> void:
	_waters.clear()
	for node in get_tree().get_nodes_in_group(Groups.WATER):
		var w := node as WaterSurface
		if w != null:
			_waters.append(w)


# --- pure force math (unit-tested) ------------

## Per-probe buoyancy: a spring on depth plus a damper on vertical velocity, one-tick clamped so
## the damper never exceeds the force reversing that velocity within a tick. Non-negative, since
## water only pushes up, and hard-capped at max_force.
static func probe_force(depth: float, vert_vel: float, k: float, damp: float,
		probe_mass: float, delta: float, max_force: float) -> float:
	if depth <= 0.0:
		return 0.0
	var tick_cap := probe_mass * absf(vert_vel) / delta
	var damper := clampf(-damp * vert_vel, -tick_cap, tick_cap)
	return clampf(k * depth + damper, 0.0, max_force)


## Aground this tick: the hull is settled, with vertical speed under vspeed_max to filter wave
## chop and a jump apex, and either has no water under it or its probes sit shallower than a
## genuinely floating hull would.
static func aground_now(has_water: bool, mean_depth: float, vert_speed: float,
		rest_depth: float, shallow_frac: float, vspeed_max: float) -> bool:
	if absf(vert_speed) > vspeed_max:
		return false
	if not has_water:
		return true
	return mean_depth < rest_depth * shallow_frac


## Seconds the aground condition has held continuously; drops to zero the moment it breaks.
static func aground_hold(prev_s: float, now: bool, delta: float) -> float:
	return prev_s + maxf(delta, 0.0) if now else 0.0


## Signed thrust fraction: forward throttle passes through, reverse is scaled down.
static func thrust_scale(throttle: float, reverse_factor: float) -> float:
	var t := clampf(throttle, -1.0, 1.0)
	return t if t >= 0.0 else t * reverse_factor


## Rudder authority 0..1: no flow over the blade means no turn. Hull speed provides flow and prop
## wash gives some even from a standstill, so the boat can turn out of a dock.
static func rudder_authority(forward_speed: float, throttle: float) -> float:
	return VehicleMath.flow_authority(forward_speed, RUDDER_SPEED_REF, RUDDER_PROP_WASH, throttle)


# --- the sounder (pure, unit-tested) --------------------------------------------

## Depth under `point`, off the heightmap the hull collides with, through the terrain list
## BaseVehicle collects for the wheels. `contains_xz` is the gate: `height_at` CLAMPS its UV
## outside the extent and would hand back a fabricated edge bottom. RayWheel.terrain_at is the
## wrong tool: it only sees a surface within SURFACE_GRIP_REACH, and the seabed is metres down.
## The topmost surface under the point is the bed.
static func seabed_sounding(point: Vector3, terrains: Array[Node]) -> float:
	var has_bottom := false
	var seabed_y := 0.0
	for terrain in terrains:
		if not is_instance_valid(terrain) or not terrain.contains_xz(point):
			continue
		var y: float = terrain.height_at(point)
		if not has_bottom or y > seabed_y:
			seabed_y = y
			has_bottom = true
	return BoatTelemetry.sounding(has_bottom, point.y, seabed_y)

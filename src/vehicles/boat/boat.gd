class_name BoatVehicle
extends BaseVehicle
## Boat, through the two BaseVehicle seams only. Float probes sample WaterSurface's flat height
## and push the hull up, thrust acts at the stern, the rudder makes yaw torque, the hull below the
## waterline drags against the level's CurrentField and the hull above it takes windage from the
## level's WindField — two frames on one body. The force
## magnitudes are pure static functions with RayWheel-style one-tick clamps; do not weaken any of
## them. Hull geometry is node knobs, while drive tuning lives in boat_spec.tres. The autopilot
## (BoatAutopilot) is a vehicle-level controller like DroneModes and steers through the same helm
## slew the hand does — no arbitration of its own; see _autopilot.

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

## Hull drag absorbs each hull's own mass * 0.1 share of the engine's default_linear_damp, folded
## into the shipped overrides, so the feel is unchanged.
@export_group("Hull drag")
@export var drag_long := 380.0            ## N per m/s forward (sets top speed vs thrust)
@export var drag_lat := 2600.0            ## N per m/s sideways (the keel)
@export var drag_yaw := 5000.0            ## N*m per rad/s of yaw
@export var keel_offset := -0.65          ## body-space Y where lateral drag acts (roll in turns)

## Windage: the above-waterline hull in the AIR-relative flow, the mirror of the hull drag
## below. Both coefficients are a labelled honest model — `0.5 * rho * Cd * A` linearized at a
## ~6 m/s reference for a 4-5 m hull (side area is roughly three times the frontal), so the
## force is genuinely small next to the water's: air is 1/800 the density. It costs ~1-2 % of
## top speed in dead calm against `drag_long`, which is the honest price and not tuned away.
@export_group("Windage")
@export var windage_long := 6.0           ## N per m/s of air-relative fore-aft flow
@export var windage_lat := 18.0           ## N per m/s athwartships (the bigger side area)
## Body-space centre of windage, measured from the origin at the waterline like `prop_offset`:
## +Y puts it above the COM (which sits below the waterline) so wind heels the hull, +Z puts it
## aft so a beam wind yaws the bow up into the wind. A Y-only offset would give heel alone.
@export var windage_offset := Vector3(0.0, 0.55, 0.45)

## The rig (contract `sheet` -> `sail_angle`). Every law is a BoatSail static; what lives here is
## the anatomy, and `sail_area` 0 is what says THIS HULL HAS NO RIG — the whole block is skipped,
## so the two powerboats pay one comparison a tick. Declared per variant in
## `tools/gen_boat_variants.gd`, like the drag coefficients, never derived from the mesh.
@export_group("Sail")
@export var sail_area := 0.0            ## m^2 of working sail; 0 = no rig
## Body-space centre of effort, measured from the origin at the waterline like `prop_offset`'s and
## `windage_offset`'s: +Y above the COM so the rig HEELS the hull (which is what the deep keel is
## there to resist), a little +Z to put it abaft the mast.
@export var sail_center := Vector3.ZERO
## Boom travel at the sheet fully eased. 90 is the value that makes a dead run pure drag (the boom
## square to the wind, zero angle of attack against the plate's broadside), so a shorter one is a
## rig the shrouds stop early, not a tuning knob to reach for.
@export var sheet_max_deg := 0.0
## The sail mesh, swung about its mast so the boom you see is the boom the force is computed from.
## Purely visual and optional — an empty path is a rig with no mesh to turn, which is every hull
## with `sail_area` 0. Resolved once in `_ready`; the node's own rest basis is identity, so the
## yaw is written rather than composed.
@export var sail_pivot: NodePath

## Depth sounder, on the centreline at `transducer_station` aft of the origin (+Z, the origin
## being at the waterline like prop_offset's). Its DEPTH is not a knob: it rides the probe plane,
## `-float_depth`, which is the bottom the buoyancy model gives this hull and the exact plane the
## aground predicate below measures. That is what makes `depth` and the ground bit two readings of
## one seabed — the sounding passes 0 as the bed reaches the probes, and the bit sets once the bed
## has come up far enough to hold the hull off its rest depth. Give the transducer a Y of its own
## and the two drift apart, per hull, silently: each variant has its own float_depth. The mesh's
## real keel is deeper still (the generator's `draft`, which no runtime field carries), so this is
## a sounder at the model's hull bottom rather than at the lowest point of the hull.
@export_group("Sounder")
@export var transducer_station := 0.6   ## m aft of the origin, on the centreline

## Aground detection (contract `status` bit 1, ST_GROUND, which a wheel-less body answers for
## itself). Floating in open water is not "on the ground": aground means the hull rests on the bed
## or beach. The buoyancy spring is derived so a genuinely floating hull settles every probe to
## ~float_depth on average, while a hull the bed is holding up reads shallower however hard the
## spring pushes. Read off the probe depths already computed for buoyancy, with no new raycast.
const AGROUND_SHALLOW_FRAC := 0.5 ## mean probe depth must be under this fraction of float_depth
const AGROUND_VSPEED := 0.2       ## m/s hull vertical speed below which it's settled, not falling
const AGROUND_DEBOUNCE := 1.0     ## seconds the shallow reading must hold — filters wave chop
								   ## at the shoreline and the near-zero apex of a wake jump

var _trim := 0.0        ## %, chases forward throttle (BoatTelemetry.trim_step)
var _aground_hold := 0.0  ## seconds the aground condition has held continuously
var _nav_mode := BoatAutopilot.STANDBY  ## what the pilot is DOING (contract 'nav_mode_actual')
var _heading_target := 0.0              ## deg the pilot steers to (contract 'heading_target')
## The rudder this hull applied last tick — the value the autopilot re-slews from. See _autopilot.
var _helm := 0.0
var _yaw_inertia := 1000.0
var _waters: Array[WaterSurface] = []  ## the level's water bodies, collected once (see _find_water)
var _waters_found := false             ## one-shot guard, the _terrains_found shape
var _sail_node: Node3D = null          ## the mesh `sail_pivot` names, or null (see _ready)


func _make_telemetry() -> VehicleTelemetry:
	return BoatTelemetry.new()


func _ready() -> void:
	super._ready()
	# Yaw inertia proxy from the hull footprint the probes span, clamps the yaw damping torque.
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
	# First, so the rudder torque below is this tick's — the pilot steers before the hull is pushed.
	_autopilot(input, t, delta)
	if not _waters_found:
		_collect_waters()
		_waters_found = true
	var water := _find_water()
	# Read once per tick: the windage below, the rig and the four wind instruments need the same
	# value. `aw` is hoisted up here with it because the sail force below is the earliest reader —
	# nothing between here and the instruments touches either.
	var wind := WindField.at(self)
	var aw := BoatTelemetry.apparent_wind(linear_velocity, wind, global_transform.basis)
	# Likewise the tide — the hull drag, the speed log and the two tide instruments read one
	# vector. `through_water` is the velocity the hull actually swims at; it is what every hull
	# force and the speed log are measured against, and it collapses to `linear_velocity` on a
	# level with no CurrentField.
	var current := CurrentField.at(self)
	var through_water := linear_velocity - current
	# The boom, read here rather than inside the buoyancy gate below: it is a function of the sheet
	# and the apparent wind alone, both of which read on the trailer, and a boom frozen at its last
	# angle out of the water would be a STALE reading rather than a still one — the rule the wind
	# instruments already follow. Only the FORCE is gated. `sail_area` 0 leaves it on the centreline,
	# which is the honest angle for a hull with no boom.
	var boom := 0.0
	if sail_area > 0.0:
		boom = BoatSail.boom_angle(input.sheet, aw.y, sheet_max_deg)
	var stern_wet := false
	var submerged := 0
	var depth_sum := 0.0

	if water != null:
		var probe_count := maxf(1.0, probe_points.size())
		var probe_mass := spec.mass / probe_count
		var k := spec.mass * _gravity / (probe_count * float_depth)
		var damp := buoyancy_damp * 2.0 * sqrt(k * probe_mass)
		var max_f := max_probe_force_factor * probe_mass * _gravity
		var water_y := water.get_height(global_position)
		for p_local in probe_points:
			var p := global_transform * p_local
			var depth := water_y - p.y
			depth_sum += depth
			var vert_vel := (linear_velocity + angular_velocity.cross(p - global_position)).y
			var f := probe_force(depth, vert_vel, k, damp, probe_mass, delta, max_f)
			if f > 0.0:
				submerged += 1
				if p_local.z > 0.0:
					stern_wet = true
				apply_force(Vector3.UP * f, p - global_position)

	if submerged > 0:
		var fwd := -global_transform.basis.z
		var right := global_transform.basis.x
		var up := global_transform.basis.y
		var v_long := through_water.dot(fwd)
		# Hull drag: forward resistance at the COM, while the keel's lateral resistance acts
		# below it at keel_offset, so the hull heels in turns. Both against the WATER, not the
		# ground — a hull lying stopped in a tide is being dragged downstream, and one stemming
		# the stream at the drift rate sits still over the bed with full steerage.
		apply_central_force(fwd * VehicleMath.damped_force(v_long, drag_long, spec.mass, delta))
		var v_lat := through_water.dot(right)
		apply_force(right * VehicleMath.damped_force(v_lat, drag_lat, spec.mass, delta),
				up * keel_offset)
		# Yaw stays on the RAW angular velocity: a uniform stream has no gradient across the
		# hull, so it exerts no yaw moment. Only a shear would, and there is none.
		var yaw_rate := angular_velocity.dot(up)
		apply_torque(up * VehicleMath.damped_force(yaw_rate, drag_yaw, _yaw_inertia, delta))

		# Windage, the same anisotropic shape against the air: the lateral term acts at
		# windage_offset (above the COM to heel, aft of it to weathercock) as the keel's acts
		# below. NOT VehicleMath.air_damper — its `axis` masks the WORLD-space relative
		# velocity component-wise, and fore-aft against athwartships is a BODY-frame split on
		# a hull that yaws, which no world mask expresses.
		var air := linear_velocity - wind
		apply_central_force(fwd * VehicleMath.damped_force(
				air.dot(fwd), windage_long, spec.mass, delta))
		apply_force(right * VehicleMath.damped_force(air.dot(right), windage_lat,
				spec.mass, delta), global_transform.basis * windage_offset)

		# The rig, the third body-frame air term and the only one that DRIVES. The FORCE is gated
		# with the hull's, not with the instruments above: out of the water this hull has no drag
		# either, so an ungated sail would push a beached boat unopposed.
		if sail_area > 0.0:
			apply_force(BoatSail.force(aw, boom, sail_area, fwd, right),
					global_transform.basis * sail_center)

		if stern_wet:
			# Thrust at the stern, below the COM, so the bow rises under throttle. The gear owns
			# direction and reverse thrust is weaker, like a real outdrive.
			apply_force(fwd * thrust_force * thrust_scale(input.throttle, reverse_thrust_factor),
					global_transform.basis * prop_offset)
			# Rudder torque scaled by flow over the blade — speed THROUGH THE WATER (v_long is
			# water-relative above) plus prop wash, not speed over the ground. Steer negative is
			# left and +Y torque yaws left, so the sign flips.
			var authority := rudder_authority(v_long, input.throttle)
			apply_torque(up * (-_steer * rudder_torque * authority))

	# trim is modeled (honest-model, see BoatTelemetry); pitch/roll are the base's.
	_trim = BoatTelemetry.trim_step(_trim, input.throttle, BoatTelemetry.TRIM_RATE, delta)
	t.rudder_actual = roundi(clampf(_steer, -1.0, 1.0) * 100.0)
	t.trim = roundi(_trim)

	# Engine room, ungated by the buoyancy: the gauges read whether the hull is swimming or
	# not, same as the wind instruments below.
	var running := input.key == InputRouter.KEY_IGNITION
	var load_frac := clampf(drivetrain.applied_throttle, 0.0, 1.0)
	t.fuel_rate = BoatTelemetry.fuel_rate_model(load_frac, running)
	t.oil_press = BoatTelemetry.oil_press_model(drivetrain.rpm, spec.idle_rpm, running)
	t.tank_level = BoatTelemetry.tank_step(t.tank_level, running, delta)

	# Ungated by the buoyancy: an anemometer reads on the trailer too. (`aw` itself is read at the
	# top of the tick — the rig needs it before this.)
	t.aws = aw.x
	t.awa = aw.y
	var tw := BoatTelemetry.true_wind(wind)
	t.tws = tw.x
	t.twd = tw.y
	# The boom rides with them, ungated for the same reason (see `boom` above).
	t.sail_angle = boom
	if _sail_node != null:
		# Godot's +Y yaw swings the bow to PORT (the sign BoatAutopilot.turn_rate_deg states) while
		# the boom angle is positive in the other sense, so it negates. A yaw commutes with the
		# Model node's 180 deg Y flip, so there is no extra term.
		_sail_node.rotation.y = -deg_to_rad(boom)

	# Ground track, water track and the tide itself, ungated by the buoyancy like the wind
	# instruments above.
	var track := BoatTelemetry.flow_toward(linear_velocity)
	t.sog = track.x
	t.cog = track.y
	t.stw = BoatTelemetry.flow_toward(through_water).x
	var tide := BoatTelemetry.flow_toward(current)
	t.current_drift = tide.x
	t.current_set = tide.y

	# The sounder IS gated on the water, unlike the instruments above: an anemometer reads on the
	# trailer, a depth sounder out of the water reads nothing at all.
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
## IT OWNS THE RUDDER SLEW RATHER THAN ADDING A SECOND ONE. BaseVehicle has already slewed `_steer`
## toward the HAND's request by the time _tick_extras runs, and re-slewing that value toward the
## pilot's demand cancels exactly — move_toward(move_toward(x, 0, r), c, r) is x for any x below c,
## so the rudder would drift toward centre and never advance toward the course. So the hull
## remembers the rudder it actually applied (`_helm`) and re-runs the base's own move_toward at the
## SAME spec.steer_speed: the pilot cannot move the rudder faster than a helmsman can, which is the
## whole point of feeding it through the helm rather than writing the rudder directly.
##
## `t.steer` is rewritten for the same reason: _update_telemetry ran before this and published the
## pre-empted value, so without this line the 'steer' out signal shows the rudder centring while
## the real rudder is holding a course.
func _autopilot(input: VehicleInput, t: BoatTelemetry, delta: float) -> void:
	var was := _nav_mode
	_nav_mode = BoatAutopilot.resolve_mode(input.nav_mode, input.steer)
	if _nav_mode == BoatAutopilot.HEADING_HOLD:
		if input.heading_cmd >= 0.0:
			_heading_target = input.heading_cmd  # the bus is steering (presence IS the command)
		elif was != BoatAutopilot.HEADING_HOLD:
			# Engaging with nothing commanded CAPTURES the heading the boat is on. That edge also
			# fires when a helm nudge is released, so nudging the helm is how a course is changed
			# under the pilot. Only the EDGE captures: an already-engaged pilot whose bus goes
			# quiet holds the course it had rather than abandoning it for wherever the bow is.
			_heading_target = t.heading
		var demand := BoatAutopilot.autopilot_rudder(
				BoatAutopilot.heading_error(_heading_target, t.heading),
				BoatAutopilot.turn_rate_deg(t.yaw), BoatAutopilot.KP, BoatAutopilot.KD)
		_steer = move_toward(_helm, demand, spec.steer_speed * delta)
	else:
		# Standing by holds no target, so the echo reports the course an engage WOULD capture.
		# Not 0, which is a perfectly good bearing and would read as a real target.
		_heading_target = t.heading
	_helm = _steer
	t.nav_mode_actual = _nav_mode
	t.heading_target = _heading_target
	t.steer = _steer


## A rig is anatomy, not a family trait: only `boat-sail-a` carries one, so the SHEET control is
## capability-gated the way the refuse body's is rather than family-gated. The contract signals key
## on the FAMILY, so all three boats declare `sheet` / `sail_angle` and the two powerboats simply
## publish a resting 0 — the same shape as every truck declaring `body_cmd`.
func vehicle_capabilities() -> Dictionary:
	var caps := super()
	caps["sail"] = sail_area > 0.0
	return caps


func respawn() -> void:
	super.respawn()
	_trim = 0.0
	_aground_hold = 0.0
	# The base zeroed `_steer`; `_helm` mirrors it. Dropping to STANDBY makes the next tick a fresh
	# engage edge, so a respawned hull captures where it now points instead of steering back to the
	# course it held on the far side of the map.
	_helm = 0.0
	_nav_mode = BoatAutopilot.STANDBY
	_heading_target = 0.0


## First WaterSurface whose region contains the hull, null when ashore. The list is collected
## once, but `contains_xz` stays per tick, since that changes as the boat moves.
func _find_water() -> WaterSurface:
	for w in _waters:
		if w.contains_xz(global_position):
			return w
	return null


func _collect_waters() -> void:
	_waters.clear()
	for node in get_tree().get_nodes_in_group(WaterSurface.WATER_GROUP):
		var w := node as WaterSurface
		if w != null:
			_waters.append(w)


# --- pure force math (unit-tested, one-tick clamped like RayWheel) ------------

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

## Depth under `point`, off the seabed the hull actually collides with — the level's heightmap
## (rule 2: ground IS the heightmap), through the terrain list BaseVehicle already collects for
## the wheels. No raycast and no second world walk. `contains_xz` is the gate, because `height_at`
## CLAMPS its UV outside the extent and would otherwise hand back the edge height as a fabricated
## bottom; off every terrain there is genuinely no bottom to report. RayWheel.terrain_at is the
## wrong tool for the same walk: it only sees a surface within SURFACE_GRIP_REACH, and the seabed
## is metres down by design. The topmost surface under the point is the bed.
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

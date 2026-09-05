class_name BoatVehicle
extends BaseVehicle
## Boat, through the two BaseVehicle seams only. Float probes sample WaterSurface's flat height
## and push the hull up, thrust acts at the stern, and the rudder makes yaw torque. The force
## magnitudes are pure static functions with RayWheel-style one-tick clamps; do not weaken any of
## them. Hull geometry is node knobs, while drive tuning lives in boat_spec.tres.

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
var _yaw_inertia := 1000.0
var _waters: Array[WaterSurface] = []  ## the level's water bodies, collected once (see _find_water)
var _waters_found := false             ## one-shot guard, the _terrains_found shape


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


func _tick_extras(input: VehicleInput, delta: float) -> void:
	var t := telemetry as BoatTelemetry
	if not _waters_found:
		_collect_waters()
		_waters_found = true
	var water := _find_water()
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
		var v_long := linear_velocity.dot(fwd)
		# Hull drag: forward resistance at the COM, while the keel's lateral resistance acts
		# below it at keel_offset, so the hull heels in turns.
		apply_central_force(fwd * VehicleMath.damped_force(v_long, drag_long, spec.mass, delta))
		var v_lat := linear_velocity.dot(right)
		apply_force(right * VehicleMath.damped_force(v_lat, drag_lat, spec.mass, delta),
				up * keel_offset)
		var yaw_rate := angular_velocity.dot(up)
		apply_torque(up * VehicleMath.damped_force(yaw_rate, drag_yaw, _yaw_inertia, delta))

		if stern_wet:
			# Thrust at the stern, below the COM, so the bow rises under throttle. The gear owns
			# direction and reverse thrust is weaker, like a real outdrive.
			apply_force(fwd * thrust_force * thrust_scale(input.throttle, reverse_thrust_factor),
					global_transform.basis * prop_offset)
			# Rudder torque scaled by flow (hull speed plus prop wash). Steer negative is left
			# and +Y torque yaws left, so the sign flips.
			var authority := rudder_authority(v_long, input.throttle)
			apply_torque(up * (-_steer * rudder_torque * authority))

	# trim is modeled (honest-model, see BoatTelemetry); pitch/roll are the base's.
	_trim = BoatTelemetry.trim_step(_trim, input.throttle, BoatTelemetry.TRIM_RATE, delta)
	t.rudder_actual = roundi(clampf(_steer, -1.0, 1.0) * 100.0)
	t.trim = roundi(_trim)

	var mean_depth := depth_sum / maxf(1.0, probe_points.size())
	var aground := aground_now(water != null, mean_depth, linear_velocity.y,
			float_depth, AGROUND_SHALLOW_FRAC, AGROUND_VSPEED)
	_aground_hold = aground_hold(_aground_hold, aground, delta)
	t.ground = _aground_hold >= AGROUND_DEBOUNCE
	t.status = VehicleTelemetry.with_status_bit(t.status, VehicleTelemetry.ST_GROUND, t.ground)


func respawn() -> void:
	super.respawn()
	_trim = 0.0
	_aground_hold = 0.0


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

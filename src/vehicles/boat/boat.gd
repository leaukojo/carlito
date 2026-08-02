class_name BoatVehicle
extends BaseVehicle
## Boat. A real BaseVehicle subclass because it owns the buoyancy/
## thrust/rudder locomotion module the base has no concept of. It never forks
## _physics_process — it plugs into the two base seams (_make_telemetry, _tick_extras),
## exactly like the tractor.
##
## Locomotion: float probes sample the WaterSurface height API and
## push the hull up; thrust at the stern; rudder yaw torque. All force magnitudes are
## pure static fns with the RayWheel one-tick clamps (60 Hz locked tick) —
## a damper/drag term may never exceed the impulse that reverses/zeroes the velocity
## it acts on within one tick, and buoyancy is hard-capped like max_suspension_force.
## Unit-tested in tests/test_boat.gd. DO NOT remove or weaken any clamp.
##
## Hull geometry (probes, prop position) is authored here as node knobs, like the
## tractor's implement knobs; drive tuning (mass, rudder slew) is boat_spec.tres.

const RUDDER_SPEED_REF := 6.0   ## m/s of forward flow that gives full rudder authority
const RUDDER_PROP_WASH := 0.5   ## authority contributed by full throttle prop wash

@export_group("Buoyancy")
## Float probe positions, body space (bow = -Z). 4-6 probes.
@export var probe_points := PackedVector3Array([
	Vector3(-0.8, -0.2, -1.6), Vector3(0.8, -0.2, -1.6),
	Vector3(-0.8, -0.2, 1.8), Vector3(0.8, -0.2, 1.8),
])
## Rest submersion (m) of the probes when floating level: the per-probe spring rate is
## derived from it (k = m*g / (probes * float_depth)), so the boat floats by construction.
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

var _trim := 0.0        ## %, chases forward throttle (BoatTelemetry.trim_step)
var _gravity := 9.8
var _yaw_inertia := 1000.0


func _make_telemetry() -> VehicleTelemetry:
	return BoatTelemetry.new()


func _ready() -> void:
	super._ready()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	# Yaw inertia proxy from the hull footprint the probes span — used only to CLAMP the
	# yaw damping torque (same role corner_mass plays for RayWheel's force caps).
	var length := 0.0
	var width := 0.0
	for p in probe_points:
		length = maxf(length, absf(p.z) * 2.0)
		width = maxf(width, absf(p.x) * 2.0)
	_yaw_inertia = VehicleMath.inertia_of(spec.mass, length, width)


func _tick_extras(input: InputRouter.VehicleInput, delta: float) -> void:
	var t := telemetry as BoatTelemetry
	var water := _find_water()
	var stern_wet := false
	var submerged := 0

	if water != null:
		var probe_count := maxf(1.0, probe_points.size())
		var probe_mass := spec.mass / probe_count
		var k := spec.mass * _gravity / (probe_count * float_depth)
		var damp := buoyancy_damp * 2.0 * sqrt(k * probe_mass)
		var max_f := max_probe_force_factor * probe_mass * _gravity
		var water_y := water.get_height(global_position)
		for p_local in probe_points:
			var p := global_transform * p_local
			var vert_vel := (linear_velocity + angular_velocity.cross(p - global_position)).y
			var f := probe_force(water_y - p.y, vert_vel, k, damp, probe_mass, delta, max_f)
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
		# Hull drag: forward resistance at the COM; the keel's lateral resistance acts
		# BELOW the COM (keel_offset) so the hull heels in turns — both one-tick clamped.
		apply_central_force(fwd * VehicleMath.damped_force(v_long, drag_long, spec.mass, delta))
		var v_lat := linear_velocity.dot(right)
		apply_force(right * VehicleMath.damped_force(v_lat, drag_lat, spec.mass, delta),
				up * keel_offset)
		var yaw_rate := angular_velocity.dot(up)
		apply_torque(up * VehicleMath.damped_force(yaw_rate, drag_yaw, _yaw_inertia, delta))

		if stern_wet:
			# Thrust at the stern, below the COM -> the bow rises under throttle. Throttle
			# arrives signed by the arbitration (gear owns direction on the bridge, S = R
			# locally); reverse thrust is weaker like a real outdrive.
			apply_force(fwd * thrust_force * thrust_scale(input.throttle, reverse_thrust_factor),
					global_transform.basis * prop_offset)
			# Rudder: yaw torque scaled by flow over the blade (hull speed + prop wash).
			# steer is negative = left; +Y torque yaws left, so the sign flips.
			var authority := rudder_authority(v_long, input.throttle)
			apply_torque(up * (-_steer * rudder_torque * authority))

	# Telemetry: pitch/roll straight out of the body basis, rudder as applied (the base
	# slews _steer), trim modeled (honest-model latitude — see BoatTelemetry).
	_trim = BoatTelemetry.trim_step(_trim, input.throttle, BoatTelemetry.TRIM_RATE, delta)
	t.pitch = VehicleMath.pitch_deg(global_transform.basis)
	t.roll = VehicleMath.roll_deg(global_transform.basis)
	t.rudder_actual = roundi(clampf(_steer, -1.0, 1.0) * 100.0)
	t.trim = roundi(_trim)


func respawn() -> void:
	super.respawn()
	_trim = 0.0


## First WaterSurface whose region contains the hull; null when on dry land / ashore.
func _find_water() -> WaterSurface:
	for node in get_tree().get_nodes_in_group(WaterSurface.WATER_GROUP):
		var w := node as WaterSurface
		if w != null and w.contains_xz(global_position):
			return w
	return null


# --- pure force math (unit-tested, one-tick clamped like RayWheel) ------------

## Per-probe buoyancy: spring on depth + damper on the probe's vertical velocity.
## 60 Hz guardrails (RayWheel discipline): the damper may never exceed the
## force that would reverse the vertical velocity within one tick, and the total is
## non-negative (water only pushes up) and hard-capped at max_force.
static func probe_force(depth: float, vert_vel: float, k: float, damp: float,
		probe_mass: float, delta: float, max_force: float) -> float:
	if depth <= 0.0:
		return 0.0
	var tick_cap := probe_mass * absf(vert_vel) / delta
	var damper := clampf(-damp * vert_vel, -tick_cap, tick_cap)
	return clampf(k * depth + damper, 0.0, max_force)


## Signed thrust fraction: forward throttle passes through, reverse is scaled down.
static func thrust_scale(throttle: float, reverse_factor: float) -> float:
	var t := clampf(throttle, -1.0, 1.0)
	return t if t >= 0.0 else t * reverse_factor


## Rudder authority 0..1: no flow over the blade = no turn. Hull speed provides flow,
## prop wash provides some even from standstill (so the boat can turn out of a dock).
static func rudder_authority(forward_speed: float, throttle: float) -> float:
	return clampf(absf(forward_speed) / RUDDER_SPEED_REF
			+ absf(throttle) * RUDDER_PROP_WASH, 0.0, 1.0)

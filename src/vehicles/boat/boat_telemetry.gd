class_name BoatTelemetry
extends VehicleTelemetry
## Boat telemetry. Adds the boat-only fields; names match the contract signals exactly
## (rudder_actual/trim, awa/aws/twd/tws, stw/sog/cog/current_set/current_drift, depth, sail_angle,
## nav_mode_actual/heading_target). pitch/roll are shared VehicleTelemetry fields written by the
## base. rudder_actual, the four wind readings, the five track/tide readings, the sounding, the
## boom angle and the two autopilot readbacks are read straight from the sim; trim is a modeled
## honest value (same latitude as fuel/coolant/engine_load). A hull with no rig publishes
## sail_angle 0 and never writes it, which is what the two powerboats do.

const TRIM_RATE := 40.0            ## %/s the trim chases its target
const DEPTH_INVALID := -1.0        ## no bottom under the transducer; never 0 (see `sounding`)

const FUEL_RATE_IDLE := 1.5        ## L/h burned just running, no load
const FUEL_RATE_LOAD := 8.5        ## L/h added at full load_frac, on top of idle

const OIL_PRESS_IDLE := 80.0       ## kPa floor, right at idle_rpm (the low-idle droop)
const OIL_PRESS_NOMINAL := 350.0   ## kPa plateau, reached at OIL_PRESS_PLATEAU_FRAC of idle_rpm
const OIL_PRESS_PLATEAU_FRAC := 1.5

const TANK_RATE := 2.0             ## %/s fresh water drains and waste rises while running

var rudder_actual := 0            ## %, contract 'rudder_actual' (- = port/left)
var trim := 0                      ## %, contract 'trim'
var awa := 0.0                     ## deg, contract 'awa' (0 = dead ahead, - = from port)
var aws := 0.0                     ## m/s, contract 'aws'
var twd := 0.0                     ## deg, contract 'twd' (the bearing it comes FROM)
var tws := 0.0                     ## m/s, contract 'tws'
var stw := 0.0                     ## m/s, contract 'stw' (through the water, unsigned)
var sog := 0.0                     ## m/s, contract 'sog' (over the ground, unsigned)
var cog := 0.0                     ## deg, contract 'cog' (the bearing actually travelled)
var current_set := 0.0             ## deg, contract 'current_set' (the bearing the tide flows TOWARD)
var current_drift := 0.0           ## m/s, contract 'current_drift'
var depth := 0.0                   ## m, contract 'depth' (DEPTH_INVALID = no bottom)
var fuel_rate := 0.0               ## L/h, contract 'fuel_rate' (modeled, see fuel_rate_model())
var oil_press := 0.0               ## kPa, contract 'oil_press' (modeled, see oil_press_model())
var tank_level: Array = [100.0, 0.0, 50.0]  ## %, contract 'tank_level' (fresh/waste/live-well)
var sail_angle := 0.0              ## deg, contract 'sail_angle' (boom off the centreline, signed like awa)
var nav_mode_actual := 0           ## contract 'nav_mode_actual' (BoatAutopilot ladder)
var heading_target := 0.0          ## deg, contract 'heading_target' (tracks heading in STANDBY)


## Modeled engine trim: trims up with forward throttle demand, returns to zero
## off-throttle/in reverse, slewing at `rate` %/s.
static func trim_step(current: float, throttle_demand: float, rate: float, delta: float) -> float:
	var target := clampf(throttle_demand, 0.0, 1.0) * 100.0
	return move_toward(current, target, rate * delta)


## Apparent wind as (speed m/s, angle deg from the bow, + to starboard). Measured entirely in
## the water plane — WindField is horizontal, and the heading axes are flattened too, or a
## heeling hull would read a lateral component shortened by the cosine of its own heel. Zero
## relative air (running dead downwind at exactly wind speed) leaves the angle undefined; 0.
static func apparent_wind(velocity: Vector3, wind: Vector3, basis: Basis) -> Vector2:
	var rel := velocity - wind          # points where the air comes FROM, in world space
	var flat := Vector3(rel.x, 0.0, rel.z)
	var flow := flat.length()
	if flow < 1e-6:
		return Vector2.ZERO
	var bow := Vector3(-basis.z.x, 0.0, -basis.z.z)
	if bow.length_squared() < 1e-12:
		return Vector2(flow, 0.0)       # bow straight up or down: no heading to measure from
	bow = bow.normalized()
	var stbd := Vector3(-bow.z, 0.0, bow.x)   # the bow turned 90 deg right in the water plane
	return Vector2(flow, rad_to_deg(atan2(flat.dot(stbd), flat.dot(bow))))


## Any horizontal flow as (speed m/s, compass bearing deg it flows TOWARD). Flattened to the
## water plane because these are speeds ACROSS the water: a hull riding a wave must not read its
## own heave as speed made good. A zero-length flow has no bearing and reads (0, 0). This is the
## reading a CURRENT wants as-is — marine practice names a current by where it goes, so
## `current_set` calls this directly and only `true_wind` below inverts.
static func flow_toward(v: Vector3) -> Vector2:
	var flat := Vector3(v.x, 0.0, v.z)
	var flow := flat.length()
	if flow < 1e-6:
		return Vector2.ZERO
	return Vector2(flow, VehicleTelemetry.heading_from_forward(flat))


## Water depth below the transducer, which rides the keel line, so this is under-keel clearance
## and 0 means the bed is against the hull. DEPTH_INVALID (-1) when there is no bottom to report —
## never 0, which is precisely the value a shoal alarm acts on; the `agl` rule. The clamp at 0 is
## honest rather than cosmetic: a bed at or above the keel leaves no water under it, and a
## negative depth is a number no sounder produces.
static func sounding(has_bottom: bool, transducer_y: float, seabed_y: float) -> float:
	if not has_bottom:
		return DEPTH_INVALID
	return maxf(0.0, transducer_y - seabed_y)


## True wind as (speed m/s, bearing deg it comes FROM). `WindField.direction_deg` is the heading
## the wind blows TOWARD, so this is the one place the marine inversion happens — a wind is named
## by where it comes from and a current by where it goes, and that asymmetry is the convention,
## not an oversight. Dead calm reads (0, 0).
static func true_wind(wind: Vector3) -> Vector2:
	var f := flow_toward(wind)
	if f.x <= 0.0:
		return Vector2.ZERO
	return Vector2(f.x, fposmod(f.y + 180.0, 360.0))


## Modeled fuel burn rate, contract 'fuel_rate': idle burn plus a load term, zero with the key
## not at Ignition. A labelled honest model, like fuel/coolant/engine_load — it does not
## reconcile against the 'fuel' percent-of-tank drain, which is a separate abstraction.
static func fuel_rate_model(load_frac: float, running: bool) -> float:
	if not running:
		return 0.0
	return FUEL_RATE_IDLE + FUEL_RATE_LOAD * clampf(load_frac, 0.0, 1.0)


## Modeled oil pressure, contract 'oil_press': zero with the key not at Ignition, otherwise a
## low-idle droop rising to a nominal plateau by OIL_PRESS_PLATEAU_FRAC * idle_rpm. Gated on
## `running` rather than `engine_rpm <= 0`: the boat's inert engine model never actually zeros
## Drivetrain.rpm off-ignition (throttle is forced 0, so rpm just lerps down to idle_rpm and
## holds there), the same reason fuel_step/coolant_target/battery_volts all take `running`
## explicitly rather than reading it off rpm. `engine_rpm` here is the boat's own
## Drivetrain.rpm, which reaches no contract signal of its own — the boat drives no gearbox
## limiter, so this is the one place it is read.
static func oil_press_model(engine_rpm: float, idle_rpm: float, running: bool) -> float:
	if not running:
		return 0.0
	var plateau_rpm := idle_rpm * OIL_PRESS_PLATEAU_FRAC
	var t := clampf(inverse_lerp(idle_rpm, plateau_rpm, engine_rpm), 0.0, 1.0)
	return lerpf(OIL_PRESS_IDLE, OIL_PRESS_NOMINAL, t)


## Modeled tank levels, contract 'tank_level' (fresh/waste/live-well). While running, fresh
## water drains and waste rises at the same rate, both clamped to [0, 100]; the live-well is
## held, since nothing in the sim fills or drains it — an honest omission, not a fiction.
static func tank_step(current: Array, running: bool, delta: float) -> Array:
	if not running:
		return current.duplicate()
	var rate := TANK_RATE * delta
	return [
		clampf(current[0] - rate, 0.0, 100.0),
		clampf(current[1] + rate, 0.0, 100.0),
		current[2],
	]

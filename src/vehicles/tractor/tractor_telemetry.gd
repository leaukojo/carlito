class_name TractorTelemetry
extends VehicleTelemetry
## Tractor telemetry (ISOBUS fields on top of VehicleTelemetry). Field names match the contract
## exactly for Bridge/dashboard name-keyed reads. Most fields are read straight out of the sim;
## engine_load is a modeled honest value; draft_force reports a real applied force, so the rpm
## sag/engine_load/wheel_slip it causes are consequences, not separate terms.

const PTO_RPM_MAX := 1200          ## contract 'pto_rpm' range max

## Engine rpm at which the PTO stub turns at its named speed. Driveline gearing, not a feel
## knob: at the shipped redline (2600) the 1000 mode lands at 1182 rpm, inside PTO_RPM_MAX.
## test_tractor pins this against the shipped spec so a redline change can't silently clamp it.
const PTO_RATED_RPM := 2200.0
const PTO_MODE_540 := 0            ## contract 'pto_mode' enum
const PTO_MODE_1000 := 1

## Wheel speed below which slip reads 0 — near-zero wheel/ground speeds make the ratio noise.
const SLIP_FLOOR_KMH := 0.5

## Travel speed (m/s) at which draft reaches its rated value (~7 km/h). A labelled model: real
## draft is mostly speed-independent, but a constant rearward force would shove a standing tractor
## backwards out of the furrow, so only the speed-dependent ramp is modeled. It is also the 60 Hz
## stability margin, since below the reference this is a linear damper F = -k*v, stable while
## k*dt/m < 2 (0.025 at the shipped 12 kN / 4 t).
const DRAFT_SPEED_REF := 2.0

var hitch_pos_actual := 100        ## %, contract 'hitch_pos_actual'
var pto_state := false             ## contract 'pto_state'
var pto_rpm := 0                   ## rev/min, contract 'pto_rpm'
var engine_load := 0               ## %, contract 'engine_load'
var implement_connected := false   ## contract 'implement_connected' (address claimed)
var implement_type := 0            ## ISO device class, contract 'implement_type' (0 = none)
var diff_lock_state := false       ## contract 'diff_lock_state' (driveline state, not the request)
var fwd_drive_state := false       ## contract 'fwd_drive_state' (driveline state, not the request)
var wheel_speed := 0.0             ## km/h, contract 'wheel_speed' (ISO wheel-based)
var ground_speed := 0.0            ## km/h, contract 'ground_speed' (ISO ground-based / radar)
var wheel_slip := 0                ## %, contract 'wheel_slip'
var draft_force := 0               ## %, contract 'draft_force' (of rated draft; 0 out of the soil)


## engine_load_pct and hours_step live on VehicleTelemetry, not here: engine_load (SPN 92) is a
## shared tractor/truck signal, so the model is one, not two.

## Shaft speed the selected PTO mode names, rev/min. Falls back to 540 for any byte but 1000.
static func pto_speed_for_mode(mode: int) -> float:
	return 1000.0 if mode == PTO_MODE_1000 else 540.0


## Engine rpm -> PTO shaft rpm gearing for the selected mode.
static func pto_ratio_for_mode(mode: int) -> float:
	return pto_speed_for_mode(mode) / PTO_RATED_RPM


## PTO stub speed at an engine speed. Clamp is a backstop only — see PTO_RATED_RPM, the shipped
## gearing never reaches it.
static func pto_shaft_rpm(engine_rpm: float, mode: int) -> int:
	return int(clampf(engine_rpm * pto_ratio_for_mode(mode), 0.0, float(PTO_RPM_MAX)))


## ISO wheel-based speed, km/h, from the drive axle's mean spin. `radius` is the physics radius
## (RayWheel integrates one radius; the tractor's differing wheel sizes are visual only).
static func wheel_kmh(axle_omega: float, radius: float) -> float:
	return absf(axle_omega) * radius * 3.6


## ISO wheel slip %, unsigned like J1939 SPN 1858: braking slip and anything below
## SLIP_FLOOR_KMH both read 0.
static func slip_pct(wheel_speed_kmh: float, ground_speed_kmh: float) -> float:
	if wheel_speed_kmh <= SLIP_FLOOR_KMH:
		return 0.0
	return clampf((wheel_speed_kmh - ground_speed_kmh) / wheel_speed_kmh * 100.0, 0.0, 100.0)


## Fraction of the implement's working depth still in soil: 1 at full lower, 0 once lifted clear.
## `ball_lift_m` is the linkage's own lift, `tool_depth_m` the implement's declared reach. The
## balls travel 0.57 m over the stroke, so a 0.055 m tool is in soil for only the bottom ~10%.
static func draft_depth01(ball_lift_m: float, tool_depth_m: float) -> float:
	if tool_depth_m <= 0.0:
		return 0.0
	return clampf((tool_depth_m - ball_lift_m) / tool_depth_m, 0.0, 1.0)


## Draft force in newtons, signed along the tractor's forward axis and negative while driving
## forward, because draft always resists travel. The whole model is rated draft x depth x soil x
## speed ramp, applied to the chassis as a real force.
##
## The 60 Hz backstop is that resistance may never exceed the force reversing travel in one tick.
## It bounds only the linear impulse: the force acts ~1.3 m behind the centre of mass, so it can
## still spin the chassis. Keep the rating in the range test_tractor asserts and neither limit is
## in play.
static func draft_newtons(v_fwd: float, depth01: float, soil01: float, max_force: float,
		body_mass: float, delta: float) -> float:
	var mag := maxf(max_force, 0.0) * clampf(depth01, 0.0, 1.0) * clampf(soil01, 0.0, 1.0) \
			* clampf(absf(v_fwd) / DRAFT_SPEED_REF, 0.0, 1.0)
	mag = minf(mag, body_mass * absf(v_fwd) / maxf(delta, 1e-5))
	return -signf(v_fwd) * mag


## Draft as a percentage of rated draft. Unsigned — direction is "backwards" by definition.
static func draft_pct(force_n: float, max_force: float) -> float:
	if max_force <= 0.0:
		return 0.0
	return clampf(absf(force_n) / max_force * 100.0, 0.0, 100.0)

class_name TractorTelemetry
extends VehicleTelemetry
## Tractor telemetry (ISOBUS fields on top of VehicleTelemetry). Field names match the contract
## exactly (Bridge/dashboard reads are name-keyed). engine_load is a modeled honest value;
## draft_force reports a real applied force, so the rpm sag / engine_load / wheel_slip it causes
## are consequences, not separate terms.

const PTO_RPM_MAX := 1200          ## contract 'pto_rpm' range max

## Engine rpm at which the PTO stub turns at its named speed. Driveline gearing, not a feel knob:
## at the shipped redline (2600) the 1000 mode lands at 1182 rpm, inside PTO_RPM_MAX.
## test_tractor pins it against the shipped spec.
const PTO_RATED_RPM := 2200.0
const PTO_MODE_540 := 0            ## contract 'pto_mode' enum
const PTO_MODE_1000 := 1

## Wheel speed below which slip reads 0 (the ratio is noise near zero).
const SLIP_FLOOR_KMH := 0.5

## Speed (km/h) every implement's `draft_rating()` is given at: D497's typical ploughing speed.
const DRAFT_S_REF_KMH := 7.0

## Hitch speed (m/s) below which draft fades linearly to 0, so a standing tractor is not shoved out
## of the furrow. The bound it sets:
## - Draft acts along the forward axis f̂ at r = hitch point - COM, so the hitch's own speed meets the
##   effective mass m_eff = 1 / (1/m + (r × f̂)·I⁻¹(r × f̂)): the body plus the pitch the arm turns.
## - Below DRAFT_V_CRAWL the force is a damper on that speed, k = F_crawl / DRAFT_V_CRAWL, F_crawl
##   the largest `draft_rating() · draft_speed01(0)` (the plough's 16.2 kN). An explicit damper is
##   stable while k·dt/m_eff < 2; test_tractor holds it under 0.5 at the lowest m_eff it measures.
## - m_eff is lowest on the bare tractor, 5.38 t (computed: plough down 6.21 t, harrow 5.77 t), so
##   the smallest round speed inside that is 0.15 m/s, k·dt/m_eff 0.33 (0.1 sits on 0.50).
const DRAFT_V_CRAWL := 0.15

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
var axle_load := 0.0               ## kg, contract 'axle_load' (rear axle, off the suspension)


## engine_load_pct and hours_step live on VehicleTelemetry: engine_load (SPN 92) is a shared
## tractor/truck signal, so there is one model.

## Shaft speed the selected PTO mode names, rev/min. Falls back to 540 for any byte but 1000.
static func pto_speed_for_mode(mode: int) -> float:
	return 1000.0 if mode == PTO_MODE_1000 else 540.0


## Engine rpm -> PTO shaft rpm gearing for the selected mode.
static func pto_ratio_for_mode(mode: int) -> float:
	return pto_speed_for_mode(mode) / PTO_RATED_RPM


## PTO stub speed at an engine speed. The clamp is a backstop; the shipped gearing never reaches it.
static func pto_shaft_rpm(engine_rpm: float, mode: int) -> int:
	return int(clampf(engine_rpm * pto_ratio_for_mode(mode), 0.0, float(PTO_RPM_MAX)))


## ISO wheel-based speed, km/h, from the drive axle's mean spin. `radius` is that axle's physics
## radius, the tyre drawn under it.
static func wheel_kmh(axle_omega: float, radius: float) -> float:
	return absf(axle_omega) * radius * 3.6


## ISO wheel slip %, unsigned like J1939 SPN 1858: braking slip and anything below
## SLIP_FLOOR_KMH both read 0.
static func slip_pct(wheel_speed_kmh: float, ground_speed_kmh: float) -> float:
	if wheel_speed_kmh <= SLIP_FLOOR_KMH:
		return 0.0
	return clampf((wheel_speed_kmh - ground_speed_kmh) / wheel_speed_kmh * 100.0, 0.0, 100.0)


## Fraction of the implement's working depth still in soil: 1 at full lower, 0 once lifted clear.
## `ball_lift_m` is the linkage's lift, `tool_depth_m` the implement's declared reach. The balls
## travel 0.57 m over the stroke, so the plough's 0.25 m shares are in soil over its bottom ~43%.
static func draft_depth01(ball_lift_m: float, tool_depth_m: float) -> float:
	if tool_depth_m <= 0.0:
		return 0.0
	return clampf((tool_depth_m - ball_lift_m) / tool_depth_m, 0.0, 1.0)


## D497's speed factor g(S) = (A + B S + C S²) / (A + B S_ref + C S_ref²) off `shape` (ImplementBase.
## draft_shape), S in km/h, held at the range top `shape.w`: 1 at DRAFT_S_REF_KMH. 0 for a shape
## with no positive value at the reference.
static func draft_speed01(s_kmh: float, shape: Vector4) -> float:
	var at_ref := shape.x + (shape.y + shape.z * DRAFT_S_REF_KMH) * DRAFT_S_REF_KMH
	if at_ref <= 0.0:
		return 0.0
	var s := minf(absf(s_kmh), maxf(shape.w, 0.0))
	return maxf(shape.x + (shape.y + shape.z * s) * s, 0.0) / at_ref


## Draft force in newtons along the tractor's forward axis, negative while the hitch moves forward
## (draft resists travel): rating x depth x soil x D497's g(S) x the crawl taper, S the hitch's
## speed, applied to the chassis as a real force.
##
## The one-tick cap: resistance never exceeds `eff_mass · |v_hitch| / dt`, the force that would
## stop the hitch in one tick, so it bounds the angular impulse with the linear one. A backstop:
## DRAFT_V_CRAWL keeps the shipped ratings inside it.
static func draft_newtons(v_hitch: float, depth01: float, soil01: float, rating: float,
		shape: Vector4, eff_mass: float, delta: float) -> float:
	var v := absf(v_hitch)
	var mag := maxf(rating, 0.0) * clampf(depth01, 0.0, 1.0) * clampf(soil01, 0.0, 1.0) \
			* draft_speed01(v * 3.6, shape) * clampf(v / DRAFT_V_CRAWL, 0.0, 1.0)
	mag = minf(mag, maxf(eff_mass, 0.0) * v / maxf(delta, 1e-5))
	return -signf(v_hitch) * mag


## Draft as a percentage of rated draft. Unsigned: draft is always backwards.
static func draft_pct(force_n: float, max_force: float) -> float:
	if max_force <= 0.0:
		return 0.0
	return clampf(absf(force_n) / max_force * 100.0, 0.0, 100.0)

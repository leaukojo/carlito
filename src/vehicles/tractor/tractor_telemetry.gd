class_name TractorTelemetry
extends VehicleTelemetry
## Tractor telemetry (ISOBUS flavor). Adds the ISOBUS "out" fields on top of the
## ground-vehicle VehicleTelemetry. Field names are EXACTLY the contract names so the Bridge's
## name-keyed marshaling and the dashboard's t.get(name) reads work unchanged.
##
## hitch_pos_actual / pto_state / pto_rpm, the two speeds, wheel_slip and the two driveline
## state flags are read straight out of the tractor sim (real values, no derived fictions);
## engine_load is a modeled honest value (same latitude as fuel/coolant/battery) but built out
## of the drivetrain's own torque curve at the drivetrain's own rpm, computed by the pure
## VehicleTelemetry.engine_load_pct and unit-tested.
##
## draft_force is the same shape as neither: the draft model below is an honest model of soil
## resistance, but its output is APPLIED TO THE CHASSIS as a real force, so the published
## percentage is a report of something that happened to the body — and the rpm sag, engine_load
## and wheel_slip that come with it are consequences of that force, not extra terms.
##
## The two implement fields report the linkage's actual state. DETACHED is not a missing
## reading — it is false / CLASS_NONE, published every tick like any other value, so the
## dashboard cluster stays the same shape whatever is (or is not) on the hitch.

const PTO_RPM_MAX := 1200          ## contract 'pto_rpm' range max

## Engine speed at which the PTO stub turns at its NAMED speed — a real tractor's "rated PTO
## speed" mark on the tachometer. It is driveline gearing, not a feel knob, so it lives here
## next to the range it has to respect rather than as an @export: at the shipped redline
## (2600) the 1000 mode lands at 1182 rev/min, inside PTO_RPM_MAX without the clamp biting.
## test_tractor pins that against the shipped tractor spec so a redline change can't silently clamp.
const PTO_RATED_RPM := 2200.0
const PTO_MODE_540 := 0            ## contract 'pto_mode' enum
const PTO_MODE_1000 := 1

## Wheel speed below which slip reads 0. A stationary tractor's wheel and ground speeds are
## both ~0, and their ratio is meaningless noise; ISO slip only means something once turning.
const SLIP_FLOOR_KMH := 0.5

## Travel speed (m/s) at which draft reaches its full rated value — ~7 km/h, a real ploughing
## speed. A real plough's draft is mostly speed-INDEPENDENT (the constant term of the ASAE draft
## equation), but a constant rearward force is exactly what must NOT be modelled: it would shove
## a standing tractor backwards out of the furrow, which soil does not do. So the model keeps the
## speed-dependent part only — resistance builds as the tools are actually driven through the
## soil and saturates here.
##
## THIS RAMP IS ALSO THE 60 Hz STABILITY MARGIN, and the reason a large rearward force is safe
## at the locked tick. Below the reference the model is exactly a linear damper, F = -k*v with
## k = rated_draft / DRAFT_SPEED_REF, and an explicit damper is stable while k*dt/m < 2: at the
## shipped 12 kN on 4 t that is 6000 * (1/60) / 4000 = 0.025, two orders of margin, and the
## feedback is negative (draft falls as the chassis slows) so it cannot ring. The one-tick cap in
## draft_newtons is a BACKSTOP for a future rating edit, not what holds the tick together —
## test_tractor pins the margin against the shipped rating so raising it past here fails CI.
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
var engine_hours := 0.0            ## h, contract 'engine_hours' (hour meter; survives respawn)
var draft_force := 0               ## %, contract 'draft_force' (of rated draft; 0 out of the soil)


## engine_load_pct lives on VehicleTelemetry now, not here: engine_load is a shared signal
## (the tractor reads SPN 92 as ISOBUS, the truck as J1939) and the model must be one, not two.
## The same goes for hours_step / engine_hours.

## Shaft speed the selected PTO mode names, in rev/min. 540 and 1000 are SHAFT speeds, which
## is what a real selector picks — different gearing, not a different engine speed. Anything
## but the 1000 mode falls back to 540, the safe default for an unknown byte off the bus.
static func pto_speed_for_mode(mode: int) -> float:
	return 1000.0 if mode == PTO_MODE_1000 else 540.0


## Engine rpm -> PTO shaft rpm gearing for the selected mode.
static func pto_ratio_for_mode(mode: int) -> float:
	return pto_speed_for_mode(mode) / PTO_RATED_RPM


## PTO stub speed at an engine speed, through the selected mode's gearing. Clamped to the
## contract range as a backstop only — see PTO_RATED_RPM, the shipped gearing never reaches it.
static func pto_shaft_rpm(engine_rpm: float, mode: int) -> int:
	return int(clampf(engine_rpm * pto_ratio_for_mode(mode), 0.0, float(PTO_RPM_MAX)))


## ISO wheel-based speed in km/h: the DRIVELINE's own speed, from the mean spin of the drive
## axle through the tire radius. `radius` is the PHYSICS radius (spec.wheel_radius) — the
## tractor's big rears and small fronts are visual only, RayWheel integrates one radius.
static func wheel_kmh(axle_omega: float, radius: float) -> float:
	return absf(axle_omega) * radius * 3.6


## ISO wheel slip %: how far the wheel-based speed runs ahead of the ground-based one, as a
## fraction of the wheel speed. Unsigned like J1939 SPN 1858 — braking slip (ground running
## faster than the wheels) reads 0, and so does anything below SLIP_FLOOR_KMH.
static func slip_pct(wheel_speed_kmh: float, ground_speed_kmh: float) -> float:
	if wheel_speed_kmh <= SLIP_FLOOR_KMH:
		return 0.0
	return clampf((wheel_speed_kmh - ground_speed_kmh) / wheel_speed_kmh * 100.0, 0.0, 100.0)


## How deep the implement's tools still are, as a fraction of their full working depth: 1 at full
## lower, 0 once the linkage has lifted them clear of the soil. `ball_lift_m` is the linkage's own
## lift (ThreePointHitch.ball_lift), so the depth and the drawn pose come from the same solve, and
## `tool_depth_m` is the IMPLEMENT's own declared reach (ImplementBase.tool_depth) so each machine
## leaves the soil when its own steel does.
##
## Consequence worth knowing before tuning: the balls travel 0.57 m over the hitch stroke, so a
## tool reaching 0.055 m down is in the soil for only the bottom ~10 % of it. That is geometry,
## not a model choice — the lever for a wider depth sweep is the implement's authored reach.
static func draft_depth01(ball_lift_m: float, tool_depth_m: float) -> float:
	if tool_depth_m <= 0.0:
		return 0.0
	return clampf((tool_depth_m - ball_lift_m) / tool_depth_m, 0.0, 1.0)


## The draft force in newtons, SIGNED along the tractor's forward axis — negative while driving
## forward, because draft is a RESISTANCE and always opposes travel. `soil01` is how strongly the
## ground under the hitch is the ploughable field, `max_force` the tractor's rated draft.
##
## This is the whole model: rated draft x depth x soil x speed ramp. It is applied to the chassis
## as a real force, and nothing else in the tractor reads it — rpm sag, engine_load and
## wheel_slip move because the body was pulled back, which is the point of the signal.
##
## 60 Hz backstop (same shape as the boat's damped_force): a resistance may never exceed the
## force that would reverse the tractor's travel inside one tick. Read DRAFT_SPEED_REF for what
## actually keeps this stable — the ramp is a linear damper with two orders of margin, and it
## dominates this cap by a factor of ~40 at the shipped rating, so the cap is UNREACHABLE until
## someone raises `draft_max_force` past ~480 kN. It is here for that edit, and it bounds only the
## LINEAR impulse: the force is applied ~1.3 m behind the centre of mass, so a rating big enough
## to make this bind would still be free to spin the chassis. Keep the rating in the range
## test_tractor asserts and neither limit is in play.
static func draft_newtons(v_fwd: float, depth01: float, soil01: float, max_force: float,
		body_mass: float, delta: float) -> float:
	var mag := maxf(max_force, 0.0) * clampf(depth01, 0.0, 1.0) * clampf(soil01, 0.0, 1.0) \
			* clampf(absf(v_fwd) / DRAFT_SPEED_REF, 0.0, 1.0)
	mag = minf(mag, body_mass * absf(v_fwd) / maxf(delta, 1e-5))
	return -signf(v_fwd) * mag


## Draft as the contract's percentage: the force actually applied over the tractor's rated draft.
## Unsigned — the bar reports the size of the pull, its direction is "backwards" by definition.
static func draft_pct(force_n: float, max_force: float) -> float:
	if max_force <= 0.0:
		return 0.0
	return clampf(absf(force_n) / max_force * 100.0, 0.0, 100.0)


func to_bridge_dict() -> Dictionary:
	var d := super()
	d["hitch_pos_actual"] = hitch_pos_actual
	d["pto_state"] = pto_state
	d["pto_rpm"] = pto_rpm
	d["engine_load"] = engine_load
	d["implement_connected"] = implement_connected
	d["implement_type"] = implement_type
	d["diff_lock_state"] = diff_lock_state
	d["fwd_drive_state"] = fwd_drive_state
	d["wheel_speed"] = wheel_speed
	d["ground_speed"] = ground_speed
	d["wheel_slip"] = wheel_slip
	d["engine_hours"] = engine_hours
	d["draft_force"] = draft_force
	return d

class_name Drivetrain
extends RefCounted
## Simplified clutch-less, diff-less drivetrain: engine torque curve ->
## gearbox (RAMN gear byte semantics) -> drive axle. RPM follows wheel speed through
## the ratio with idle/redline clamps — the *real* RPM signal.
##
## All math lives in static pure functions (unit-tested); the instance only holds
## current gear + smoothed RPM. Approach informed by Dechode/Godot-Advanced-Vehicle
## and Tobalation/GDCustomRaycastVehicle (both MIT, credited in README); no code copied.

## RAMN gear byte: 0x00 = N, 0x01..0x06 = D1-D6, 0xFF = R.
const GEAR_N := 0x00
const GEAR_R := 0xFF

const RADS_TO_RPM := 60.0 / TAU
const RPM_SMOOTH := 8.0  ## 1/s exponential rate the displayed/torque RPM tracks the target

var spec: VehicleSpec
var gear_byte := GEAR_N
var rpm: float


func _init(p_spec: VehicleSpec) -> void:
	spec = p_spec
	rpm = spec.idle_rpm


static func is_drive(byte: int) -> bool:
	return byte >= 1 and byte <= 6


static func is_reverse(byte: int) -> bool:
	return byte == GEAR_R


## Any byte outside the RAMN semantics is treated as Neutral (safe).
static func normalize_byte(byte: int) -> int:
	if is_drive(byte) or is_reverse(byte):
		return byte
	return GEAR_N


## Total engine->wheel ratio, signed by direction (forward +, reverse -), 0 in N.
static func ratio_for_byte(p_spec: VehicleSpec, byte: int) -> float:
	if is_drive(byte):
		return p_spec.gear_ratios[byte - 1] * p_spec.final_drive
	if is_reverse(byte):
		return -p_spec.reverse_ratio * p_spec.final_drive
	return 0.0


## Peak of the engine torque curve — the most this engine can ever make, at ANY rpm. The
## denominator for engine load (a load normalized against the torque available at the CURRENT
## rpm would cancel to plain throttle) and the garage's headline torque figure.
static func peak_torque(p_spec: VehicleSpec) -> float:
	var peak := 0.0
	for p in p_spec.torque_curve:
		peak = maxf(peak, p.y)
	return peak


## Full-throttle engine torque at rpm; 0 at/above redline (soft limiter).
static func engine_torque(p_spec: VehicleSpec, at_rpm: float) -> float:
	if at_rpm >= p_spec.redline_rpm:
		return 0.0
	return VehicleSpec.sample_curve(p_spec.torque_curve, at_rpm)


## RPM implied by wheel speed through the ratio, clamped [idle, redline]; idle in N.
static func rpm_from_wheel(p_spec: VehicleSpec, wheel_omega: float, byte: int) -> float:
	var ratio := ratio_for_byte(p_spec, byte)
	if ratio == 0.0:
		return p_spec.idle_rpm
	return clampf(absf(wheel_omega * ratio) * RADS_TO_RPM, p_spec.idle_rpm, p_spec.redline_rpm)


## Torque delivered to the drive axle, signed by the gear ratio (throttle is a 0..1
## magnitude — direction always comes from the gear).
static func wheel_torque(p_spec: VehicleSpec, at_rpm: float, throttle: float, byte: int) -> float:
	return engine_torque(p_spec, at_rpm) * clampf(throttle, 0.0, 1.0) \
			* ratio_for_byte(p_spec, byte) * p_spec.efficiency


## Common spin speed of a rigidly LOCKED axle: a locked differential is one shaft, so its two
## wheels cannot turn at different speeds. RayWheel is single-inertia, so the momentum-
## conserving result is the plain mean. Averaging only ever shrinks the spread between the two
## wheels, so it adds no energy and needs no 60 Hz clamp of its own.
## Unlocked there is nothing to compute: equal torque to both half-shafts — what BaseVehicle
## already does — IS the open-differential torque law, and the wheels spin independently.
static func locked_axle_omega(omega_a: float, omega_b: float) -> float:
	return (omega_a + omega_b) * 0.5


# --- auxiliary driveline retarder (truck, J1939 SPN 520) ------------------------------------
## Lives here with locked_axle_omega for the same reason: it is DRIVELINE behaviour, gated by a
## VehicleSpec flag (retarder_equipped) and applied by BaseVehicle, not a vehicle subclass. The
## retarder torque joins the other brake torques on the driven wheels, so RayWheel integrates it
## with the same semi-implicit step everything else gets — there is no second brake model.
##
## That placement is load-bearing, and it was measured: applying the retarder as its own
## move_toward AFTER the wheels had ticked over-corrected on the very first tick, threw the
## driven axle straight to slip 1.0 and pulled 8 m/s^2 — an emergency stop wearing a retarder's
## name. An explicit brake step outside the stabilized integrator is exactly what CLAUDE.md's
## wheel-spin note warns about. (The spring brake is different and stays a post-tick write: it
## is a kinematic lock to zero, which can only remove energy.)

## Retarder rating per driven wheel, as a fraction of spec.brake_torque — the 100 % end of the
## 'retarder_state' signal. The number is ARITHMETIC, not a remembered measurement, so it can be
## rechecked from the spec at any time: fully faded in, the whole driven axle makes
## `frac * brake_torque * rear_wheels / wheel_radius` newtons, and dividing by mass gives the
## retardation. On the shipped trucks (brake_torque 9583, r 0.36, two driven wheels) that is
## `frac * 6.66 m/s^2` at 8000 kg and `frac * 7.10` at 7500, so **0.20 lands at 1.3-1.4 m/s^2** —
## a retarder you can feel holding the truck on a grade without it ever standing in for the foot
## brake. `test_truck` asserts that band per shipped spec, so this constant and the figure quoted
## in the docs can no longer drift apart.
##
## It stays an AUXILIARY brake by construction: 0.20 of the per-wheel brake torque is 10 % of the
## four-wheel service brake and ~14 % of what the tires can make, so brake > peak drive >
## handbrake is untouched (also asserted per spec). Raising it further means re-checking the
## settled slip below rather than assuming the cap absorbs it.
const RETARDER_MAX_FRAC := 0.20
const RETARDER_CUTOUT_MS := 1.5  ## m/s below which a driveline brake does nothing at all
const RETARDER_FULL_MS := 8.0    ## m/s (~29 km/h) at which it reaches its rating
## THE CANNOT-LOCK-A-WHEEL BACKSTOP: the slip ratio the retarder will not drive the driven axle
## past, whatever is asked for. At the shipped rating the axle settles at 0.024 slip (garbage
## truck) to 0.029 (firetruck) — under a third of this — because the road needs only ~20-25 % of
## the rear grip budget to answer the retarder. So the cap is a backstop and not the operating
## point; it is here so a rating edit fails visibly instead of quietly skidding the axle.
## `test_truck` pins that margin off the spec's own grip curve and static rear-axle load.
##
## A REAL mechanism, not a fudge: a driveline brake acts on both wheels through the differential
## and has no wheel-by-wheel modulation, so every J1939 truck cuts the retarder back through the
## EBS the moment the driven axle slips — SPN 520 rides ERC1, which IS that interface.
##
## It has to be a SLIP limit and not a force limit, which is worth writing down: a cap at
## mu * N * r bounds the SATURATED road torque, and a locked wheel is already making that much,
## so a force cap permits a full skid (measured: slip 1.0).
const RETARDER_SLIP_TARGET := 0.10


## The retarder's rated torque at one driven wheel (Nm).
static func retarder_rating(brake_torque: float) -> float:
	return maxf(brake_torque, 0.0) * RETARDER_MAX_FRAC


## How much of its rating a driveline retarder can make at this road speed, 0..1. A real
## retarder falls off to nothing at walking pace — it works through the driveline, so there is
## no shaft speed to work against — and it saturates once the truck is properly rolling.
static func retarder_speed_fade(speed_ms: float) -> float:
	return clampf((absf(speed_ms) - RETARDER_CUTOUT_MS) / (RETARDER_FULL_MS - RETARDER_CUTOUT_MS),
			0.0, 1.0)


## What the driver asked for at one driven wheel (Nm): rating x request x speed fade.
static func retarder_demand(request01: float, speed_ms: float, brake_torque: float) -> float:
	return clampf(request01, 0.0, 1.0) * retarder_rating(brake_torque) \
			* retarder_speed_fade(speed_ms)


## The anti-lock backstop (Nm): the most spin this wheel may lose in one tick without being
## pushed past RETARDER_SLIP_TARGET. Returns 0 once the axle is already at or past the target,
## so the retarder simply stops deepening a slip it is not allowed to deepen.
##
## Worked in SLIP VELOCITY against RayWheel's own denominator (LOW_SPEED_FLOOR), so the ratio
## bounded here is the same ratio RayWheel computes — not a second, nearly-identical definition
## of slip.
##
## `road_speed` is the CHASSIS forward velocity and is SIGNED (negative in reverse) — that sign
## is what makes the headroom below work in both directions, so never pass a magnitude here. It
## is deliberately not the per-wheel contact-patch velocity RayWheel calls `v_long`: the two
## differ only by the yaw term across the track (a couple of percent in a hard corner), RayWheel
## does not expose its own, and this is a backstop that does not bite at the shipped rating.
static func retarder_slip_cap(omega: float, road_speed: float, radius: float, inertia: float,
		delta: float) -> float:
	if radius <= 0.0 or delta <= 0.0:
		return 0.0
	var denom := maxf(absf(road_speed), RayWheel.LOW_SPEED_FLOOR)
	var slip_vel := omega * radius - road_speed
	# Headroom toward the braking side, in m/s of slip velocity. Braking drives slip_vel away
	# from travel, so the sign of road_speed says which way "further" is.
	#
	# At a standstill signf() is 0 and this degenerates to a nonzero cap, which is harmless
	# rather than a hole: retarder_torque takes the MINIMUM of this and the demand, and the
	# demand has already been faded to exactly 0 below RETARDER_CUTOUT_MS by the same
	# road_speed. A cap is a ceiling, so a high one grants nothing on its own.
	var headroom := signf(road_speed) * slip_vel + RETARDER_SLIP_TARGET * denom
	return maxf(headroom, 0.0) * maxf(inertia, 0.0) / (radius * delta)


## Retarder braking torque for ONE driven wheel (Nm, unsigned — it always opposes the spin):
## the demand held under the anti-lock backstop. BaseVehicle adds this to that wheel's brake
## torque, so RayWheel does the integrating. `road_speed` is signed — see retarder_slip_cap.
static func retarder_torque(request01: float, road_speed: float, omega: float,
		p_spec: VehicleSpec, delta: float) -> float:
	return minf(retarder_demand(request01, road_speed, p_spec.brake_torque),
			retarder_slip_cap(omega, road_speed, p_spec.wheel_radius, p_spec.wheel_inertia, delta))


## Retarder torque as the contract's percentage: what was ACTUALLY applied across the driven
## axle over its rating. Unsigned — J1939 SPN 520 reports retarder torque negative (it is a
## brake), but the signal publishes the magnitude so the generated bar fills as retardation
## rises; the convention is documented in the contract 'desc' rather than encoded in the range.
static func retarder_pct(applied_nm: float, rated_nm: float) -> float:
	if rated_nm <= 0.0:
		return 0.0
	return clampf(absf(applied_nm) / rated_nm * 100.0, 0.0, 100.0)


## One clutch-less shift step within D1-D6 on rpm thresholds; N/R never auto-shift.
static func auto_shift(p_spec: VehicleSpec, byte: int, at_rpm: float) -> int:
	if not is_drive(byte):
		return normalize_byte(byte)
	if at_rpm >= p_spec.shift_up_rpm and byte < 6:
		return byte + 1
	if at_rpm <= p_spec.shift_down_rpm and byte > 1:
		return byte - 1
	return byte


## Per-tick update: adopt the gear request, update RPM, return drive-axle torque (Nm).
## auto=true (local input): the request is a direction (N / enter-D / R) and the box
## auto-shifts within D1-D6. auto=false (bridge): the byte is exact — the bridge
## gear owns direction and auto-shift is bypassed.
## `ground_speed` is the body's forward road speed (m/s); auto-shift decides on it, not
## on `drive_wheel_omega`, so wheelspin can't fake a high rpm and make the box hunt.
func process(delta: float, throttle: float, drive_wheel_omega: float,
		ground_speed: float, requested_byte: int, auto: bool) -> float:
	var req := normalize_byte(requested_byte)
	if auto:
		if req == GEAR_R or req == GEAR_N:
			gear_byte = req
		elif not is_drive(gear_byte):
			gear_byte = req
		if is_drive(gear_byte):
			# Shift on ROAD speed, not the spinning drive wheel: under wheelspin the
			# wheel over-reads rpm, upshifting early; the taller gear then bogs below the
			# downshift point and drops back -> hunting. The real (spinning) rpm still
			# drives the engine target below and the tach.
			var road_omega := ground_speed / spec.wheel_radius
			gear_byte = auto_shift(spec, gear_byte, rpm_from_wheel(spec, road_omega, gear_byte))
	else:
		gear_byte = req

	var target_rpm: float
	if gear_byte == GEAR_N:
		target_rpm = lerpf(spec.idle_rpm, spec.redline_rpm, clampf(throttle, 0.0, 1.0))
	else:
		target_rpm = rpm_from_wheel(spec, drive_wheel_omega, gear_byte)
	rpm = lerpf(rpm, target_rpm, 1.0 - exp(-RPM_SMOOTH * delta))

	return wheel_torque(spec, rpm, throttle, gear_byte)

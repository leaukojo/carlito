class_name Drivetrain
extends RefCounted
## Clutch-less, diff-less drivetrain: torque curve -> gearbox (RAMN gear byte) -> drive axle.
## RPM follows wheel speed through the ratio, clamped [idle, redline]. Static pure functions; the
## instance holds only the current gear and smoothed RPM. Approach informed by
## Dechode/Godot-Advanced-Vehicle and Tobalation/GDCustomRaycastVehicle (MIT, credited in README);
## no code copied.

## RAMN gear byte: 0x00 = N, 0x01..0x06 = D1-D6, 0xFF = R.
const GEAR_N := 0x00
const GEAR_R := 0xFF
## Tallest drive byte RAMN can express. Bus-defined, not spec-defined: do not replace with
## `gear_ratios.size()`. The shift functions take `mini()` of both, since a short array counts too.
const TOP_GEAR := 6

const RADS_TO_RPM := 60.0 / TAU
const RPM_SMOOTH := 8.0  ## 1/s exponential rate the displayed/torque RPM tracks the target

## m/s below speed_limit_kmh over which the governor fades throttle out, so the vehicle settles
## on the limit instead of hunting (hard cut -> decelerate -> uncut -> accelerate).
const GOVERNOR_BAND := 1.5

## Gear-selection radius (m) for a body with no ground drive, which still walks a gearbox and
## publishes the gear byte without owning a wheel.
const DEFAULT_ROAD_RADIUS := 0.32

var spec: VehicleSpec
## Radius the gear-selection scale (`ground_speed / road_radius`) is measured against, declared
## here rather than read off the spec because a wheel-less body still needs it.
var road_radius: float
var gear_byte := GEAR_N
var rpm: float
## Throttle actually delivered this tick, 0..1, after the governor and rev limiter. Telemetry
## reads this, not `input.throttle` (rule 3): a governed vehicle holds the pedal down while fuel
## is cut.
var applied_throttle := 0.0


func _init(p_spec: VehicleSpec) -> void:
	spec = p_spec
	road_radius = p_spec.ground_drive.wheel_radius if p_spec.ground_drive != null \
			else DEFAULT_ROAD_RADIUS
	rpm = spec.idle_rpm


static func is_drive(byte: int) -> bool:
	return byte >= 1 and byte <= TOP_GEAR


static func is_reverse(byte: int) -> bool:
	return byte == GEAR_R


## Any byte outside RAMN semantics is Neutral (safe).
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


## Peak of the torque curve, at any rpm. The denominator for engine_load, since the current-rpm
## torque would cancel to plain throttle.
static func peak_torque(p_spec: VehicleSpec) -> float:
	var peak := 0.0
	for p in p_spec.torque_curve:
		peak = maxf(peak, p.y)
	return peak


## Full-throttle torque at rpm, off the curve. Redline is not handled here: the limiter is a
## fuel cut (`limiter_cut`, applied via `applied_throttle`), so the curve stays honest past it.
static func engine_torque(p_spec: VehicleSpec, at_rpm: float) -> float:
	return VehicleSpec.sample_curve(p_spec.torque_curve, at_rpm)


## Engine speed the wheels impose through the ratio (rpm), unclamped; idle in N. This is what
## the limiter judges — clutch-less, so the engine really can be driven past redline.
static func wheel_engine_rpm(p_spec: VehicleSpec, wheel_omega: float, byte: int) -> float:
	var ratio := ratio_for_byte(p_spec, byte)
	if ratio == 0.0:
		return p_spec.idle_rpm
	return absf(wheel_omega * ratio) * RADS_TO_RPM


## RPM clamped [idle, redline]; idle in N. The published rpm (dash needle, `rpm` bridge signal).
## Never gate fuel on this: the smoothing lerp settles an epsilon short of redline.
static func rpm_from_wheel(p_spec: VehicleSpec, wheel_omega: float, byte: int) -> float:
	return clampf(wheel_engine_rpm(p_spec, wheel_omega, byte), p_spec.idle_rpm, p_spec.redline_rpm)


## Rev limiter: does the engine get fuel at this crank speed? Feed it `wheel_engine_rpm`, never
## the clamped `rpm`. A hard cut on purpose: any visible fade band would eat real torque below
## redline and move shipped top speeds.
static func limiter_cut(p_spec: VehicleSpec, engine_rpm: float) -> bool:
	return engine_rpm >= p_spec.redline_rpm


## Fraction of throttle that reaches the engine at this road speed, 1.0 ungoverned. Fades
## linearly to 0 across the last GOVERNOR_BAND m/s below the limit. Unsigned: it governs reverse.
static func governor_scale(p_spec: VehicleSpec, ground_speed: float) -> float:
	if p_spec.speed_limit_kmh <= 0.0:
		return 1.0
	var limit := p_spec.speed_limit_kmh / 3.6
	return clampf((limit - absf(ground_speed)) / GOVERNOR_BAND, 0.0, 1.0)


## Gear a governed vehicle belongs in: the tallest one still above its downshift point.
## Auto-shift alone cannot get there, since it upshifts on rpm and a limit can sit just below the
## next upshift's road speed. The `shift_down_rpm` guard stops this lugging a slow-governed body.
static func governed_upshift(p_spec: VehicleSpec, gear: int, ground_speed: float,
		p_road_radius: float) -> int:
	var g := gear
	var road_omega := ground_speed / p_road_radius
	while g < mini(p_spec.gear_ratios.size(), TOP_GEAR) \
			and rpm_from_wheel(p_spec, road_omega, g + 1) > p_spec.shift_down_rpm:
		g += 1
	return g


## Torque delivered to the drive axle, signed by the gear ratio (throttle is a 0..1 magnitude).
static func wheel_torque(p_spec: VehicleSpec, at_rpm: float, throttle: float, byte: int) -> float:
	return engine_torque(p_spec, at_rpm) * clampf(throttle, 0.0, 1.0) \
			* ratio_for_byte(p_spec, byte) * p_spec.efficiency


## Common spin speed of a rigidly locked axle: one shaft, so the mean is the momentum-conserving
## result. It only shrinks the spread between the two wheels, so it adds no energy and needs no
## clamp. Unlocked, equal torque to both half-shafts is the open-differential law.
static func locked_axle_omega(omega_a: float, omega_b: float) -> float:
	return (omega_a + omega_b) * 0.5


# --- auxiliary driveline retarder (truck, J1939 SPN 520) ------------------------------------
## Driveline behaviour, gated by GroundDriveSpec.retarder_equipped and applied by WheelDrive, not
## a vehicle subclass. It joins the other brake torques on the driven wheels so RayWheel
## integrates it with the same semi-implicit step, and must stay inside that integrator: a
## separate move_toward after the wheels tick over-corrects on the first tick (slip 1.0, 8 m/s^2).
## The spring brake is a post-tick kinematic zero-lock, which can only remove energy.

## Retarder rating per driven wheel, as a fraction of brake_torque (the 'retarder_state' 100%
## point). Derived: mass and radius cancel to `frac * BRAKE_GRIP_FRAC * mu_long * g / 2`, so 0.20
## is 0.93 m/s^2 on both Kenney trucks and 1.46 on the hand-built units with a fixed 10500 Nm
## brake. `test_truck` pins a 0.9-1.6 band per spec.
##
## It stays auxiliary by construction: 0.20 of per-wheel brake torque is ~10% of the four-wheel
## service brake and ~14% of tyre grip, so brake > transmissible drive > handbrake holds. Raising
## it means re-checking the settled slip below.
const RETARDER_MAX_FRAC := 0.20
const RETARDER_CUTOUT_MS := 1.5  ## m/s below which a driveline brake does nothing at all
const RETARDER_FULL_MS := 8.0    ## m/s (~29 km/h) at which it reaches its rating
## Slip ratio the retarder will not drive the driven axle past. A backstop, not the operating
## point (measured settled slip is 0.024-0.029), so a rating edit fails visibly instead of quietly
## skidding the axle. Slip, not force: a locked wheel is already making the saturated road torque,
## so a force cap at mu*N*r permits a full skid.
const RETARDER_SLIP_TARGET := 0.10


## The retarder's rated torque at one driven wheel (Nm).
static func retarder_rating(brake_torque: float) -> float:
	return maxf(brake_torque, 0.0) * RETARDER_MAX_FRAC


## Fraction of rating a driveline retarder can make at this road speed, 0..1. Falls off to
## nothing at walking pace (no shaft speed to work against), saturates once rolling.
static func retarder_speed_fade(speed_ms: float) -> float:
	return clampf((absf(speed_ms) - RETARDER_CUTOUT_MS) / (RETARDER_FULL_MS - RETARDER_CUTOUT_MS),
			0.0, 1.0)


## What the driver asked for at one driven wheel (Nm): rating x request x speed fade.
static func retarder_demand(request01: float, speed_ms: float, brake_torque: float) -> float:
	return clampf(request01, 0.0, 1.0) * retarder_rating(brake_torque) \
			* retarder_speed_fade(speed_ms)


## Anti-lock backstop (Nm): the most spin this wheel may lose in one tick without exceeding
## RETARDER_SLIP_TARGET, and 0 once the axle is already at or past the target. Worked in slip
## velocity against RayWheel's own denominator (LOW_SPEED_FLOOR), the same ratio RayWheel computes.
##
## `road_speed` is the signed chassis forward velocity (negative in reverse), needed for the
## headroom sign below, so never pass a magnitude.
static func retarder_slip_cap(omega: float, road_speed: float, radius: float, inertia: float,
		delta: float) -> float:
	if radius <= 0.0 or delta <= 0.0:
		return 0.0
	var denom := maxf(absf(road_speed), RayWheel.LOW_SPEED_FLOOR)
	var slip_vel := omega * radius - road_speed
	# Headroom toward the braking side, in m/s of slip velocity; the sign of road_speed picks the
	# braking direction. At a standstill this degenerates to a nonzero cap, which is harmless: the
	# demand it is minned against is already 0 below RETARDER_CUTOUT_MS.
	var headroom := signf(road_speed) * slip_vel + RETARDER_SLIP_TARGET * denom
	return maxf(headroom, 0.0) * maxf(inertia, 0.0) / (radius * delta)


## Retarder braking torque for one driven wheel (Nm, unsigned): demand held under the anti-lock
## backstop. `road_speed` is signed — see retarder_slip_cap.
static func retarder_torque(request01: float, road_speed: float, omega: float,
		gd: GroundDriveSpec, delta: float) -> float:
	return minf(retarder_demand(request01, road_speed, gd.brake_torque),
			retarder_slip_cap(omega, road_speed, gd.wheel_radius, gd.wheel_inertia, delta))


## Retarder torque as the contract's percentage: applied over rating. Unsigned, though SPN 520
## reports it negative, so the bar fills as retardation rises.
static func retarder_pct(applied_nm: float, rated_nm: float) -> float:
	if rated_nm <= 0.0:
		return 0.0
	return clampf(absf(applied_nm) / rated_nm * 100.0, 0.0, 100.0)


## One clutch-less shift step within D1-D6 on rpm thresholds; N/R never auto-shift.
static func auto_shift(p_spec: VehicleSpec, byte: int, at_rpm: float) -> int:
	if not is_drive(byte):
		return normalize_byte(byte)
	# mini(TOP_GEAR, gear_ratios.size()): ratio_for_byte indexes gear_ratios[byte-1], so
	# upshifting past a short array is an out-of-range read.
	if at_rpm >= p_spec.shift_up_rpm and byte < mini(TOP_GEAR, p_spec.gear_ratios.size()):
		return byte + 1
	if at_rpm <= p_spec.shift_down_rpm and byte > 1:
		return byte - 1
	return byte


## Per-tick update: adopt the gear request, update RPM, return drive-axle torque (Nm).
## auto=true (local input): request is a direction (N/enter-D/R), box auto-shifts within D1-D6.
## auto=false (bridge): byte is exact, auto-shift bypassed.
## `ground_speed` (not `drive_wheel_omega`) drives auto-shift so wheelspin can't fake a high rpm.
func process(delta: float, throttle: float, drive_wheel_omega: float,
		ground_speed: float, requested_byte: int, auto: bool) -> float:
	var req := normalize_byte(requested_byte)
	if auto:
		if req == GEAR_R or req == GEAR_N:
			gear_byte = req
		elif not is_drive(gear_byte):
			gear_byte = req
		if is_drive(gear_byte):
			# Shift on road speed, not the spinning drive wheel: wheelspin over-reads rpm,
			# causing an early upshift that then bogs and hunts.
			var road_omega := ground_speed / road_radius
			gear_byte = auto_shift(spec, gear_byte, rpm_from_wheel(spec, road_omega, gear_byte))
			# Against the limiter, take the tallest gear that will hold.
			if governor_scale(spec, ground_speed) < 1.0:
				gear_byte = governed_upshift(spec, gear_byte, ground_speed, road_radius)
	else:
		gear_byte = req

	# In N the wheels say nothing about crank speed, so a free-rev model stands in, built off the
	# redline so it can never trip the limiter.
	var limiter_rpm := spec.idle_rpm
	var target_rpm: float
	if gear_byte == GEAR_N:
		target_rpm = lerpf(spec.idle_rpm, spec.redline_rpm, clampf(throttle, 0.0, 1.0))
	else:
		limiter_rpm = wheel_engine_rpm(spec, drive_wheel_omega, gear_byte)
		target_rpm = clampf(limiter_rpm, spec.idle_rpm, spec.redline_rpm)
	rpm = lerpf(rpm, target_rpm, 1.0 - exp(-RPM_SMOOTH * delta))

	# Both cuts sit between the pedal and the engine: rpm above still follows the wheels, torque
	# below is what was actually allowed.
	applied_throttle = clampf(throttle, 0.0, 1.0) * governor_scale(spec, ground_speed)
	if limiter_cut(spec, limiter_rpm):
		applied_throttle = 0.0
	return wheel_torque(spec, rpm, applied_throttle, gear_byte)

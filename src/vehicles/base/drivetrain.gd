class_name Drivetrain
extends RefCounted
## Diff-less drivetrain: torque curve -> fluid coupling -> gearbox (RAMN gear byte) -> drive axle.
## RPM follows wheel speed through the ratio, clamped [idle, redline], and on a wheel-driving
## engine never falls below what the converter lets it reach (`converter_free_rpm`, which is the
## only thing between crank and gearbox: no clutch, no bite point, no stall). Static pure
## functions; the instance holds only the current gear and smoothed RPM. Approach informed by
## Dechode/Godot-Advanced-Vehicle and Tobalation/GDCustomRaycastVehicle (credited in README).

## RAMN gear byte: 0x00 = N, 0x01..0x06 = D1-D6, 0xFF = R.
const GEAR_N := 0x00
const GEAR_R := 0xFF
## Tallest drive byte RAMN can express. Bus-defined, not spec-defined (never `gear_ratios.size()`);
## the shift functions take `mini()` of both, since a short array counts too.
const TOP_GEAR := 6

const RADS_TO_RPM := 60.0 / TAU
const RPM_SMOOTH := 8.0  ## 1/s exponential rate the displayed/torque RPM tracks the target

## m/s below speed_limit_kmh over which the governor fades throttle out, so the vehicle settles
## on the limit instead of hunting.
const GOVERNOR_BAND := 1.5

## Gear-selection radius (m) for a body with no ground drive, which still walks a gearbox and
## publishes the gear byte without owning a wheel.
const DEFAULT_ROAD_RADIUS := 0.32
## Floor under any declared `wheel_radius` (m): a divisor in gear selection and `governed_upshift`,
## so a misconfigured 0 cannot reach the division.
const MIN_ROAD_RADIUS := 0.05

var spec: VehicleSpec
## Radius the gear-selection scale (`ground_speed / road_radius`) is measured against; here rather
## than on the spec because a wheel-less body still needs it.
var road_radius: float
var gear_byte := GEAR_N
var rpm: float
## Throttle actually delivered this tick, 0..1, after the governor, rev limiter and shift cut.
## Telemetry reads this, not `input.throttle`: a governed vehicle holds the pedal down while fuel
## is cut.
var applied_throttle := 0.0
## Ticks left in the post-shift throttle cut (`spec.shift_cut_s`), 0 when driving through.
var _shift_cut_ticks := 0


func _init(p_spec: VehicleSpec) -> void:
	spec = p_spec
	road_radius = maxf(p_spec.ground_drive.wheel_radius, MIN_ROAD_RADIUS) \
			if p_spec.ground_drive != null else DEFAULT_ROAD_RADIUS
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


## Total engine->wheel ratio, signed by direction (forward +, reverse -), 0 in N. A drive byte
## past a short gearbox (a bridge-exact D6 on a 3-speed) selects its top ratio; no ratios, 0.
static func ratio_for_byte(p_spec: VehicleSpec, byte: int) -> float:
	if is_drive(byte):
		var n := p_spec.gear_ratios.size()
		if n == 0:
			return 0.0
		return p_spec.gear_ratios[mini(byte, n) - 1] * p_spec.final_drive
	if is_reverse(byte):
		return -p_spec.reverse_ratio * p_spec.final_drive
	return 0.0


## Peak of the torque curve, at any rpm. The engine_load denominator (the current-rpm torque would
## cancel to plain throttle).
static func peak_torque(p_spec: VehicleSpec) -> float:
	var peak := 0.0
	for p in p_spec.torque_curve:
		peak = maxf(peak, p.y)
	return peak


## Full-throttle torque at rpm, off the curve. Redline is not handled here: the limiter is a fuel
## cut (`limiter_cut`, via `applied_throttle`).
static func engine_torque(p_spec: VehicleSpec, at_rpm: float) -> float:
	return VehicleSpec.sample_curve(p_spec.torque_curve, at_rpm)


## Engine speed the wheels impose through the ratio (rpm), unclamped; idle in N. This is what the
## limiter judges: the engine can be driven past redline.
static func wheel_engine_rpm(p_spec: VehicleSpec, wheel_omega: float, byte: int) -> float:
	var ratio := ratio_for_byte(p_spec, byte)
	if ratio == 0.0:
		return p_spec.idle_rpm
	return absf(wheel_omega * ratio) * RADS_TO_RPM


## RPM clamped [idle, redline]; idle in N. The published rpm (dash needle, `rpm` bridge signal).
## Never gate fuel on this: the smoothing lerp settles an epsilon short of redline.
static func rpm_from_wheel(p_spec: VehicleSpec, wheel_omega: float, byte: int) -> float:
	return clampf(wheel_engine_rpm(p_spec, wheel_omega, byte), p_spec.idle_rpm, p_spec.redline_rpm)


## Rev limiter: does the engine get fuel at this crank speed? Feed it `wheel_engine_rpm`, never the
## clamped `rpm`. A hard cut on purpose (a fade band moves top speeds).
static func limiter_cut(p_spec: VehicleSpec, engine_rpm: float) -> bool:
	return engine_rpm >= p_spec.redline_rpm


## Fraction of throttle that reaches the engine at this road speed, 1.0 ungoverned. Fades
## linearly to 0 across the last GOVERNOR_BAND m/s below the limit. Unsigned: it governs reverse.
static func governor_scale(p_spec: VehicleSpec, ground_speed: float) -> float:
	if p_spec.speed_limit_kmh <= 0.0:
		return 1.0
	var limit := p_spec.speed_limit_kmh / 3.6
	return clampf((limit - absf(ground_speed)) / GOVERNOR_BAND, 0.0, 1.0)


## Gear a governed vehicle belongs in: the tallest one still above its downshift point. Auto-shift
## alone cannot get there: it upshifts on rpm, and a limit can sit just below the next upshift's
## road speed. The `shift_down_rpm` guard stops it lugging a slow-governed body.
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


## Overrun torque at the drive axle (Nm) with the pedal released: the engine absorbing
## `engine_brake_frac` of its peak, scaled linearly from 0 at idle to full at redline, through
## the gear ratio and DIVIDED by efficiency (a load the engine absorbs pays the driveline loss
## the other way). Signed AGAINST the gear's rolling direction, so reverse overrun is +.
## Hard edge at throttle 0 on purpose (a fade moves top speeds). 0 in N, at idle, or with any
## throttle at all.
static func overrun_torque(p_spec: VehicleSpec, at_rpm: float, throttle: float,
		byte: int) -> float:
	if throttle > 0.0 or p_spec.engine_brake_frac <= 0.0:
		return 0.0
	var ratio := ratio_for_byte(p_spec, byte)
	if ratio == 0.0:
		return 0.0
	var rpm01 := clampf((at_rpm - p_spec.idle_rpm)
			/ maxf(1.0, p_spec.redline_rpm - p_spec.idle_rpm), 0.0, 1.0)
	return -p_spec.engine_brake_frac * peak_torque(p_spec) * rpm01 * ratio \
			/ maxf(p_spec.efficiency, 0.05)


# --- torque converter (the crank against a held wheel) -------------------------------------
## The one element between engine and gearbox, and a rev model only: it multiplies NO torque
## where a real converter makes 1.8-2.2x at stall, which keeps every launch figure conservative
## and leaves the brake > drive > handbrake hierarchy alone (src/vehicles/CLAUDE.md).

## Converter stall speed as a fraction of the engine's own usable band (idle -> redline): one
## derivation for every machine, not a per-spec knob. 0.25 puts every shipped stall below its
## torque peak, which keeps the foot brake winning. It cannot reach the limiter at any value: that
## judges `wheel_engine_rpm`, the raw wheel side.
const STALL_RPM_FRAC := 0.25


## Whether this machine has a fluid coupling between engine and gearbox: an engine that drives
## wheels does. Boat, drone, train (no `ground_drive`) and plane (undriven wheels) keep the rigid
## crank, where wheel speed alone sets rpm.
static func has_converter(p_spec: VehicleSpec) -> bool:
	var gd := p_spec.ground_drive
	return gd != null and (gd.driven_front or gd.driven_rear)


## Crank speed the converter alone will let the engine reach with the turbine held (rpm): idle at
## a closed throttle rising to the stall speed at full, so a held vehicle revs and the torque curve
## is sampled there. LINEAR in throttle (a real converter's capacity goes as N^2 and would rev
## harder at a small pedal); the handbrake break-away figures in `docs/vehicles.md` § Physics
## derivations and figures are read off this line. `idle_rpm` with no converter.
static func converter_free_rpm(p_spec: VehicleSpec, throttle: float) -> float:
	if not has_converter(p_spec):
		return p_spec.idle_rpm
	var stall := p_spec.idle_rpm + STALL_RPM_FRAC * (p_spec.redline_rpm - p_spec.idle_rpm)
	return lerpf(p_spec.idle_rpm, stall, clampf(throttle, 0.0, 1.0))


# --- auxiliary driveline retarder (truck, J1939 SPN 520) ------------------------------------
## Gated by GroundDriveSpec.retarder_equipped and applied by WheelDrive. It joins the other brake
## torques so RayWheel integrates it in the same semi-implicit step, and must stay inside that
## integrator: a separate move_toward after the wheels tick over-corrects on the first tick.

## Retarder rating per driven wheel, as a fraction of brake_torque (the 'retarder_state' 100%
## point); retardation figures: docs/heavy_vehicles.md. `test_truck` pins a band per spec. It stays
## auxiliary by construction: on a grip-derived brake it is `0.20 * BRAKE_GRIP_FRAC` of the wheel's
## own grip torque whatever mu is, so brake > transmissible drive > handbrake holds at any tyre.
## Raising it means re-checking `RETARDER_SLIP_TARGET`.
const RETARDER_MAX_FRAC := 0.20
const RETARDER_CUTOUT_MS := 1.5  ## m/s below which a driveline brake does nothing at all
const RETARDER_FULL_MS := 8.0    ## m/s (~29 km/h) at which it reaches its rating
## Slip ratio the retarder will not drive the driven axle past. A backstop, not the operating
## point, so a rating edit fails visibly instead of quietly skidding the axle. Slip, not force: a
## locked wheel already makes the saturated road torque, so a force cap at mu*N*r permits a skid.
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
## RETARDER_SLIP_TARGET, and 0 once the axle is already at or past it. Uses RayWheel's own slip
## denominator (LOW_SPEED_FLOOR). `road_speed` is the signed chassis forward velocity (negative in
## reverse), never a magnitude.
static func retarder_slip_cap(omega: float, road_speed: float, radius: float, inertia: float,
		delta: float) -> float:
	if radius <= 0.0 or delta <= 0.0:
		return 0.0
	var denom := maxf(absf(road_speed), RayWheel.LOW_SPEED_FLOOR)
	var slip_vel := omega * radius - road_speed
	# Headroom toward the braking side (m/s of slip velocity); the sign of road_speed picks the
	# direction. Nonzero at a standstill, harmless: demand is 0 below RETARDER_CUTOUT_MS.
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


## True while the post-shift throttle cut is running. Test accessor for `_shift_cut_ticks`.
func shift_cut_active() -> bool:
	return _shift_cut_ticks > 0


## Ticks a shift cut lasts at this tick length: whole ticks, rounded up, 0 for no cut.
static func shift_cut_ticks(cut_s: float, delta: float) -> int:
	if cut_s <= 0.0 or delta <= 0.0:
		return 0
	return ceili(cut_s / delta)


## A byte change that is a SHIFT: both sides engaged (D or R), so N<->D is a selection, not a
## shift.
static func is_shift(from_byte: int, to_byte: int) -> bool:
	return from_byte != to_byte and from_byte != GEAR_N and to_byte != GEAR_N


## One clutch-less shift step within D1-D6 on rpm thresholds; N/R never auto-shift.
static func auto_shift(p_spec: VehicleSpec, byte: int, at_rpm: float) -> int:
	if not is_drive(byte):
		return normalize_byte(byte)
	# mini(TOP_GEAR, gear_ratios.size()): never upshift past the last real ratio.
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
	var prev_byte := gear_byte
	if auto:
		if req == GEAR_R or req == GEAR_N:
			gear_byte = req
		elif not is_drive(gear_byte):
			gear_byte = req
		if is_drive(gear_byte):
			# Road speed, not the drive wheel: wheelspin over-reads rpm and upshifts early.
			var road_omega := ground_speed / road_radius
			gear_byte = auto_shift(spec, gear_byte, rpm_from_wheel(spec, road_omega, gear_byte))
			# Against the limiter, take the tallest gear that will hold.
			if governor_scale(spec, ground_speed) < 1.0:
				gear_byte = governed_upshift(spec, gear_byte, ground_speed, road_radius)
	else:
		gear_byte = req
	# One latch per tick however many gears governed_upshift walked: the comparison is against
	# the byte this tick STARTED with.
	if is_shift(prev_byte, gear_byte):
		_shift_cut_ticks = shift_cut_ticks(spec.shift_cut_s, delta)

	# In N the wheels say nothing about crank speed, so a free-rev model stands in, built off the
	# redline so it can never trip the limiter.
	var limiter_rpm := spec.idle_rpm
	var target_rpm: float
	if gear_byte == GEAR_N:
		target_rpm = lerpf(spec.idle_rpm, spec.redline_rpm, clampf(throttle, 0.0, 1.0))
	else:
		limiter_rpm = wheel_engine_rpm(spec, drive_wheel_omega, gear_byte)
		# A floor under the wheels, never a ceiling: the faster side wins, so a held vehicle revs to
		# stall and a rolling one reads what the wheels impose. The limiter keeps judging
		# `limiter_rpm` (a converter only spins to stall).
		target_rpm = maxf(clampf(limiter_rpm, spec.idle_rpm, spec.redline_rpm),
				converter_free_rpm(spec, throttle))
	rpm = lerpf(rpm, target_rpm, 1.0 - exp(-RPM_SMOOTH * delta))

	# The limiter and governor cut between pedal and engine: rpm still follows the wheels.
	applied_throttle = clampf(throttle, 0.0, 1.0) * governor_scale(spec, ground_speed)
	if limiter_cut(spec, limiter_rpm):
		applied_throttle = 0.0
	# Overrun reads the PEDAL, not applied_throttle: a governed or limited engine with the
	# pedal down is not on overrun, and applied_throttle stays 0 on overrun so fuel / coolant /
	# engine_load see no load (J1939 negative percent-torque is deliberately not modelled).
	var pedal := clampf(throttle, 0.0, 1.0)
	# The shift cut is a lift: no drive, overrun as if the pedal were up, and it rides
	# applied_throttle so telemetry reads it.
	if _shift_cut_ticks > 0:
		_shift_cut_ticks -= 1
		applied_throttle = 0.0
		pedal = 0.0
	return wheel_torque(spec, rpm, applied_throttle, gear_byte) \
			+ overrun_torque(spec, rpm, pedal, gear_byte)

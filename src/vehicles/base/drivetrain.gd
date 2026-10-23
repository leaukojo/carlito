class_name Drivetrain
extends RefCounted
## Diff-less drivetrain: torque curve -> coupling -> gearbox (RAMN gear byte) -> drive axle.
## On a body that `drives_wheels` the crank is a rotating mass integrated from the engine law,
## meeting the wheels through a clutch (`coupling_step`) or a converter (`TorqueConverter`) solved
## inside the spin step (`couple`). Nothing stalls: the controller opens a clutch first, and the
## idle controller fuels a converter's load. Every other body keeps the rigid crank (rpm follows
## the wheels, clamped [idle, redline]). Informed by Dechode/Godot-Advanced-Vehicle and
## Tobalation/GDCustomRaycastVehicle (credited in README).

## RAMN gear byte: 0x00 = N, 0x01..0x18 = D1-D24, 0xFF = R, plus 0xFE = P, a value RAMN never
## sends, so every byte it does send keeps its meaning.
const GEAR_N := 0x00
const GEAR_R := 0xFF
const GEAR_P := 0xFE
## Tallest drive byte the bus expresses (the contract's `gear` enum; `test_contract` pins the two).
## Bus-defined, not spec-defined (never `gear_ratios.size()`): the shift functions take `mini()` of
## both, since a short array counts too. RAMN sends up to its own MAX_GEAR_VALUE.
const TOP_GEAR := 24

const RADS_TO_RPM := 60.0 / TAU
## 1/s exponential rate the rigid crank's rpm tracks the wheels (the wheel-less bodies and the
## plane only; a wheel-driving crank is integrated).
const RPM_SMOOTH := 8.0

## m/s below speed_limit_kmh over which the governor fades throttle out, so the vehicle settles
## on the limit instead of hunting.
const GOVERNOR_BAND := 1.5

## Gear-selection radius (m) for a body with no ground drive, which still walks a gearbox and
## publishes the gear byte without owning a wheel.
const DEFAULT_ROAD_RADIUS := 0.32
## Floor under any declared drive radius (`GroundDriveSpec.drive_radius`, m): a divisor in gear
## selection and `governed_upshift`, so a misconfigured 0 cannot reach the division.
const MIN_ROAD_RADIUS := 0.05

var spec: VehicleSpec
## Radius the gear-selection scale (`ground_speed / road_radius`) is measured against; here rather
## than on the spec because a wheel-less body still needs it.
var road_radius: float
var gear_byte := GEAR_N
## Engine speed (rpm): on a wheel-driving body the crank's integrated state, settled by `couple`
## each tick, and the published rpm (it may read past the redline when the wheels over-rev it).
var rpm: float
## Throttle actually delivered this tick, 0..1, after the governor, rev limiter and shift cut.
## Telemetry reads this, not `input.throttle`: a governed vehicle holds the pedal down while fuel
## is cut.
var applied_throttle := 0.0
## A road-speed cap (km/h) imposed at runtime on top of the spec's governor, 0 = none: what a
## towing host asks for while a tipping body is up (`TowHost.speed_cap_kmh`). The lower one governs.
var speed_cap_kmh := 0.0
## A load on the crank (N·m, + = absorbing) set by the owner, like `speed_cap_kmh`: what a driven
## PTO takes (`VehicleTelemetry.pto_crank_torque`). Constant over the tick, so it enters the crank's
## predictor with no stiffness, and the controller's floors fuel it as load. Set in `_tick_extras`
## after `process`, so it acts from the next tick. `ShiftPolicy`'s estimates leave it out: its road
## load reads the torque the coupling passed, already net of it.
var accessory_torque := 0.0
## The hand throttle (0..1), owner-set the same way (`TractorVehicle._tick_extras`, so from the next
## tick): on an all-speed governor the demand is the higher of it and the pedal
## (`PedalMap.demand`), read by the fuel, the shift policy and the launch line; any other map ignores
## it. The pull-away still waits on the pedal: the start-up ramp and a clutch's opening at rest read
## the pedal alone, as a shuttle's release.
var hand_throttle := 0.0
## The PTO is engaged, owner-set the same way (`TractorVehicle._tick_extras`): a CVT's engine-speed
## management stands down, so the shaft keeps the demand's speed (`_cvt_managed_demand`).
var pto_engaged := false
## The PTO mode's set speed (rpm, 0 = off), owner-set the same way (`TruckVehicle._tick_extras`, from
## the PTO, the park brake and the road speed): the fuel runs the governor law at the higher of it and
## the pedal's demand (`PedalMap.demand`), at `spec.governor_droop`, on any map. It acts only while
## the box is in N or P (`_fuel_step`): the neutral interlock, read on the byte engaged this tick, so
## a selected D drops it before any fuel reaches the wheels.
var pto_set_rpm := 0.0
## A transmission interlock set by the owner, like `speed_cap_kmh`: while on, a D or R request is
## engaged as N (the park-brake auto-neutral of an Allison-class box or an AMT; `TruckVehicle` sets
## it while the spring brakes are on). N and P requests pass unchanged. COMPROMISE: it engages at
## any speed, where a real auto-neutral waits for the vehicle to stop; air lost at speed sets the
## spring brakes, which are stopping it anyway, so only the drive into them differs.
var drive_inhibit := false
## Ticks left in the post-shift throttle cut (`spec.shift_cut_s`), 0 when driving through.
var _shift_cut_ticks := 0
## The fuel's ceiling after a shift cut, 0..1 (`torque_restore_step`): 0 through the cut, rising
## back to 1 over `spec.shift_torque_ramp_s`.
var _torque_restore := 1.0
## The shift policy's state (`ShiftPolicy`), the gearbox's own: seconds since the gear byte last
## changed (the dwell's clock), and a kickdown armed and waiting on the dwell.
var _gear_s := 0.0
var _kickdown := false
## The demand (0..1, `PedalMap.demand`: the pedal, or the higher of it and the hand throttle) the
## shift policy read on the last `process`: a kickdown's edge, and what the launch trace judges a
## shift's landing at.
var last_pedal := 0.0
## Owner-set before `process` (`WheelDrive.hold_step`), like `speed_cap_kmh`: the rig's mass (kg, the
## body's live mass plus what it tows) and the load standing on the ground puts against D (N·m at the
## axle, `ShiftPolicy.standing_load`). 0 mass = no estimate: the policy reads no load.
var load_mass_kg := 0.0
var standing_load := 0.0
## Owner-set the same way: what the driven tyres put down (N), off their loads at rest, the coupled
## load and the surface included (`WheelDrive.hold_step`), held while rolling. The grip the
## policy's estimates cap the drive at (`ShiftPolicy.time_to_upshift`, `start_gear`); 0 = no
## estimate, no cap.
var drive_grip_n := 0.0
## Owner-set the same way: the fitted tyre's hard-road rolling resistance
## (`WheelDrive.rolling_resistance`), the flat road `ShiftPolicy.on_grade` weighs against. The
## spec's stock figure until the owner sets it.
var rolling_crr := 0.0
## The road-load estimate the policy reads (N·m at the axle, + = resisting forward motion): the
## torque the coupling passed less the rig's mass times its measured acceleration, filtered
## (`ShiftPolicy.road_load_step`); `standing_load` at rest, held while the foot brake is on (the brake
## would read as load). The mass is the sim's own. NAN on the rigid crank or with no mass set.
var road_load := NAN
## Axle torque (N·m) `couple` passed last tick, and the road speed (m/s) `process` read last tick:
## the road-load estimate's inputs.
var _axle_torque := 0.0
var _last_speed := NAN
## The start gear (`ShiftPolicy.start_gear`, with `spec.start_gear_max` above 1): the gear a pull-away
## takes; while `_launching` (picked, and the coupling not yet locked) no downshift goes under it.
## `_launch_s` counts a pull-away held at rest with the pedal down: a launch that has not moved by
## `launch_engage_s + shift_dwell_s` steps its start gear down.
var _start_gear := 1
var _launching := false
var _launch_s := 0.0
## The start-up ramp, 0..1 (`ramp_step`): on a wheel-driving body the share of the coupling's
## rating the controller may command (a powershift's pressure ramp); on the rigid crank the share
## of the torque reaching the axle. Always 1 with no `spec.launch_engage_s`.
var ramp := 1.0

## The coupling between crank and gearbox on a wheel-driving body: open (nothing passes), slipping
## (the controller commands a capacity that lands the crank on its target), or locked (the whole
## rating, the two sides turning together). `couple` locks a slipping coupling the tick it carries
## less than its capacity; `coupling_step` decides the rest.
enum CouplingState { OPEN, SLIPPING, LOCKED }
var coupling_state := CouplingState.OPEN
## The capacity the controller commands this tick over the rating (`clutch_rating`), 0..1: a
## clutch's, or a converter's lock-up; 1 on the rigid crank.
var clutch := 1.0
## The converter law carried this tick (`TorqueConverter.solve`): a converter body slipping with its
## lock-up open or closing, never a shift (which slips its gearbox clutch, `handover_rate`).
var converting := false
## Torque the coupling carried at the crank this tick (N·m, + = the crank driving the wheels).
var coupling_torque := 0.0
## Owner-set before `process`, like `drive_inhibit`: the key is at Ignition. Off, the engine gets no
## fuel, the coupling opens and the crank runs down (`crank_torque`).
var running := true
## Owner-set (`WheelDrive`): ABS held a driven wheel last tick. The controller opens a clutch, as an
## AMT does under an ABS event, and releases a converter's lock-up, so the crank's reflected inertia
## never rides a modulated wheel rigidly.
var abs_release := false
## Owner-set before `process`, like `running`: the foot brake is applied. On a converter body
## (`spec.coupling` CONVERTER) it releases the lock-up, as an automatic's TCU does on braking: the
## coupling slips on the converter's law instead of locking, so the brakes never have to slow the
## crank through a lower gear, and a downshift under braking slips the converter, blipping nothing.
## A clutch body (AMT, powershift, sequential) keeps its clutch closed for engine braking.
var braking := false
## Owner-set (`WheelDrive`): engine braking slipped the driven wheels past the traction control's
## floor last tick. Drag-torque control: the controller fuels the crank to zero net motoring torque
## (`drag_fuel`), never a torque on the wheel.
var drag_control := false
## The coupling ran in overrun at its last solve (the wheels driving the crank).
var overrun := false
var _was_running := true
## `couple` landed last tick's crossing on the redline: this tick is the hard cut, however the
## settled crank rounded against it.
var _landed := false
## The rev limiter shaped this tick's fuel: its hard cut, or a crossing landed on the redline.
var on_limiter := false
## This tick's crank predictor, `omega + crank_torque * delta / J`, linear in fuel: the unfuelled
## part (rad/s) and what full fuel adds.
var _pred_base := 0.0
var _pred_per_fuel := 0.0
## This tick's `crank_compliance` (rad/s per N·m at the crank).
var _compliance := 0.0
## This tick's commanded capacity at the crank (N·m), and whether it acts in drive (the crank
## faster than the wheels) or in overrun.
var _capacity := 0.0
var _drives := true
## An inertia phase is under way: a shift's slip (on a converter body its gearbox clutch closes, the
## friction path, the converter law standing aside), or a clutch's pull-away closing onto turning
## wheels. `couple` ends it when it locks.
var _inertia_phase := false
## The inertia phase's rate (rad/s per s): the oncoming clutch brings the crank down to the wheels at
## it (`handover_rate`), latched on the phase's first tick; INF closes it at the rating.
var _handover_rate := INF
## The converter's capacity coefficient (`TorqueConverter.capacity_coefficient`), cached in `_init`;
## this tick's torque ratio, read at the tick's start speed ratio; and what the converter could pass
## at most this tick (N·m at the crank, the ratio times the law against a held turbine), which
## bounds the traction control's share (`tcs_drive_torque`).
var _coef := 0.0
var _ratio := 1.0
var _stall_bound := 0.0


func _init(p_spec: VehicleSpec) -> void:
	spec = p_spec
	road_radius = maxf(p_spec.ground_drive.drive_radius(), MIN_ROAD_RADIUS) \
			if p_spec.ground_drive != null else DEFAULT_ROAD_RADIUS
	rolling_crr = p_spec.ground_drive.rolling_resistance if p_spec.ground_drive != null else 0.0
	rpm = spec.idle_rpm
	ramp = 0.0 if spec.launch_engage_s > 0.0 else 1.0
	if p_spec.coupling == VehicleSpec.Coupling.CONVERTER and drives_wheels(p_spec):
		_coef = TorqueConverter.capacity_coefficient(p_spec)


static func is_drive(byte: int) -> bool:
	return byte >= 1 and byte <= TOP_GEAR


static func is_reverse(byte: int) -> bool:
	return byte == GEAR_R


## N or P: nothing drives the wheels, the engine revs free.
static func is_open(byte: int) -> bool:
	return not is_drive(byte) and not is_reverse(byte)


## The gear's direction: +1 in D, -1 in R, 0 in N or P.
static func drive_sign(byte: int) -> float:
	if is_drive(byte):
		return 1.0
	return -1.0 if is_reverse(byte) else 0.0


## The gearbox has a parking pawl, so P is a gear of its own; without one a P request is N.
static func has_park_pawl(p_spec: VehicleSpec) -> bool:
	return p_spec.ground_drive != null and p_spec.ground_drive.park_pawl_torque > 0.0


## Any byte outside RAMN semantics (and P) is Neutral (safe).
static func normalize_byte(byte: int) -> int:
	if is_drive(byte) or is_reverse(byte) or byte == GEAR_P:
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


## Engine speed the wheels impose through the ratio (rpm), unclamped; idle in N. On a wheel-driving
## body the coupling's synchronous speed in that gear; on the rigid crank what the limiter judges.
static func wheel_engine_rpm(p_spec: VehicleSpec, wheel_omega: float, byte: int) -> float:
	var ratio := ratio_for_byte(p_spec, byte)
	if ratio == 0.0:
		return p_spec.idle_rpm
	return absf(wheel_omega * ratio) * RADS_TO_RPM


## RPM clamped [idle, redline]; idle in N: the road-speed scale gear selection reads, and the rigid
## crank's target. Never gate fuel on this: the smoothing lerp settles an epsilon short of redline.
static func rpm_from_wheel(p_spec: VehicleSpec, wheel_omega: float, byte: int) -> float:
	return clampf(wheel_engine_rpm(p_spec, wheel_omega, byte), p_spec.idle_rpm, p_spec.redline_rpm)


## Rev limiter: does the engine get fuel at this crank speed? Feed it the crank (`rpm` on a
## wheel-driving body, `wheel_engine_rpm` on the rigid crank), never a clamped rpm. A hard cut on
## purpose (a fade band moves top speeds); `couple` lands the crossing tick on the redline.
static func limiter_cut(p_spec: VehicleSpec, engine_rpm: float) -> bool:
	return engine_rpm >= p_spec.redline_rpm


## Fraction of throttle that reaches the engine at this road speed, 1.0 ungoverned. Fades
## linearly to 0 across the last GOVERNOR_BAND m/s below the limit: the spec's, or `cap_kmh` where
## that is lower (see `speed_cap_kmh`). Unsigned: it governs reverse.
static func governor_scale(p_spec: VehicleSpec, ground_speed: float, cap_kmh := 0.0) -> float:
	var limit_kmh := p_spec.speed_limit_kmh
	if cap_kmh > 0.0 and (limit_kmh <= 0.0 or cap_kmh < limit_kmh):
		limit_kmh = cap_kmh
	if limit_kmh <= 0.0:
		return 1.0
	var limit := limit_kmh / 3.6
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


## Overrun (motoring) torque at the drive axle (Nm): the unfuelled share `1 - fuel` of the motoring
## law (`motoring_torque`) through the gear ratio and DIVIDED by efficiency (a load the engine
## absorbs pays the driveline loss the other way). Signed AGAINST the gear's rolling direction, so
## reverse overrun is +. `fuel` is the DELIVERED fraction (`applied_throttle`, after governor,
## limiter and shift cut), so with `wheel_torque` this is the one engine law
## `f * T_wot + (1 - f) * T_motoring`: at `f = 1` it is the curve alone (drag-bound top speeds do not
## move), and every fuel cut is engine braking. 0 in N.
static func overrun_torque(p_spec: VehicleSpec, at_rpm: float, fuel: float,
		byte: int) -> float:
	var unfuelled := 1.0 - clampf(fuel, 0.0, 1.0)
	if unfuelled <= 0.0:
		return 0.0
	var ratio := ratio_for_byte(p_spec, byte)
	if ratio == 0.0:
		return 0.0
	return unfuelled * motoring_torque(p_spec, at_rpm) * ratio / maxf(p_spec.efficiency, 0.05)


# --- the crank and its coupling ------------------------------------------------------------
## Floor under `engine_inertia` (kg·m²): a divisor, so a misdeclared 0 cannot reach it
## (`test_vehicle_catalog` asserts every wheel-driven spec declares one).
const MIN_ENGINE_INERTIA := 1e-4
## Bisection steps `couple` takes to land a crossing tick on the redline (the settled crank is
## monotone in fuel, kinked where the wheels' holds bite); it keeps the low side, so a tick never
## ends past it on fuel, and lands within 2^-16 of the fuel.
const LIMITER_LANDING_STEPS := 16


## Whether the engine drives wheels: then the crank is a rotating mass behind a coupling. Boat,
## drone, train (no `ground_drive`) and plane (undriven wheels) keep the rigid crank, where wheel
## speed alone sets rpm.
static func drives_wheels(p_spec: VehicleSpec) -> bool:
	var gd := p_spec.ground_drive
	return gd != null and (gd.driven_front or gd.driven_rear)


## The crank's inertia (kg·m²), floored at MIN_ENGINE_INERTIA.
static func crank_inertia(p_spec: VehicleSpec) -> float:
	return maxf(p_spec.engine_inertia, MIN_ENGINE_INERTIA)


## The coupling's torque rating at the crank (N·m): `clutch_reserve` times the curve's peak.
static func clutch_rating(p_spec: VehicleSpec) -> float:
	return maxf(p_spec.clutch_reserve, 0.0) * peak_torque(p_spec)


## Motoring torque at the crank (N·m, <= 0): an unfuelled engine absorbing `engine_friction_frac` of
## its peak at and below idle (its friction, which runs a free crank down to idle and a key-off one
## to rest), rising linearly to `engine_brake_frac` at redline. `overrun_torque` is the same law at
## the axle.
static func motoring_torque(p_spec: VehicleSpec, at_rpm: float) -> float:
	var rpm01 := clampf((at_rpm - p_spec.idle_rpm)
			/ maxf(1.0, p_spec.redline_rpm - p_spec.idle_rpm), 0.0, 1.0)
	return -lerpf(maxf(p_spec.engine_friction_frac, 0.0), maxf(p_spec.engine_brake_frac, 0.0),
			rpm01) * peak_torque(p_spec)


## Net torque the engine puts on its own crank (N·m) at `fuel` (the delivered fraction): the
## one engine law, `f * curve + (1 - f) * motoring`. With the key off it gets no fuel and turns against the
## motoring law alone; the caller stops it at zero.
static func crank_torque(p_spec: VehicleSpec, at_rpm: float, fuel: float,
		p_running := true) -> float:
	var motoring := motoring_torque(p_spec, at_rpm)
	if not p_running:
		return motoring if at_rpm > 0.0 else 0.0
	var f := clampf(fuel, 0.0, 1.0)
	return f * engine_torque(p_spec, at_rpm) + (1.0 - f) * motoring


## How fast the engine's net torque falls with crank speed at this fuel (N·m per rad/s, >= 0): the
## curve's segment slope and the motoring law's, blended by fuel; 0 where the torque rises. The
## crank's step divides by `1 + stiffness * delta / J` (`crank_compliance`), the semi-implicit
## form the wheels' spin step takes: on `race`'s droop (6600-6800 rpm) an explicit step gains ~3 a
## tick and a free crank rings there.
## On a tick the all-speed governor's line governs, `governed` (`PedalMap.governor_stiffness`, NAN
## otherwise) is the stiffness instead: the line's net torque replaces the blend, so the step stays
## semi-implicit at any droop (explicit, `k dt / J` is ~0.5 on the tractor at 7 %, ~3.7 at 1 %).
static func crank_stiffness(p_spec: VehicleSpec, at_rpm: float, fuel: float,
		governed := NAN) -> float:
	if not is_nan(governed):
		return maxf(governed, 0.0)
	var curve_slope := 0.0
	var points := p_spec.torque_curve
	for i in range(1, points.size()):
		if at_rpm > points[i - 1].x and at_rpm <= points[i].x:
			curve_slope = (points[i].y - points[i - 1].y) / (points[i].x - points[i - 1].x)
			break
	var motoring_slope := 0.0
	if at_rpm > p_spec.idle_rpm and at_rpm < p_spec.redline_rpm:
		motoring_slope = -(maxf(p_spec.engine_brake_frac, 0.0)
				- maxf(p_spec.engine_friction_frac, 0.0)) * peak_torque(p_spec) \
				/ maxf(1.0, p_spec.redline_rpm - p_spec.idle_rpm)
	var f := clampf(fuel, 0.0, 1.0)
	return maxf(-(f * curve_slope + (1.0 - f) * motoring_slope), 0.0) * RADS_TO_RPM


## The crank's spin change per N·m this tick (rad/s per N·m): `delta / (J (1 + k delta / J))`, with
## `k` its `crank_stiffness` at the tick's fuel (`governed`: the governor line's, see there). Every
## torque on the crank (its own, a coupling's) goes through it, as a wheel's go through
## `RayWheel.spin_compliance`.
static func crank_compliance(p_spec: VehicleSpec, at_rpm: float, fuel: float,
		delta: float, governed := NAN) -> float:
	var j := crank_inertia(p_spec)
	return delta / (j + crank_stiffness(p_spec, at_rpm, fuel, governed) * delta)


## The fuel (0..1) whose one tick lands a free crank at `omega` (rad/s) on `target` (rad/s), through
## a step of `compliance` (`crank_compliance`): the step is linear in fuel, so it is closed form. 0
## when the motoring law alone gets there, 1 when full fuel cannot. The idle controller, the
## rev-match blip and the free limiter use it. `load_nm` is what else the crank drives
## (`accessory_torque`).
static func fuel_to_land(p_spec: VehicleSpec, omega: float, target: float,
		compliance: float, load_nm := 0.0) -> float:
	var at_rpm := omega * RADS_TO_RPM
	var motoring := motoring_torque(p_spec, at_rpm)
	var span := engine_torque(p_spec, at_rpm) - motoring
	var need := (target - omega) / maxf(compliance, 1e-12) - motoring + load_nm
	if span <= 0.0:
		return 1.0 if need > 0.0 else 0.0
	return clampf(need / span, 0.0, 1.0)


## The fuel (0..1) at which the engine's net torque is zero at this rpm: drag-torque control's floor
## (`drag_control`), so the crank stops braking the wheels and never pushes them. `load_nm` is
## what else the crank drives (`accessory_torque`).
static func drag_fuel(p_spec: VehicleSpec, at_rpm: float, load_nm := 0.0) -> float:
	var motoring := motoring_torque(p_spec, at_rpm)
	var span := engine_torque(p_spec, at_rpm) - motoring
	return clampf((load_nm - motoring) / span, 0.0, 1.0) if span > 0.0 else 0.0


## The transmission controller's coupling state for this tick (`sync_rpm` is the wheel side through
## the gear, signed: negative turning against it). OPEN with the key off, in N or P, and on a
## direction change; leaving OPEN, and on every shift, it SLIPS. A clutch also opens under ABS
## (`abs_release`) and with the pedal up once the wheel side is under idle (a stop, or a roll-back),
## and a locked clutch slips again on anti-stall (the crank under idle and the wheels slower, pedal
## down). A converter never opens in gear (at a stop it slips: creep); its lock-up lets go
## (`lockup_holds`). `couple` locks either.
static func coupling_step(p_spec: VehicleSpec, state: CouplingState, from_byte: int, to_byte: int,
		pedal: float, crank_rpm: float, sync_rpm: float, p_running: bool,
		p_abs_release: bool, p_braking := false) -> CouplingState:
	if not p_running or is_open(to_byte):
		return CouplingState.OPEN
	if is_shift(from_byte, to_byte) and is_reverse(from_byte) != is_reverse(to_byte):
		return CouplingState.OPEN
	if p_spec.coupling == VehicleSpec.Coupling.CONVERTER:
		if state == CouplingState.OPEN or is_shift(from_byte, to_byte):
			return CouplingState.SLIPPING
		if state == CouplingState.LOCKED and not lockup_holds(p_spec, to_byte, sync_rpm,
				converter_free_rpm(p_spec, pedal), p_abs_release, p_braking):
			return CouplingState.SLIPPING
		return state
	if p_abs_release:
		return CouplingState.OPEN
	if pedal <= 0.0 and sync_rpm < p_spec.idle_rpm:
		return CouplingState.OPEN
	if state == CouplingState.OPEN or is_shift(from_byte, to_byte):
		return CouplingState.SLIPPING
	if state == CouplingState.LOCKED and crank_rpm < p_spec.idle_rpm \
			and sync_rpm < p_spec.idle_rpm:
		return CouplingState.SLIPPING
	return state


## A converter's lock-up may stay closed: in a D gear from `spec.lockup_gear` up, off the foot brake
## (`braking`, as a TCU releases it on braking), with no ABS event, and with the wheel side at or
## above `free_rpm`, the converter's free rev with the pedal read as the fuel (`converter_free_rpm`:
## under it, the lock-up would lug the crank below what the converter lets it reach, and at a stop
## stall it). COMPROMISE: the line reads the pedal, not its mapped fuel (`PedalMap`), as a TCU keys
## its lock-up schedule on the pedal; on the petrol map's fuel a third of the pedal would put the
## line near the stall speed, and the `sedan` at pedal 0.3 would pull through D3-D5 on the
## converter, 400-500 rpm of slip. Full pedal reads the stall speed either way. No lock-up schedule
## is sourced; undoing this is that schedule.
static func lockup_holds(p_spec: VehicleSpec, byte: int, sync_rpm: float, free_rpm: float,
		p_abs_release: bool, p_braking: bool) -> bool:
	return p_spec.coupling == VehicleSpec.Coupling.CONVERTER and is_drive(byte) \
			and byte >= p_spec.lockup_gear and not p_braking and not p_abs_release \
			and sync_rpm >= free_rpm


## A slipping converter's lock-up closes this tick: it may hold (`lockup_holds`), and the two sides
## turn within the coupling point of each other (`TorqueConverter.COUPLING_POINT`, either way round).
static func lockup_engages(p_spec: VehicleSpec, byte: int, crank_rpm: float, sync_rpm: float,
		free_rpm: float, p_abs_release: bool, p_braking: bool) -> bool:
	return lockup_holds(p_spec, byte, sync_rpm, free_rpm, p_abs_release, p_braking) \
			and minf(crank_rpm, sync_rpm) \
			>= TorqueConverter.COUPLING_POINT * maxf(crank_rpm, sync_rpm)


## A converter body's lock-up is released (`braking` on a converter): it slips on the converter's
## law, never closing onto the wheels.
static func lock_up_released(p_spec: VehicleSpec, p_braking: bool) -> bool:
	return p_braking and p_spec.coupling == VehicleSpec.Coupling.CONVERTER


## The capacity (N·m at the crank, >= 0) a slipping coupling needs to land a crank predicted at
## `pred` (rad/s) on `target` (rad/s) this tick, through a step of `compliance`
## (`crank_compliance`). Unbounded here; the caller holds it under the rating.
static func landing_capacity(pred: float, target: float, compliance: float) -> float:
	return absf(pred - target) / maxf(compliance, 1e-12)


## An upshift's inertia phase (rad/s per s): the rate the oncoming clutch brings the crank down
## across `rev_drop` (rad/s, the crank over the new gear's speed on the shift's tick), so the phase
## spans `spec.shift_handover_s`. Landed at that rate (`landing_capacity`), the clutch carries the
## engine's delivered torque plus `J rev_drop / t`, never past the rating: during the inertia phase
## the oncoming clutch's capacity sets the output torque, a little over the driver's demand, the
## surplus taking out the crank's inertia (US 10,343,690; the phase lasts ~0.15-0.5 s on a converter
## automatic, US 11,724,688). INF at 0: the rating, the limit that law approaches as `t` shrinks.
static func handover_rate(p_spec: VehicleSpec, rev_drop: float) -> float:
	if p_spec.shift_handover_s <= 0.0:
		return INF
	return absf(rev_drop) / p_spec.shift_handover_s


## A seamless box's torque reduction through an inertia phase (a converter automatic's or a
## powershift's, `spec.shift_cut_s` 0; the powershift's is a COMPROMISE at TRACTOR_BASE): the
## fuel, at most the pedal's `fuel`, that lands the crank (predicted `pred_base + pred_per_fuel *
## f`, rad/s) on `target` while the clutch passes `demand` (N·m at the crank: the engine's net
## torque at the pedal's fuel, the driver's demand), so the output follows the pedal through the
## shift with no shock and no hole. The TCU holds the engine's torque reduced through the phase (US 9,327,733), the oncoming
## clutch passing a little over the driver's demand (US 10,343,690). Where even no fuel cannot shed
## the inertia at that rate (a lift upshift), it is 0 and the clutch takes the surplus.
static func handover_fuel(pred_base: float, pred_per_fuel: float, target: float, demand: float,
		compliance: float, fuel: float) -> float:
	if pred_per_fuel <= 0.0:
		return 0.0
	return clampf((target + maxf(demand, 0.0) * compliance - pred_base) / pred_per_fuel, 0.0,
			maxf(fuel, 0.0))


# --- torque converter -----------------------------------------------------------------------
## A converter body (`spec.coupling` CONVERTER) runs `TorqueConverter`'s law while it slips, with
## its lock-up clutch (rated `clutch_rating`) in parallel from `spec.lockup_gear` past the coupling
## point (`lockup_engages`), so it carries drive from the first tick of a pull-away and loads the
## idling crank in gear: it creeps. COMPROMISE: the torque ratio is data and ships 1.0
## (`spec.converter_stall_ratio`, a fluid coupling), where a real converter makes about 2.0 at stall
## (docs/drivetrain.md § Converter): at 2.0, seven more bodies fail the foot brake's static stall hold
## (`BrakeSizing.stall_hold_margin` reads `stall_axle_torque`), which waits on a review of their
## brake classes against sourced hardware. A shift slips the gearbox's own clutch (the friction
## path, `_inertia_phase`, at `handover_rate`), never the converter.

## Converter stall speed as a fraction of the engine's own usable band (idle -> redline): one
## derivation for every machine, not a per-spec knob. 0.25 puts every shipped stall below its
## torque peak, which keeps the foot brake winning, and far under the redline.
const STALL_RPM_FRAC := 0.25
## Bisection steps `converter_free_rpm` takes across idle -> stall (2^-30 of the span).
const FREE_RPM_STEPS := 30


## The stall speed (rpm): where full fuel against a held turbine balances the converter, and the
## clutch controller's full-pedal launch line. One derivation: STALL_RPM_FRAC of idle -> redline.
static func stall_rpm(p_spec: VehicleSpec) -> float:
	return p_spec.idle_rpm + STALL_RPM_FRAC * (p_spec.redline_rpm - p_spec.idle_rpm)


## Crank speed the converter lets the engine reach with the turbine held (rpm) at `fuel`: where the
## engine law meets the converter's N^2 load (`TorqueConverter.capacity_coefficient`), the stall
## speed at full fuel, and never under idle (the idle controller fuels the converter's load there).
## `idle_rpm` on the rigid crank.
static func converter_free_rpm(p_spec: VehicleSpec, fuel: float) -> float:
	if not drives_wheels(p_spec):
		return p_spec.idle_rpm
	var stall := stall_rpm(p_spec)
	var f := clampf(fuel, 0.0, 1.0)
	if f >= 1.0:
		return stall
	var coef := TorqueConverter.capacity_coefficient(p_spec)
	var lo := p_spec.idle_rpm
	var hi := stall
	if _held_turbine_balance(p_spec, lo, f, coef) <= 0.0:
		return lo
	for i in FREE_RPM_STEPS:
		var mid := (lo + hi) * 0.5
		if _held_turbine_balance(p_spec, mid, f, coef) > 0.0:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## The crank's net torque (N·m) at `at_rpm` and fuel `f` against a held turbine.
static func _held_turbine_balance(p_spec: VehicleSpec, at_rpm: float, f: float,
		coef: float) -> float:
	var omega := at_rpm / RADS_TO_RPM
	return crank_torque(p_spec, at_rpm, f) - coef * omega * omega


## The crank speed (rpm) a held body sits at, and a clutch's pull-away lands on: idle plus
## `launch_rpm_over_idle` where the spec declares one (a heavy AMT's launch target); on a converter
## body its free rev with the pedal read as the fuel (`converter_free_rpm`; the lock-up's line,
## `lockup_holds`' COMPROMISE); on any other clutch the line from idle to
## the stall speed, linear in pedal. Every one but the AMT's is the stall speed at full pedal, so the
## foot brake is sized against it (`stall_axle_torque`).
static func launch_target_rpm(p_spec: VehicleSpec, pedal: float) -> float:
	if p_spec.launch_rpm_over_idle > 0.0:
		return p_spec.idle_rpm + p_spec.launch_rpm_over_idle
	if not drives_wheels(p_spec) or p_spec.coupling == VehicleSpec.Coupling.CONVERTER:
		return converter_free_rpm(p_spec, pedal)
	return lerpf(p_spec.idle_rpm, stall_rpm(p_spec), clampf(pedal, 0.0, 1.0))


## The axle torque (N·m) full pedal in gear 1 makes with the wheels held: the curve at the launch
## target, times a converter's stall torque ratio; on a CVT its relief (`cvt_max_axle_torque`), the
## most its deepest ratio passes. What the foot brake must hold (`BrakeSizing.stall_hold_margin`).
static func stall_axle_torque(p_spec: VehicleSpec) -> float:
	if is_cvt(p_spec):
		return maxf(p_spec.cvt_max_axle_torque, 0.0)
	var ratio := maxf(p_spec.converter_stall_ratio, 1.0) \
			if p_spec.coupling == VehicleSpec.Coupling.CONVERTER else 1.0
	return wheel_torque(p_spec, launch_target_rpm(p_spec, 1.0), 1.0, 1) * ratio


# --- power-split CVT (`spec.cvt_range_tops`) -------------------------------------------------
## An Eccom-class box (ZF; Deere's AutoPowr): the ratio `cvt_i` (gearbox output over input speed,
## signed, R negative) is drivetrain state the controller moves (`cvt_ratio_step`), solved as the
## gear in the spin step at the overall speed ratio `k = cvt_i / final_drive` (`_solve_cvt`), so a
## ratio of 0 is a hold, never a division: active standstill, the park pawl's form at the
## hydrostatic relief (`cvt_max_axle_torque`). Its mechanical ranges change synchronously as it
## drives, and the gear byte publishes the one engaged. No `ShiftPolicy`, no launch clutch, no shift.
## Sources and figures: docs/tractor.md § The CVT tractor.

## The variator's efficiency, 45-degree bent-axis hydrostatic units (Renius & Resch, ASAE Lecture 29,
## 2005, p. 25).
const CVT_VARIATOR_EFF := 0.85
## The hydrostatic path's share of the power at a range's bottom and top, through zero at its lock-up
## (the Eccom's, Renius & Resch Fig. 40: about +40 % to -35 %).
const CVT_SHARE_BOTTOM := 0.40
const CVT_SHARE_TOP := -0.35
## A range is published past its top by this share of the boundary, so a ratio held on a synchronous
## point does not chatter the byte (an estimate; the engaged range sets the efficiency within it).
const CVT_RANGE_HYSTERESIS := 0.02
## Seconds limit-load control takes to pull the ratio back toward holding the crank on its limit
## speed (`cvt_ratio_step`; an estimate, under the crank's own settle).
const CVT_LOAD_TAU_S := 0.3
## Reverse's top speed (km/h): Renius & Resch's market demand, "from zero to about 25 km/h".
const CVT_REVERSE_KMH := 25.0
## Engine-speed management's light-load speed over rated speed (`cvt_managed_setting`): the bottom of
## Deere's maximum speed-reduction mode, 57-81 % of rated (US 6,553,302; its example 1140 rpm on a
## 2000 rpm engine).
const CVT_LIGHT_LOAD_SHARE := 0.57
## SPN 526's largest value (0.001 per bit over two bytes): the ratio active standstill publishes.
const GEAR_RATIO_MAX := 64.255

## The CVT's current ratio (gearbox output over input, signed) and engaged range (1-based).
var cvt_i := 0.0
var cvt_range := 1
## The top ratio the box may reach this tick: its last range's, or the range a bridge byte selects.
var _cvt_top := 0.0
## The crank speed (rpm) `cvt_i` was set at: through it the ratio names the ground-speed reference
## (`cvt_ground_speed`) the rate moves, so a crank that changes speed between ticks moves none.
var _cvt_set_rpm := 0.0
## The pedal's ground-speed command (m/s) last tick: how fast the command itself moves
## (`cvt_commanded_accel`).
var _cvt_v_cmd := 0.0
## Engine-speed management's setting (rpm) last tick (`cvt_setting_step`); the demand's own while it
## stands down.
var _cvt_setting := 0.0
## The demand the all-speed governor runs this tick: on a CVT in pedal mode engine-speed
## management's (`_cvt_managed_demand`), otherwise the driver's (`PedalMap.demand`).
var governor_demand := 0.0
## The body runs at or past `WheelDrive.PAWL_ENGAGE_SPEED` this tick: active standstill holds
## nothing there (`standstill_hold`), and a ratio of 0 re-synchronises to the wheels.
var _cvt_moving := false


## The body runs a CVT: its ranges are declared, and its engine drives wheels.
static func is_cvt(p_spec: VehicleSpec) -> bool:
	return not p_spec.cvt_range_tops.is_empty() and drives_wheels(p_spec)


## The top ratio of range `byte` (a byte past the last range reads the last, as a short box reads
## its top ratio).
static func cvt_top_ratio(p_spec: VehicleSpec, byte: int) -> float:
	var tops := p_spec.cvt_range_tops
	return tops[clampi(byte, 1, tops.size()) - 1]


## The range holding `i_abs` from `current`: up past a top, down under the one below, each by
## CVT_RANGE_HYSTERESIS.
static func cvt_range_for(p_spec: VehicleSpec, i_abs: float, current: int) -> int:
	var tops := p_spec.cvt_range_tops
	var r := clampi(current, 1, tops.size())
	while r < tops.size() and i_abs > tops[r - 1] * (1.0 + CVT_RANGE_HYSTERESIS):
		r += 1
	while r > 1 and i_abs < tops[r - 2] * (1.0 - CVT_RANGE_HYSTERESIS):
		r -= 1
	return r


## The driveline efficiency at `i_abs` in range `range_i`: `efficiency` (the stepped box's, axles
## included) less the variator's loss on the hydrostatic share, which runs linearly from
## CVT_SHARE_BOTTOM at the range's bottom to CVT_SHARE_TOP at its top, so it peaks at each lock-up.
## COMPROMISE: range I's circulating power near zero speed is not modelled, where an input-coupled
## split's rises hyperbolically (Renius & Resch Fig. 30); it is traction-limited there, and the
## crank's load at a ratio near 0 is near 0 either way.
static func cvt_efficiency(p_spec: VehicleSpec, i_abs: float, range_i: int) -> float:
	var tops := p_spec.cvt_range_tops
	var r := clampi(range_i, 1, tops.size())
	var lo := tops[r - 2] if r > 1 else 0.0
	var u := clampf((i_abs - lo) / maxf(tops[r - 1] - lo, 1e-6), 0.0, 1.0)
	var share := lerpf(CVT_SHARE_BOTTOM, CVT_SHARE_TOP, u)
	return p_spec.efficiency * (1.0 - absf(share) * (1.0 - CVT_VARIATOR_EFF))


## The forward top speed (m/s): the road-speed governor's, else the last range at the redline.
static func cvt_top_speed(p_spec: VehicleSpec) -> float:
	if p_spec.speed_limit_kmh > 0.0:
		return p_spec.speed_limit_kmh / 3.6
	return cvt_top_ratio(p_spec, TOP_GEAR) / p_spec.final_drive \
			* p_spec.redline_rpm / RADS_TO_RPM * p_spec.ground_drive.drive_radius()


## The ground speed (m/s, signed with `dir`) the CVT's foot pedal commands: its share of the top
## speed (`cvt_top_speed` forward, CVT_REVERSE_KMH back), never past `cap_kmh` (a towing host's,
## `speed_cap_kmh`): a CVT governs road speed through its ratio, not by cutting the engine's fuel
## (`_fuel_step`). 0 in N or P, and under the foot brake, which brings the box to active standstill
## (Deere's AutoClutch). The hand throttle commands none: it sets engine speed only, so it never
## pulls away alone.
static func cvt_speed_command(p_spec: VehicleSpec, pedal: float, dir: float, p_braking: bool,
		cap_kmh := 0.0) -> float:
	if p_braking or dir == 0.0:
		return 0.0
	var top := CVT_REVERSE_KMH / 3.6 if dir < 0.0 else cvt_top_speed(p_spec)
	if cap_kmh > 0.0:
		top = minf(top, cap_kmh / 3.6)
	return dir * clampf(pedal, 0.0, 1.0) * top


## Limit-load control's engine speed (rpm) at `p_demand`: the governor line's full-fuel end, never
## over the curve's peak power (`PedalMap.rated_rpm`; at the top setting the line is the curve's own
## tail). Held there, the engine makes its most at that setting and the ground speed gives.
static func cvt_limit_rpm(p_spec: VehicleSpec, p_demand: float) -> float:
	return minf(PedalMap.governor_line(p_spec, p_demand).y, PedalMap.rated_rpm(p_spec))


## Engine-speed management's setting (rpm) in pedal mode: the governor's at `p_demand` brought down
## in proportion to the load, as Deere's automatic mode does (US 6,553,302): at full load the setting
## whose full-fuel end is the limit speed (`cvt_limit_rpm`, so a heavy load never runs on the
## curve's falling tail), at none CVT_LIGHT_LOAD_SHARE of rated speed. The load is `power` (W, asked
## at the crank) over what the limit speed makes at full fuel. Never under the setting whose
## full-fuel end turns `top_i` into `v_cmd` (m/s), so the commanded speed stays in reach, and never
## past the demand's own setting.
static func cvt_managed_setting(p_spec: VehicleSpec, p_demand: float, power: float, v_cmd: float,
		top_i: float) -> float:
	var own := PedalMap.setting_rpm(p_spec, p_demand)
	var droop := 1.0 + maxf(p_spec.governor_droop, PedalMap.MIN_DROOP)
	var limit := cvt_limit_rpm(p_spec, p_demand)
	var full_load := minf(own, limit * droop)
	var full_power := engine_torque(p_spec, limit) * limit / RADS_TO_RPM
	var share := clampf(power / full_power, 0.0, 1.0) if full_power > 0.0 else 1.0
	var light := minf(CVT_LIGHT_LOAD_SHARE * PedalMap.rated_rpm(p_spec), full_load)
	var reach := own
	if top_i > 0.0:
		reach = absf(v_cmd) * p_spec.final_drive / (top_i * p_spec.ground_drive.drive_radius()) \
				* RADS_TO_RPM * droop
	return minf(maxf(lerpf(light, full_load, share), reach), own)


## The ground acceleration (m/s², >= 0) the speed reference is commanded this tick, from `gap` (the
## command's speed over the reference's, m/s) and `moved` (how far the command itself moved since
## last tick): the full `cvt_accel_ms2` while the command sits past one tick's reach (the reference
## ramps at its rate), else the command's own rate, capped there. A gap inside one tick's reach is
## the reference landing, or the pressure cut-off holding it a little under a crank that slows, and
## asks for nothing.
static func cvt_commanded_accel(p_spec: VehicleSpec, gap: float, moved: float,
		delta: float) -> float:
	var accel := maxf(p_spec.cvt_accel_ms2, 0.0)
	if delta <= 0.0:
		return 0.0
	if gap > accel * delta:
		return accel
	return clampf(moved / delta, 0.0, accel)


## One tick of engine-speed management's setting (rpm) from `prev` toward `target`: up at once, down
## no faster than the ratio can wind up to hold the ground speed at its rate, `cvt_accel_ms2` over
## `speed` (m/s) a tick. Faster, the crank sits past its setting with no fuel while the ratio winds
## up behind it, the rig sags, and the reference asks for the power back.
static func cvt_setting_step(p_spec: VehicleSpec, prev: float, target: float, speed: float,
		delta: float) -> float:
	var fall := maxf(p_spec.cvt_accel_ms2, 0.0) * delta
	if target >= prev or absf(speed) <= fall:
		return target
	return maxf(target, prev * (1.0 - fall / absf(speed)))


## The ground speed (m/s, signed) ratio `i` turns a crank at `at_rpm` into, idle at least (the
## floor the ratio's rate reads too).
static func cvt_ground_speed(p_spec: VehicleSpec, i: float, at_rpm: float) -> float:
	return i * p_spec.ground_drive.drive_radius() * maxf(at_rpm, p_spec.idle_rpm) / RADS_TO_RPM \
			/ p_spec.final_drive


## One tick of the CVT's ratio from `i`, set at crank speed `set_rpm`: the ground speed it named
## there (`cvt_ground_speed`), moved toward `v_cmd` (m/s) at `cvt_accel_ms2`, as a ratio at
## `crank_rpm`, so a crank that droops or lifts between ticks moves no ground speed. Capped at
## ±`top_i` (a cap under the ratio reached at the rate), never a step past the wheels' own ratio
## (pressure cut-off); under `limit_rpm` pulled back over CVT_LOAD_TAU_S (limit-load control: the
## crank holds its limit speed, the ground speed gives). Then two hard bounds past the rate, as a
## clutch's anti-stall opens it: a crank under idle lets the ratio follow the wheels (`wheel_omega`,
## rad/s at the axle) down to idle, to 0 against held wheels, and the ratio on the wheels' side never
## puts the crank past the redline.
static func cvt_ratio_step(p_spec: VehicleSpec, i: float, v_cmd: float, crank_rpm: float,
		set_rpm: float, limit_rpm: float, wheel_omega: float, top_i: float, delta: float) -> float:
	var fd := p_spec.final_drive
	var per_ms := 1.0 / cvt_ground_speed(p_spec, 1.0, crank_rpm)
	var accel := maxf(p_spec.cvt_accel_ms2, 0.0)
	var step := accel * per_ms * delta
	var v_top := top_i / per_ms
	var bound := maxf(top_i, absf(i))
	var next := clampf(move_toward(cvt_ground_speed(p_spec, i, set_rpm),
			clampf(v_cmd, -v_top, v_top), accel * delta) * per_ms, -bound, bound)
	# Pressure cut-off: the ratio never grows more than a step past the wheels' own (`wheel_omega`
	# through it at this crank speed), so an overload the relief slips under holds the ratio
	# rather than winding it up against wheels that do not follow.
	var lead := absf(wheel_omega) * fd / (maxf(crank_rpm, p_spec.idle_rpm) / RADS_TO_RPM) + step
	if absf(next) > absf(i) and absf(next) > lead:
		next = signf(next) * maxf(absf(i), lead)
	if crank_rpm < limit_rpm:
		var pulled := lerpf(i, i * crank_rpm / limit_rpm, 1.0 - exp(-delta / CVT_LOAD_TAU_S))
		if absf(pulled) < absf(next):
			next = pulled
	if crank_rpm < p_spec.idle_rpm and wheel_omega * next >= 0.0:
		var stall_i := wheel_omega * fd / (p_spec.idle_rpm / RADS_TO_RPM)
		next = minf(next, stall_i) if next > 0.0 else maxf(next, stall_i)
	# The redline bound binds only past a step: under it the wheels turn at the crank's speed through
	# the ratio, so a bound read off them only shrinks it by the crank's share of the redline a tick
	# and never lets it reach or cross 0 (a stop, a direction change).
	if i * wheel_omega > 0.0:
		var over_i := wheel_omega * fd / (p_spec.redline_rpm / RADS_TO_RPM)
		if absf(over_i) > step:
			next = maxf(next, over_i) if wheel_omega > 0.0 else minf(next, over_i)
	return next


## The CVT's torque capacity at the axle (N·m) at overall speed ratio `k`: the range clutches'
## `capacity` at the crank (N·m) through `k` with `factor` (eta driving, 1 / eta in overrun), never
## past the relief; the relief alone at `k` 0.
static func cvt_axle_capacity(p_spec: VehicleSpec, capacity: float, k: float,
		factor: float) -> float:
	var relief := maxf(p_spec.cvt_max_axle_torque, 0.0)
	if k == 0.0:
		return relief
	return minf(capacity * factor / absf(k), relief)


## SPN 526's actual gear ratio: the gearbox's input speed over its output (no final drive),
## unsigned, 0 in N or P. On a CVT its live ratio `i` (output over input) inverted, GEAR_RATIO_MAX at
## active standstill.
static func gear_ratio_of(p_spec: VehicleSpec, byte: int, i: float) -> float:
	if is_open(byte):
		return 0.0
	if is_cvt(p_spec):
		return GEAR_RATIO_MAX if absf(i) * GEAR_RATIO_MAX <= 1.0 else 1.0 / absf(i)
	if is_reverse(byte):
		return p_spec.reverse_ratio
	var n := p_spec.gear_ratios.size()
	return p_spec.gear_ratios[mini(byte, n) - 1] if n > 0 else 0.0


## Active standstill's hold at the drive axle (N·m): the relief, while a locked CVT sits at a ratio
## of 0 under `WheelDrive.PAWL_ENGAGE_SPEED`, the pawl's own gate; else 0. The owner hands it to the
## wheels' lock (`WheelDrive.standstill_lock`), the park pawl's path with its stiction, as the
## transmission holding the output still; the coupling then passes nothing (`_process_cvt`), so the
## two never hold twice. Faster, brakes that hold the wheels still bring the ratio to 0 while the
## body slides, and a hold there would keep them locked once the brakes let go.
func standstill_hold() -> float:
	if not is_cvt(spec) or coupling_state != CouplingState.LOCKED or cvt_i != 0.0 \
			or _cvt_moving:
		return 0.0
	return maxf(spec.cvt_max_axle_torque, 0.0)


## The gearbox as a spec sheet names it: its forward ratios' count, or a CVT's ranges.
static func gears_label(p_spec: VehicleSpec) -> String:
	if is_cvt(p_spec):
		return "CVT, %d ranges" % p_spec.cvt_range_tops.size()
	return "%d" % p_spec.gear_ratios.size()


## This tick's SPN 526 ratio (`gear_ratio_of`).
func gearbox_ratio() -> float:
	return gear_ratio_of(spec, gear_byte, cvt_i)


# --- auxiliary driveline retarder (truck, J1939 SPN 520) ------------------------------------
## Gated by GroundDriveSpec.retarder_equipped and applied by WheelDrive. It joins the other brake
## torques so RayWheel integrates it in the same semi-implicit step (through `spin_compliance`),
## and must stay inside that integrator: a separate move_toward after the wheels tick
## over-corrects on the first tick.

## Its rating is the hardware's own (`GroundDriveSpec.retarder_rating_nm`, at the gearbox output);
## retardation figures: docs/truck.md. `test_truck` pins a band per spec. Raising a rating
## means re-checking `RETARDER_SLIP_TARGET`.
const RETARDER_CUTOUT_MS := 1.5  ## m/s below which a driveline brake does nothing at all
const RETARDER_FULL_MS := 8.0    ## m/s (~29 km/h) at which it reaches its rating
## Slip ratio the retarder will not drive the driven axle past. A backstop, not the operating
## point, so a rating edit fails visibly instead of quietly skidding the axle. Slip, not force: a
## locked wheel already makes the saturated road torque, so a force cap at mu*N*r permits a skid.
const RETARDER_SLIP_TARGET := 0.10


## The retarder's rated torque at one driven rear wheel (Nm), the 'retarder_state' 100 % point: its
## gearbox-output rating through `final_drive`, shared by the driven rear wheels, the ones
## `WheelDrive` applies it to.
static func retarder_rating(p_spec: VehicleSpec) -> float:
	var gd := p_spec.ground_drive
	if gd == null:
		return 0.0
	return maxf(gd.retarder_rating_nm, 0.0) * p_spec.final_drive / maxf(1.0, _driven_rears(gd))


## The retarder at full as a share of the whole foot brake's capacity (every wheel's): what it asks
## of a towed trailer's brakes. A trailer apportioned to its tractor brakes like it at any shared
## fraction (box_spec.tres), so the two ends decelerate alike
## (`TruckTelemetry.trailer_brake_blend`).
static func retarder_fraction(p_spec: VehicleSpec) -> float:
	var gd := p_spec.ground_drive
	if gd == null or gd.brake_torque <= 0.0 or gd.wheel_positions.is_empty():
		return 0.0
	return clampf(retarder_rating(p_spec) * _driven_rears(gd)
			/ (gd.brake_torque * gd.wheel_positions.size()), 0.0, 1.0)


static func _driven_rears(gd: GroundDriveSpec) -> int:
	if not gd.driven_rear:
		return 0
	var n := 0
	for p in gd.wheel_positions:
		if RayWheel.is_rear_z(p.z):
			n += 1
	return n


## Fraction of rating a driveline retarder can make at this road speed, 0..1. Falls off to
## nothing at walking pace (no shaft speed to work against), saturates once rolling.
static func retarder_speed_fade(speed_ms: float) -> float:
	return clampf((absf(speed_ms) - RETARDER_CUTOUT_MS) / (RETARDER_FULL_MS - RETARDER_CUTOUT_MS),
			0.0, 1.0)


## What the driver asked for at one driven wheel (Nm): `rating` (`retarder_rating`) x request x
## speed fade.
static func retarder_demand(request01: float, speed_ms: float, rating: float) -> float:
	return clampf(request01, 0.0, 1.0) * maxf(rating, 0.0) * retarder_speed_fade(speed_ms)


## Anti-lock backstop (Nm): the most spin this wheel may lose in one tick without exceeding
## RETARDER_SLIP_TARGET, and 0 once the axle is already at or past it. Uses RayWheel's own slip
## denominator at its least floor (LOW_SPEED_FLOOR, under any wheel's `slip_floor`, so the cap only
## tightens). `road_speed` is the signed chassis forward velocity (negative in
## reverse), never a magnitude. `compliance` is the wheel's spin change per N·m of brake this tick
## (`RayWheel.spin_compliance`; `delta / inertia` on a free wheel), so a gripping wheel, which the
## road holds up, may take more torque than a free one.
static func retarder_slip_cap(omega: float, road_speed: float, radius: float,
		compliance: float) -> float:
	if radius <= 0.0 or compliance <= 0.0:
		return 0.0
	var denom := maxf(absf(road_speed), RayWheel.LOW_SPEED_FLOOR)
	var slip_vel := omega * radius - road_speed
	# Headroom toward the braking side (m/s of slip velocity); the sign of road_speed picks the
	# direction. Nonzero at a standstill, harmless: demand is 0 below RETARDER_CUTOUT_MS.
	var headroom := signf(road_speed) * slip_vel + RETARDER_SLIP_TARGET * denom
	return maxf(headroom, 0.0) / (radius * compliance)


## Retarder braking torque for one driven wheel of `radius` (Nm, unsigned): demand on `rating` held
## under the anti-lock backstop. `road_speed` is signed — see retarder_slip_cap.
static func retarder_torque(request01: float, road_speed: float, omega: float, radius: float,
		compliance: float, rating: float) -> float:
	return minf(retarder_demand(request01, road_speed, rating),
			retarder_slip_cap(omega, road_speed, radius, compliance))


## Retarder torque as the contract's percentage: applied over rating. Unsigned, though SPN 520
## reports it negative, so the bar fills as retardation rises.
static func retarder_pct(applied_nm: float, rated_nm: float) -> float:
	if rated_nm <= 0.0:
		return 0.0
	return clampf(absf(applied_nm) / rated_nm * 100.0, 0.0, 100.0)


# --- start-up ramp (powershift modulation) -------------------------------------------------
## Road speed (m/s) under which a released pedal restarts the start-up ramp, as a powershift
## disengages before the engine would lug to a stall.
const CLUTCH_OPEN_SPEED := 0.5


## One tick of the start-up ramp (`spec.launch_engage_s`): 0 in N, on a direction change, and when
## nearly stopped with the pedal up; otherwise rising linearly over `launch_engage_s`. On a
## wheel-driving body it bounds the capacity the controller may command (a powershift's pressure
## ramp); on the rigid crank it scales the torque. It only ever withholds torque, so
## brake > drive > handbrake holds.
static func ramp_step(p_spec: VehicleSpec, current: float, from_byte: int, to_byte: int,
		throttle: float, ground_speed: float, delta: float) -> float:
	if p_spec.launch_engage_s <= 0.0:
		return 1.0
	if is_open(to_byte) or (is_shift(from_byte, to_byte)
			and is_reverse(from_byte) != is_reverse(to_byte)):
		return 0.0
	if throttle <= 0.0 and absf(ground_speed) < CLUTCH_OPEN_SPEED:
		return 0.0
	return move_toward(current, 1.0, delta / p_spec.launch_engage_s)


## True while the post-shift throttle cut is running. Test accessor for `_shift_cut_ticks`.
func shift_cut_active() -> bool:
	return _shift_cut_ticks > 0


## One tick of the fuel's ceiling after a shift cut (`spec.shift_torque_ramp_s`): 0 while `cutting`,
## then rising linearly to 1 over the ramp; 1 with no ramp. A ceiling only: it never adds fuel.
static func torque_restore_step(p_spec: VehicleSpec, current: float, cutting: bool,
		delta: float) -> float:
	if p_spec.shift_torque_ramp_s <= 0.0:
		return 1.0
	if cutting:
		return 0.0
	return move_toward(current, 1.0, delta / p_spec.shift_torque_ramp_s)


## Ticks a shift cut lasts at this tick length: whole ticks, rounded up, 0 for no cut.
static func shift_cut_ticks(cut_s: float, delta: float) -> int:
	if cut_s <= 0.0 or delta <= 0.0:
		return 0
	return ceili(cut_s / delta)


## A byte change that is a SHIFT: both sides engaged (D or R), so N<->D or P<->D is a selection,
## not a shift.
static func is_shift(from_byte: int, to_byte: int) -> bool:
	return from_byte != to_byte and not is_open(from_byte) and not is_open(to_byte)


## The automatic's shift step within D1-D24, as `ShiftPolicy.next_gear` gives it at `at_rpm` (the
## road speed's, in `byte`), the pedal, the time in gear, an armed kickdown, the road load, the
## lowest gear a downshift takes, the foot brake, whether the load reads as a grade and the rig's
## mass and grip; N/R/P never auto-shift. The defaults are a full pedal with no state: the
## fixed-threshold step.
static func auto_shift(p_spec: VehicleSpec, byte: int, at_rpm: float, pedal := 1.0,
		gear_s := INF, kickdown := false, road := NAN, floor_gear := 1,
		p_braking := false, grade := true, mass := 0.0, grip := INF) -> int:
	if not is_drive(byte):
		return normalize_byte(byte)
	return ShiftPolicy.next_gear(p_spec, byte, at_rpm, pedal, gear_s, kickdown, road, floor_gear,
			p_braking, grade, mass, grip)


## Per-tick update: adopt the gear request, then either run the rigid crank and return the
## drive-axle torque (Nm), or, on a body that drives wheels, run the controller and the crank's
## predictor and return 0: there the drive reaches the wheels only through `couple`, which the
## wheels' solve calls this same tick, so the wheels' own steps carry none.
## auto=true (local input): request is a direction (N/enter-D/R), box auto-shifts within D1-D24.
## auto=false (bridge): byte is exact, auto-shift bypassed.
## `ground_speed` (not `drive_wheel_omega`) drives auto-shift so wheelspin can't fake a high rpm.
func process(delta: float, throttle: float, drive_wheel_omega: float,
		ground_speed: float, requested_byte: int, auto: bool) -> float:
	var crank := drives_wheels(spec)
	var req := normalize_byte(requested_byte)
	if req == GEAR_P and not has_park_pawl(spec):
		req = GEAR_N
	if drive_inhibit and not is_open(req):
		req = GEAR_N
	var prev_byte := gear_byte
	# The policy reads the driver's demand, never `applied_throttle` (ShiftPolicy's header): the
	# pedal, or on an all-speed governor the higher of it and the hand throttle.
	var pedal := clampf(throttle, 0.0, 1.0)
	var demand := PedalMap.demand(spec, pedal, hand_throttle)
	governor_demand = demand
	var at_rest := absf(ground_speed) < HillHold.REST_SPEED
	_update_road_load(delta, ground_speed, at_rest)
	var kick := false
	if is_cvt(spec):
		# The CVT's byte: the direction here, the range once the ratio moves (`_process_cvt`). A
		# bridge's exact drive byte caps the range.
		_cvt_top = cvt_top_ratio(spec, req if is_drive(req) and not auto else TOP_GEAR)
		if not is_drive(req):
			gear_byte = req
		elif not is_drive(gear_byte):
			gear_byte = cvt_range
		_launching = false
	elif auto:
		var starts := spec.start_gear_max > 1
		if req == GEAR_R or is_open(req):
			gear_byte = req
		elif not is_drive(gear_byte):
			gear_byte = _pick_start_gear() if starts and at_rest else req
		if is_drive(gear_byte):
			if starts:
				gear_byte = _start_gear_step(delta, pedal, demand, at_rest)
			# Road speed, not the drive wheel: wheelspin over-reads rpm and upshifts early.
			var road_omega := ground_speed / road_radius
			var gear_s := _gear_s if gear_byte == prev_byte else 0.0
			var from := gear_byte
			var at_rpm := rpm_from_wheel(spec, road_omega, from)
			var floor_gear := _start_gear if _launching else 1
			kick = ShiftPolicy.kickdown_armed(spec, _kickdown, demand, last_pedal)
			gear_byte = auto_shift(spec, from, at_rpm, demand, gear_s, kick, road_load, floor_gear,
					braking, ShiftPolicy.on_grade(spec, road_load, ground_speed, load_mass_kg,
							rolling_crr),
					load_mass_kg, _grip())
			kick = kick and not ShiftPolicy.kickdown_spent(spec, from, at_rpm, demand, gear_s,
					floor_gear)
			# Against the limiter, take the tallest gear that will hold.
			if governor_scale(spec, ground_speed, speed_cap_kmh) < 1.0:
				gear_byte = governed_upshift(spec, gear_byte, ground_speed, road_radius)
		else:
			_launching = false
	else:
		gear_byte = req
		_launching = false
	_kickdown = kick
	_gear_s = 0.0 if gear_byte != prev_byte else _gear_s + delta
	last_pedal = demand
	# One latch per tick however many gears governed_upshift walked: the comparison is against
	# the byte this tick STARTED with.
	if is_shift(prev_byte, gear_byte):
		_shift_cut_ticks = shift_cut_ticks(spec.shift_cut_s, delta)
	ramp = ramp_step(spec, ramp, prev_byte, gear_byte, throttle, ground_speed, delta)
	if crank:
		_process_crank(delta, pedal, demand, drive_wheel_omega, ground_speed, prev_byte)
		return 0.0

	# The rigid crank. In N or P the wheels say nothing about crank speed, so a free-rev model
	# stands in, built off the redline so it can never trip the limiter.
	var limiter_rpm := spec.idle_rpm
	var target_rpm: float
	if is_open(gear_byte):
		target_rpm = lerpf(spec.idle_rpm, spec.redline_rpm, clampf(throttle, 0.0, 1.0))
	else:
		limiter_rpm = wheel_engine_rpm(spec, drive_wheel_omega, gear_byte)
		target_rpm = maxf(clampf(limiter_rpm, spec.idle_rpm, spec.redline_rpm),
				converter_free_rpm(spec, throttle))
	rpm = lerpf(rpm, target_rpm, 1.0 - exp(-RPM_SMOOTH * delta))

	# Wheels turning against the engaged gear (rolled back in D, forward in R) drive the crank
	# backwards: that is no overspeed, and no engine braking either. Judged on |rpm|, a backwards
	# wheel would trip the limiter and the overrun, signed against the gear, would spin it further
	# back: a latch only the brake breaks.
	var crank_forward := drive_wheel_omega * ratio_for_byte(spec, gear_byte) >= 0.0
	# The limiter and governor cut between pedal and engine: rpm still follows the wheels.
	applied_throttle = clampf(throttle, 0.0, 1.0) * governor_scale(spec, ground_speed, speed_cap_kmh)
	on_limiter = crank_forward and limiter_cut(spec, limiter_rpm)
	if on_limiter:
		applied_throttle = 0.0
	# The shift cut is a lift: no fuel, and it rides applied_throttle so telemetry reads it.
	_torque_restore = torque_restore_step(spec, _torque_restore, _shift_cut_ticks > 0, delta)
	applied_throttle = minf(applied_throttle, _torque_restore)
	if _shift_cut_ticks > 0:
		_shift_cut_ticks -= 1
		applied_throttle = 0.0
	# One law on the DELIVERED fuel: every cut (limiter, governor, shift, a lifted pedal) is engine
	# braking. applied_throttle stays the fuel fraction, so a motoring engine shows no load to fuel
	# / coolant / engine_load (J1939 negative percent-torque is deliberately not modelled).
	var overrun_t := overrun_torque(spec, rpm, applied_throttle, gear_byte) if crank_forward else 0.0
	return (wheel_torque(spec, rpm, applied_throttle, gear_byte) + overrun_t) * ramp


## One tick of the road-load estimate (`road_load`), before the gear is chosen: `standing_load` at
## rest, held under the foot brake, otherwise last tick's coupling torque less the rig's mass times
## the acceleration since the last tick (`ShiftPolicy.road_load_step`).
func _update_road_load(delta: float, ground_speed: float, at_rest: bool) -> void:
	if not drives_wheels(spec) or load_mass_kg <= 0.0:
		road_load = NAN
	elif at_rest:
		road_load = standing_load
	elif not braking and not is_nan(_last_speed) and delta > 0.0:
		road_load = ShiftPolicy.road_load_step(road_load, _axle_torque, load_mass_kg,
				(ground_speed - _last_speed) / delta, road_radius, delta)
	_last_speed = ground_speed


## `drive_grip_n` as the policy reads it: INF (no cap) with no estimate.
func _grip() -> float:
	return drive_grip_n if drive_grip_n > 0.0 else INF


## The start gear for a pull-away from here (`ShiftPolicy.start_gear` on `standing_load`, the rig's
## mass and grip), and the launch it starts.
func _pick_start_gear() -> int:
	_start_gear = ShiftPolicy.start_gear(spec, standing_load, 1.0, load_mass_kg, _grip())
	_launching = true
	_launch_s = 0.0
	return _start_gear


## The start gear's tick, in D (`spec.start_gear_max` above 1). At rest with the pedal up the box
## re-picks for the load standing there, at full pedal. Through the launch it steps down to what the
## driver's `demand` holds (`ShiftPolicy.start_gear`), never up: the moving estimate reads a launch's
## transients as load. Held at rest with the pedal down for `launch_engage_s + shift_dwell_s`, it
## steps to a deeper ratio (`ShiftPolicy.start_step_down`), and again after as long. The launch ends
## once the coupling locks, or on a lift while rolling; the lock starts the dwell's clock, as tyres
## slipping at their peak lock a heavy launch under the downshift point while it gains speed.
func _start_gear_step(delta: float, pedal: float, demand: float, at_rest: bool) -> int:
	if at_rest and pedal <= 0.0:
		return _pick_start_gear()
	if not _launching:
		return gear_byte
	if coupling_state == CouplingState.LOCKED:
		_launching = false
		_gear_s = 0.0
		return gear_byte
	if not at_rest and pedal <= 0.0:
		_launching = false
		return gear_byte
	var fit := ShiftPolicy.start_gear(spec, standing_load, demand, load_mass_kg, _grip())
	if fit < _start_gear:
		_start_gear = fit
		_launch_s = 0.0
		return _start_gear
	_launch_s = _launch_s + delta if at_rest else 0.0
	if _start_gear > 1 and _launch_s >= spec.launch_engage_s + spec.shift_dwell_s:
		_start_gear = ShiftPolicy.start_step_down(spec, _start_gear)
		_launch_s = 0.0
		return _start_gear
	return gear_byte


## The tick's delivered fuel (0..1) and the crank's predictor at it: the demand through its map (or,
## in N or P with a PTO set speed, the governor at it: `pto_set_rpm`) and
## the road-speed governor (on a stepped box; a CVT's ratio governs, `cvt_speed_command`), the
## limiter's hard cut on the crank and the shift cut; then the
## controller's floors (idle, drag-torque control), which no cut lifts. Sets `_compliance`,
## `_pred_base` and `_pred_per_fuel`.
func _fuel_step(delta: float, demand: float, ground_speed: float, omega: float) -> float:
	var pto_set := pto_set_rpm if is_open(gear_byte) else 0.0
	var pto_governs := pto_set > 0.0
	if pto_governs:
		demand = PedalMap.demand(spec, demand, hand_throttle, pto_set)
	var fuel := 0.0
	if running:
		fuel = PedalMap.fuel(spec, demand, rpm, pto_governs)
		if not is_cvt(spec):
			fuel *= governor_scale(spec, ground_speed, speed_cap_kmh)
		if limiter_cut(spec, rpm) or _landed:
			fuel = 0.0
	on_limiter = running and (limiter_cut(spec, rpm) or _landed)
	_landed = false
	_torque_restore = torque_restore_step(spec, _torque_restore, _shift_cut_ticks > 0, delta)
	fuel = minf(fuel, _torque_restore)
	if _shift_cut_ticks > 0:
		_shift_cut_ticks -= 1
		fuel = 0.0
	# The step's stiffness is read at the pedal's fuel, before the floors: they move the fuel a
	# little, and the step stays semi-implicit either way. The pedal map's own slope in rpm is left
	# out: the petrol request's steepest fall is k dt / J 0.23 on `race-future`'s crank, explicit
	# and well inside the step's limit of 2. An all-speed governor's line is not: on a tick its line
	# governs (`PedalMap.governor_stiffness`, the line's fuel strictly between 0 and 1) with this
	# fuel inside (0, 1) too, the line's slope is the stiffness. A cap that holds the fuel under the
	# line's (the road-speed governor, the torque restore) keeps that slope, which over-damps the
	# step and never destabilises it.
	var governed := PedalMap.governor_stiffness(spec, demand, rpm, pto_governs) \
			if running and fuel > 0.0 and fuel < 1.0 else NAN
	_compliance = crank_compliance(spec, rpm, fuel, delta, governed)
	# A free crank's governor fuels no more than lands it on its setting this tick (`fuel_to_land`):
	# read at the tick's start, full fuel carries it ~90 rpm a tick, past an isochronous line ~1 rpm
	# wide, which it would then jump both ways and cycle on. In gear the wheels hold it under.
	if running and is_open(gear_byte) \
			and (spec.pedal_map == PedalMap.Kind.ALL_SPEED or pto_governs):
		fuel = minf(fuel, fuel_to_land(spec, omega, PedalMap.setting_rpm(spec, demand) / RADS_TO_RPM,
				_compliance, accessory_torque))
	if running:
		fuel = maxf(fuel, fuel_to_land(spec, omega, spec.idle_rpm / RADS_TO_RPM, _compliance,
				accessory_torque))
		if drag_control:
			fuel = maxf(fuel, drag_fuel(spec, rpm, accessory_torque))
	var unfuelled := crank_torque(spec, rpm, 0.0, running)
	_pred_base = omega + (unfuelled - accessory_torque) * _compliance
	_pred_per_fuel = (crank_torque(spec, rpm, 1.0, running) - unfuelled) * _compliance \
			if running else 0.0
	return fuel


## The crank path's half of `process`: the controller's state, the delivered fuel and the crank's
## predictor, plus the capacity `couple` solves with. The fuel and the launch line read `demand`; a
## clutch's opening at rest reads the `pedal` (the hand throttle never pulls away alone).
func _process_crank(delta: float, pedal: float, demand: float, drive_wheel_omega: float,
		ground_speed: float, prev_byte: int) -> void:
	if running and not _was_running and rpm < spec.idle_rpm:
		rpm = spec.idle_rpm  # the key's Ignition edge: the starter, not modelled
	_was_running = running
	var omega := rpm / RADS_TO_RPM
	if is_cvt(spec):
		_process_cvt(delta, pedal, demand, omega, drive_wheel_omega, ground_speed)
		return
	var g := ratio_for_byte(spec, gear_byte)
	var sync := drive_wheel_omega * g
	coupling_state = coupling_step(spec, coupling_state, prev_byte, gear_byte, pedal, rpm,
			sync * RADS_TO_RPM, running, abs_release, braking)
	if is_shift(prev_byte, gear_byte):
		_inertia_phase = true
		_handover_rate = handover_rate(spec, omega - sync)
	if coupling_state != CouplingState.SLIPPING:
		_inertia_phase = false
		_handover_rate = INF
	var fuel := _fuel_step(delta, demand, ground_speed, omega)

	# The capacity the controller commands at the crank, never past the rating times the ramp.
	var ceiling := clutch_rating(spec) * ramp
	_capacity = 0.0
	_drives = true
	_stall_bound = 0.0
	converting = false
	match coupling_state:
		CouplingState.LOCKED:
			_capacity = ceiling
			_drives = _predict(fuel) >= sync
		CouplingState.SLIPPING:
			var line := launch_target_rpm(spec, demand) / RADS_TO_RPM
			var closing := sync >= line and not lock_up_released(spec, braking)
			if spec.coupling == VehicleSpec.Coupling.CONVERTER and not (_inertia_phase and closing):
				# The converter law, the lock-up closing in parallel once the two sides are past the
				# coupling point. Under the foot brake, or with the wheel side under the line, a
				# shift's slip is the converter's too.
				_inertia_phase = false
				converting = true
				if lockup_engages(spec, gear_byte, rpm, sync * RADS_TO_RPM, line * RADS_TO_RPM,
						abs_release, braking):
					_capacity = ceiling
				_ratio = TorqueConverter.torque_ratio(spec.converter_stall_ratio,
						sync / maxf(omega, 1e-6))
				_stall_bound = _ratio * TorqueConverter.impeller_torque(_coef, _predict(fuel), 0.0)
				_drives = _predict(fuel) >= sync
			elif closing:
				# Closing onto turning wheels: the whole rating; the solve carries only what closes
				# the slip, and `couple` locks it the tick it closes. An inertia phase (an upshift,
				# or a clutch pull-away turning to closing, whose flare would reach the wheels in a
				# tick) lands at `handover_rate` instead. Where the wheels run faster (a downshift)
				# the clutch stays open until the rev-match blip reaches them: closed early, the
				# rating drags the driven wheels to spin the crank up (an ABS trip under braking).
				_capacity = ceiling
				if not _inertia_phase and spec.coupling == VehicleSpec.Coupling.CLUTCH:
					_inertia_phase = true
					_handover_rate = handover_rate(spec, omega - sync)
				if _inertia_phase and _predict(fuel) >= sync and not is_inf(_handover_rate):
					var target := maxf(omega - _handover_rate * delta, sync)
					# A seamless box (no `shift_cut_s`: a converter automatic, a powershift) reduces
					# the engine; a cut box's interruption is its cut.
					if spec.shift_cut_s <= 0.0:
						fuel = handover_fuel(_pred_base, _pred_per_fuel, target,
								crank_torque(spec, rpm, fuel, running) - accessory_torque, _compliance,
								fuel)
					# Nothing while the crank's own motoring already falls faster (a cut). The
					# phase's last tick keeps the rating, so the solve closes the slip and locks
					# (on a seamless box at the reduced fuel, so it passes the demand there too).
					if target > sync:
						_capacity = landing_capacity(_predict(fuel), target, _compliance) \
								if _predict(fuel) > target else 0.0
				if _predict(fuel) < sync:
					var blip := fuel_to_land(spec, omega,
							minf(sync, spec.redline_rpm / RADS_TO_RPM), _compliance, accessory_torque)
					fuel = maxf(fuel, blip)
					if _predict(fuel) < sync and blip >= 1.0:
						_capacity = 0.0
				_drives = _predict(fuel) >= sync
			else:
				# A clutch's pull-away: land the crank on its launch target. Under it the coupling
				# carries nothing and the pedal revs the crank.
				# Never more than the engine's fuelled torque, as a slipping clutch at a steady crank
				# passes: when a lifted pedal lowers the target, the crank sinks to it on its own
				# motoring, and its inertia never floods the wheels (a slip flash a feathered pedal on
				# mud chases into a limit cycle).
				if _predict(fuel) > line:
					_capacity = minf(landing_capacity(_predict(fuel), line, _compliance),
							maxf(fuel * engine_torque(spec, rpm) - accessory_torque, 0.0))
	_capacity = minf(_capacity, ceiling)
	var rating := clutch_rating(spec)
	clutch = _capacity / rating if rating > 0.0 else 0.0
	applied_throttle = fuel


## The CVT's half of `_process_crank`: the fuel (the all-speed governor's law, with no road-speed
## fade), then the ratio (`cvt_ratio_step`) the solve will hold, chosen before it so the solve
## carries what the ratio's change takes from the crank's inertia. Open with the key off and in N or
## P; otherwise locked, the relief its only slip, and at a ratio of 0 at rest its hold the wheels'
## (`standstill_hold`). Engaged from open, or at a ratio of 0 on the move, the ratio is synchronised
## to the wheels first. The foot `pedal` commands ground speed; the `demand`, managed in pedal mode
## (`_cvt_managed_demand`), sets the engine speed and the limit-load speed.
func _process_cvt(delta: float, pedal: float, demand: float, omega: float, wheel_omega: float,
		ground_speed: float) -> void:
	var dir := drive_sign(gear_byte)
	var v_cmd := cvt_speed_command(spec, pedal, dir, braking, speed_cap_kmh)
	governor_demand = _cvt_managed_demand(delta, demand, dir, v_cmd, ground_speed)
	var fuel := _fuel_step(delta, governor_demand, ground_speed, omega)
	var was_open := coupling_state == CouplingState.OPEN
	_cvt_moving = absf(ground_speed) >= WheelDrive.PAWL_ENGAGE_SPEED
	coupling_state = CouplingState.OPEN if not running or dir == 0.0 else CouplingState.LOCKED
	converting = false
	_inertia_phase = false
	_stall_bound = 0.0
	_capacity = 0.0
	_drives = true
	if coupling_state == CouplingState.OPEN:
		cvt_i = 0.0
	else:
		if was_open or (cvt_i == 0.0 and _cvt_moving):
			cvt_i = clampf(wheel_omega * spec.final_drive
					/ maxf(omega, spec.idle_rpm / RADS_TO_RPM), -_cvt_top, _cvt_top)
			_cvt_set_rpm = rpm
		cvt_i = cvt_ratio_step(spec, cvt_i, v_cmd, rpm, _cvt_set_rpm,
				cvt_limit_rpm(spec, governor_demand), wheel_omega, _cvt_top, delta)
		_cvt_set_rpm = rpm
		cvt_range = cvt_range_for(spec, absf(cvt_i), cvt_range)
		if dir > 0.0:
			gear_byte = cvt_range
		# At a ratio of 0 the hold is the wheels' lock (`standstill_hold`), not the coupling's.
		_capacity = clutch_rating(spec) if cvt_i != 0.0 else 0.0
		var k := cvt_i / spec.final_drive
		_drives = k == 0.0 or (_predict(fuel) * k - wheel_omega) * signf(k) >= 0.0
	clutch = 1.0 if _capacity > 0.0 else 0.0
	applied_throttle = fuel


## The demand a CVT's governor runs this tick. In pedal mode (in D or R with the hand throttle off, no
## PTO engaged and a road-load estimate in hand) engine-speed management's (`cvt_managed_setting`)
## at the power the rig asks: the road load, plus the rig's mass at the acceleration the speed
## reference is commanded (`cvt_commanded_accel`, read before limit-load control, so a pull-back
## never starves the setting), at the road speed and through the box's efficiency; it falls no
## faster than the ratio can follow (`cvt_setting_step`). Otherwise `demand`: the hand throttle pins
## engine speed, and with the PTO on the engine keeps the demand's speed (Deere's automatic mode
## keeps rated speed there).
func _cvt_managed_demand(delta: float, demand: float, dir: float, v_cmd: float,
		ground_speed: float) -> float:
	var moved := absf(v_cmd) - absf(_cvt_v_cmd)
	_cvt_v_cmd = v_cmd
	if not running or dir == 0.0 or hand_throttle > 0.0 or pto_engaged or is_nan(road_load) \
			or delta <= 0.0:
		_cvt_setting = PedalMap.setting_rpm(spec, demand)
		return demand
	var gap := absf(v_cmd) - absf(cvt_ground_speed(spec, cvt_i, _cvt_set_rpm))
	var accel := cvt_commanded_accel(spec, gap, moved, delta)
	var axle := (road_load * dir + load_mass_kg * accel * road_radius) * absf(ground_speed) \
			/ road_radius
	var power := maxf(axle, 0.0) / maxf(cvt_efficiency(spec, absf(cvt_i), cvt_range), 0.05)
	_cvt_setting = cvt_setting_step(spec, _cvt_setting,
			cvt_managed_setting(spec, demand, power, v_cmd, _cvt_top), ground_speed, delta)
	return PedalMap.demand_for_setting(spec, _cvt_setting)


## The crank's predicted spin (rad/s) at the end of this tick with `fuel` and no coupling.
func _predict(fuel: float) -> float:
	return maxf(_pred_base + _pred_per_fuel * fuel, 0.0)


## The gearbox-output coupling, solved first in `WheelDrive._couple_differentials`: the crank is
## one more output, spin `omega / G` and compliance `c / G^2` at the axle, the loss by direction
## (driving `c / (G^2 eta)`, capacity `C |G| eta`; overrun `eta c / G^2`, `C |G| / eta`).
## `wheel_solve(spin, compliance, capacity)` returns the axle torque (+ = forward) with the wheels'
## holds; while `converting`, `TorqueConverter.solve` runs against `wheel_spin` instead. Locks a
## coupling that carried under its capacity. Returns the axle torque; 0 in N, P or open.
func couple(wheel_solve: Callable, wheel_spin: Callable) -> float:
	var cvt := is_cvt(spec)
	var g := ratio_for_byte(spec, gear_byte)
	var fuel := applied_throttle
	var red := spec.redline_rpm / RADS_TO_RPM
	if (g == 0.0 and not cvt) or (not converting and _capacity <= 0.0):
		overrun = false
		coupling_torque = 0.0
		if _predict(fuel) > red and fuel > 0.0:
			fuel = minf(fuel, fuel_to_land(spec, rpm / RADS_TO_RPM, red, _compliance,
					accessory_torque))
			_landed = true
			on_limiter = true
		applied_throttle = fuel
		rpm = _predict(fuel) * RADS_TO_RPM
		_axle_torque = 0.0
		return 0.0
	var solved := _solve_output(wheel_solve, wheel_spin, fuel, g)
	if solved[1] > red and fuel > 0.0:
		var lo := 0.0
		var lo_solved := _solve_output(wheel_solve, wheel_spin, 0.0, g)
		if lo_solved[1] < red:
			var hi := fuel
			for i in LIMITER_LANDING_STEPS:
				var f := (lo + hi) * 0.5
				var at := _solve_output(wheel_solve, wheel_spin, f, g)
				if at[1] > red:
					hi = f
				else:
					lo = f
					lo_solved = at
		fuel = lo
		solved = lo_solved
		_landed = true
		on_limiter = true
	applied_throttle = fuel
	var t: float = solved[0]
	overrun = t * (cvt_i if cvt else g) < 0.0
	# An engine does not turn backwards: the controller opens the coupling before the wheels could
	# drag it there.
	rpm = maxf(solved[1], 0.0) * RADS_TO_RPM
	coupling_torque = solved[3]
	if coupling_state == CouplingState.SLIPPING and solved[2]:
		coupling_state = CouplingState.LOCKED
		_inertia_phase = false
	_axle_torque = t
	return t


## One solve of the gearbox-output coupling at `fuel`: [axle torque to the wheels, the crank's
## settled spin (rad/s), whether it carried less than its capacity (it locks), the torque at the
## crank].
func _solve_output(wheel_solve: Callable, wheel_spin: Callable, fuel: float, g: float) -> Array:
	if is_cvt(spec):
		return _solve_cvt(wheel_solve, fuel)
	var pred := _predict(fuel)
	var eta := maxf(spec.efficiency, 0.05)
	if converting:
		var r := TorqueConverter.solve(pred, _compliance, _coef, g, eta, _ratio, _capacity,
				wheel_spin)
		return [r[1], r[2], r[3], r[0]]
	var reflect := _compliance / (g * g)
	var capacity := _capacity * absf(g) * eta
	var t: float = wheel_solve.call(pred / g, reflect / eta, capacity)
	var crank_load := t / (g * eta)
	if t * g < 0.0:
		capacity = _capacity * absf(g) / eta
		t = wheel_solve.call(pred / g, reflect * eta, capacity)
		crank_load = t * eta / g
	return [t, pred - crank_load * _compliance, absf(t) < capacity, crank_load]


## `_solve_output` on a CVT, at the overall speed ratio `k = cvt_i / final_drive` rather than its
## inverse, so a ratio of 0 holds (spin 0, compliance 0, the relief: the park pawl's form) and never
## divides. The loss is the range's (`cvt_efficiency`), by direction as the stepped box's.
func _solve_cvt(wheel_solve: Callable, fuel: float) -> Array:
	var pred := _predict(fuel)
	var k := cvt_i / spec.final_drive
	var eta := maxf(cvt_efficiency(spec, absf(cvt_i), cvt_range), 0.05)
	var reflect := _compliance * k * k
	var capacity := cvt_axle_capacity(spec, _capacity, k, eta)
	var t: float = wheel_solve.call(pred * k, reflect / eta, capacity)
	var crank_load := t * k / eta
	if t * k < 0.0:
		capacity = cvt_axle_capacity(spec, _capacity, k, 1.0 / eta)
		t = wheel_solve.call(pred * k, reflect * eta, capacity)
		crank_load = t * k * eta
	return [t, pred - crank_load * _compliance, absf(t) < capacity, crank_load]


## The drive torque (N·m at the axle, signed with the gear) traction control may hold back across
## the driven wheels this tick: the coupling's capacity in drive (a converter's: its lock-up's plus
## what its law could pass against a held turbine), 0 in overrun or open. Each wheel's share bounds
## its hold (`RayWheel.tcs_spin`), so TC removes drive and never brakes.
func tcs_drive_torque() -> float:
	var bound := _capacity + _stall_bound
	if not _drives or bound <= 0.0:
		return 0.0
	if is_cvt(spec):
		# Signed with the ratio, which a shuttle carries through 0 against the byte's direction.
		var eta := maxf(cvt_efficiency(spec, absf(cvt_i), cvt_range), 0.05)
		var dir := signf(cvt_i) if cvt_i != 0.0 else drive_sign(gear_byte)
		return cvt_axle_capacity(spec, bound, cvt_i / spec.final_drive, eta) * dir
	return bound * ratio_for_byte(spec, gear_byte) * maxf(spec.efficiency, 0.05)

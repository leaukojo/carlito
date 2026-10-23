class_name ShiftPolicy
extends RefCounted
## The automatic gearbox's shift policy, as pure statics beside `TorqueConverter` and `HillHold`:
## which D byte the box takes next (`next_gear`, through `Drivetrain.auto_shift`). Its state (the
## time in gear, the last pedal, the kickdown's arm) is the gearbox's, on `Drivetrain`. Sources and
## figures: docs/drivetrain.md, "The shift policy" and "The load".
##
## It reads the PEDAL (the driver's demand: on an all-speed governor the higher of the pedal and
## the hand throttle, `PedalMap.demand`) and the road speed's rpm in the engaged gear, never
## `applied_throttle` (the limiter, governor and shift cut would read as lifts) and never the wheels'
## spin (wheelspin would fake rpm). With no road-load estimate (NAN) none of the load rules act.

## Pedal at and under which the light pair applies (the Malibu map's ~20 % line).
const LIGHT_PEDAL := 0.2
## On an all-speed governor a part demand upshifts once the road speed's rpm reaches this many droops
## under the setting (`governed_up_rpm`): the line's full-fuel end, less a droop's width again for
## the drive tyres' slip on a pull, which the road speed reads and the crank does not, so a loaded
## pull still reaches it (an estimate; no governed shift schedule is sourced: docs/sources.md
## § Governor). The map's own point can sit over a part demand's setting, where the box would never
## leave its start gear.
const GOVERNED_UPSHIFT_DROOP := 2.0
## An upshift lands at least this far over the downshift point at the same pedal.
const LANDING_MARGIN := 1.1
## A kickdown lands at or under this share of the redline (EPA ALPHA's default ceiling).
const KICKDOWN_CEILING := 0.85
## A kickdown's gear must hold this long at full pedal before its forced upshift, or it hunts.
const KICKDOWN_HOLD_S := 1.0
## An upshift needs this much drive over the road load in the gear it lands in (EPA ALPHA).
const TORQUE_RESERVE := 1.1
## A start gear's launch drive must beat the standing load by this factor (an estimate).
const START_RESERVE := 2.0
## A start gear's clutch must lock within this many seconds of a floored launch (`launch_slip_s`):
## Eaton's example reference (US 6,953,410: 0.25-5 s acceptable), the rig's mass and grade in it.
const START_SLIP_S := 1.5
## A launch that has not moved steps down to a ratio at least this much deeper (an estimate: about
## a six-speed powershift's 1.33-1.35 step), whatever the box's own step (`start_step_down`).
const START_STEP := 1.3
## Seconds the road-load estimate is filtered over, so a handover or bump never reads as a grade.
const LOAD_FILTER_S := 1.0
## The road load reads as a grade past the flat road's by this grade's pull (an estimate).
const GRADE_LOGIC := 0.02


## The upshift rpm the map gives at this pedal, before the landing floor (`upshift_rpm`). On an
## all-speed governor (`PedalMap.Kind.ALL_SPEED`) the demand caps the engine at its setting, so a
## part demand's point is held under it (`governed_up_rpm`).
static func up_rpm(spec: VehicleSpec, pedal: float) -> float:
	var light := spec.shift_up_light_rpm if spec.shift_up_light_rpm > 0.0 else spec.shift_up_rpm
	var up := _blend(light, spec.shift_up_rpm, pedal)
	if spec.pedal_map == PedalMap.Kind.ALL_SPEED:
		up = minf(up, governed_up_rpm(spec, pedal))
	return up


## An all-speed governor's upshift cap at this demand: GOVERNED_UPSHIFT_DROOP droops under its
## setting (the droop floored as `PedalMap.governor_line` floors it).
static func governed_up_rpm(spec: VehicleSpec, pedal: float) -> float:
	return PedalMap.setting_rpm(spec, pedal) \
			/ (1.0 + GOVERNED_UPSHIFT_DROOP * maxf(spec.governor_droop, PedalMap.MIN_DROOP))


## The downshift rpm at this pedal: the coast downshift at pedal 0, `shift_down_rpm` at pedal 1.
## The map's on every spec, an all-speed governor's too, as a box that shifts on engine speed keeps
## its points: a governed setting under the landing floor (`upshift_rpm`) holds its gear, and one
## under the coast line steps down to a crawl in D1 (`forced_gear`).
static func down_rpm(spec: VehicleSpec, pedal: float) -> float:
	var light := spec.shift_down_light_rpm if spec.shift_down_light_rpm > 0.0 \
			else spec.shift_down_rpm
	return _blend(light, spec.shift_down_rpm, pedal)


## The rpm in `byte` at which the box upshifts to `byte + 1` at this pedal: the map's, raised until
## the landing sits LANDING_MARGIN over `down_rpm` at the same pedal, never past `shift_up_rpm`. On
## the last ratio, with no step to land, the map's own point.
static func upshift_rpm(spec: VehicleSpec, byte: int, pedal: float) -> float:
	var up := minf(spec.shift_up_rpm, up_rpm(spec, pedal))
	if byte >= spec.gear_ratios.size():
		return up
	var step := _ratio(spec, byte) / _ratio(spec, byte + 1)
	return minf(spec.shift_up_rpm, maxf(up, LANDING_MARGIN * down_rpm(spec, pedal) * step))


## The gear an upshift from `byte` at `at_rpm` takes: `byte + 1`, or with `skip_shifts` the gear a
## sequential box would ripple to in one shift (it keeps stepping while the next landing is still at
## or past that gear's own upshift point). At full pedal a landing sits under `shift_up_rpm` unless
## the crank is over-revved a step past it, so a full pedal's skip is `forced_upshift`'s. Never past
## the last real ratio or the bus's TOP_GEAR.
static func upshift_target(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float) -> int:
	var top := _top(spec)
	var g := byte + 1
	if spec.skip_shifts:
		while g < top and at_rpm * _ratio(spec, g) / _ratio(spec, byte) \
				>= upshift_rpm(spec, g, pedal):
			g += 1
	return mini(g, top)


## The gear a forced upshift (at `shift_up_rpm`) from `byte` takes: `upshift_target`, then with
## `skip_shifts` and a road-load estimate on up while the gear it reached would not hold
## `shift_dwell_s` at full pedal (`time_to_upshift`, on the rig's mass and grip), as an AMT's or a
## powershift's skip-shift lets a floored, lightly loaded rig pass the gears it would rip through.
## The next gear must land at or over LANDING_MARGIN times `shift_down_rpm` and hold the road load
## at full pedal (`holds_grade`).
## A heavier rig holds more of its gears and steps singly through them; a gear that cannot gain
## speed reads INF and stops the walk.
static func forced_upshift(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float, road: float,
		mass: float, grip := INF) -> int:
	var g := upshift_target(spec, byte, at_rpm, pedal)
	if not spec.skip_shifts or is_nan(road) or mass <= 0.0:
		return g
	var top := _top(spec)
	var floor_rpm := LANDING_MARGIN * spec.shift_down_rpm
	while g < top:
		var landing := at_rpm * _ratio(spec, g) / _ratio(spec, byte)
		if time_to_upshift(spec, g, landing, road, mass, grip) >= spec.shift_dwell_s:
			break
		var next_landing := at_rpm * _ratio(spec, g + 1) / _ratio(spec, byte)
		if next_landing < floor_rpm or not holds_grade(spec, byte, g + 1, at_rpm, 1.0, road):
			break
		g += 1
	return g


## The highest rpm a kickdown may land at: KICKDOWN_CEILING of the redline (EPA ALPHA), under
## `shift_up_rpm`. With `held` the gear's hold on the road load (`time_to_upshift` against
## KICKDOWN_HOLD_S) keeps a kickdown off its forced upshift; with no estimate to judge it, the
## landing stays LANDING_MARGIN under `shift_up_rpm` instead.
static func kickdown_ceiling_rpm(spec: VehicleSpec, held := false) -> float:
	var margin := 1.0 if held else LANDING_MARGIN
	return minf(KICKDOWN_CEILING * spec.redline_rpm, spec.shift_up_rpm / margin)


## Seconds a floored body holds `g` from a shift landing at `landing` rpm to `shift_up_rpm`: the
## shift's own dead time (`shift_dead_s`), then a constant net drive at the landing (reads short),
## never more than the driven tyres' `grip` (N) puts down. INF when it would not gain speed, or with
## no estimate.
static func time_to_upshift(spec: VehicleSpec, g: int, landing: float, road: float,
		mass: float, grip := INF) -> float:
	var gd := spec.ground_drive
	if is_nan(road) or mass <= 0.0 or gd == null or gd.drive_radius() <= 0.0:
		return INF
	var r := gd.drive_radius()
	var ratio := absf(Drivetrain.ratio_for_byte(spec, g))
	if ratio <= 0.0:
		return INF
	var accel := _floored_accel(spec, g, landing, road, mass, grip, true)
	if accel <= 0.0:
		return INF
	var rpm_rate := accel / r * ratio * 60.0 / TAU
	return shift_dead_s(spec) + maxf(spec.shift_up_rpm - landing, 0.0) / rpm_rate


## Seconds a shift spends with no drive, as the box estimates it: an AMT's cut and half its torque
## ramp back (an estimate: the ramp rises linearly); 0 on a seamless box (no `shift_cut_s`).
static func shift_dead_s(spec: VehicleSpec) -> float:
	if spec.shift_cut_s <= 0.0:
		return 0.0
	return spec.shift_cut_s + 0.5 * spec.shift_torque_ramp_s


## The rig's acceleration (m/s²) floored in `g` at `at_rpm` against `road` (N·m at the axle), on
## `mass` (kg): the drive less the road load over the mass, never past what the driven tyres' `grip`
## (N) puts down. With `crank` the crank turns with the wheels and its reflected inertia takes its
## share of the drive; without, the crank is held on a slipping coupling's line and takes none.
## Grip-bound, the crank's surplus over the tyres feeds its own inertia, so the rig takes the grip.
static func _floored_accel(spec: VehicleSpec, g: int, at_rpm: float, road: float, mass: float,
		grip: float, crank: bool) -> float:
	var r := spec.ground_drive.drive_radius()
	var ratio := absf(Drivetrain.ratio_for_byte(spec, g))
	var reflected := spec.engine_inertia * ratio * ratio / (r * r) if crank else 0.0
	var engine := (drive_at(spec, g, at_rpm, 1.0) - road) / r / (mass + reflected)
	return minf(engine, (grip * r - road) / r / mass)


## Seconds a floored launch in `g` slips its coupling: until the rig reaches the road speed at which
## the launch line (`Drivetrain.launch_target_rpm` at full pedal) turns `g`, at the drive the line
## makes (the crank held there, its inertia out of it), plus half a powershift's engagement ramp
## (`launch_engage_s`, an estimate as `shift_dead_s`). Eaton's acceleration slip time (US
## 6,953,410). INF when the rig would not move, or with no estimate.
static func launch_slip_s(spec: VehicleSpec, g: int, road: float, mass: float,
		grip := INF) -> float:
	var gd := spec.ground_drive
	if is_nan(road) or mass <= 0.0 or gd == null or gd.drive_radius() <= 0.0:
		return INF
	var ratio := absf(Drivetrain.ratio_for_byte(spec, g))
	var line := Drivetrain.launch_target_rpm(spec, 1.0)
	var accel := _floored_accel(spec, g, line, road, mass, grip, false)
	if accel <= 0.0 or ratio <= 0.0:
		return INF
	var lock_speed := line * TAU / 60.0 / ratio * gd.drive_radius()
	return 0.5 * spec.launch_engage_s + lock_speed / accel


## A kickdown's gear, in one shift: the lowest under `kickdown_ceiling_rpm` that a floored body
## holds KICKDOWN_HOLD_S. `byte` itself when no lower gear does.
static func kickdown_target(spec: VehicleSpec, byte: int, at_rpm: float, road := NAN,
		mass := 0.0, grip := INF) -> int:
	if spec.gear_ratios.is_empty():
		return byte
	var ceiling := kickdown_ceiling_rpm(spec, not is_nan(road) and mass > 0.0)
	for g in range(1, byte):
		var landing := at_rpm * _ratio(spec, g) / _ratio(spec, byte)
		if landing <= ceiling \
				and time_to_upshift(spec, g, landing, road, mass, grip) >= KICKDOWN_HOLD_S:
			return g
	return byte


## Whether a kickdown is armed: an edge on `kickdown_pedal`, not a level, or a floored pedal would
## kick back down after every upshift. Off at 0.
static func kickdown_armed(spec: VehicleSpec, armed: bool, pedal: float, last_pedal: float) -> bool:
	var point := spec.kickdown_pedal
	if point <= 0.0 or pedal < point:
		return false
	return armed or last_pedal < point


## The minimum time in gear (`shift_dwell_s`) is still running.
static func dwelling(spec: VehicleSpec, gear_s: float) -> bool:
	return gear_s < spec.shift_dwell_s


## The gear the hard limits force from `byte`, which no dwell holds: an upshift at `shift_up_rpm`
## (`forced_upshift`, on the road load and the rig's mass), a downshift at the coast line
## (`forced_downshift`, to `floor_gear`), else `byte`.
static func forced_gear(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float,
		floor_gear := 1, road := NAN, mass := 0.0, grip := INF) -> int:
	if byte < _top(spec) and at_rpm >= spec.shift_up_rpm:
		return forced_upshift(spec, byte, at_rpm, pedal, road, mass, grip)
	if byte > floor_gear and at_rpm <= down_rpm(spec, 0.0):
		return forced_downshift(spec, byte, at_rpm, floor_gear)
	return byte


## The gear a downshift at the coast line from `byte` takes: `byte - 1`, or with `skip_shifts` the
## highest lower gear that lands over the coast line, in one shift (a lugged crank on a close-ratio
## box would otherwise walk down a gear a tick, a handover each). Never under `floor_gear`.
static func forced_downshift(spec: VehicleSpec, byte: int, at_rpm: float, floor_gear := 1) -> int:
	var g := byte - 1
	if spec.skip_shifts:
		var coast := down_rpm(spec, 0.0)
		while g > floor_gear and at_rpm * _ratio(spec, g) / _ratio(spec, byte) <= coast:
			g -= 1
	return maxi(g, floor_gear)


## An armed kickdown is spent once `next_gear` reached it, whether or not a lower gear fitted.
static func kickdown_spent(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float,
		gear_s: float, floor_gear := 1) -> bool:
	return not dwelling(spec, gear_s) and forced_gear(spec, byte, at_rpm, pedal, floor_gear) == byte


## Drive (N·m at the axle, + = forward) `byte` makes at `at_rpm` on the pedal's fuel
## (`PedalMap.fuel`).
static func drive_at(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float) -> float:
	var eta := maxf(spec.efficiency, 0.05)
	var t := Drivetrain.crank_torque(spec, at_rpm, PedalMap.fuel(spec, pedal, at_rpm))
	return t * absf(Drivetrain.ratio_for_byte(spec, byte)) * (eta if t >= 0.0 else 1.0 / eta)


## An upshift to `target` keeps the road speed (beats `road` by TORQUE_RESERVE at its landing).
## True on a lifted pedal: a lift upshift is the driver letting the speed go.
static func holds_grade(spec: VehicleSpec, byte: int, target: int, at_rpm: float, pedal: float,
		road: float) -> bool:
	if is_nan(road) or road <= 0.0 or pedal <= 0.0:
		return true
	var landing := maxf(at_rpm * _ratio(spec, target) / _ratio(spec, byte), spec.idle_rpm)
	return drive_at(spec, target, landing, pedal) >= TORQUE_RESERVE * road


## The crank lugs in `byte`: at or under the pedal's downshift point with less drive than the road
## load. The dwell never holds it there.
static func lugging(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float, road: float,
		floor_gear := 1) -> bool:
	return byte > floor_gear and not is_nan(road) and road > 0.0 \
			and at_rpm <= down_rpm(spec, pedal) and drive_at(spec, byte, at_rpm, pedal) < road


## A descent (the road load pulls the body along) under the foot brake: the box takes no map upshift
## and steps down for engine braking (`next_gear`).
static func descending(road: float, braking: bool) -> bool:
	return braking and not is_nan(road) and road < 0.0


## The gear a pull-away takes: the highest up to `start_gear_max` whose launch drive on `pedal`'s
## fuel beats `road` (`standing_load` at rest) by START_RESERVE, the grade's floor, and which, with
## the rig's `mass` (kg) and the driven tyres' `grip` (N), a floored launch locks within
## START_SLIP_S (`launch_slip_s`: the box's picture of the rig, at full pedal whatever the driver's,
## as an AMT picks from gross weight and grade). D1 when none does; no slip test with no mass.
static func start_gear(spec: VehicleSpec, road: float, pedal := 1.0, mass := 0.0,
		grip := INF) -> int:
	var line := Drivetrain.launch_target_rpm(spec, pedal)
	for g in range(mini(spec.start_gear_max, _top(spec)), 1, -1):
		if Drivetrain.wheel_torque(spec, line, PedalMap.fuel(spec, pedal, line), g) \
				< START_RESERVE * road:
			continue
		if mass <= 0.0 or launch_slip_s(spec, g, road, mass, grip) <= START_SLIP_S:
			return g
	return 1


## The start gear a launch that has not moved steps down to from `byte`: the highest lower gear
## whose ratio is at least START_STEP times `byte`'s, else D1. By ratio, not index, so a step covers
## the same ratio whatever the box's own step.
static func start_step_down(spec: VehicleSpec, byte: int) -> int:
	var need := START_STEP * _ratio(spec, byte)
	for g in range(byte - 1, 1, -1):
		if _ratio(spec, g) >= need:
			return g
	return 1


## The load a body standing on a grade puts against D (N·m at the axle): gravity's pull plus `crr`
## (tyres and soil) on the weight the contact plane carries.
static func standing_load(gravity: Vector3, normal: Vector3, forward: Vector3, crr: float,
		mass_lever: float) -> float:
	return -HillHold.pull_torque(gravity, normal, forward, mass_lever) \
			+ maxf(crr, 0.0) * absf(gravity.dot(normal)) * mass_lever


## The road load a body declares on the flat at `speed` (N·m at the axle): aero drag plus rolling
## resistance `crr` (the fitted tyre's, `WheelDrive.rolling_resistance`), the reference `on_grade`
## weighs against. 0 with no ground drive.
static func flat_load(spec: VehicleSpec, speed: float, mass: float, crr: float) -> float:
	var gd := spec.ground_drive
	if gd == null:
		return 0.0
	return (VehicleMath.aero_drag(absf(speed), gd.drag_area)
			+ maxf(crr, 0.0) * mass * BrakeSizing.G) * gd.drive_radius()


## Grade logic: `road` sits past the flat road's by more than GRADE_LOGIC of the rig's weight (a
## climb, soft ground or a heavy draft). False with no estimate.
static func on_grade(spec: VehicleSpec, road: float, speed: float, mass: float,
		crr: float) -> bool:
	if is_nan(road) or spec.ground_drive == null:
		return false
	return road > flat_load(spec, speed, mass, crr) \
			+ GRADE_LOGIC * mass * BrakeSizing.G * spec.ground_drive.drive_radius()


## One tick of the road-load estimate (N·m at the axle, + = resisting): the coupling's drive less
## what accelerated the rig, filtered over LOAD_FILTER_S. A NAN `prev` starts at this reading.
static func road_load_step(prev: float, axle_t: float, mass: float, accel: float, radius: float,
		delta: float) -> float:
	var raw := axle_t - mass * accel * radius
	if is_nan(prev):
		return raw
	return lerpf(prev, raw, 1.0 - exp(-delta / LOAD_FILTER_S))


## The D byte the box takes from `byte` this tick. `at_rpm` is the road speed's rpm in `byte`;
## `gear_s` the time in gear; `road` the road-load estimate (NAN for none); `floor_gear` the lowest
## a downshift takes; `mass` and `grip` the rig's (kg, and N the driven tyres put down). Priority:
## hard limits, lugging, then (after the dwell) kickdown, the map's upshift, an engine-braking step
## on a braked descent, the map's downshift.
static func next_gear(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float, gear_s: float,
		kickdown: bool, road := NAN, floor_gear := 1, braking := false, grade := true,
		mass := 0.0, grip := INF) -> int:
	var top := _top(spec)
	var forced := forced_gear(spec, byte, at_rpm, pedal, floor_gear, road, mass, grip)
	if forced != byte:
		return forced
	if dwelling(spec, gear_s):
		return byte - 1 if lugging(spec, byte, at_rpm, pedal, road, floor_gear) else byte
	if kickdown:
		var k := maxi(kickdown_target(spec, byte, at_rpm, road, mass, grip), floor_gear)
		if k < byte:
			return k
	var descent := descending(road, braking)
	if byte < top and at_rpm >= upshift_rpm(spec, byte, pedal) and not descent:
		var g := upshift_target(spec, byte, at_rpm, pedal)
		while g > byte and grade and not holds_grade(spec, byte, g, at_rpm, pedal, road):
			g -= 1
		if g > byte:
			return g
	if descent and byte > floor_gear and at_rpm * _ratio(spec, byte - 1) / _ratio(spec, byte) \
			< upshift_rpm(spec, byte - 1, 0.0):
		return byte - 1
	if byte > floor_gear and at_rpm <= down_rpm(spec, pedal):
		return byte - 1
	return byte


## The tallest D byte the box may take: its last real ratio, within the bus's TOP_GEAR.
static func _top(spec: VehicleSpec) -> int:
	return mini(Drivetrain.TOP_GEAR, spec.gear_ratios.size())


## `byte`'s gearbox ratio (a byte past a short box reads its last ratio, as `ratio_for_byte`).
static func _ratio(spec: VehicleSpec, byte: int) -> float:
	return spec.gear_ratios[clampi(byte, 1, spec.gear_ratios.size()) - 1]


## `light` at and under LIGHT_PEDAL, `full` at pedal 1, linear between; exactly `full` at 1.
static func _blend(light: float, full: float, pedal: float) -> float:
	var t := clampf((pedal - LIGHT_PEDAL) / (1.0 - LIGHT_PEDAL), 0.0, 1.0)
	if t >= 1.0:
		return full
	return lerpf(light, full, t)

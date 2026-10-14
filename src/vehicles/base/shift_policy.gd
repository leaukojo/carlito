class_name ShiftPolicy
extends RefCounted
## The automatic gearbox's shift policy, as pure statics beside `TorqueConverter` and `HillHold`:
## which D byte the box takes next (`next_gear`, through `Drivetrain.auto_shift`). Its state (the
## time in gear, the last pedal, the kickdown's arm) is the gearbox's, on `Drivetrain`.
##
## It reads the PEDAL and the road speed's rpm in the engaged gear, never `applied_throttle` (the
## limiter, governor and shift cut would read as lifts) and never the wheels' spin (wheelspin would
## fake rpm). The map blends from a light pair (`shift_up_light_rpm`, `shift_down_light_rpm`) at and
## under LIGHT_PEDAL to the full pair (`shift_up_rpm`, `shift_down_rpm`, where the launches are
## tuned) at pedal 1. Each upshift point is raised, step by step, until its landing sits
## LANDING_MARGIN over the downshift point at the same pedal, so no gearing hunts. A spec that
## declares no light pair, kickdown, dwell or skip-shifts shifts at its two fixed thresholds.
##
## Where the gearbox keeps a road-load estimate (`Drivetrain.road_load`: the torque the coupling
## passed less the rig's mass times its measured acceleration) the map reads it too: on a grade
## (`on_grade`, a TCU's grade logic) no map upshift whose landing cannot hold the road speed at this
## pedal (`holds_grade`), a lugging crank
## downshifts through the dwell (`lugging`), and on a descent under the brake the box holds or steps
## down for engine braking. A body may pull away above D1 (`start_gear`). With no estimate (NAN)
## none of these act.

## Pedal at and under which the light pair applies: the lowest line of the one measured converter
## map found, a 2013 Malibu's 6T40 at ~20 % pedal (EPA, SAE 2015-01-1142, Fig. 11). The map is
## linear from here to the full pair at pedal 1 (an estimate; its ~40 % line sits about there).
const LIGHT_PEDAL := 0.2
## An upshift lands at least this far over the downshift point at the same pedal: the Malibu's light
## upshifts land 1.07-1.12x over the next coast downshift (SAE 2015-01-1142), and the launch trace's
## landing gate reads the same figure.
const LANDING_MARGIN := 1.1
## A kickdown lands at or under this share of the redline: EPA ALPHA's default downshift ceiling
## without vehicle data, 85 % of the lower gear's maximum speed (SAE 2015-01-1142). Capped by
## `kickdown_ceiling_rpm`.
const KICKDOWN_CEILING := 0.85
## A kickdown's gear must hold this long at full pedal before its forced upshift: EPA ALPHA's minimum
## time in gear after a downshift on a six-speed, 1.0 s (SAE 2015-01-1142; the Malibu's shortest
## measured stay after a downshift, ~1.0 s). A gear the floored body revs out of sooner makes a
## down-up pair, the hunt the launch trace's gate reads.
const KICKDOWN_HOLD_S := 1.0
## An upshift needs this much drive over the road load in the gear it lands in, at the landing's
## speed and this pedal: EPA ALPHA's torque reserve (SAE 2015-01-1142, a ratio of 1.1).
const TORQUE_RESERVE := 1.1
## A start gear's launch drive must beat the standing load (grade, rolling and soil) by this factor,
## the share left to accelerate the rig. An estimate: the I-Shift picks its start gear from gross
## weight and gradient (Volvo, "I-Shift drive modes", 2024) and publishes no margin.
const START_RESERVE := 2.0
## Seconds the road-load estimate is filtered over: a TCU's estimate is read over a window, never
## per tick (a shift's handover or a bump would read as a grade). An estimate.
const LOAD_FILTER_S := 1.0
## Grade logic: the road load reads as a grade once it passes the flat road's (`flat_load`) by this
## grade's pull on the rig (a share of its weight). Under it a light upshift lands and the driver's
## pedal makes up the step, as on any flat road; over it the box holds a gear whose next cannot hold
## the speed at this pedal, the hunt a fixed pedal on a climb otherwise starts. An estimate (2 %).
const GRADE_LOGIC := 0.02


## The upshift rpm the map gives at this pedal, before the landing floor (`upshift_rpm`).
static func up_rpm(spec: VehicleSpec, pedal: float) -> float:
	var light := spec.shift_up_light_rpm if spec.shift_up_light_rpm > 0.0 else spec.shift_up_rpm
	return _blend(light, spec.shift_up_rpm, pedal)


## The downshift rpm at this pedal: the coast downshift at pedal 0, `shift_down_rpm` at pedal 1.
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
## or past that gear's own upshift point). A landing sits under `shift_up_rpm`, so a full pedal never
## skips. Never past the last real ratio or the bus's TOP_GEAR.
static func upshift_target(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float) -> int:
	var top := _top(spec)
	var g := byte + 1
	if spec.skip_shifts:
		while g < top and at_rpm * _ratio(spec, g) / _ratio(spec, byte) \
				>= upshift_rpm(spec, g, pedal):
			g += 1
	return mini(g, top)


## The highest rpm a kickdown may land at: KICKDOWN_CEILING of the redline (EPA's share of the
## gear's maximum speed), never within LANDING_MARGIN of `shift_up_rpm`, the hysteresis every
## upshift keeps over the downshift point, so a floored kickdown does not land on its forced upshift.
## The cap binds on every shipped box, and lets a kickdown reach the rpm where the engine makes its
## power: the vans' rated 3000 rpm under their 3300 upshift, the Kenney trucks' 2400 under 2600.
static func kickdown_ceiling_rpm(spec: VehicleSpec) -> float:
	return minf(KICKDOWN_CEILING * spec.redline_rpm, spec.shift_up_rpm / LANDING_MARGIN)


## Seconds a floored body in `g` takes from `landing` rpm to `shift_up_rpm`: the drive the gear makes
## there less `road` (N·m at the axle), on `mass` plus the crank's inertia through the gear, held
## constant (the curve is near its peak there, and the drag only grows, so it reads short). INF when
## the body would not gain speed, or with no estimate (`road` NAN, no mass, no ground drive).
static func time_to_upshift(spec: VehicleSpec, g: int, landing: float, road: float,
		mass: float) -> float:
	var gd := spec.ground_drive
	if is_nan(road) or mass <= 0.0 or gd == null or gd.wheel_radius <= 0.0:
		return INF
	var r := gd.wheel_radius
	var ratio := absf(Drivetrain.ratio_for_byte(spec, g))
	var net := drive_at(spec, g, landing, 1.0) - road
	if net <= 0.0 or ratio <= 0.0:
		return INF
	var accel := net / r / (mass + spec.engine_inertia * ratio * ratio / (r * r))
	var rpm_rate := accel / r * ratio * 60.0 / TAU
	return maxf(spec.shift_up_rpm - landing, 0.0) / rpm_rate


## A kickdown's gear: the lowest whose rpm at this road speed sits at or under
## `kickdown_ceiling_rpm` and which a floored body holds KICKDOWN_HOLD_S before its forced upshift
## (`time_to_upshift` on the road load `road` and the rig's `mass`; the ceiling alone with no
## estimate), in one shift. `byte` itself when no lower gear does.
static func kickdown_target(spec: VehicleSpec, byte: int, at_rpm: float, road := NAN,
		mass := 0.0) -> int:
	if spec.gear_ratios.is_empty():
		return byte
	var ceiling := kickdown_ceiling_rpm(spec)
	for g in range(1, byte):
		var landing := at_rpm * _ratio(spec, g) / _ratio(spec, byte)
		if landing <= ceiling and time_to_upshift(spec, g, landing, road, mass) >= KICKDOWN_HOLD_S:
			return g
	return byte


## Whether a kickdown is armed this tick: the pedal crossed `kickdown_pedal` upward (a stab, or a
## key press), or it was armed and the pedal is still past the point. A held pedal never re-arms
## (a level trigger would kick back down after every upshift at full pedal). Off at 0.
static func kickdown_armed(spec: VehicleSpec, armed: bool, pedal: float, last_pedal: float) -> bool:
	var point := spec.kickdown_pedal
	if point <= 0.0 or pedal < point:
		return false
	return armed or last_pedal < point


## The minimum time in gear is still running (`shift_dwell_s`): the pedal-dependent part of the map
## and a kickdown wait.
static func dwelling(spec: VehicleSpec, gear_s: float) -> bool:
	return gear_s < spec.shift_dwell_s


## The gear the hard limits force from `byte`, which no dwell holds, or `byte` itself: an upshift at
## `shift_up_rpm` (a floored launch upshifts at its full-pedal point) and a downshift at the coast
## line (a stop still steps down, to `floor_gear`: the start gear while a pull-away slips, else D1).
static func forced_gear(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float,
		floor_gear := 1) -> int:
	if byte < _top(spec) and at_rpm >= spec.shift_up_rpm:
		return upshift_target(spec, byte, at_rpm, pedal)
	if byte > floor_gear and at_rpm <= down_rpm(spec, 0.0):
		return byte - 1
	return byte


## An armed kickdown is spent this tick: `next_gear` reached it (no hard limit forced a shift first,
## and the dwell had run), whether or not a lower gear fitted. Otherwise it stays armed.
static func kickdown_spent(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float,
		gear_s: float, floor_gear := 1) -> bool:
	return not dwelling(spec, gear_s) and forced_gear(spec, byte, at_rpm, pedal, floor_gear) == byte


## Drive (N·m at the axle, + = forward) `byte` makes at `at_rpm` on the pedal's fuel: the engine's
## net torque there (`Drivetrain.crank_torque`, motoring past a lift) through the ratio and the
## driveline loss by direction. What the load rules weigh against `road_load`.
static func drive_at(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float) -> float:
	var eta := maxf(spec.efficiency, 0.05)
	var t := Drivetrain.crank_torque(spec, at_rpm, pedal)
	return t * absf(Drivetrain.ratio_for_byte(spec, byte)) * (eta if t >= 0.0 else 1.0 / eta)


## An upshift from `byte` at `at_rpm` to `target` keeps the road speed: the drive `target` makes at
## its landing on this pedal beats `road` (N·m at the axle) by TORQUE_RESERVE. True with no estimate
## (NAN), on a load that pulls the body along, and on a lifted pedal: a lift upshift is the driver
## letting the speed go, never held.
static func holds_grade(spec: VehicleSpec, byte: int, target: int, at_rpm: float, pedal: float,
		road: float) -> bool:
	if is_nan(road) or road <= 0.0 or pedal <= 0.0:
		return true
	var landing := maxf(at_rpm * _ratio(spec, target) / _ratio(spec, byte), spec.idle_rpm)
	return drive_at(spec, target, landing, pedal) >= TORQUE_RESERVE * road


## The crank lugs in `byte`: at or under the pedal's downshift point with less drive than the road
## load, so the body is losing speed in a gear it cannot hold. The dwell never holds it there. The
## map takes no upshift straight back: the landing floor puts the lower gear's upshift point past
## LANDING_MARGIN x this one, and on a grade the gear left cannot hold the same load (`holds_grade`).
static func lugging(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float, road: float,
		floor_gear := 1) -> bool:
	return byte > floor_gear and not is_nan(road) and road > 0.0 \
			and at_rpm <= down_rpm(spec, pedal) and drive_at(spec, byte, at_rpm, pedal) < road


## A descent (the road load pulls the body along) under the foot brake: the box takes no map upshift
## and steps down for engine braking (`next_gear`).
static func descending(road: float, braking: bool) -> bool:
	return braking and not is_nan(road) and road < 0.0


## The gear a pull-away takes (`spec.start_gear_max` above 1): the highest up to that cap whose
## launch drive at `pedal` (the curve at `Drivetrain.launch_target_rpm` on the pedal's fuel, through
## the gear) beats `road` (N·m at the axle: `standing_load` at rest) by START_RESERVE; D1 when none
## does. A powershift's start gear is a driver preset, higher empty and lower laden; this is the
## I-Shift's rule (its start gear from gross weight and gradient). Picked at full pedal while the body
## stands; the driver's own pedal may then take a lower one (`Drivetrain`), since the launch line
## and its fuel follow the pedal.
static func start_gear(spec: VehicleSpec, road: float, pedal := 1.0) -> int:
	var line := Drivetrain.launch_target_rpm(spec, pedal)
	for g in range(mini(spec.start_gear_max, _top(spec)), 1, -1):
		if Drivetrain.wheel_torque(spec, line, pedal, g) >= START_RESERVE * road:
			return g
	return 1


## The load a body standing on a grade puts against D (N·m at the axle): gravity's pull back down the
## slope (`HillHold.pull_torque`, off the contact plane of unit normal `normal`) plus `crr` (the
## tyres' rolling resistance and the soil's) on the weight the plane carries, times `mass_lever` (the
## rig's mass times the wheel radius).
static func standing_load(gravity: Vector3, normal: Vector3, forward: Vector3, crr: float,
		mass_lever: float) -> float:
	return -HillHold.pull_torque(gravity, normal, forward, mass_lever) \
			+ maxf(crr, 0.0) * absf(gravity.dot(normal)) * mass_lever


## The road load a body declares on the flat at `speed` (N·m at the axle): its drag area's aero drag
## plus its tyres' rolling resistance on `mass` (`GroundDriveSpec.drag_area`,
## `GroundDriveSpec.rolling_resistance`), the reference grade logic weighs `road_load` against, as a
## TCU's against its calibrated flat-road load. 0 with no ground drive.
static func flat_load(spec: VehicleSpec, speed: float, mass: float) -> float:
	var gd := spec.ground_drive
	if gd == null:
		return 0.0
	return (VehicleMath.aero_drag(absf(speed), gd.drag_area)
			+ maxf(gd.rolling_resistance, 0.0) * mass * BrakeSizing.G) * gd.wheel_radius


## Grade logic: the road load `road` (N·m at the axle) at `speed` on a rig of `mass` sits past the
## flat road's by more than GRADE_LOGIC of its weight. A climb, soft ground or a heavy draft all
## read as one. False with no estimate.
static func on_grade(spec: VehicleSpec, road: float, speed: float, mass: float) -> bool:
	if is_nan(road) or spec.ground_drive == null:
		return false
	return road > flat_load(spec, speed, mass) \
			+ GRADE_LOGIC * mass * BrakeSizing.G * spec.ground_drive.wheel_radius


## One tick of the road-load estimate (N·m at the axle, + = resisting forward motion): the drive the
## coupling passed (`axle_t`) less what accelerated the rig (`mass` kg at `accel` m/s², through
## `radius`), filtered over LOAD_FILTER_S. A TCU's road-load estimate, on the sim's own mass. A NAN
## `prev` starts it at this tick's reading.
static func road_load_step(prev: float, axle_t: float, mass: float, accel: float, radius: float,
		delta: float) -> float:
	var raw := axle_t - mass * accel * radius
	if is_nan(prev):
		return raw
	return lerpf(prev, raw, 1.0 - exp(-delta / LOAD_FILTER_S))


## The D byte the box takes from `byte` this tick. `at_rpm` is the road speed's rpm in `byte`,
## clamped [idle, redline] (`Drivetrain.rpm_from_wheel`); `gear_s` the time since the last byte
## change; `kickdown` whether one is armed (`kickdown_armed`); `road` the road-load estimate (N·m at
## the axle, NAN for none); `floor_gear` the lowest a downshift takes (the start gear while a
## pull-away slips); `braking` the foot brake; `grade` whether that load reads as a grade
## (`on_grade`); `mass` the rig's (kg, 0 for none: `kickdown_target`). The gear's hard limits come first (`forced_gear`), then a lugging crank's downshift,
## which the dwell does not hold. Then, once the dwell has run: a kickdown; the map's upshift, on a
## grade to the tallest gear whose landing holds it, and none on a braked descent; a step down for
## engine braking on a braked descent, where the lower gear lands under its lifted upshift point;
## the map's downshift, one gear.
static func next_gear(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float, gear_s: float,
		kickdown: bool, road := NAN, floor_gear := 1, braking := false, grade := true,
		mass := 0.0) -> int:
	var top := _top(spec)
	var forced := forced_gear(spec, byte, at_rpm, pedal, floor_gear)
	if forced != byte:
		return forced
	if dwelling(spec, gear_s):
		return byte - 1 if lugging(spec, byte, at_rpm, pedal, road, floor_gear) else byte
	if kickdown:
		var k := maxi(kickdown_target(spec, byte, at_rpm, road, mass), floor_gear)
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

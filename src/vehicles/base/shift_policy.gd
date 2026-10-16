class_name ShiftPolicy
extends RefCounted
## The automatic gearbox's shift policy, as pure statics beside `TorqueConverter` and `HillHold`:
## which D byte the box takes next (`next_gear`, through `Drivetrain.auto_shift`). Its state (the
## time in gear, the last pedal, the kickdown's arm) is the gearbox's, on `Drivetrain`. Sources and
## figures: docs/vehicles.md, "The shift policy" and "The load".
##
## It reads the PEDAL and the road speed's rpm in the engaged gear, never `applied_throttle` (the
## limiter, governor and shift cut would read as lifts) and never the wheels' spin (wheelspin would
## fake rpm). With no road-load estimate (NAN) none of the load rules act.

## Pedal at and under which the light pair applies (the Malibu map's ~20 % line).
const LIGHT_PEDAL := 0.2
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
## Seconds the road-load estimate is filtered over, so a handover or bump never reads as a grade.
const LOAD_FILTER_S := 1.0
## The road load reads as a grade past the flat road's by this grade's pull (an estimate).
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


## The highest rpm a kickdown may land at: KICKDOWN_CEILING of the redline, never within
## LANDING_MARGIN of `shift_up_rpm`, so a floored kickdown does not land on its forced upshift.
static func kickdown_ceiling_rpm(spec: VehicleSpec) -> float:
	return minf(KICKDOWN_CEILING * spec.redline_rpm, spec.shift_up_rpm / LANDING_MARGIN)


## Seconds a floored body in `g` takes from `landing` rpm to `shift_up_rpm`, at a constant net
## drive (reads short). INF when it would not gain speed, or with no estimate.
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


## A kickdown's gear, in one shift: the lowest under `kickdown_ceiling_rpm` that a floored body
## holds KICKDOWN_HOLD_S. `byte` itself when no lower gear does.
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


## The gear the hard limits force from `byte`, which no dwell holds: an upshift at `shift_up_rpm`,
## a downshift at the coast line (to `floor_gear`), else `byte`.
static func forced_gear(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float,
		floor_gear := 1) -> int:
	if byte < _top(spec) and at_rpm >= spec.shift_up_rpm:
		return upshift_target(spec, byte, at_rpm, pedal)
	if byte > floor_gear and at_rpm <= down_rpm(spec, 0.0):
		return byte - 1
	return byte


## An armed kickdown is spent once `next_gear` reached it, whether or not a lower gear fitted.
static func kickdown_spent(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float,
		gear_s: float, floor_gear := 1) -> bool:
	return not dwelling(spec, gear_s) and forced_gear(spec, byte, at_rpm, pedal, floor_gear) == byte


## Drive (N·m at the axle, + = forward) `byte` makes at `at_rpm` on the pedal's fuel.
static func drive_at(spec: VehicleSpec, byte: int, at_rpm: float, pedal: float) -> float:
	var eta := maxf(spec.efficiency, 0.05)
	var t := Drivetrain.crank_torque(spec, at_rpm, pedal)
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


## The gear a pull-away takes: the highest up to `start_gear_max` whose launch drive at `pedal`
## beats `road` (`standing_load` at rest) by START_RESERVE; D1 when none does.
static func start_gear(spec: VehicleSpec, road: float, pedal := 1.0) -> int:
	var line := Drivetrain.launch_target_rpm(spec, pedal)
	for g in range(mini(spec.start_gear_max, _top(spec)), 1, -1):
		if Drivetrain.wheel_torque(spec, line, pedal, g) >= START_RESERVE * road:
			return g
	return 1


## The load a body standing on a grade puts against D (N·m at the axle): gravity's pull plus `crr`
## (tyres and soil) on the weight the contact plane carries.
static func standing_load(gravity: Vector3, normal: Vector3, forward: Vector3, crr: float,
		mass_lever: float) -> float:
	return -HillHold.pull_torque(gravity, normal, forward, mass_lever) \
			+ maxf(crr, 0.0) * absf(gravity.dot(normal)) * mass_lever


## The road load a body declares on the flat at `speed` (N·m at the axle): aero drag plus rolling
## resistance, the reference `on_grade` weighs against. 0 with no ground drive.
static func flat_load(spec: VehicleSpec, speed: float, mass: float) -> float:
	var gd := spec.ground_drive
	if gd == null:
		return 0.0
	return (VehicleMath.aero_drag(absf(speed), gd.drag_area)
			+ maxf(gd.rolling_resistance, 0.0) * mass * BrakeSizing.G) * gd.wheel_radius


## Grade logic: `road` sits past the flat road's by more than GRADE_LOGIC of the rig's weight (a
## climb, soft ground or a heavy draft). False with no estimate.
static func on_grade(spec: VehicleSpec, road: float, speed: float, mass: float) -> bool:
	if is_nan(road) or spec.ground_drive == null:
		return false
	return road > flat_load(spec, speed, mass) \
			+ GRADE_LOGIC * mass * BrakeSizing.G * spec.ground_drive.wheel_radius


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
## a downshift takes. Priority: hard limits, lugging, then (after the dwell) kickdown, the map's
## upshift, an engine-braking step on a braked descent, the map's downshift.
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

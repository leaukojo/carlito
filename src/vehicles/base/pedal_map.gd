class_name PedalMap
extends RefCounted
## The pedal map: the one place the driver's pedal becomes the delivered fuel fraction on a
## wheel-driving crank (`VehicleSpec.pedal_map`; the rigid crank keeps the pedal). Every reading of
## "the drive at this pedal" goes through `fuel`, so the shift policy predicts what the crank makes.
## Sources and grades: docs/drivetrain.md § The pedal map.

## LINEAR: the fuel is the pedal (a road diesel's min-max governor, where the pedal moves the
## injection pump's control rod directly: Bosch, *Governors for In-Line Pumps*, 1975). PETROL: a
## torque-based engine management's request map (`PETROL_REQUEST`). ALL_SPEED: a tractor diesel's
## all-speed governor (the same source's variable-speed governor): the demand, the higher of the
## pedal and the hand throttle (`demand`), sets an engine speed, and the fuel holds it on a droop
## line (`governor_fuel`).
enum Kind { LINEAR, PETROL, ALL_SPEED }

## Pedal rows of PETROL_REQUEST. The pedal-0 row is fuel 0 by definition: the figure's 0 % line is
## the motoring line, and its 1 % line already sits at ~zero brake torque (the "discrete transition"
## the paper names).
const PETROL_PEDALS: Array[float] = [0.0, 0.01, 0.05, 0.10, 0.20, 0.30, 0.40, 0.50, 0.60,
		0.70, 0.80, 0.90, 1.0]
## Columns of PETROL_REQUEST: crank rpm over rated speed (peak power). The figure's 1000-5000 rpm
## over the L15B7's 6000 (Honda: 174 hp at 6000 rpm); held flat outside them.
const PETROL_RPM: Array[float] = [1000.0 / 6000.0, 1500.0 / 6000.0, 2000.0 / 6000.0,
		2500.0 / 6000.0, 3000.0 / 6000.0, 3500.0 / 6000.0, 4000.0 / 6000.0, 4500.0 / 6000.0,
		5000.0 / 6000.0]
## The driver's torque request as a share of the curve's peak, a row per PETROL_PEDALS entry past
## 0, row-major in PETROL_RPM's columns: US EPA's benchmark of a 2016 Honda L15B7 (1.5 L turbo),
## SAE 2018-01-1412 Fig. 2 (brake torque against pedal % and rpm), its contours read at 600 dpi over
## the figure's own 237 N·m peak (±3 N·m, a secondary-grade reading of a primary measurement).
## Where full load clips a contour, the first unclipped column's request is carried down to the
## clipped ones (1000 rpm on the 30 % and 40 % rows, 1000-1500 rpm on the 50-90 % rows), so the
## request stays flat in rpm there: any request at or past full load fuels 1 anyway, so the carry
## only keeps each column monotone. The last row asks for the peak, which no curve passes: full
## pedal fuels exactly 1.
const PETROL_REQUEST: Array[float] = [
	0.049, 0.025, 0.019, 0.018, 0.005, 0.013, 0.019, 0.002, -0.097,
	0.114, 0.093, 0.084, 0.080, 0.076, 0.069, 0.063, 0.054, -0.024,
	0.276, 0.281, 0.262, 0.228, 0.215, 0.207, 0.198, 0.176, 0.059,
	0.489, 0.536, 0.449, 0.435, 0.437, 0.426, 0.403, 0.418, 0.388,
	0.772, 0.772, 0.738, 0.677, 0.667, 0.654, 0.635, 0.616, 0.565,
	0.806, 0.806, 0.861, 0.797, 0.791, 0.776, 0.755, 0.743, 0.705,
	0.928, 0.928, 0.928, 0.876, 0.859, 0.838, 0.814, 0.806, 0.776,
	0.958, 0.958, 0.958, 0.903, 0.890, 0.869, 0.844, 0.835, 0.808,
	0.966, 0.966, 0.966, 0.924, 0.918, 0.890, 0.859, 0.859, 0.835,
	0.975, 0.975, 0.975, 0.941, 0.937, 0.909, 0.878, 0.878, 0.857,
	0.983, 0.983, 0.983, 0.960, 0.958, 0.928, 0.897, 0.899, 0.878,
	1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
]
## Bisection steps `pedal_for` takes across the pedal's travel.
const INVERSE_STEPS := 24
## Floor under `governor_droop` (a divisor): a declared 0 governs isochronously in all but name.
const MIN_DROOP := 0.001
## N·m within which the governor line reads as reaching the full-load curve: at full demand the line
## is the curve's own straight tail, which float arithmetic rounds a hair either side of.
const LINE_ON_CURVE_NM := 1e-3


## The delivered fuel (0..1) the pedal (0..1) asks for at `at_rpm`. LINEAR returns the pedal, as
## does any map on a body whose crank drives no wheels (`Drivetrain.drives_wheels`: the rigid crank
## keeps the pedal). PETROL solves each bracketing row's torque request for the fuel that makes it
## on the one engine law (`Drivetrain.crank_torque`: `f * curve + (1 - f) * motoring`), clamped to
## 0..1, and blends the two rows by pedal: 0 at pedal 0, 1 at pedal 1 at every rpm, monotone in
## pedal. Under full load the crank then delivers the measured request. ALL_SPEED, or any map while
## `governed` (a truck's PTO mode, `Drivetrain.pto_set_rpm`), reads `pedal` as the governor's demand
## (`governor_fuel`).
static func fuel(spec: VehicleSpec, pedal: float, at_rpm: float, governed := false) -> float:
	var p := clampf(pedal, 0.0, 1.0)
	if not Drivetrain.drives_wheels(spec):
		return p
	if spec.pedal_map == Kind.ALL_SPEED or governed:
		return governor_fuel(spec, p, at_rpm)
	if spec.pedal_map == Kind.LINEAR or p <= 0.0:
		return p
	if p >= 1.0:
		return 1.0
	var hi := 1
	while PETROL_PEDALS[hi] < p:
		hi += 1
	var x := at_rpm / maxf(rated_rpm(spec), 1.0)
	var f_hi := _row_fuel(spec, hi, x, at_rpm)
	var f_lo := 0.0 if hi == 1 else _row_fuel(spec, hi - 1, x, at_rpm)
	var lo_p := PETROL_PEDALS[hi - 1]
	return lerpf(f_lo, f_hi, (p - lo_p) / (PETROL_PEDALS[hi] - lo_p))


## The pedal (0..1) that delivers `target` fuel at `at_rpm`: `fuel`'s inverse, the least pedal
## reaching it (to 2^-INVERSE_STEPS), full fuel included, so it is continuous in the fuel: where
## full load clips the request a saturated command holds the pedal there, never steps it to 1. The
## fuel itself wherever `fuel` returns the pedal (LINEAR, or a crank that drives no wheels). A
## speed-holding driver that commands fuel through it keeps one loop gain on every map (the measure
## tools' PI pedals and `measure_rough`'s crawl).
static func pedal_for(spec: VehicleSpec, target: float, at_rpm: float) -> float:
	var u := clampf(target, 0.0, 1.0)
	if spec.pedal_map == Kind.LINEAR or u <= 0.0 or not Drivetrain.drives_wheels(spec):
		return u
	var lo := 0.0
	var hi := 1.0
	for i in INVERSE_STEPS:
		var mid := (lo + hi) * 0.5
		if fuel(spec, mid, at_rpm) >= u:
			hi = mid
		else:
			lo = mid
	return hi


## The driver's demand (0..1) the fuel and the shift policy read: on ALL_SPEED the higher of the foot
## pedal and the hand throttle (`Drivetrain.hand_throttle`), which both set the governor's engine
## speed; on any other map the pedal, so a hand throttle latched on another body never reaches it.
## A PTO mode's set speed (`pto_set_rpm` > 0, any map) raises it to that setting's demand: the pedal
## overrides it upward only (J1939 SPN 976's "accelerator override").
static func demand(spec: VehicleSpec, pedal: float, hand: float, pto_set_rpm := 0.0) -> float:
	var p := clampf(pedal, 0.0, 1.0)
	if pto_set_rpm > 0.0:
		p = maxf(p, demand_for_setting(spec, pto_set_rpm))
	if spec.pedal_map != Kind.ALL_SPEED:
		return p
	return maxf(p, clampf(hand, 0.0, 1.0))


## The all-speed governor's engine-speed setting (rpm) at `demand`: idle at 0, the high idle at 1,
## linear between. The high idle is the redline, where the curve's governed tail reaches 0.
static func setting_rpm(spec: VehicleSpec, p_demand: float) -> float:
	return lerpf(spec.idle_rpm, spec.redline_rpm, clampf(p_demand, 0.0, 1.0))


## The demand (0..1) whose setting is `at_rpm`: `setting_rpm`'s inverse (a hand-throttle preset).
static func demand_for_setting(spec: VehicleSpec, at_rpm: float) -> float:
	return clampf((at_rpm - spec.idle_rpm) / maxf(spec.redline_rpm - spec.idle_rpm, 1.0), 0.0, 1.0)


## The governor's line at `p_demand`: [the setting (rpm), the full-fuel speed `setting / (1 + droop)`
## (rpm), the line's slope (N·m of net crank torque per rpm, >= 0)]. The line runs from the curve at
## the full-fuel speed to no net torque at the setting.
static func governor_line(spec: VehicleSpec, p_demand: float) -> Vector3:
	var n_s := setting_rpm(spec, p_demand)
	var n_full := n_s / (1.0 + maxf(spec.governor_droop, MIN_DROOP))
	return Vector3(n_s, n_full, maxf(Drivetrain.engine_torque(spec, n_full), 0.0) / (n_s - n_full))


## The all-speed governor's fuel (0..1) at `p_demand` and `at_rpm`: the fuel whose net torque on the
## one engine law is the line's (`governor_line`), 1 at or under the full-fuel speed and wherever the
## line reaches the full-load curve (at full demand the line is the curve's own tail, so a floored
## crank's fuel is the full curve's). Past the setting the line runs on below zero, so the fuel falls
## continuously to the motoring law's 0. A free crank settles on the setting; a load holds it on the
## line, `load / slope` under it. The idle controller stays the floor (`Drivetrain.fuel_to_land`).
static func governor_fuel(spec: VehicleSpec, p_demand: float, at_rpm: float) -> float:
	var line := governor_line(spec, p_demand)
	if at_rpm <= line.y:
		return 1.0
	var t_line := line.z * (line.x - at_rpm)
	if t_line >= Drivetrain.engine_torque(spec, at_rpm) - LINE_ON_CURVE_NM:
		return 1.0
	return Drivetrain.drag_fuel(spec, at_rpm, t_line)


## The governor line's stiffness (N·m per rad/s, >= 0) where it governs this tick (its fuel strictly
## between 0 and 1): the crank's net torque there is the line's, so its slope replaces the curve's
## and the motoring law's in `Drivetrain.crank_stiffness`. NAN where it does not govern, and on any
## map but ALL_SPEED unless `governed` (`fuel`'s).
static func governor_stiffness(spec: VehicleSpec, p_demand: float, at_rpm: float,
		governed := false) -> float:
	if (spec.pedal_map != Kind.ALL_SPEED and not governed) or not Drivetrain.drives_wheels(spec):
		return NAN
	var f := governor_fuel(spec, p_demand, at_rpm)
	if f <= 0.0 or f >= 1.0:
		return NAN
	return governor_line(spec, p_demand).z * Drivetrain.RADS_TO_RPM


## Rated speed (rpm): where the curve's power `T n` peaks, inside a falling segment or on a point.
static func rated_rpm(spec: VehicleSpec) -> float:
	var points := spec.torque_curve
	var best := 0.0
	var best_n := spec.redline_rpm
	for i in points.size():
		if points[i].x * points[i].y > best:
			best = points[i].x * points[i].y
			best_n = points[i].x
		if i == 0:
			continue
		var a := points[i - 1]
		var b := points[i]
		var s := (b.y - a.y) / maxf(b.x - a.x, 1e-6)
		if s < 0.0:
			var n := (s * a.x - a.y) / (2.0 * s)
			if n > a.x and n < b.x and n * (a.y + s * (n - a.x)) > best:
				best = n * (a.y + s * (n - a.x))
				best_n = n
	return best_n


## The fuel (0..1) that delivers row `row`'s request at `x` (rpm over rated speed).
static func _row_fuel(spec: VehicleSpec, row: int, x: float, at_rpm: float) -> float:
	var request := _sample_row(row - 1, x) * Drivetrain.peak_torque(spec)
	var motoring := Drivetrain.motoring_torque(spec, at_rpm)
	var span := Drivetrain.engine_torque(spec, at_rpm) - motoring
	if span <= 0.0:
		return 1.0 if request > motoring else 0.0
	return clampf((request - motoring) / span, 0.0, 1.0)


## Row `row` of PETROL_REQUEST at `x`, linear between columns, held flat outside them.
static func _sample_row(row: int, x: float) -> float:
	var cols := PETROL_RPM.size()
	var at := row * cols
	if x <= PETROL_RPM[0]:
		return PETROL_REQUEST[at]
	for i in range(1, cols):
		if x <= PETROL_RPM[i]:
			return lerpf(PETROL_REQUEST[at + i - 1], PETROL_REQUEST[at + i],
					(x - PETROL_RPM[i - 1]) / (PETROL_RPM[i] - PETROL_RPM[i - 1]))
	return PETROL_REQUEST[at + cols - 1]

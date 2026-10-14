class_name TorqueConverter
extends RefCounted
## A torque converter between the crank (the impeller) and the gearbox input (the turbine), as pure
## statics beside `Differential`: what a converter body's coupling carries while its lock-up is open
## or closing (`Drivetrain.couple`, `spec.coupling` CONVERTER).
##
## The impeller absorbs `coef * omega_p^2 * shape(SR)`, SR the speed ratio `omega_t / omega_p`, and
## the turbine passes that times the torque ratio (`torque_ratio`, falling from the spec's
## `converter_stall_ratio` to 1.0 at the coupling point). `coef` puts the full-fuel balance against a
## held turbine on `Drivetrain.stall_rpm`. The law's speed slope through the gear ratio squared is far
## past what an explicit step holds (about 8 against 2 on the sedan in gear 1, wheels lifted), so
## `solve` finds the torque where the law and the two sides' end-of-tick speeds agree.

## Speed ratio at which the torque ratio has fallen to 1.0 (the MathWorks Powertrain Blockset
## defaults: 1.07 at 0.87, 1.00 at 0.94): docs/vehicles.md § Converter.
const COUPLING_POINT := 0.9
## The impeller's torque at one impeller speed over its stall torque, `(K_stall / K(SR))^2`, against
## the speed ratio: the MathWorks defaults' capacity factor K (12.3 at stall, 14.6 at 0.8, 16.3 at
## 0.87, 22.1 at 0.94, 50 at 0.97), K going to infinity at 1.
const CAPACITY_SHAPE: Array[Vector2] = [
	Vector2(0.0, 1.0), Vector2(0.8, 0.710), Vector2(0.87, 0.569), Vector2(0.94, 0.310),
	Vector2(0.97, 0.061), Vector2(1.0, 0.0)]
## Overrun (the turbine faster, the wheels driving the crank) runs the same shape with the roles
## swapped, at this share of the drive capacity. A labelled estimate: a coast curve exists (NREL
## ADVISOR) but no figure was found, and with the stator freewheeling it is weaker than drive.
const OVERRUN_CAPACITY := 0.5
## Bisection steps `solve` takes: the bracket's 2^-30, a few µN·m on a truck.
const SOLVE_STEPS := 30


## `CAPACITY_SHAPE` at speed ratio `sr`: 1 with the turbine held or turning back, 0 at 1.
static func capacity_shape(sr: float) -> float:
	if sr <= 0.0:
		return 1.0
	if sr >= 1.0:
		return 0.0
	for i in range(1, CAPACITY_SHAPE.size()):
		var p := CAPACITY_SHAPE[i]
		if sr <= p.x:
			var q := CAPACITY_SHAPE[i - 1]
			return lerpf(q.y, p.y, (sr - q.x) / (p.x - q.x))
	return 0.0


## The capacity coefficient (N·m per (rad/s)^2): the engine's full-fuel torque at the stall speed
## over that speed squared, so full fuel against a held turbine balances on `Drivetrain.stall_rpm`.
static func capacity_coefficient(p_spec: VehicleSpec) -> float:
	var stall := Drivetrain.stall_rpm(p_spec)
	var omega := stall / Drivetrain.RADS_TO_RPM
	return Drivetrain.engine_torque(p_spec, stall) / maxf(omega * omega, 1e-6)


## The impeller's torque (N·m at the crank, + = the crank driving) at impeller spin `omega_p` (>= 0)
## and turbine spin `omega_t` (rad/s, signed with the gear): `coef omega_p^2 shape(SR)` in drive,
## `-OVERRUN_CAPACITY coef omega_t^2 shape(1 / SR)` in overrun. 0 at one speed; rising with the
## impeller, falling with the turbine.
static func impeller_torque(coef: float, omega_p: float, omega_t: float) -> float:
	if omega_p >= omega_t:
		if omega_p <= 0.0:
			return 0.0
		return coef * omega_p * omega_p * capacity_shape(omega_t / omega_p)
	return -OVERRUN_CAPACITY * coef * omega_t * omega_t * capacity_shape(omega_p / omega_t)


## Turbine torque over impeller torque at speed ratio `sr`: `stall_ratio` with the turbine held,
## falling linearly to 1.0 at COUPLING_POINT and 1.0 past it. 1.0 everywhere for a fluid coupling.
static func torque_ratio(stall_ratio: float, sr: float) -> float:
	if stall_ratio <= 1.0:
		return 1.0
	return lerpf(stall_ratio, 1.0, clampf(sr / COUPLING_POINT, 0.0, 1.0))


## One tick of the converter with a lock-up clutch of `lockup_capacity` (N·m at the crank, 0 open)
## in parallel, solved with both sides' steps. The crank is predicted at `pred` (rad/s, no coupling)
## and moves `crank_c` rad/s per N·m (`Drivetrain.crank_compliance`); the gear's signed ratio is `g`
## and its efficiency `eta`. `wheel_spin(axle_torque)` returns the driven wheels' settled mean spin
## (rad/s) with that axle torque (+ = forward) shared over them, their holds solved in
## (`Differential.settled_mean_spin`). The unknown is the impeller torque `T`: the crank ends at
## `pred - T c`, the axle takes `T ratio g eta` driving (`ratio` the torque ratio, read by the caller
## at the tick's start) or `T g / eta` in overrun, and the turbine turns at the wheels' spin times
## `g`. `T - law - lockup * sgn(slip)` rises strictly with `T`, with a jump where the lock-up closes
## the slip, so bisection finds the one root. Returns [T, axle torque, the crank's end spin, whether
## the lock-up closed it: carried less than its capacity].
static func solve(pred: float, crank_c: float, coef: float, g: float, eta: float, ratio: float,
		lockup_capacity: float, wheel_spin: Callable) -> Array:
	var cap := maxf(lockup_capacity, 0.0)
	var at := _evaluate(0.0, pred, crank_c, coef, g, eta, ratio, cap, wheel_spin)
	var residual: float = at[0]
	if residual != 0.0:
		var dir := -signf(residual)
		var law0: float = at[3]
		var lo := 0.0
		var hi := dir * law0 + cap
		for i in SOLVE_STEPS:
			var mid := (lo + hi) * 0.5
			var f: float = _evaluate(dir * mid, pred, crank_c, coef, g, eta, ratio, cap,
					wheel_spin)[0]
			if f == 0.0:
				lo = mid
				hi = mid
				break
			if signf(f) == signf(residual):
				lo = mid
			else:
				hi = mid
		at = _evaluate(dir * (lo + hi) * 0.5, pred, crank_c, coef, g, eta, ratio, cap, wheel_spin)
	var t: float = at[4]
	var law: float = at[3]
	return [t, at[1], at[2], cap > 0.0 and absf(t - law) < cap]


## `solve`'s residual at impeller torque `t`: [residual, axle torque, crank spin, law, t].
static func _evaluate(t: float, pred: float, crank_c: float, coef: float, g: float, eta: float,
		ratio: float, cap: float, wheel_spin: Callable) -> Array:
	var axle := t * ratio * g * eta if t >= 0.0 else t * g / eta
	var omega_p := maxf(pred - t * crank_c, 0.0)
	var omega_t: float = wheel_spin.call(axle) * g
	var law := impeller_torque(coef, omega_p, omega_t)
	return [t - law - cap * signf(omega_p - omega_t), axle, omega_p, law, t]

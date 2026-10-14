class_name Differential
extends RefCounted
## A differential as a friction coupling between its two outputs: pure statics, applied by
## `WheelDrive._couple_differentials` after the wheels integrate their spin, with each output's
## holds (traction control, brake) solved in the same step (`braked_coupling_torque`).
##
## Every diff splits its input torque equally (the open-diff law) and then moves a coupling torque
## from the faster output to the slower one, bounded by a CAPACITY: 0 is an open diff, a torque-
## biasing diff (Torsen, plate LSD) scales with the torque going through it, and a locked or rigid
## one is unbounded. Never a traction cap: nothing here reads grip or load.
##
## The coupling is solved inside the wheels' semi-implicit spin step, not after it. That step is
## linear in the applied torque (`RayWheel.spin_compliance`), so a torque `T` applied as
## `omega -= T * compliance` after integrating is exactly what adding it to the drive torque would
## have given. An explicit post-tick transfer skips the `1 + reaction_stiffness` divisor, acts that
## much too strong on a gripping wheel and turns any limited-slip diff into a spool.

## Spread (rad/s) `braked_coupling_torque` reads as zero at a kink: rounding, not slip.
const SPREAD_EPS := 1e-12


## Largest coupling torque (N·m) a torque-biasing diff can carry with `input_torque` through it: the
## slow output may take up to `bias_ratio` times what the fast one takes. With an equal nominal split
## `T/2 ± cap`, that ratio is `(T/2 + cap) / (T/2 - cap) = b`, so `cap = |T|/2 * (b-1)/(b+1)`. 0 for
## an open diff (b = 1) and with no torque through it, since a torque-sensing diff biases nothing
## when unloaded. Blind to the torque's sign, since overrun biases the same way.
static func bias_capacity(input_torque: float, bias_ratio: float) -> float:
	if bias_ratio <= 1.0:
		return 0.0
	return absf(input_torque) * 0.5 * (bias_ratio - 1.0) / (bias_ratio + 1.0)


## Coupling torque (N·m) moved from output a to output b, positive when a runs faster: the torque
## that brings the two outputs to one speed this tick, `(omega_a - omega_b) / (compliance_a +
## compliance_b)`, clamped to `capacity` (INF for a locked diff or a rigid coupling). The caller
## applies it as `omega_a -= T * compliance_a`, `omega_b += T * compliance_b`, so an unbounded
## coupling lands both outputs on the compliance-weighted mean, and a bounded one only shrinks the
## spread. It never reverses the spread, so it needs no 60 Hz clamp of its own. 0 when the outputs
## have no compliance (nothing to move) or the capacity is 0 (an open diff, a bit-exact no-op).
static func coupling_torque(omega_a: float, omega_b: float, compliance_a: float,
		compliance_b: float, capacity: float) -> float:
	var compliance := compliance_a + compliance_b
	if capacity <= 0.0 or compliance <= 0.0:
		return 0.0
	return clampf((omega_a - omega_b) / compliance, -capacity, capacity)


## Coupling torque (N·m) moved from side a to side b, positive when a runs faster, with every
## output's holds solved in the same step. Outputs `[0, n_a)` are side a, the rest side b; a side's
## torque splits equally over its outputs (the open-diff law) and its spin is their mean, so one
## output a side is an axle diff and an axle a side the centre. Each output enters as its spin
## before its holds, its `compliance`, its brake (`can_take`, `stop_at`: `RayWheel.brake_spin` and
## `abs_floor`) and its traction-control hold (`tcs_share`, `tcs_at`: `RayWheel.tcs_spin` and
## `tcs_ceiling`; 0 share = none).
## The settled spread `g(t)`, side a's mean spin less side b's once `t` is applied and each output
## settled (`RayWheel.settled_spin`), is piecewise linear and never rises with `t`: the root nearest
## zero, clamped to `capacity`, is walked off the holds' kinks exactly. So a braked output stays
## held unless the torque the coupling must pass it beats its brake, a TC-held output stays at its
## ceiling unless the coupling passes it more than its drive share, and between two held sides the
## coupling carries only what holding them takes. With no hold it is `coupling_torque` on the two
## means. The torque takes the settled spread's sign and never more than closes it, so it never
## reverses a spread and needs no 60 Hz clamp of its own.
static func braked_coupling_torque(omega: PackedFloat64Array, compliance: PackedFloat64Array,
		can_take: PackedFloat64Array, stop_at: PackedFloat64Array, tcs_share: PackedFloat64Array,
		tcs_at: PackedFloat64Array, n_a: int, capacity: float) -> float:
	var n_b := omega.size() - n_a
	if capacity <= 0.0 or n_a <= 0 or n_b <= 0:
		return 0.0
	# Each side's mean compliance: the spread's slope where every output turns past its holds.
	var sum_a := 0.0
	var sum_b := 0.0
	var spin_a := 0.0
	var spin_b := 0.0
	var held := false
	for i in omega.size():
		held = held or can_take[i] > 0.0 or tcs_share[i] != 0.0
		if i < n_a:
			sum_a += compliance[i]
			spin_a += omega[i]
		else:
			sum_b += compliance[i]
			spin_b += omega[i]
	var c_a := sum_a / (n_a * n_a)
	var c_b := sum_b / (n_b * n_b)
	if not held:
		return coupling_torque(spin_a / n_a, spin_b / n_b, c_a, c_b, capacity)
	var slope := c_a + c_b
	if slope <= 0.0:
		return 0.0
	var g0 := _settled_spread(omega, compliance, can_take, stop_at, tcs_share, tcs_at, n_a, 0.0)
	if g0 == 0.0:
		return 0.0
	# Walk `s = dir * t` up from 0, where `h(s) = dir * g(dir * s)` starts positive and falls.
	var dir := signf(g0)
	var kinks := PackedFloat64Array()
	var beyond_cap := false  # a kink lies past the capacity
	for i in omega.size():
		# This output's spin moves `rate` rad/s per N·m of `t`.
		var rate := -compliance[i] / n_a if i < n_a else compliance[i] / n_b
		if rate == 0.0:
			continue
		for kink: float in _settle_kinks(can_take[i], stop_at[i], tcs_share[i], tcs_at[i]):
			var at := dir * (kink - omega[i]) / rate
			if at >= capacity:
				beyond_cap = true
			elif at > 0.0:
				kinks.append(at)
	kinks.sort()
	var prev_s := 0.0
	var prev_h := absf(g0)
	for s: float in kinks:
		var h := dir * _settled_spread(omega, compliance, can_take, stop_at, tcs_share, tcs_at, n_a,
				dir * s)
		if h <= 0.0:
			return dir * (prev_s + prev_h / (prev_h - h) * (s - prev_s))
		if h <= SPREAD_EPS:
			# Zero but for the rounding of `omega - t * c` at the kink: the root is the kink.
			return dir * s
		prev_s = s
		prev_h = h
	if not beyond_cap:
		# Past the last kink every output turns with its full compliance: both holds have slope 1
		# beyond their outer kinks.
		return dir * minf(prev_s + prev_h / slope, capacity)
	var h_cap := dir * _settled_spread(omega, compliance, can_take, stop_at, tcs_share, tcs_at,
			n_a, dir * capacity)
	if h_cap > 0.0:
		return dir * capacity
	return dir * (prev_s + prev_h / (prev_h - h_cap) * (capacity - prev_s))


## The mean settled spin (rad/s) of a set of outputs with `torque` (N·m, + = forward) shared equally
## over them, each settled on its holds (`RayWheel.settled_spin`; the arrays as
## `braked_coupling_torque` takes them): what a converter's turbine turns at
## (`TorqueConverter.solve`). Never falls as the torque rises.
static func settled_mean_spin(omega: PackedFloat64Array, compliance: PackedFloat64Array,
		can_take: PackedFloat64Array, stop_at: PackedFloat64Array, tcs_share: PackedFloat64Array,
		tcs_at: PackedFloat64Array, torque: float) -> float:
	var n := omega.size()
	if n == 0:
		return 0.0
	var sum := 0.0
	for i in n:
		sum += RayWheel.settled_spin(omega[i] + torque * compliance[i] / n, can_take[i], stop_at[i],
				tcs_share[i], tcs_at[i])
	return sum / n


## Side a's mean settled spin less side b's with `t` applied (`braked_coupling_torque`).
static func _settled_spread(omega: PackedFloat64Array, compliance: PackedFloat64Array,
		can_take: PackedFloat64Array, stop_at: PackedFloat64Array, tcs_share: PackedFloat64Array,
		tcs_at: PackedFloat64Array, n_a: int, t: float) -> float:
	var n_b := omega.size() - n_a
	var sum_a := 0.0
	var sum_b := 0.0
	for i in omega.size():
		if i < n_a:
			sum_a += RayWheel.settled_spin(omega[i] - t * compliance[i] / n_a, can_take[i],
					stop_at[i], tcs_share[i], tcs_at[i])
		else:
			sum_b += RayWheel.settled_spin(omega[i] + t * compliance[i] / n_b, can_take[i],
					stop_at[i], tcs_share[i], tcs_at[i])
	return sum_a / n_a - sum_b / n_b


## The spins (rad/s, before the holds) where `RayWheel.settled_spin`'s slope changes: the TC hold's
## own, where the spin reaches its ceiling `tcs_at` and where it has taken its whole `tcs_share`,
## and each of the brake's (`_brake_kinks`) mapped back through the hold. A brake kink short of the
## ceiling on the drive's side stays put; past it the hold has already taken the share, so it sits
## that share further out; one at the ceiling exactly lies on the hold's flat, whose ends are kinks
## already.
static func _settle_kinks(can_take: float, stop_at: float, tcs_share: float,
		tcs_at: float) -> PackedFloat64Array:
	var kinks := _brake_kinks(can_take, stop_at)
	if tcs_share == 0.0:
		return kinks
	var dir := signf(tcs_share)
	var out := PackedFloat64Array([tcs_at, tcs_at + tcs_share])
	for k in kinks:
		var past := dir * (k - tcs_at)
		if past < 0.0:
			out.append(k)
		elif past > 0.0:
			out.append(k + tcs_share)
	return out


## The spins (rad/s, before the brake) where `RayWheel.braked_spin`'s slope changes: none with no
## brake, `±can_take` around a stop at zero, and under an ABS floor `stop_at` (sign `σ`) the stop at
## zero from the far side plus the hold at the floor, `{-σ can_take, 0, stop_at, stop_at + σ
## can_take}`.
static func _brake_kinks(can_take: float, stop_at: float) -> PackedFloat64Array:
	if can_take <= 0.0:
		return PackedFloat64Array()
	if stop_at == 0.0:
		return PackedFloat64Array([-can_take, can_take])
	var side := signf(stop_at)
	return PackedFloat64Array([-side * can_take, 0.0, stop_at, stop_at + side * can_take])

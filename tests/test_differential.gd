extends GdUnitTestSuite
## Differential: the bias capacity, the coupling torque and the coupling solved with its outputs'
## holds (brake, traction control), pure statics. The coupling's equivalence with the wheel's own
## spin step lives in test_wheel_spin (`spin_compliance`), and so do the WheelDrive passes that
## apply it.

const DiffScript := preload("res://src/vehicles/base/differential.gd")
const WheelScript := preload("res://src/vehicles/base/wheel.gd")


# --- capacity -----------------------------------------------------------------------

func test_an_open_diff_carries_no_coupling_torque() -> void:
	assert_float(DiffScript.bias_capacity(1000.0, 1.0)).is_equal(0.0)
	# A ratio below 1 is not a diff anyone builds; it reads as open, never as a negative capacity.
	assert_float(DiffScript.bias_capacity(1000.0, 0.5)).is_equal(0.0)


func test_the_capacity_holds_the_declared_bias_ratio() -> void:
	# Equal nominal shares T/2 +- cap: the slow side's share over the fast side's IS the ratio.
	for bias: float in [1.5, 2.5, 3.0, 5.0]:
		var torque := 1200.0
		var cap := DiffScript.bias_capacity(torque, bias)
		assert_float((torque * 0.5 + cap) / (torque * 0.5 - cap)).is_equal_approx(bias, 1e-9)


func test_the_capacity_is_blind_to_the_torque_sign_and_zero_when_unloaded() -> void:
	# Overrun biases the same way as drive; a torque-sensing diff with nothing through it is open.
	assert_float(DiffScript.bias_capacity(-800.0, 3.0)) \
			.is_equal(DiffScript.bias_capacity(800.0, 3.0))
	assert_float(DiffScript.bias_capacity(0.0, 3.0)).is_equal(0.0)


# --- coupling -----------------------------------------------------------------------

func test_zero_capacity_is_an_exact_no_op() -> void:
	# The open diff: nothing moves, so an all-open body is today's equal split bit for bit.
	assert_float(DiffScript.coupling_torque(40.0, 10.0, 0.01, 0.002, 0.0)).is_equal(0.0)


func test_no_compliance_means_nothing_to_move() -> void:
	assert_float(DiffScript.coupling_torque(40.0, 10.0, 0.0, 0.0, INF)).is_equal(0.0)


func test_an_unbounded_coupling_lands_on_the_compliance_weighted_mean() -> void:
	var c_a := 0.004  # spinning: soft
	var c_b := 0.001  # gripping: stiff, moves less
	var t := DiffScript.coupling_torque(40.0, 10.0, c_a, c_b, INF)
	var a := 40.0 - t * c_a
	var b := 10.0 + t * c_b
	assert_float(a).is_equal_approx(b, 1e-9)
	assert_float(a).is_equal_approx((c_b * 40.0 + c_a * 10.0) / (c_a + c_b), 1e-9)


func test_equal_compliances_lock_onto_the_plain_mean() -> void:
	# One rigid shaft on equal wheels: the momentum-conserving mean, either direction, either sign.
	for pair: Array in [[40.0, 10.0], [10.0, 40.0], [-40.0, -10.0], [12.5, 12.5]]:
		var a: float = pair[0]
		var b: float = pair[1]
		var t := DiffScript.coupling_torque(a, b, 0.002, 0.002, INF)
		assert_float(a - t * 0.002).is_equal_approx((a + b) * 0.5, 1e-9)
		assert_float(b + t * 0.002).is_equal_approx((a + b) * 0.5, 1e-9)


func test_a_bounded_coupling_shrinks_the_spread_and_never_reverses_it() -> void:
	for cap: float in [1.0, 100.0, 1.0e4, INF]:
		var c_a := 0.003
		var c_b := 0.0015
		var t := DiffScript.coupling_torque(30.0, 5.0, c_a, c_b, cap)
		var spread := (30.0 - t * c_a) - (5.0 + t * c_b)
		assert_float(spread).is_between(-1e-9, 25.0)


func test_swapping_the_outputs_negates_the_torque() -> void:
	assert_float(DiffScript.coupling_torque(10.0, 40.0, 0.001, 0.004, 500.0)) \
			.is_equal(-DiffScript.coupling_torque(40.0, 10.0, 0.004, 0.001, 500.0))


func test_the_torque_never_exceeds_the_capacity() -> void:
	var t := DiffScript.coupling_torque(40.0, 10.0, 0.001, 0.001, 250.0)
	assert_float(t).is_equal(250.0)
	assert_float(DiffScript.coupling_torque(10.0, 40.0, 0.001, 0.001, 250.0)).is_equal(-250.0)
	# Under the capacity it is the exact lock torque, not the cap.
	assert_float(DiffScript.coupling_torque(10.1, 10.0, 0.001, 0.001, 250.0)) \
			.is_equal_approx(50.0, 1e-6)


# --- the coupling with its outputs' brakes inside -------------------------------------

## One output a side (an axle diff): `[spin, compliance, can_take, stop_at]` each, plus
## `[tcs_share, tcs_at]` for a TC-held one.
func _axle_torque(a: Array, b: Array, capacity: float) -> float:
	return DiffScript.braked_coupling_torque(PackedFloat64Array([a[0], b[0]]),
			PackedFloat64Array([a[1], b[1]]), PackedFloat64Array([a[2], b[2]]),
			PackedFloat64Array([a[3], b[3]]), PackedFloat64Array([_tc(a, 4), _tc(b, 4)]),
			PackedFloat64Array([_tc(a, 5), _tc(b, 5)]), 1, capacity)


## An output's TC entry `k`, 0 (no hold) where it declares none.
func _tc(o: Array, k: int) -> float:
	return o[k] if o.size() > k else 0.0


## Output `o`'s spin once `t` is applied on `side` (-1 a, +1 b) and its holds have acted.
func _after(o: Array, t: float, side: float) -> float:
	return WheelScript.settled_spin(o[0] + side * t * o[1], o[2], o[3], _tc(o, 4), _tc(o, 5))


func test_with_no_brake_it_is_the_plain_coupling() -> void:
	for cap: float in [1.0, 100.0, 1.0e4, INF]:
		assert_float(_axle_torque([30.0, 0.003, 0.0, 0.0], [5.0, 0.0015, 0.0, 0.0], cap)) \
				.is_equal_approx(DiffScript.coupling_torque(30.0, 5.0, 0.003, 0.0015, cap), 1e-9)
	# Two outputs a side (the centre): the plain coupling of the two means, at each side's mean
	# compliance.
	var omega := PackedFloat64Array([30.0, 26.0, 5.0, 7.0])
	var c := PackedFloat64Array([0.003, 0.001, 0.0015, 0.002])
	var none := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for cap: float in [10.0, INF]:
		assert_float(DiffScript.braked_coupling_torque(omega, c, none, none, none, none, 2, cap)) \
				.is_equal_approx(DiffScript.coupling_torque(28.0, 6.0, 0.004 / 4.0, 0.0035 / 4.0,
				cap), 1e-9)


func test_a_braked_output_stays_held_unless_the_coupling_must_pass_it_more_than_its_brake() -> void:
	# Output a is driven past its own brake (0.3 rad/s of spin against 0.1); b's brake has spare.
	var a := [0.3, 0.01, 0.1, 0.0]
	var strong := [0.0, 0.01, 0.5, 0.0]
	var t := _axle_torque(a, strong, INF)
	# a's brake ends at its limit, so its spin is zero to rounding; b holds with spare.
	assert_float(_after(a, t, -1.0)).is_equal_approx(0.0, 1e-12)
	assert_float(_after(strong, t, 1.0)).is_equal(0.0)
	# Between two held outputs the shaft carries only what holding a takes: (0.3 - 0.1) / 0.01.
	assert_float(t).is_equal_approx(20.0, 1e-9)
	# Too little brake in total (0.1 + 0.05 against 0.3): both turn together, both brakes slipping.
	var weak := [0.0, 0.01, 0.05, 0.0]
	t = _axle_torque(a, weak, INF)
	assert_float(_after(a, t, -1.0)).is_equal_approx(0.075, 1e-9)
	assert_float(_after(weak, t, 1.0)).is_equal_approx(0.075, 1e-9)


func test_a_braked_coupling_never_exceeds_its_capacity() -> void:
	var a := [0.3, 0.01, 0.1, 0.0]
	var b := [0.0, 0.01, 0.5, 0.0]
	assert_float(_axle_torque(a, b, 5.0)).is_equal(5.0)
	assert_float(_axle_torque(b, a, 5.0)).is_equal(-5.0)
	# The capacity leaves a turning: its brake takes 0.1, the coupling 0.05.
	assert_float(_after(a, 5.0, -1.0)).is_equal_approx(0.15, 1e-9)


func test_a_braked_coupling_never_reverses_the_braked_spread() -> void:
	var outputs := [
		[0.3, 0.01, 0.1, 0.0], [0.0, 0.01, 0.5, 0.0], [-2.0, 0.004, 0.3, 0.0],
		[5.0, 0.002, 0.0, 0.0], [1.0, 0.03, 2.0, 0.0], [12.0, 0.01, 1.0, 9.0],
		# TC-held: past the ceiling, inside the share, overrun under its floor, braked as well.
		[12.0, 0.01, 0.0, 0.0, 1.5, 10.0], [8.0, 0.004, 0.5, 0.0, 1.0, 6.0],
		[-4.0, 0.01, 0.0, 0.0, -2.0, -2.5], [3.0, 0.02, 4.0, 0.0, 3.0, 1.0],
	]
	for a: Array in outputs:
		for b: Array in outputs:
			for cap: float in [0.5, 50.0, INF]:
				var spread_in := _after(a, 0.0, -1.0) - _after(b, 0.0, 1.0)
				var t := _axle_torque(a, b, cap)
				var spread_out := _after(a, t, -1.0) - _after(b, t, 1.0)
				assert_float(t * spread_in).is_greater_equal(0.0)
				assert_float(spread_out * signf(spread_in)).is_between(-1e-9, absf(spread_in) + 1e-9)


func test_an_abs_floor_stops_the_brake_short_of_zero_inside_the_coupling() -> void:
	# The law alone: down to the floor, never past it, and never lifting a wheel already below it.
	assert_float(WheelScript.braked_spin(10.0, 100.0, 8.0)).is_equal(8.0)
	assert_float(WheelScript.braked_spin(5.0, 100.0, 8.0)).is_equal(5.0)
	assert_float(WheelScript.braked_spin(-1.0, 100.0, 8.0)).is_equal(0.0)
	# Rigidly coupled to a faster free output, the ABS wheel takes torque until both turn at 9.25:
	# a's brake holds it 1 rad/s under its pre-brake spin, over its 8 rad/s floor.
	var a := [10.0, 0.01, 1.0, 8.0]
	var b := [9.5, 0.01, 0.0, 0.0]
	var t := _axle_torque(a, b, INF)
	assert_float(_after(a, t, -1.0)).is_equal_approx(9.25, 1e-9)
	assert_float(_after(b, t, 1.0)).is_equal_approx(9.25, 1e-9)


# --- the traction-control hold inside the coupling -------------------------------------

## Settle laws `[can_take, stop_at, tcs_share, tcs_at]`: TC alone each way, a brake kink past the
## ceiling, an ABS floor under it, a reversing brake against an overrun hold, mixed signs.
const LAWS := [
	[0.0, 0.0, 2.0, 5.0], [0.0, 0.0, -2.0, -5.0], [3.0, 0.0, 2.0, 1.0], [1.0, 8.0, 1.5, 10.0],
	[4.0, 6.0, 2.0, 7.0], [2.0, 0.0, -1.5, -1.0], [0.5, -3.0, 1.0, 2.0], [2.0, 0.0, 0.0, 0.0],
]


func test_the_settle_law_is_monotone_and_linear_between_its_kinks() -> void:
	for law: Array in LAWS:
		var f := func(x: float) -> float:
			return WheelScript.settled_spin(x, law[0], law[1], law[2], law[3])
		var x := -20.0
		while x < 20.0:
			assert_float(f.call(x + 0.05)).is_greater_equal(f.call(x) - 1e-12)
			x += 0.05
		# Every slope change is a listed kink: between two neighbours the law is a straight line.
		var points := DiffScript._settle_kinks(law[0], law[1], law[2], law[3])
		points.append_array([-20.0, 20.0])
		points.sort()
		for i in points.size() - 1:
			var lo: float = points[i]
			var hi: float = points[i + 1]
			if hi - lo < 1e-9:
				continue
			for frac: float in [0.25, 0.5, 0.75]:
				var at := lerpf(lo, hi, frac)
				assert_float(f.call(at)) \
						.override_failure_message("%s: kink missed in [%f, %f]" % [law, lo, hi]) \
						.is_equal_approx(lerpf(f.call(lo), f.call(hi), frac), 1e-9)


func test_the_tc_hold_takes_only_the_drive_share() -> void:
	# Forward: down to the ceiling, never more than the share, nothing under the ceiling.
	assert_float(WheelScript.settled_spin(5.5, 0.0, 0.0, 2.0, 5.0)).is_equal(5.0)
	assert_float(WheelScript.settled_spin(9.0, 0.0, 0.0, 2.0, 5.0)).is_equal(7.0)
	assert_float(WheelScript.settled_spin(4.0, 0.0, 0.0, 2.0, 5.0)).is_equal(4.0)
	# Overrun mirrors it: up to the floor, never more than the (negative) share.
	assert_float(WheelScript.settled_spin(-5.5, 0.0, 0.0, -2.0, -5.0)).is_equal(-5.0)
	assert_float(WheelScript.settled_spin(-9.0, 0.0, 0.0, -2.0, -5.0)).is_equal(-7.0)


func test_a_tc_held_output_stays_at_its_ceiling_under_a_biasing_coupling() -> void:
	# a spins past its ceiling (32 against 30, share 4); b grips. Bounded, the coupling carries its
	# capacity into b and a stays held at 30, never pulled under it.
	var a := [32.0, 0.002, 0.0, 0.0, 4.0, 30.0]
	var b := [28.0, 0.0002, 0.0, 0.0]
	var t := _axle_torque(a, b, 200.0)
	assert_float(t).is_equal(200.0)
	assert_float(_after(a, t, -1.0)).is_equal_approx(30.0, 1e-9)
	assert_float(_after(b, t, 1.0)).is_equal_approx(28.04, 1e-9)
	# Unbounded, the shaft pulls a through its whole share and under the ceiling: one speed.
	t = _axle_torque(a, b, INF)
	assert_float(_after(a, t, -1.0)).is_equal_approx(_after(b, t, 1.0), 1e-9)
	assert_float(_after(a, t, -1.0)).is_less(30.0)


# --- a coupling to ground (the park pawl) ---------------------------------------------

func test_a_ground_side_takes_the_mean_to_zero_within_its_capacity() -> void:
	# Two outputs against one that never turns and yields nothing (`compliance` 0): the gearbox
	# case under the pawl. Unbounded, the torque stops the pair's mean; the spread stays.
	var omega := PackedFloat64Array([0.4, 0.2, 0.0])
	var c := PackedFloat64Array([0.01, 0.01, 0.0])
	var none := PackedFloat64Array([0.0, 0.0, 0.0])
	var t := DiffScript.braked_coupling_torque(omega, c, none, none, none, none, 2, INF)
	assert_float(t).is_equal_approx(0.3 / (0.02 / 4.0), 1e-9)
	assert_float((0.4 - t * 0.01 / 2.0) + (0.2 - t * 0.01 / 2.0)).is_equal_approx(0.0, 1e-12)
	# Bounded under it, the capacity is all it carries.
	assert_float(DiffScript.braked_coupling_torque(omega, c, none, none, none, none, 2, 10.0)) \
			.is_equal(10.0)
	# A brake on one output holds it at zero over the whole range the ground's share swings it
	# through, so the ground stops the other alone: 0.4 / 0.005.
	var brake := PackedFloat64Array([0.0, 0.2, 0.0])
	t = DiffScript.braked_coupling_torque(omega, c, brake, none, none, none, 2, INF)
	assert_float(t).is_equal_approx(80.0, 1e-9)
	assert_float(WheelScript.braked_spin(0.4 - t * 0.005, 0.0, 0.0)).is_equal_approx(0.0, 1e-12)
	assert_float(WheelScript.braked_spin(0.2 - t * 0.005, 0.2, 0.0)).is_equal(0.0)


# --- the settled mean (a converter's turbine) ----------------------------------------

func test_the_settled_mean_shares_a_torque_and_settles_each_output_on_its_holds() -> void:
	# Two free outputs (0.01 rad/s per N·m each) and 100 N·m forward: 50 each, 0.5 rad/s up.
	var omega := PackedFloat64Array([1.0, 3.0])
	var c := PackedFloat64Array([0.01, 0.01])
	var none := PackedFloat64Array([0.0, 0.0])
	assert_float(DiffScript.settled_mean_spin(omega, c, none, none, none, none, 100.0)) \
			.is_equal_approx(2.5, 1e-12)
	# A TC hold on the second (share 0.4, ceiling 3.2) takes it back to its ceiling.
	var share := PackedFloat64Array([0.0, 0.4])
	var ceiling := PackedFloat64Array([0.0, 3.2])
	assert_float(DiffScript.settled_mean_spin(omega, c, none, none, share, ceiling, 100.0)) \
			.is_equal_approx((1.5 + 3.2) / 2.0, 1e-12)
	# A brake on the first that can take 2 rad/s holds it at zero.
	var brake := PackedFloat64Array([2.0, 0.0])
	assert_float(DiffScript.settled_mean_spin(omega, c, brake, none, none, none, 100.0)) \
			.is_equal_approx(3.5 / 2.0, 1e-12)
	# Never falling as the torque rises, holds or none.
	var prev := -INF
	for i in 81:
		var at := DiffScript.settled_mean_spin(omega, c, brake, none, share, ceiling,
				-400.0 + i * 10.0)
		assert_float(at).is_greater_equal(prev)
		prev = at
	assert_float(DiffScript.settled_mean_spin(PackedFloat64Array(), PackedFloat64Array(),
			PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(),
			100.0)).is_equal(0.0)

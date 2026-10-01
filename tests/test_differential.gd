extends GdUnitTestSuite
## Differential: the bias capacity and the coupling torque, pure statics. The coupling's
## equivalence with the wheel's own spin step lives in test_wheel_spin (`spin_compliance`), and so
## do the WheelDrive passes that apply it.

const DiffScript := preload("res://src/vehicles/base/differential.gd")


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

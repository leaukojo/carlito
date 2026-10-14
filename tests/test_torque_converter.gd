extends GdUnitTestSuite
## TorqueConverter: the hydrodynamic law and its implicit solve, pure statics. A crank and a lumped
## turbine side built inline, so every figure is hand-checkable.

const TICK := 1.0 / 60.0


## `test_drivetrain`'s round-number engine behind a converter: stall at 1600 rpm, 160 N·m there.
func _spec() -> VehicleSpec:
	var spec := VehicleSpec.new()
	spec.ground_drive = GroundDriveSpec.new()
	spec.torque_curve = PackedVector2Array([
		Vector2(1000, 100), Vector2(2000, 200), Vector2(3000, 300), Vector2(4000, 200)])
	spec.idle_rpm = 800.0
	spec.redline_rpm = 4000.0
	spec.coupling = VehicleSpec.Coupling.CONVERTER
	spec.engine_inertia = 0.2
	return spec


## A lumped wheel side at `omega` (rad/s) moving `c` rad/s per N·m of axle torque: `solve`'s
## `wheel_spin`. `c` 0 holds it.
func _wheels(omega: float, c: float) -> Callable:
	return func(torque: float) -> float: return omega + torque * c


func test_the_capacity_shape_falls_from_stall_to_nothing_at_one_speed() -> void:
	assert_float(TorqueConverter.capacity_shape(0.0)).is_equal(1.0)
	assert_float(TorqueConverter.capacity_shape(-0.5)).is_equal(1.0)
	assert_float(TorqueConverter.capacity_shape(1.0)).is_equal(0.0)
	assert_float(TorqueConverter.capacity_shape(0.4)).is_equal_approx(1.0 - 0.5 * 0.29, 1e-6)
	var prev := 1.0
	for i in range(1, 101):
		var at := TorqueConverter.capacity_shape(i / 100.0)
		assert_float(at).is_less_equal(prev)
		prev = at


func test_the_law_is_continuous_at_one_speed_and_weaker_in_overrun() -> void:
	var coef := 0.01
	assert_float(TorqueConverter.impeller_torque(coef, 100.0, 100.0)).is_equal(0.0)
	assert_float(TorqueConverter.impeller_torque(coef, 100.0, 99.999)).is_equal_approx(0.0, 1e-2)
	assert_float(TorqueConverter.impeller_torque(coef, 99.999, 100.0)).is_equal_approx(0.0, 1e-2)
	# The turbine held: the stall law, coef * omega^2.
	assert_float(TorqueConverter.impeller_torque(coef, 100.0, 0.0)).is_equal_approx(100.0, 1e-9)
	# Turning back, it loads the impeller no more than held.
	assert_float(TorqueConverter.impeller_torque(coef, 100.0, -50.0)).is_equal_approx(100.0, 1e-9)
	# The impeller held, the turbine pumping: the same shape at OVERRUN_CAPACITY, against the crank.
	assert_float(TorqueConverter.impeller_torque(coef, 0.0, 100.0)) \
			.is_equal_approx(-TorqueConverter.OVERRUN_CAPACITY * 100.0, 1e-9)


func test_the_law_rises_with_the_impeller_and_falls_with_the_turbine() -> void:
	var coef := 0.01
	for wt: float in [-20.0, 0.0, 40.0, 90.0, 120.0, 200.0]:
		var prev := -INF
		for i in 41:
			var at := TorqueConverter.impeller_torque(coef, i * 5.0, wt)
			assert_float(at).is_greater_equal(prev)
			prev = at
	for wp: float in [0.0, 50.0, 100.0, 150.0]:
		var prev := INF
		for i in 41:
			var at := TorqueConverter.impeller_torque(coef, wp, -20.0 + i * 5.0)
			assert_float(at).is_less_equal(prev)
			prev = at


func test_the_coefficient_balances_full_fuel_on_the_stall_speed() -> void:
	var spec := _spec()
	var coef := TorqueConverter.capacity_coefficient(spec)
	var stall := Drivetrain.stall_rpm(spec)
	assert_float(stall).is_equal(1600.0)
	var omega := stall / Drivetrain.RADS_TO_RPM
	assert_float(TorqueConverter.impeller_torque(coef, omega, 0.0)) \
			.is_equal_approx(Drivetrain.engine_torque(spec, stall), 1e-6)


func test_the_torque_ratio_falls_to_one_at_the_coupling_point() -> void:
	assert_float(TorqueConverter.torque_ratio(2.0, 0.0)).is_equal(2.0)
	assert_float(TorqueConverter.torque_ratio(2.0, 0.45)).is_equal_approx(1.5, 1e-9)
	assert_float(TorqueConverter.torque_ratio(2.0, TorqueConverter.COUPLING_POINT)).is_equal(1.0)
	assert_float(TorqueConverter.torque_ratio(2.0, 1.2)).is_equal(1.0)
	# A fluid coupling multiplies nothing.
	assert_float(TorqueConverter.torque_ratio(1.0, 0.0)).is_equal(1.0)


func test_against_a_held_turbine_the_end_speeds_satisfy_the_law() -> void:
	# A floored crank predicted at 200 rad/s against held wheels: the impeller torque is the law at
	# the crank's END speed, which it pulls down.
	var coef := 0.004
	var c := TICK / 0.2
	var g := 12.0
	var r := TorqueConverter.solve(200.0, c, coef, g, 0.9, 1.0, 0.0, _wheels(0.0, 0.0))
	var t: float = r[0]
	var end: float = r[2]
	assert_float(end).is_equal_approx(200.0 - t * c, 1e-6)
	assert_float(t).is_equal_approx(TorqueConverter.impeller_torque(coef, end, 0.0), 1e-4)
	assert_float(r[1]).is_equal_approx(t * g * 0.9, 1e-6)
	assert_bool(r[3]).is_false()


func test_a_stall_ratio_multiplies_the_axle_torque() -> void:
	var coef := 0.004
	var c := TICK / 0.2
	var one := TorqueConverter.solve(200.0, c, coef, 12.0, 0.9, 1.0, 0.0, _wheels(0.0, 0.0))
	var two := TorqueConverter.solve(200.0, c, coef, 12.0, 0.9, 2.0, 0.0, _wheels(0.0, 0.0))
	# The same impeller torque: the crank does not know the turbine is multiplied.
	assert_float(two[0]).is_equal_approx(one[0], 1e-4)
	assert_float(two[1]).is_equal_approx(2.0 * float(one[1]), 1e-3)


func test_against_a_free_turbine_the_slip_shrinks_and_never_reverses() -> void:
	# A light free wheel side under a fast crank: the solve takes it toward the crank and stops short
	# of passing it, however stiff the law, and the crank pays what the wheels gained.
	var coef := 0.05
	var c := TICK / 0.2
	var g := 12.0
	var wc := TICK / 2.4
	for w0: float in [0.0, 5.0, 12.0]:
		var r := TorqueConverter.solve(200.0, c, coef, g, 0.9, 1.0, 0.0, _wheels(w0, wc))
		var axle: float = r[1]
		var turbine: float = (w0 + axle * wc) * g
		assert_float(axle).is_greater(0.0)
		assert_float(turbine).is_less_equal(float(r[2]) + 1e-4)
		assert_float(r[2]).is_equal_approx(200.0 - float(r[0]) * c, 1e-6)
	# Overrun, the wheels faster: the torque drags the crank up, never past them.
	var r := TorqueConverter.solve(50.0, c, coef, g, 0.9, 1.0, 0.0, _wheels(10.0, wc))
	assert_float(r[0]).is_less(0.0)
	assert_float(r[2]).is_less_equal((10.0 + float(r[1]) * wc) * g + 1e-4)


func test_a_lock_up_closes_the_slip_when_it_has_the_capacity_and_slips_at_it_when_not() -> void:
	# Crank 200 against wheels at 190 (through the gear) that the road holds (2400 kg·m² at the
	# axle): closing that slip in one tick takes ~120 N·m, far past a weak lock-up's 20, so it carries
	# the law plus 20; a strong one (2000) closes the slip and locks.
	var coef := 0.004
	var c := TICK / 0.2
	var g := 12.0
	var wc := TICK / 2400.0
	var w0 := 190.0 / g
	var weak := TorqueConverter.solve(200.0, c, coef, g, 0.9, 1.0, 20.0, _wheels(w0, wc))
	assert_bool(weak[3]).is_false()
	var weak_end: float = weak[2]
	var weak_turbine := (w0 + float(weak[1]) * wc) * g
	assert_float(weak[0]).is_equal_approx(
			TorqueConverter.impeller_torque(coef, weak_end, weak_turbine) + 20.0, 1e-3)
	var strong := TorqueConverter.solve(200.0, c, coef, g, 0.9, 1.0, 2000.0, _wheels(w0, wc))
	assert_bool(strong[3]).is_true()
	var strong_turbine := (w0 + float(strong[1]) * wc) * g
	assert_float(strong[2]).is_equal_approx(strong_turbine, 1e-3)

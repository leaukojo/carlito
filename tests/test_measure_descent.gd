extends GdUnitTestSuite
## `measure_grade`'s descent pass helpers: the hold's PI (`MeasureRig.PiHold`), the held gear, and
## the energy check's slip term and share.

const Measure := preload("res://tools/measure_grade.gd")
const MeasureRig := preload("res://tools/measure_rig.gd")
const DT := 1.0 / 60.0


## A foot-brake hold's PI with its integral at `integral`.
static func _hold(integral: float) -> MeasureRig.PiHold:
	var hold := MeasureRig.PiHold.new(0.15, 0.03)
	hold.integral = integral
	return hold


func test_the_hold_asks_nothing_under_its_speed() -> void:
	var hold := _hold(0.0)
	assert_float(hold.step(-2.0, DT)).is_equal(0.0)
	assert_float(hold.integral).is_equal(0.0)


func test_the_hold_answers_overspeed_in_proportion_and_integrates_it() -> void:
	var hold := _hold(0.2)
	var demand := hold.step(1.0, DT)
	assert_float(hold.integral).is_equal_approx(0.2 + 0.03 * DT, 1e-12)
	assert_float(demand).is_equal_approx(hold.integral + 0.15, 1e-12)


func test_the_hold_clamps_its_demand_and_its_integral() -> void:
	var hold := _hold(0.999)
	assert_float(hold.step(100.0, 1.0)).is_equal(1.0)
	assert_float(hold.integral).is_equal(1.0)
	# An integral wound to 1 bleeds off once under speed, the demand with it.
	hold = _hold(1.0)
	assert_float(hold.step(-1.0, 1.0)).is_equal_approx(0.82, 1e-12)
	assert_float(hold.integral).is_equal_approx(0.97, 1e-12)


func test_a_frozen_hold_keeps_its_integral() -> void:
	var hold := _hold(0.4)
	assert_float(hold.step(1.0, 1.0, true)).is_equal_approx(0.55, 1e-12)
	assert_float(hold.integral).is_equal(0.4)


func test_the_held_gear_is_the_lowest_under_the_upshift_point() -> void:
	var spec := VehicleSpec.new()
	spec.gear_ratios = PackedFloat32Array([4.0, 2.0, 1.0])
	spec.final_drive = 1.0
	spec.shift_up_rpm = 3000.0
	# rpm = omega * ratio * 60 / TAU: at 100 rad/s D1 reads 3820, D2 1910.
	assert_int(Measure.held_gear_for(spec, 100.0)).is_equal(2)
	assert_int(Measure.held_gear_for(spec, 200.0)).is_equal(3)
	assert_int(Measure.held_gear_for(spec, 1000.0)).is_equal(0)


func test_slip_loss_is_the_force_on_the_slip_velocity() -> void:
	# Braking: the patch is 1 m/s faster than the tread, the force opposes it.
	assert_float(Measure.slip_loss_w(-1000.0, 9.0, 1.0, 10.0)).is_equal_approx(1000.0, 1e-6)
	# Driving: the tread outruns the patch.
	assert_float(Measure.slip_loss_w(1000.0, 11.0, 1.0, 10.0)).is_equal_approx(1000.0, 1e-6)
	assert_float(Measure.slip_loss_w(-1000.0, 10.0, 1.0, 10.0)).is_equal_approx(0.0, 1e-6)
	# A side force against the patch's side velocity.
	assert_float(Measure.slip_loss_w(0.0, 10.0, 1.0, 10.0, -500.0, 0.2)).is_equal_approx(100.0, 1e-6)


func test_the_longest_descent_is_the_deepest_unbroken_fall_either_way() -> void:
	# Down 3 m over 2 steps, a rise, then down 5 m over 3; read backwards the 4 m rise is a descent.
	var h := PackedFloat32Array([10.0, 8.0, 7.0, 11.0, 9.0, 7.0, 6.0])
	assert_vector(Measure.longest_descent(h)).is_equal(Vector2(5.0, 3.0))
	assert_vector(Measure.longest_descent(PackedFloat32Array([0.0, 1.0, 2.0, 8.0]))).is_equal(
			Vector2(8.0, 3.0))
	assert_vector(Measure.longest_descent(PackedFloat32Array([4.0, 4.0]))).is_equal(Vector2.ZERO)


func test_the_heat_share_is_the_heat_over_what_the_rest_leaves() -> void:
	assert_float(Measure.heat_share(12.0, 9.0, 3.0)).is_equal_approx(1.0, 1e-6)
	assert_float(Measure.heat_share(12.0, 9.9, 3.0)).is_equal_approx(1.1, 1e-6)
	assert_bool(is_nan(Measure.heat_share(3.0, 1.0, 3.0))).is_true()
	# A retarder hold: the rest leaves the brakes under the tolerance of the drop, a residue.
	assert_bool(is_nan(Measure.heat_share(100.0, 0.0, 99.9))).is_true()


func test_the_gsrs_brake_power_is_table_11_over_ten_brakes() -> void:
	# 74,000 lb down 7 % at 31 mph: (5180 - 586.2) * 31 / 375 - 63.3 = 316.45 hp over the rig.
	assert_float(Measure.gsrs_brake_power_w(74000.0, 7.0, 31.0 * 1.609344)).is_equal_approx(
			316.45 * 745.7 / 10.0, 5.0)


func test_the_front_brake_share_is_the_front_force_at_the_road() -> void:
	var gd := GroundDriveSpec.new()
	gd.wheel_positions = PackedVector3Array([Vector3(-1, 0, -1.5), Vector3(1, 0, -1.5),
			Vector3(-1, 0, 1.2), Vector3(1, 0, 1.2)])
	gd.wheel_radius = 0.3
	gd.brake_torque = 1000.0
	assert_float(Measure.front_brake_share(gd)).is_equal_approx(0.5, 1e-6)
	gd.brake_bias_front = 0.7
	assert_float(Measure.front_brake_share(gd)).is_equal_approx(0.7, 1e-6)
	# A larger rear wheel turns the same torque into less force at the road.
	gd.wheel_radius_rear = 0.6
	assert_float(Measure.front_brake_share(gd)).is_equal_approx(0.7 / (0.7 + 0.3 / 2.0), 1e-6)


func test_a_check_verdict_scores_each_rise_against_its_tolerance() -> void:
	var mean := {"job": {"check": "mean", "t0": 50.0, "field": 150.0, "tol": 0.2},
			"hold": {"mean": {"mean": 170.0}}}
	var v := Measure.check_verdict(mean)
	assert_float(v["ratios"][0]).is_equal_approx(1.2, 1e-6)
	assert_int(v["ok"]).is_equal(1)
	var below := {"job": {"check": "below", "field": 149.7},
			"hold": {"units": {"powered": {"peak": 150.0}}}}
	assert_int(Measure.check_verdict(below)["ok"]).is_equal(0)
	var stops := {"job": {"check": "stops", "tol": 0.1}, "stops": [
			{"front_rise": 10.0, "front_expected": 10.0}, {"front_rise": 8.5, "front_expected": 10.0}]}
	v = Measure.check_verdict(stops)
	assert_int(v["n"]).is_equal(2)
	assert_int(v["ok"]).is_equal(1)
	assert_str(v["cell"]).is_equal("0.85-1.00")

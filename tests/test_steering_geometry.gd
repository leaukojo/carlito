extends GdUnitTestSuite
## Ackermann steering: `WheelDrive.ackermann_angle`, each steered wheel's angle off the bicycle
## angle, pure statics. The per-body domain check lives in test_vehicle_catalog.

const WheelDriveScript := preload("res://src/vehicles/base/wheel_drive.gd")

## `sedan`: track 1.264 m (t / L 0.80), wheelbase 1.58 m.
const SEDAN_L := 1.58
const SEDAN_HALF_TRACK := 0.632


func test_parallel_steer_returns_the_mean_for_any_offset() -> void:
	for x in [-0.9, -0.3, 0.4, 1.2]:
		assert_float(WheelDriveScript.ackermann_angle(0.5, x, 2.0, 0.0)).is_equal(0.5)


func test_a_centred_wheel_and_a_straight_rack_are_untouched() -> void:
	assert_float(WheelDriveScript.ackermann_angle(0.5, 0.0, 2.0, 1.0)).is_equal(0.5)
	assert_float(WheelDriveScript.ackermann_angle(0.0, 0.7, 2.0, 1.0)).is_equal(0.0)


func test_full_ackermann_puts_both_wheels_on_one_centre() -> void:
	var mean := deg_to_rad(30.0)
	var left := WheelDriveScript.ackermann_angle(mean, -SEDAN_HALF_TRACK, SEDAN_L, 1.0)
	var right := WheelDriveScript.ackermann_angle(mean, SEDAN_HALF_TRACK, SEDAN_L, 1.0)
	# The centre's distance left of the body axis, read from each wheel: L cot δ_w - x.
	assert_float(SEDAN_L / tan(left) + SEDAN_HALF_TRACK).is_equal_approx(
			SEDAN_L / tan(right) - SEDAN_HALF_TRACK, 1e-4)


func test_sedan_full_lock_splits_to_the_computed_pair() -> void:
	var mean := deg_to_rad(38.0)
	var inner := WheelDriveScript.ackermann_angle(mean, -SEDAN_HALF_TRACK, SEDAN_L, 1.0)
	var outer := WheelDriveScript.ackermann_angle(mean, SEDAN_HALF_TRACK, SEDAN_L, 1.0)
	assert_float(rad_to_deg(inner)).is_equal_approx(48.6, 0.1)
	assert_float(rad_to_deg(outer)).is_equal_approx(30.8, 0.1)


func test_any_fraction_orders_the_pair_mirrors_it_and_keeps_the_cotangent_mean() -> void:
	for f in [0.25, 0.6, 1.0]:
		for mean_deg in [5.0, 20.0, 38.0]:
			var mean := deg_to_rad(mean_deg)
			# A left turn (+): the left wheel (x < 0) is the inner one.
			var inner := WheelDriveScript.ackermann_angle(mean, -SEDAN_HALF_TRACK, SEDAN_L, f)
			var outer := WheelDriveScript.ackermann_angle(mean, SEDAN_HALF_TRACK, SEDAN_L, f)
			assert_float(inner).is_greater(mean)
			assert_float(outer).is_less(mean)
			# Mirrored: a right turn swaps the wheels.
			assert_float(WheelDriveScript.ackermann_angle(-mean, SEDAN_HALF_TRACK, SEDAN_L, f)) \
					.is_equal_approx(-inner, 1e-6)
			assert_float(WheelDriveScript.ackermann_angle(-mean, -SEDAN_HALF_TRACK, SEDAN_L, f)) \
					.is_equal_approx(-outer, 1e-6)
			assert_float((1.0 / tan(inner) + 1.0 / tan(outer)) / 2.0).is_equal_approx(
					1.0 / tan(mean), 1e-5)

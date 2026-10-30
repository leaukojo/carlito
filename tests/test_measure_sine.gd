extends GdUnitTestSuite
## measure_vehicles' sine-with-dwell pass, its pure parts: the steer profile, the series on A and a
## run's verdict (FMVSS 126 S5.2 / S7.9, `docs/sources.md` § Stability control).

const Measure := preload("res://tools/measure_vehicles.gd")
const TICK := 1.0 / 60.0


func test_the_steer_is_a_sine_to_its_second_peak_a_dwell_then_back_to_zero() -> void:
	var quarter := 0.25 / Measure.SINE_HZ
	assert_float(Measure.sine_dwell_steer(0.0, 0.5)).is_equal(0.0)
	assert_float(Measure.sine_dwell_steer(quarter, 0.5)).is_equal_approx(0.5, 1e-6)
	assert_float(Measure.sine_dwell_steer(3.0 * quarter + 0.01, 0.5)).is_equal_approx(-0.5, 1e-6)
	assert_float(Measure.sine_dwell_steer(3.0 * quarter + Measure.SINE_DWELL_S - 0.01, 0.5)) \
			.is_equal_approx(-0.5, 1e-6)
	# Continuous at the dwell's end, back to 0 when the steer completes, 0 after.
	assert_float(Measure.sine_dwell_steer(3.0 * quarter + Measure.SINE_DWELL_S + 1e-4, 0.5)) \
			.is_equal_approx(-0.5, 1e-3)
	assert_float(Measure.sine_dwell_steer(Measure.sine_steer_end() - 1e-4, 0.5)) \
			.is_equal_approx(0.0, 1e-3)
	assert_float(Measure.sine_dwell_steer(Measure.sine_steer_end() + 0.5, 0.5)).is_equal(0.0)


func test_the_series_steps_half_a_to_six_and_a_half_a_left_then_right() -> void:
	var runs := Measure.sine_series(0.2)
	assert_float(runs[0]["k"]).is_equal(Measure.SINE_FIRST_A)
	assert_float(runs[0]["dir"]).is_equal(-1.0)
	assert_float(runs[1]["dir"]).is_equal(1.0)
	assert_float(runs[2]["k"]).is_equal(Measure.SINE_FIRST_A + Measure.SINE_STEP_A)
	# 6.5 x 0.2 passes full lock: the series ends at the first run that reaches it, capped.
	var last: Dictionary = runs[runs.size() - 1]
	assert_float(last["amp"]).is_equal(1.0)
	assert_float(last["k"]).is_equal(5.0)


func test_a_small_a_runs_on_to_the_lock_floor() -> void:
	# 6.5 x 0.05 is 0.325 of lock: the series runs on until k A reaches SINE_MIN_LOCK.
	var runs := Measure.sine_series(0.05)
	var last: Dictionary = runs[runs.size() - 1]
	assert_float(last["k"] * 0.05).is_greater_equal(Measure.SINE_MIN_LOCK - 1e-6)
	assert_float((runs[runs.size() - 3] as Dictionary)["k"] * 0.05).is_less(Measure.SINE_MIN_LOCK)
	assert_array(Measure.sine_series(0.0)).is_empty()


## A yaw trace: the second lobe's peak `peak` (rad/s, to the right for a left-first run) at the
## dwell, then `tail` of it from the steer's end on.
static func _trace(peak: float, tail: float) -> PackedFloat32Array:
	var yaw := PackedFloat32Array()
	var end := Measure.sine_steer_end()
	for i in roundi((end + 2.0) / TICK):
		var t := (i + 1) * TICK
		var r := 0.0
		if t < 0.5 / Measure.SINE_HZ:
			r = -0.3  # the first lobe, to the left
		elif t <= end:
			r = peak
		else:
			r = peak * tail
		yaw.append(r)
	return yaw


func test_a_yaw_that_dies_away_passes_and_one_that_holds_fails() -> void:
	var v := Measure.sine_verdict(_trace(0.5, 0.1), TICK, -1.0, 2.0, NAN, 1500.0)
	assert_float(v["peak"]).is_equal_approx(0.5, 1e-6)
	assert_float(v["r1"]).is_equal_approx(0.1, 1e-6)
	assert_bool(v["ok"]).is_true()
	assert_bool(v["disp_judged"]).is_false()
	assert_bool(Measure.sine_verdict(_trace(0.5, 0.3), TICK, -1.0, 2.0, NAN, 1500.0)["ok"]).is_false()


func test_the_displacement_is_judged_from_five_a_against_the_mass_gate() -> void:
	var yaw := _trace(0.5, 0.0)
	assert_bool(Measure.sine_verdict(yaw, TICK, -1.0, 5.0, 1.9, 1500.0)["ok"]).is_true()
	assert_bool(Measure.sine_verdict(yaw, TICK, -1.0, 5.0, 1.7, 1500.0)["ok"]).is_false()
	# Over SINE_LIGHT_KG the gate is the lower one.
	assert_bool(Measure.sine_verdict(yaw, TICK, -1.0, 5.0, 1.7, 4000.0)["ok"]).is_true()
	assert_bool(Measure.sine_verdict(yaw, TICK, -1.0, 4.5, 0.5, 1500.0)["ok"]).is_true()

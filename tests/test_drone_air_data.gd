extends GdUnitTestSuite
## Drone barometer: ISA solve, labelled errors in baro_alt vs altitude/agl.

const A := preload("res://src/vehicles/drone/drone_air_data.gd")

# --- the standard atmosphere --------------------------------------------------

func test_a_standard_day_at_sea_level_solves_to_zero() -> void:
	assert_float(A.pressure_at(0.0, A.QNH_STANDARD)).is_equal_approx(A.QNH_STANDARD, 1e-6)
	assert_float(A.altitude_from(A.QNH_STANDARD, A.QNH_STANDARD)).is_equal_approx(0.0, 1e-6)


func test_the_solve_round_trips_over_the_whole_flight_envelope() -> void:
	# 0 to 500 m covers the contract's own `altitude` range, which is the only altitude band
	# either aircraft can reach.
	for h in [0.0, 12.5, 120.0, 300.0, 500.0]:
		var p := A.pressure_at(h, A.QNH_STANDARD)
		assert_float(A.altitude_from(p, A.QNH_STANDARD)).is_equal_approx(h, 1e-3)


func test_pressure_falls_with_height_at_about_the_textbook_rate() -> void:
	# ~12 Pa per metre near sea level is the number a pilot carries in their head (1 hPa per
	# 27 ft), and it is what makes an 8 hPa QNH error worth ~70 m.
	var drop := A.pressure_at(0.0, A.QNH_STANDARD) - A.pressure_at(100.0, A.QNH_STANDARD)
	assert_float(drop).is_between(1100.0, 1300.0)


func test_degenerate_inputs_return_zero_rather_than_nan() -> void:
	# A NaN altitude reaches the readout line and the bus, where it is far worse than a wrong
	# number: it is a number nothing downstream can even render.
	assert_float(A.altitude_from(0.0, A.QNH_STANDARD)).is_equal(0.0)
	assert_float(A.altitude_from(A.QNH_STANDARD, 0.0)).is_equal(0.0)
	assert_float(A.pressure_at(1e9, A.QNH_STANDARD)).is_equal(0.0)

# --- error 1: the subscale is wrong -------------------------------------------

func test_the_sea_level_pressure_drifts_around_the_standard_day() -> void:
	# One sine, deterministic and seedless: two sessions read the same number at the same second,
	# which is what makes it checkable against a decoder at all.
	assert_float(A.sea_level_pressure(0.0)).is_equal_approx(A.QNH_STANDARD, 1e-6)
	var quarter := A.sea_level_pressure(A.DRIFT_PERIOD * 0.25)
	assert_float(quarter).is_equal_approx(A.QNH_STANDARD + A.DRIFT_PA, 1e-3)
	var three_quarter := A.sea_level_pressure(A.DRIFT_PERIOD * 0.75)
	assert_float(three_quarter).is_equal_approx(A.QNH_STANDARD - A.DRIFT_PA, 1e-3)
	# It really does turn around inside one flight rather than wandering off.
	assert_float(A.sea_level_pressure(A.DRIFT_PERIOD)).is_equal_approx(A.QNH_STANDARD, 1e-3)


func test_a_low_pressure_day_makes_the_altimeter_read_HIGH() -> void:
	# The sign is what this pins, and it is the one a pilot is taught as "high to low, look out
	# below". The air is at a LOWER sea-level pressure than the subscale assumes, so the
	# measured pressure looks like more height than there is.
	var truth := 100.0
	var low_day := A.QNH_STANDARD - A.DRIFT_PA
	var indicated := A.altitude_from(A.pressure_at(truth, low_day), A.QNH_STANDARD)
	assert_float(indicated).is_greater(truth)
	# ...and a high-pressure day reads low, by about the same amount.
	var high_day := A.QNH_STANDARD + A.DRIFT_PA
	assert_float(A.altitude_from(A.pressure_at(truth, high_day), A.QNH_STANDARD)).is_less(truth)


func test_the_standing_offset_is_worth_a_readable_number_of_metres() -> void:
	# Big enough to see beside the GPS on the same line, small enough not to read as a broken
	# instrument. If DRIFT_PA moves, this is the check that says what it bought.
	var err := A.altitude_from(A.pressure_at(0.0, A.QNH_STANDARD - A.DRIFT_PA), A.QNH_STANDARD)
	assert_float(err).is_between(5.0, 12.0)

# --- error 2: the static port is on a moving aircraft -------------------------

func test_the_port_under_reads_and_never_over_reads() -> void:
	# Position error is a REAL named effect and it has one sign: a port in the airflow reads
	# less than true static, so the correction can only ever be negative.
	assert_float(A.port_error_pa(0.0)).is_equal(0.0)
	assert_float(A.port_error_pa(15.0)).is_less(0.0)
	assert_float(A.port_error_pa(-15.0)).is_less(0.0)


func test_the_port_error_goes_with_the_SQUARE_of_airspeed() -> void:
	# Which is what makes the gap MOVE rather than sit still: doubling the speed quadruples it.
	var v10 := A.port_error_pa(10.0)
	assert_float(A.port_error_pa(20.0)).is_equal_approx(v10 * 4.0, 1e-4)


func test_flying_faster_makes_the_barometer_read_higher() -> void:
	# The two errors compose in the direction they should: less measured pressure is more
	# indicated height, so accelerating into the wind walks the reading UP.
	var still := A.altitude_from(A.pressure_at(50.0, A.QNH_STANDARD), A.QNH_STANDARD)
	var moving := A.altitude_from(
			A.pressure_at(50.0, A.QNH_STANDARD) + A.port_error_pa(15.0), A.QNH_STANDARD)
	assert_float(moving).is_greater(still)
	# A few metres at 15 m/s — visible on the readout line, not a cliff.
	assert_float(moving - still).is_between(2.0, 12.0)

# --- the temperature ----------------------------------------------------------

func test_oat_is_the_isa_lapse_and_nothing_else() -> void:
	assert_float(A.oat_c(0.0)).is_equal_approx(15.0, 1e-6)
	# 6.5 degrees per kilometre climbed.
	assert_float(A.oat_c(1000.0)).is_equal_approx(8.5, 1e-6)
	assert_float(A.oat_c(120.0)).is_equal_approx(15.0 - 0.78, 1e-6)

extends GdUnitTestSuite
## BrakeThermal: the lumped brake heat law and the fade curves, pure statics. The whole-body
## energy check (a stop's energy landing in the brakes) is `measure_grade`'s, on a live body.

const TICK := 1.0 / 60.0
const AMB := BrakeThermal.AMBIENT_C


## The saloon's front disc (`docs/sources.md` § Brake heat), radiation on or off.
static func _disc(radiate := true) -> BrakeThermal.Figures:
	return BrakeThermal.Figures.new(4020.0, 0.99, 0.25, 0.82 if radiate else 0.0, 0.124,
			BrakeThermal.FadeCurve.PAD)


## Heat capacity only: every loss term off.
static func _adiabatic() -> BrakeThermal.Figures:
	return BrakeThermal.Figures.new(4020.0)


static func _run(temp: float, power: float, speed: float, delta: float, steps: int,
		f: BrakeThermal.Figures) -> float:
	for i in steps:
		temp = BrakeThermal.step(temp, power, speed, delta, f)
	return temp


# --- heat in ------------------------------------------------------------------------------------

func test_with_no_losses_the_heat_in_is_c_delta_t_at_any_step_size() -> void:
	var f := _adiabatic()
	var energy := 0.0
	var temp := AMB
	# 30 kW for 10 s at 60 Hz, then 5 kW over one 7 s step: 335 kJ.
	temp = _run(temp, 30000.0, 20.0, TICK, 600, f)
	energy += 30000.0 * TICK * 600
	temp = BrakeThermal.step(temp, 5000.0, 20.0, 7.0, f)
	energy += 5000.0 * 7.0
	assert_float(f.capacity * (temp - AMB)).is_equal_approx(energy, 1e-3)


func test_zero_power_heats_nothing() -> void:
	assert_float(_run(AMB, 0.0, 30.0, TICK, 600, _disc())).is_equal(AMB)
	assert_float(_run(AMB, 0.0, 0.0, TICK, 600, _adiabatic())).is_equal(AMB)


func test_at_ambient_both_loss_terms_are_zero() -> void:
	for speed in [0.0, 10.0, 40.0]:
		assert_float(BrakeThermal.loss_w(AMB, speed, _disc())).is_equal_approx(0.0, 1e-9)


func test_no_thermal_model_stays_at_ambient_and_never_fades() -> void:
	var none := BrakeThermal.Figures.new()
	assert_float(_run(AMB, 50000.0, 20.0, TICK, 600, none)).is_equal(AMB)
	assert_float(BrakeThermal.fade_factor(900.0, none)).is_equal(1.0)


# --- cooling ------------------------------------------------------------------------------------

func test_cooling_decays_toward_ambient_and_never_past_it() -> void:
	for radiate in [false, true]:
		for speed in [0.0, 25.0]:
			var f := _disc(radiate)
			var temp := 500.0
			var last := temp
			for i in 3600:
				temp = BrakeThermal.step(temp, 0.0, speed, 1.0, f)
				assert_bool(temp < last and temp >= AMB).is_true()
				last = temp


func test_one_huge_cooling_step_lands_on_ambient_not_below() -> void:
	assert_float(BrakeThermal.step(600.0, 0.0, 30.0, 1e6, _disc())).is_equal(AMB)


func test_speed_and_radiation_each_cool_faster() -> void:
	var still := _run(400.0, 0.0, 0.0, 1.0, 300, _disc(false))
	var moving := _run(400.0, 0.0, 25.0, 1.0, 300, _disc(false))
	var radiating := _run(400.0, 0.0, 0.0, 1.0, 300, _disc(true))
	assert_float(moving).is_less(still)
	assert_float(radiating).is_less(still)


func test_radiation_reads_kelvin() -> void:
	var f := BrakeThermal.Figures.new(4020.0, 0.0, 0.0, 1.0, 1.0)
	var t_k := 400.0 + 273.15
	var a_k := AMB + 273.15
	var expected := 5.670374419e-8 * (pow(t_k, 4.0) - pow(a_k, 4.0))
	assert_float(BrakeThermal.loss_w(400.0, 0.0, f)).is_equal_approx(expected, 1e-6)


# --- fade ---------------------------------------------------------------------------------------

func test_factor_is_one_below_the_first_point() -> void:
	var f := _disc()
	assert_float(BrakeThermal.fade_factor(AMB, f)).is_equal(1.0)
	assert_float(BrakeThermal.fade_factor(400.0, f)).is_equal(1.0)


func test_factor_is_linear_between_points() -> void:
	var f := _disc()
	# Halfway along PAD's (400, 1.0) -> (465, 0.86) and (615, 0.86) -> (750, 0.5).
	assert_float(BrakeThermal.fade_factor(432.5, f)).is_equal_approx(0.93, 1e-5)
	assert_float(BrakeThermal.fade_factor(540.0, f)).is_equal_approx(0.86, 1e-5)
	assert_float(BrakeThermal.fade_factor(682.5, f)).is_equal_approx(0.68, 1e-5)


func test_factor_is_flat_past_the_last_point() -> void:
	var f := _disc()
	assert_float(BrakeThermal.fade_factor(750.0, f)).is_equal_approx(0.5, 1e-6)
	assert_float(BrakeThermal.fade_factor(2000.0, f)).is_equal_approx(0.5, 1e-6)


func test_every_curve_stays_in_range_and_never_rises() -> void:
	for curve in [BrakeThermal.FadeCurve.PAD, BrakeThermal.FadeCurve.RACE,
			BrakeThermal.FadeCurve.DRUM, BrakeThermal.FadeCurve.WET]:
		var f := BrakeThermal.Figures.new(1.0, 0.0, 0.0, 0.0, 0.0, curve)
		var last := 1.0
		for t in range(0, 1200, 5):
			var k := BrakeThermal.fade_factor(float(t), f)
			assert_bool(k > 0.0 and k <= last).is_true()
			last = k

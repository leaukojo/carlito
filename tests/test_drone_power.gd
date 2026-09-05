extends GdUnitTestSuite
## 4S LiPo pack: OCV/IR/thermal laws, envelope vs contract, endurance arithmetic pins
## to constants. Pack currents are real (from ESC model), so retuning thrust knobs
## moves the suite with it.

const D := preload("res://src/vehicles/drone/drone.gd")  ## the @export knobs _knob() reads
const Prop := preload("res://src/vehicles/drone/drone_propulsion.gd")
const P := preload("res://src/vehicles/drone/drone_power.gd")
const ContractScript := preload("res://src/bridge/contract.gd")

const DELTA := 1.0 / 60.0


# --- helpers: the real envelope, read off the drone rather than restated -----------

## A drone @export knob's authored default (test_drone.gd's helper, same reason: an envelope
## gate carrying its own copy of climb_force keeps passing after a retune moves it).
func _knob(knob: String) -> float:
	var script: Script = D
	return float(script.get_property_default_value(knob))


## One ESC's current (A) at a mixer demand — mix_quad_x clamps the summed demand and takes
## its sqrt, which is the motor SPEED the current model wants.
func _esc_amps(demand: float) -> float:
	return Prop.esc_current_a(sqrt(clampf(demand, 0.0, 1.0)), Prop.ROTOR_MAX_RPM, _knob("max_thrust"),
			_knob("prop_torque_ratio"), Prop.ESC_PACK_VOLTS, Prop.ESC_ETA, Prop.ESC_I_NOLOAD)


## Total pack current (A) with all four motors at the same demand.
func _pack_amps(demand: float) -> float:
	var amps := PackedFloat32Array()
	amps.resize(Prop.MOTORS.size())
	amps.fill(_esc_amps(demand))
	return P.pack_current_a(amps, P.AVIONICS_A)


## The three demands the header's arithmetic is written against.
func _hover_demand() -> float:
	var spec: Resource = load("res://src/vehicles/drone/drone_spec.tres")
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	return spec.mass * gravity / _knob("max_thrust")


func _climb_demand() -> float:
	var spec: Resource = load("res://src/vehicles/drone/drone_spec.tres")
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	return (spec.mass * gravity + _knob("climb_force")) / _knob("max_thrust")


## Minutes of flight at a steady pack current.
func _endurance_min(amps: float) -> float:
	return 60.0 * P.PACK_CAPACITY_AH / amps


## The steady state a pack temperature settles at — tau 0 collapses the lag to its target.
func _settled(amps: float) -> float:
	return P.pack_temp_step(0.0, amps, P.PACK_AMBIENT, P.PACK_TEMP_K, 0.0, DELTA)


# --- pack_ocv: the curve ----------------------------------------------------------

func test_pack_ocv_hits_the_quoted_4s_endpoints() -> void:
	# The two numbers a 4S LiPo is sold by: 16.8 V full, 12.6 V empty.
	assert_float(P.pack_ocv(100.0)).is_equal_approx(16.8, 1e-4)
	assert_float(P.pack_ocv(0.0)).is_equal_approx(12.6, 1e-4)
	# And the nominal it is LABELLED by sits on the curve, not beside it.
	assert_float(P.pack_ocv(20.0)).is_equal_approx(4.0 * 3.70, 1e-4)


func test_pack_ocv_interpolates_between_table_points() -> void:
	# Halfway between the 40 % and 60 % rows is halfway between their cell voltages.
	assert_float(P.pack_ocv(50.0)).is_equal_approx(P.CELLS * (3.79 + 3.87) * 0.5, 1e-4)


func test_pack_ocv_clamps_instead_of_extrapolating() -> void:
	# Out-of-range soc pins to the table: no chemistry has a 4.6 V cell.
	assert_float(P.pack_ocv(140.0)).is_equal_approx(P.pack_ocv(100.0), 1e-6)
	assert_float(P.pack_ocv(-40.0)).is_equal_approx(P.pack_ocv(0.0), 1e-6)


func test_pack_ocv_rises_monotonically_with_charge() -> void:
	# A curve that dipped anywhere would make the volts bar walk backwards during a discharge.
	var prev := P.pack_ocv(0.0)
	for i in range(1, 101):
		var v := P.pack_ocv(float(i))
		assert_float(v).override_failure_message("OCV fell between %d %% and %d %%" % [i - 1, i]) \
			.is_greater_equal(prev)
		prev = v


func test_pack_ocv_has_the_lipo_knee_not_a_straight_line() -> void:
	# The SHAPE the desc promises and the reason `soc` exists as its own signal: the top 80 %
	# of the charge spends less voltage than the bottom 20 % does. A linear model cannot.
	var shoulder := P.pack_ocv(100.0) - P.pack_ocv(20.0)
	var knee := P.pack_ocv(20.0) - P.pack_ocv(0.0)
	assert_float(knee).override_failure_message("the last 20 %% should cost more volts than the first 80") \
		.is_greater(shoulder)


# --- pack_volts: the sag ----------------------------------------------------------

func test_pack_volts_with_no_load_is_the_open_circuit_curve() -> void:
	assert_float(P.pack_volts(75.0, 0.0, P.PACK_R_INTERNAL)).is_equal_approx(P.pack_ocv(75.0), 1e-6)


func test_pack_volts_sags_by_exactly_i_times_r() -> void:
	var expected: float = P.pack_ocv(100.0) - 150.0 * P.PACK_R_INTERNAL
	assert_float(P.pack_volts(100.0, 150.0, P.PACK_R_INTERNAL)).is_equal_approx(expected, 1e-5)


func test_pack_volts_never_goes_negative() -> void:
	# A dead short is not a negative voltage; publishing 0 is the truer floor.
	assert_float(P.pack_volts(0.0, 100000.0, P.PACK_R_INTERNAL)).is_equal(0.0)


func test_pack_volts_ignores_a_negative_current_rather_than_charging() -> void:
	# The quad has no regeneration, so a negative current is nonsense input, not a charge.
	assert_float(P.pack_volts(50.0, -200.0, P.PACK_R_INTERNAL)).is_equal_approx(P.pack_ocv(50.0), 1e-6)


# --- pack_current_a: the sum of models --------------------------------------------

func test_pack_current_is_the_four_escs_plus_avionics() -> void:
	var amps := PackedFloat32Array([10.0, 11.0, 12.0, 13.0])
	assert_float(P.pack_current_a(amps, P.AVIONICS_A)).is_equal_approx(46.0 + P.AVIONICS_A, 1e-5)


func test_pack_current_with_no_motors_is_still_the_avionics_floor() -> void:
	# The flight controller draws its amps whether the props turn or not.
	assert_float(P.pack_current_a(PackedFloat32Array(), P.AVIONICS_A)).is_equal_approx(P.AVIONICS_A, 1e-6)


# --- soc_step: coulomb counting ---------------------------------------------------

func test_soc_step_counts_coulombs_at_the_stated_rate() -> void:
	# One hour at exactly the capacity in amps empties the pack: 10 A out of a 10 Ah pack for
	# 3600 s is 100 %. Checked as one big step so the arithmetic is hand-verifiable.
	assert_float(P.soc_step(100.0, P.PACK_CAPACITY_AH, P.PACK_CAPACITY_AH, 3600.0)) \
		.is_equal_approx(0.0, 1e-4)
	assert_float(P.soc_step(100.0, P.PACK_CAPACITY_AH, P.PACK_CAPACITY_AH, 1800.0)) \
		.is_equal_approx(50.0, 1e-4)


func test_soc_step_only_ever_falls() -> void:
	# No regeneration: a negative current must not put charge back in.
	assert_float(P.soc_step(40.0, -500.0, P.PACK_CAPACITY_AH, 1.0)).is_equal_approx(40.0, 1e-6)


func test_soc_step_clamps_at_empty() -> void:
	assert_float(P.soc_step(0.5, 300.0, P.PACK_CAPACITY_AH, 60.0)).is_equal(0.0)


func test_soc_step_survives_a_degenerate_pack() -> void:
	# A pack that holds nothing simply never discharges, rather than dividing by zero.
	assert_float(P.soc_step(70.0, 100.0, 0.0, DELTA)).is_equal_approx(70.0, 1e-6)
	assert_float(P.soc_step(70.0, 100.0, P.PACK_CAPACITY_AH, 0.0)).is_equal_approx(70.0, 1e-6)


func test_soc_step_integrates_the_same_charge_whatever_the_tick() -> void:
	# The accumulator is linear in delta, so 600 ticks of 1/60 s equal one 10 s step. That is
	# what makes the endurance arithmetic below independent of the physics rate.
	var fine := 100.0
	for _i in 600:
		fine = P.soc_step(fine, 120.0, P.PACK_CAPACITY_AH, DELTA)
	assert_float(fine).is_equal_approx(P.soc_step(100.0, 120.0, P.PACK_CAPACITY_AH, 10.0), 1e-3)


# --- pack_temp_step: the first-order lag ------------------------------------------

func test_pack_temp_converges_to_its_target_without_overshooting() -> void:
	var target := P.PACK_AMBIENT + P.PACK_TEMP_K * 200.0 * 200.0
	var t := P.PACK_AMBIENT
	for _i in 60 * 600:  # ten minutes at 60 Hz
		t = P.pack_temp_step(t, 200.0, P.PACK_AMBIENT, P.PACK_TEMP_K, P.PACK_TEMP_TAU, DELTA)
		assert_float(t).is_less_equal(target + 1e-4)
	assert_float(t).is_equal_approx(target, 0.1)


func test_pack_temp_cools_back_toward_ambient_with_the_same_step() -> void:
	# Heating and cooling are one expression; which way it moves is only which side it started.
	var t := 80.0
	for _i in 60 * 600:
		t = P.pack_temp_step(t, 0.0, P.PACK_AMBIENT, P.PACK_TEMP_K, P.PACK_TEMP_TAU, DELTA)
	assert_float(t).is_equal_approx(P.PACK_AMBIENT, 0.1)


func test_pack_temp_lags_further_behind_than_the_escs() -> void:
	# The pack has three times the ESC time constant, so after the same second of the same
	# current it must have moved LESS of the way toward its (identical-shape) target.
	var pack_rise := P.pack_temp_step(P.PACK_AMBIENT, 150.0, P.PACK_AMBIENT, P.PACK_TEMP_K,
			P.PACK_TEMP_TAU, 1.0) - P.PACK_AMBIENT
	var esc_rise := Prop.esc_temp_step(P.PACK_AMBIENT, 150.0, P.PACK_AMBIENT, P.PACK_TEMP_K,
			Prop.ESC_TEMP_TAU, 1.0) - P.PACK_AMBIENT
	assert_float(pack_rise).is_less(esc_rise)


func test_pack_temp_step_survives_a_degenerate_lag() -> void:
	var target := P.PACK_AMBIENT + P.PACK_TEMP_K * 100.0 * 100.0
	assert_float(P.pack_temp_step(0.0, 100.0, P.PACK_AMBIENT, P.PACK_TEMP_K, 0.0, DELTA)) \
		.is_equal_approx(target, 1e-4)


# --- the envelope: every reachable value stays on its own bar ----------------------

## The regression gate for the ranges, the pack's counterpart to test_drone's ESC version.
## The binding case is the same one: mix_quad_x clamps each motor's summed demand to [0, 1],
## so ALL FOUR pinned is a state the craft can really reach (a hover plus a full lean and a
## yaw gets one there), and every model here is monotone in current — a fit at the clamp fits
## everywhere below it. A retune of the thrust knobs, PACK_R_INTERNAL or PACK_TEMP_K that puts
## a signal off the scale it is published on fails here rather than on the bus.
func test_the_pack_models_stay_inside_their_contract_ranges() -> void:
	var volts := Contract.data.get_signal_def("battery", "out")
	var cur := Contract.data.get_signal_def("pack_current", "out")
	var temp := Contract.data.get_signal_def("pack_temp", "out")
	assert_int(volts.range.size()).is_equal(2)
	assert_int(cur.range.size()).is_equal(2)
	assert_int(temp.range.size()).is_equal(2)

	var pinned := _pack_amps(1.0)
	assert_float(pinned) \
		.override_failure_message("four pinned motors draw %.1f A, past the contract's %.0f A top" % [
			pinned, cur.range[1]]) \
		.is_between(float(cur.range[0]), float(cur.range[1]))

	# The WORST voltage the craft can reach: an empty pack with every motor at the clamp.
	# This corner is the whole reason the range bottom is 9 V rather than 12.6.
	var worst: float = P.pack_volts(0.0, pinned, P.PACK_R_INTERNAL)
	assert_float(worst) \
		.override_failure_message("an empty pack at full load sags to %.2f V, under the contract's %.0f V floor" % [
			worst, volts.range[0]]) \
		.is_greater_equal(float(volts.range[0]))
	# ...and the best: a pack straight off the charger, at rest.
	assert_float(P.pack_ocv(100.0)) \
		.override_failure_message("a full pack reads past the contract's volts top") \
		.is_less_equal(float(volts.range[1]))

	# The temperature is the one model allowed a slow approach, but its SETTLED worst case must
	# still be on the bar — unlike the ESCs, the pack is big enough that a pinned craft would
	# genuinely sit there long enough to get to it.
	assert_float(_settled(pinned)) \
		.override_failure_message("four pinned motors settle the pack at %.0f degC, past its %.0f top" % [
			_settled(pinned), temp.range[1]]) \
		.is_less_equal(float(temp.range[1]))


## The volts warn must stay a LOW-side threshold: a flat battery, never an over-voltage.
## Declared as `warn_side` in the contract, so widening the range no longer changes it.
func test_the_volts_warn_reads_as_a_low_side_danger() -> void:
	var volts := Contract.data.get_signal_def("battery", "out")
	assert_bool(volts.has_warn()).is_true()
	assert_bool(volts.warn_is_low()).is_true()
	# And it must sit below anything an ENGINED vehicle publishes, or every car warns at idle.
	assert_float(volts.warn).is_less(VehicleTelemetry.BATTERY_RESTING)


func test_the_soc_and_pack_temp_warns_read_the_right_way_round() -> void:
	var soc := Contract.data.get_signal_def("soc", "out")
	var temp := Contract.data.get_signal_def("pack_temp", "out")
	assert_bool(soc.warn_is_low()).override_failure_message("low charge must warn low").is_true()
	assert_bool(temp.warn_is_low()).override_failure_message("a hot pack must warn high").is_false()


## All three pack signals must render, or a sagging pack is invisible and nothing a pilot
## can see has shipped. The dashboard generates a bar for an "out" signal that has
## a range AND is either warn'd or flavored — so this is really a check that the metadata was
## written to be seen, not just to be published.
func test_the_pack_signals_are_all_dashboard_bars() -> void:
	for sig_name in ["battery", "pack_current", "soc", "pack_temp"]:
		var sig := Contract.data.get_signal_def(sig_name, "out")
		assert_object(sig).override_failure_message("missing '%s'" % sig_name).is_not_null()
		assert_int(sig.range.size()) \
			.override_failure_message("'%s' has no range, so it renders no bar" % sig_name).is_equal(2)
		assert_bool(sig.has_warn() or sig.flavor != "") \
			.override_failure_message("'%s' is neither warn'd nor flavored, so it renders no bar" % sig_name) \
			.is_true()


## Rule 4, the drone half: an electric aircraft has no fuel gauge, and `soc` is what it has
## instead. This is a contract assertion rather than a code one because the temptation is a
## contract edit — adding "drone" to the `fuel` vehicles list would light a fuel bar on a
## battery-electric craft.
func test_the_drone_declares_soc_and_never_fuel() -> void:
	var out_names := Contract.data.signals_for_vehicle("drone", "out").map(
			func(s: ContractScript.SignalDef) -> String: return s.name)
	assert_array(out_names).contains(["battery", "pack_current", "soc", "pack_temp"])
	assert_array(out_names).not_contains(["fuel"])


# --- the sizing: the header's arithmetic, recomputed ------------------------------

## The endurance gate. drone_power.gd's header states three flight times and derives
## PACK_CAPACITY_AH from the first of them; this recomputes all three from the constants and
## the real ESC model, so a retune of the thrust knobs or the capacity that quietly moves the
## endurance fails here instead of leaving a header that lies.
func test_a_level_hover_lasts_about_ten_real_minutes() -> void:
	var hover := _pack_amps(_hover_demand())
	assert_float(hover) \
		.override_failure_message("hover draws %.1f A, not the ~61 A the header sizes the pack from" % hover) \
		.is_between(55.0, 68.0)
	var minutes := _endurance_min(hover)
	assert_float(minutes) \
		.override_failure_message("a level hover lasts %.1f min, not roughly the ten asked for" % minutes) \
		.is_between(9.0, 11.0)


func test_an_aggressive_flight_lasts_noticeably_less_than_a_hover() -> void:
	var hover := _endurance_min(_pack_amps(_hover_demand()))
	var climb := _endurance_min(_pack_amps(_climb_demand()))
	var pinned := _endurance_min(_pack_amps(1.0))
	# "Noticeably less" is given teeth: holding the climb stick must cost at least half the
	# endurance, and flying it at the mixer's clamp at least three quarters.
	assert_float(climb) \
		.override_failure_message("a full climb lasts %.1f min against a %.1f min hover — not noticeably less" % [
			climb, hover]) \
		.is_less(hover * 0.5)
	assert_float(pinned).is_less(hover * 0.25)
	# ...and none of it is so short that the craft cannot be flown anywhere.
	assert_float(pinned).is_greater(1.0)


## The sag gate, and the one requirement about what a pilot sees rather than what the
## bus carries: punching out of a hover to a full climb must move the volts bar enough to be
## read as a dip. Measured as a fraction of the bar's own span, because that is what the eye
## actually sees — the same voltage on a wider bar would be a smaller dip.
func test_a_punch_out_visibly_dips_the_volts_bar() -> void:
	var volts := Contract.data.get_signal_def("battery", "out")
	var span: float = float(volts.range[1]) - float(volts.range[0])
	var hover_v := P.pack_volts(100.0, _pack_amps(_hover_demand()), P.PACK_R_INTERNAL)
	var climb_v := P.pack_volts(100.0, _pack_amps(_climb_demand()), P.PACK_R_INTERNAL)
	var dip := (hover_v - climb_v) / span
	assert_float(dip) \
		.override_failure_message("a punch-out moves the volts bar %.1f %% of its span — not a visible dip" % (
			dip * 100.0)) \
		.is_greater(0.10)
	# And it is a DIP, not a step: centring the stick returns the bar, because the IR term has
	# no memory. Only the (far slower) coulomb count is left behind.
	assert_float(P.pack_volts(100.0, _pack_amps(_hover_demand()), P.PACK_R_INTERNAL)) \
		.is_equal_approx(hover_v, 1e-6)


## The pack temperature's tuning is the SHAPE its desc promises, not merely a number inside
## the range: cool at a hover, warm but unwarned at a sustained climb, and only genuinely hard
## flying crosses the warn. Same gate, same reasoning, as the ESC envelope test.
func test_the_pack_temperature_is_tuned_on_the_envelope_not_the_hover() -> void:
	var temp := Contract.data.get_signal_def("pack_temp", "out")
	assert_float(_settled(_pack_amps(_hover_demand()))) \
		.override_failure_message("a hover should sit near ambient, nowhere near the warn") \
		.is_between(P.PACK_AMBIENT, P.PACK_AMBIENT + 10.0)
	assert_float(_settled(_pack_amps(_climb_demand()))) \
		.override_failure_message("a sustained climb should warm the pack without warning") \
		.is_between(P.PACK_AMBIENT + 10.0, temp.warn)
	assert_float(_settled(_pack_amps(1.0))) \
		.override_failure_message("four pinned motors should cross the warn") \
		.is_greater(temp.warn)

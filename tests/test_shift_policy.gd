extends GdUnitTestSuite
## The shift policy's pure functions (`ShiftPolicy`). Specs are built inline with round numbers so
## every expected gear is hand-checkable; the catalog's no-hunt guard over every shipped body is in
## `test_vehicle_catalog`, the gearbox's state through `process` in `test_drivetrain`.

const DrivetrainScript := preload("res://src/vehicles/base/drivetrain.gd")
const VehicleSpecScript := preload("res://src/vehicles/base/vehicle_spec.gd")

const GEAR_N := 0x00
const GEAR_R := 0xFF
const GEAR_P := 0xFE


## Steps 1.5 / 1.33 / 1.25 / 1.2 / 1.25; up 3500, down 1500 at full pedal; no light pair, kickdown,
## dwell or skip-shifts, so it shifts at its two thresholds.
func _spec() -> VehicleSpecScript:
	var spec: VehicleSpecScript = VehicleSpecScript.new()
	spec.idle_rpm = 800.0
	spec.redline_rpm = 4000.0
	spec.gear_ratios = PackedFloat32Array([3.0, 2.0, 1.5, 1.2, 1.0, 0.8])
	spec.shift_up_rpm = 3500.0
	spec.shift_down_rpm = 1500.0
	return spec


## `_spec` with a light pair: up 2000, down 1000 at and under LIGHT_PEDAL.
func _light_spec() -> VehicleSpecScript:
	var spec := _spec()
	spec.shift_up_light_rpm = 2000.0
	spec.shift_down_light_rpm = 1000.0
	return spec


## The fixed-threshold rule the box ran before the policy, the reference for the defaults.
static func _threshold_rule(spec: VehicleSpecScript, byte: int, at_rpm: float) -> int:
	if at_rpm >= spec.shift_up_rpm and byte < mini(6, spec.gear_ratios.size()):
		return byte + 1
	if at_rpm <= spec.shift_down_rpm and byte > 1:
		return byte - 1
	return byte


# --- the defaults --------------------------------------------------------------------

func test_a_spec_with_no_map_shifts_at_its_two_thresholds_at_any_pedal() -> void:
	var spec := _spec()
	for pedal in [0.0, 0.5, 1.0]:
		for byte in range(1, 7):
			for rpm in range(800, 4001, 50):
				assert_int(ShiftPolicy.next_gear(spec, byte, rpm, pedal, 0.0, false)) \
						.override_failure_message("D%d at %d rpm, pedal %.1f" % [byte, rpm, pedal]) \
						.is_equal(_threshold_rule(spec, byte, rpm))


# --- the map -----------------------------------------------------------------------------

func test_the_map_is_flat_under_the_light_pedal_and_linear_to_the_full_pair() -> void:
	var spec := _light_spec()
	assert_float(ShiftPolicy.up_rpm(spec, 0.0)).is_equal(2000.0)
	assert_float(ShiftPolicy.up_rpm(spec, ShiftPolicy.LIGHT_PEDAL)).is_equal(2000.0)
	# Halfway from LIGHT_PEDAL 0.2 to 1.
	assert_float(ShiftPolicy.up_rpm(spec, 0.6)).is_equal_approx(2750.0, 1e-3)
	assert_float(ShiftPolicy.down_rpm(spec, 0.6)).is_equal_approx(1250.0, 1e-3)
	assert_float(ShiftPolicy.up_rpm(spec, 1.0)).is_equal(3500.0)
	assert_float(ShiftPolicy.down_rpm(spec, 1.0)).is_equal(1500.0)
	assert_float(ShiftPolicy.down_rpm(spec, 0.0)).is_equal(1000.0)


func test_the_landing_floor_raises_a_wide_steps_upshift_point() -> void:
	# Light up 1500 would land D1 > D2 (1.5) at 1000, under 1.1 x the 1200 coast downshift: the
	# point rises to 1.1 x 1200 x 1.5 = 1980, which lands exactly on the margin.
	var spec := _spec()
	spec.shift_up_light_rpm = 1500.0
	spec.shift_down_light_rpm = 1200.0
	var up := ShiftPolicy.upshift_rpm(spec, 1, 0.0)
	assert_float(up).is_equal_approx(1980.0, 1e-3)
	assert_float(up / 1.5).is_equal_approx(ShiftPolicy.LANDING_MARGIN * 1200.0, 1e-3)
	# A narrower step (D4 > D5, 1.2) is raised less: 1.1 x 1200 x 1.2 = 1584.
	assert_float(ShiftPolicy.upshift_rpm(spec, 4, 0.0)).is_equal_approx(1584.0, 1e-2)
	# At full pedal the map's own 3500 clears every step: the launch's points never move.
	for byte in range(1, 6):
		assert_float(ShiftPolicy.upshift_rpm(spec, byte, 1.0)).is_equal(3500.0)


func test_the_landing_floor_never_raises_a_point_past_shift_up() -> void:
	var spec := _spec()
	spec.shift_down_rpm = 2500.0  # 1.1 x 2500 x 1.5 = 4125, past the 3500 upshift
	assert_float(ShiftPolicy.upshift_rpm(spec, 1, 1.0)).is_equal(3500.0)
	# The top gear has no step to land: the map's own point.
	assert_float(ShiftPolicy.upshift_rpm(spec, 6, 1.0)).is_equal(3500.0)
	assert_float(ShiftPolicy.upshift_rpm(_light_spec(), 6, 0.0)).is_equal(2000.0)


func test_a_lifted_pedal_upshifts_and_coasts_down_on_the_light_pair() -> void:
	var spec := _light_spec()
	# 2100 rpm in D3: the lift upshifts (light up 2000), full pedal holds the gear.
	assert_int(ShiftPolicy.next_gear(spec, 3, 2100.0, 0.0, 0.0, false)).is_equal(4)
	assert_int(ShiftPolicy.next_gear(spec, 3, 2100.0, 1.0, 0.0, false)).is_equal(3)
	# 1100 rpm in D3: coasting holds it (down 1000), full pedal downshifts (down 1500).
	assert_int(ShiftPolicy.next_gear(spec, 3, 1100.0, 0.0, 0.0, false)).is_equal(3)
	assert_int(ShiftPolicy.next_gear(spec, 3, 1100.0, 1.0, 0.0, false)).is_equal(2)


# --- skip-shifts ---------------------------------------------------------------------

func test_a_skip_shift_takes_the_ripple_in_one_shift() -> void:
	var spec := _light_spec()
	spec.skip_shifts = true
	# Lifted at 3400 rpm in D2: D3 lands 2550 and D4 2040, both still past their 2000 point; D5
	# lands 1700, under it. One shift, D2 > D5.
	assert_int(ShiftPolicy.next_gear(spec, 2, 3400.0, 0.0, 0.0, false)).is_equal(5)
	spec.skip_shifts = false
	assert_int(ShiftPolicy.next_gear(spec, 2, 3400.0, 0.0, 0.0, false)).is_equal(3)


func test_a_full_pedal_never_skips() -> void:
	var spec := _light_spec()
	spec.skip_shifts = true
	for byte in range(1, 6):
		assert_int(ShiftPolicy.next_gear(spec, byte, spec.shift_up_rpm, 1.0, 0.0, false)) \
				.is_equal(byte + 1)


func test_a_short_box_never_upshifts_past_its_last_ratio_even_skipping() -> void:
	var spec := _light_spec()
	spec.skip_shifts = true
	spec.gear_ratios = PackedFloat32Array([3.0, 2.0, 1.5])
	assert_int(ShiftPolicy.next_gear(spec, 2, 4000.0, 0.0, 0.0, false)).is_equal(3)
	assert_int(ShiftPolicy.next_gear(spec, 3, 4000.0, 0.0, 0.0, false)).is_equal(3)


# --- kickdown ------------------------------------------------------------------------

func test_a_kickdown_arms_only_on_an_upward_crossing() -> void:
	var spec := _spec()
	spec.kickdown_pedal = 0.9
	assert_bool(ShiftPolicy.kickdown_armed(spec, false, 1.0, 0.5)).is_true()   # the stab
	assert_bool(ShiftPolicy.kickdown_armed(spec, false, 1.0, 1.0)).is_false()  # held: no re-arm
	assert_bool(ShiftPolicy.kickdown_armed(spec, true, 1.0, 1.0)).is_true()    # still waiting
	assert_bool(ShiftPolicy.kickdown_armed(spec, true, 0.5, 1.0)).is_false()   # lifted: cancelled
	assert_bool(ShiftPolicy.kickdown_armed(spec, false, 0.8, 0.0)).is_false()  # short of the point
	spec.kickdown_pedal = 0.0
	assert_bool(ShiftPolicy.kickdown_armed(spec, false, 1.0, 0.0)).is_false()  # none declared


func test_a_kickdown_takes_the_lowest_gear_under_the_ceiling_in_one_shift() -> void:
	var spec := _spec()
	# 1600 rpm in D5; the ceiling is min(0.85 x 4000, 3500 / 1.1) = 3182: D1 4800, D2 3200, D3 2400.
	# D5 > D3.
	assert_int(ShiftPolicy.kickdown_target(spec, 5, 1600.0)).is_equal(3)
	assert_int(ShiftPolicy.next_gear(spec, 5, 1600.0, 1.0, 0.0, true)).is_equal(3)
	# In D3 at 2400 nothing lower fits: no shift.
	assert_int(ShiftPolicy.kickdown_target(spec, 3, 2400.0)).is_equal(3)
	assert_int(ShiftPolicy.next_gear(spec, 3, 2400.0, 1.0, 0.0, true)).is_equal(3)


func test_the_kickdown_ceiling_is_the_redlines_share_capped_under_the_upshift() -> void:
	var spec := _spec()
	# 0.85 x 4000 = 3400 sits past 3500 / 1.1 = 3182: the landing margin binds.
	assert_float(ShiftPolicy.kickdown_ceiling_rpm(spec)).is_equal_approx(3500.0 / 1.1, 1e-3)
	# A redline close over the upshift point: EPA's 0.85 x 3600 = 3060 binds.
	spec.redline_rpm = 3600.0
	assert_float(ShiftPolicy.kickdown_ceiling_rpm(spec)).is_equal_approx(3060.0, 1e-3)
	# 1600 rpm in D5 lands D2 at 3200: under the 3182 cap it would not fit, under 3060 neither.
	assert_int(ShiftPolicy.kickdown_target(spec, 5, 1600.0)).is_equal(3)
	# 1500 rpm in D5 lands D2 at 3000, under both.
	assert_int(ShiftPolicy.kickdown_target(spec, 5, 1500.0)).is_equal(2)


func test_a_kickdown_is_spent_only_when_the_policy_reaches_it() -> void:
	var spec := _light_spec()
	spec.shift_dwell_s = 1.0
	# Weighed: the dwell has run and no hard limit came first, whether a lower gear fitted (D5 at
	# 1600) or not (D3 at 2400).
	assert_bool(ShiftPolicy.kickdown_spent(spec, 5, 1600.0, 1.0, 1.0)).is_true()
	assert_bool(ShiftPolicy.kickdown_spent(spec, 3, 2400.0, 1.0, 1.0)).is_true()
	# Still armed: the dwell is running, or the coast line forced a downshift first.
	assert_bool(ShiftPolicy.kickdown_spent(spec, 5, 1600.0, 1.0, 0.5)).is_false()
	assert_bool(ShiftPolicy.kickdown_spent(spec, 5, 1000.0, 1.0, 1.0)).is_false()
	assert_int(ShiftPolicy.forced_gear(spec, 5, 1000.0, 1.0)).is_equal(4)


# --- the dwell -----------------------------------------------------------------------

func test_the_dwell_holds_the_pedal_dependent_shifts() -> void:
	var spec := _light_spec()
	spec.shift_dwell_s = 1.0
	# A light upshift (2500 in D2, pedal 0).
	assert_int(ShiftPolicy.next_gear(spec, 2, 2500.0, 0.0, 0.5, false)).is_equal(2)
	assert_int(ShiftPolicy.next_gear(spec, 2, 2500.0, 0.0, 1.0, false)).is_equal(3)
	# A part-pedal downshift (1200 in D3 at full pedal, over the 1000 coast line).
	assert_int(ShiftPolicy.next_gear(spec, 3, 1200.0, 1.0, 0.5, false)).is_equal(3)
	assert_int(ShiftPolicy.next_gear(spec, 3, 1200.0, 1.0, 1.0, false)).is_equal(2)
	# A kickdown.
	assert_int(ShiftPolicy.next_gear(spec, 5, 1600.0, 1.0, 0.5, true)).is_equal(5)
	assert_int(ShiftPolicy.next_gear(spec, 5, 1600.0, 1.0, 1.0, true)).is_equal(3)


func test_the_dwell_never_holds_a_gear_past_shift_up_or_under_the_coast_line() -> void:
	var spec := _light_spec()
	spec.shift_dwell_s = 1.0
	# A floored launch upshifts at its full-pedal point however soon.
	assert_int(ShiftPolicy.next_gear(spec, 1, 3500.0, 1.0, 0.0, false)).is_equal(2)
	# A stop steps down at the coast line however soon.
	assert_int(ShiftPolicy.next_gear(spec, 3, 1000.0, 0.0, 0.0, false)).is_equal(2)
	assert_bool(ShiftPolicy.dwelling(spec, 0.99)).is_true()
	assert_bool(ShiftPolicy.dwelling(spec, 1.0)).is_false()


# --- the gearbox's entry ---------------------------------------------------------------

func test_n_r_and_p_never_shift_whatever_the_policy_says() -> void:
	var spec := _light_spec()
	spec.kickdown_pedal = 0.9
	spec.skip_shifts = true
	for byte in [GEAR_N, GEAR_R, GEAR_P]:
		for pedal in [0.0, 1.0]:
			assert_int(DrivetrainScript.auto_shift(spec, byte, 4000.0, pedal, 10.0, true)) \
					.is_equal(byte)
			assert_int(DrivetrainScript.auto_shift(spec, byte, 800.0, pedal, 10.0, true)) \
					.is_equal(byte)


# --- the load ----------------------------------------------------------------------------

## `_light_spec` on a flat 200 N·m curve, final drive 4, no driveline loss and no friction: a gear's
## drive at pedal p is `p x 200 x ratio x 4` N·m at the axle (D3 at half pedal: 600).
func _loaded_spec() -> VehicleSpecScript:
	var spec := _light_spec()
	spec.torque_curve = PackedVector2Array([Vector2(800, 200), Vector2(4000, 200)])
	spec.final_drive = 4.0
	spec.efficiency = 1.0
	return spec


func test_the_drive_a_gear_makes_is_the_engine_law_at_the_pedals_fuel() -> void:
	var spec := _loaded_spec()
	assert_float(ShiftPolicy.drive_at(spec, 3, 2000.0, 0.5)).is_equal_approx(600.0, 1e-3)
	assert_float(ShiftPolicy.drive_at(spec, 1, 2000.0, 1.0)).is_equal_approx(2400.0, 1e-3)
	# A lift is motoring: the friction's share, paid through the loss the other way.
	spec.engine_friction_frac = 0.1
	spec.efficiency = 0.8
	assert_float(ShiftPolicy.drive_at(spec, 3, 800.0, 0.0)).is_equal_approx(-20.0 * 6.0 / 0.8, 1e-3)


func test_no_map_upshift_lands_in_a_gear_that_cannot_hold_the_road_speed() -> void:
	# Half pedal, 2600 rpm in D3: the map upshifts (2562.5) to D4, whose drive at that pedal is
	# 0.5 x 200 x 1.2 x 4 = 480 N·m. It holds a 400 N·m road load with the 1.1 reserve (440), not 450.
	var spec := _loaded_spec()
	assert_int(ShiftPolicy.next_gear(spec, 3, 2600.0, 0.5, 10.0, false, 400.0)).is_equal(4)
	assert_int(ShiftPolicy.next_gear(spec, 3, 2600.0, 0.5, 10.0, false, 450.0)).is_equal(3)
	assert_bool(ShiftPolicy.holds_grade(spec, 3, 4, 2600.0, 0.5, 450.0)).is_false()
	# No estimate is today's map.
	assert_int(ShiftPolicy.next_gear(spec, 3, 2600.0, 0.5, 10.0, false)).is_equal(4)
	# A lift upshift is the driver letting the speed go: never held.
	assert_int(ShiftPolicy.next_gear(spec, 3, 2600.0, 0.0, 10.0, false, 450.0)).is_equal(4)
	# A load that pulls the body along holds nothing.
	assert_bool(ShiftPolicy.holds_grade(spec, 3, 4, 2600.0, 0.5, -450.0)).is_true()


func test_off_a_grade_a_light_upshift_lands_and_the_pedal_makes_up_the_step() -> void:
	# The same 450 N·m load with grade logic reading no grade: the map's upshift lands.
	var spec := _loaded_spec()
	assert_int(ShiftPolicy.next_gear(spec, 3, 2600.0, 0.5, 10.0, false, 450.0, 1, false, false)) \
			.is_equal(4)


func test_grade_logic_reads_a_load_past_the_flat_roads_by_a_two_percent_pull() -> void:
	# 1000 kg on 0.36 m tyres, crr 0.02, Cd x A 0.8: at 20 m/s the flat road costs
	# (0.5 x 1.225 x 0.8 x 400 + 0.02 x 1000 x 9.8) x 0.36 = 141.1 N·m; a 2 % pull adds 70.6.
	var spec := _loaded_spec()
	spec.ground_drive = GroundDriveSpec.new()
	spec.ground_drive.wheel_radius = 0.36
	spec.ground_drive.rolling_resistance = 0.02
	spec.ground_drive.drag_area = 0.8
	var flat := ShiftPolicy.flat_load(spec, 20.0, 1000.0)
	assert_float(flat).is_equal_approx((196.0 + 196.0) * 0.36, 1e-2)
	var pull := ShiftPolicy.GRADE_LOGIC * 1000.0 * 9.8 * 0.36
	assert_bool(ShiftPolicy.on_grade(spec, flat + pull - 1.0, 20.0, 1000.0)).is_false()
	assert_bool(ShiftPolicy.on_grade(spec, flat + pull + 1.0, 20.0, 1000.0)).is_true()
	assert_bool(ShiftPolicy.on_grade(spec, NAN, 20.0, 1000.0)).is_false()


func test_a_kickdown_skips_a_gear_the_floored_body_revs_out_of_within_the_hold() -> void:
	# 1000 kg on 0.5 m tyres, no road load, no crank inertia: D2 (ratio 8) makes 1600 N·m, 3.2 m/s²,
	# so its rpm climbs 3.2 / 0.5 x 8 x 60 / tau = 488.9 rpm/s toward the 3500 upshift.
	var spec := _loaded_spec()
	spec.engine_inertia = 0.0
	spec.ground_drive = GroundDriveSpec.new()
	spec.ground_drive.wheel_radius = 0.5
	var rate := 3.2 / 0.5 * 8.0 * 60.0 / TAU
	assert_float(ShiftPolicy.time_to_upshift(spec, 2, 3000.0, 0.0, 1000.0)) \
			.is_equal_approx(500.0 / rate, 1e-4)
	# The crank's inertia through the gear adds J x 64 / 0.25 to the mass.
	spec.engine_inertia = 0.2
	assert_float(ShiftPolicy.time_to_upshift(spec, 2, 3000.0, 0.0, 1000.0)) \
			.is_equal_approx(500.0 / rate * 1051.2 / 1000.0, 1e-4)
	spec.engine_inertia = 0.0
	# A load the gear cannot beat, or no estimate: no limit.
	assert_float(ShiftPolicy.time_to_upshift(spec, 2, 3000.0, 1600.0, 1000.0)).is_equal(INF)
	assert_float(ShiftPolicy.time_to_upshift(spec, 2, 3000.0, NAN, 1000.0)).is_equal(INF)
	# From D5 at 1500 rpm D2 lands 3000 and holds 1.02 s: taken. At 1550 it lands 3100, under the
	# 3182 ceiling, but holds 0.82 s: the kickdown takes D3 (2325). With no estimate, D2.
	assert_int(ShiftPolicy.kickdown_target(spec, 5, 1500.0, 0.0, 1000.0)).is_equal(2)
	assert_int(ShiftPolicy.kickdown_target(spec, 5, 1550.0, 0.0, 1000.0)).is_equal(3)
	assert_int(ShiftPolicy.kickdown_target(spec, 5, 1550.0)).is_equal(2)
	assert_int(ShiftPolicy.next_gear(spec, 5, 1550.0, 1.0, 10.0, true, 0.0, 1, false, true, 1000.0)) \
			.is_equal(3)


func test_the_forced_upshift_is_never_held_by_the_load() -> void:
	var spec := _loaded_spec()
	assert_int(ShiftPolicy.next_gear(spec, 3, 3500.0, 1.0, 0.0, false, 1e6)).is_equal(4)


func test_a_held_skip_shift_steps_back_to_the_tallest_gear_that_holds() -> void:
	# 3400 rpm in D2 at pedal 0.3 ripples to D4. D4 makes 288 N·m there, D3 360: a 300 N·m load (330
	# with the reserve) takes D3, a 200 N·m one D4.
	var spec := _loaded_spec()
	spec.skip_shifts = true
	assert_int(ShiftPolicy.next_gear(spec, 2, 3400.0, 0.3, 10.0, false)).is_equal(4)
	assert_int(ShiftPolicy.next_gear(spec, 2, 3400.0, 0.3, 10.0, false, 300.0)).is_equal(3)
	assert_int(ShiftPolicy.next_gear(spec, 2, 3400.0, 0.3, 10.0, false, 200.0)).is_equal(4)


func test_a_lugging_crank_downshifts_through_the_dwell_and_the_map_never_undoes_it() -> void:
	# 1100 rpm in D3 at half pedal, under its 1187.5 downshift point, 0.5 s into a 1 s dwell: D3 makes
	# 600 N·m. Losing speed to a 700 N·m load it lugs and takes D2; under a 500 N·m one it holds.
	var spec := _loaded_spec()
	spec.shift_dwell_s = 1.0
	assert_bool(ShiftPolicy.lugging(spec, 3, 1100.0, 0.5, 700.0)).is_true()
	assert_int(ShiftPolicy.next_gear(spec, 3, 1100.0, 0.5, 0.5, false, 700.0)).is_equal(2)
	assert_int(ShiftPolicy.next_gear(spec, 3, 1100.0, 0.5, 0.5, false, 500.0)).is_equal(3)
	assert_int(ShiftPolicy.next_gear(spec, 3, 1100.0, 0.5, 0.5, false)).is_equal(3)
	# Never under the floor.
	assert_int(ShiftPolicy.next_gear(spec, 3, 1100.0, 0.5, 0.5, false, 700.0, 3)).is_equal(3)
	# Back in D2 the same load holds it there however fast the map would take D3.
	assert_int(ShiftPolicy.next_gear(spec, 2, 2600.0, 0.5, 10.0, false, 700.0)).is_equal(2)


func test_a_braked_descent_holds_its_gear_and_steps_down_for_engine_braking() -> void:
	# A -300 N·m road load pulls the body downhill. D3 at 2100 rpm, lifted: no upshift under the
	# brake, the lift upshift without it.
	var spec := _loaded_spec()
	assert_int(ShiftPolicy.next_gear(spec, 3, 2100.0, 0.0, 10.0, false, -300.0, 1, true)) \
			.is_equal(3)
	assert_int(ShiftPolicy.next_gear(spec, 3, 2100.0, 0.0, 10.0, false, -300.0, 1, false)) \
			.is_equal(4)
	# D4 at 1500 rpm: D3 would land 1875, under its 2000 lifted upshift, so it steps down. At 1700
	# D3 would land 2125, past it, and would upshift straight back once the brake let go: it holds.
	assert_int(ShiftPolicy.next_gear(spec, 4, 1500.0, 0.0, 10.0, false, -300.0, 1, true)) \
			.is_equal(3)
	assert_int(ShiftPolicy.next_gear(spec, 4, 1700.0, 0.0, 10.0, false, -300.0, 1, true)) \
			.is_equal(4)
	# Braking on the flat is no descent.
	assert_int(ShiftPolicy.next_gear(spec, 4, 1500.0, 0.0, 10.0, false, 300.0, 1, true)) \
			.is_equal(4)


func test_no_downshift_goes_under_the_floor_gear() -> void:
	var spec := _loaded_spec()
	# The coast line (1000) and the full pedal's downshift (1500).
	assert_int(ShiftPolicy.next_gear(spec, 3, 900.0, 0.0, 10.0, false, NAN, 1)).is_equal(2)
	assert_int(ShiftPolicy.next_gear(spec, 3, 900.0, 0.0, 10.0, false, NAN, 3)).is_equal(3)
	assert_int(ShiftPolicy.next_gear(spec, 3, 1200.0, 1.0, 10.0, false, NAN, 3)).is_equal(3)
	assert_int(ShiftPolicy.forced_gear(spec, 3, 900.0, 0.0, 3)).is_equal(3)


# --- the start gear --------------------------------------------------------------------

func test_the_start_gear_is_the_highest_whose_launch_drive_beats_the_load_twice() -> void:
	# No wheel-driving ground drive: the launch target is idle, where D1/D2/D3 make 2400/1600/1200.
	var spec := _loaded_spec()
	spec.start_gear_max = 3
	assert_float(ShiftPolicy.START_RESERVE).is_equal(2.0)
	assert_int(ShiftPolicy.start_gear(spec, 0.0)).is_equal(3)
	assert_int(ShiftPolicy.start_gear(spec, 600.0)).is_equal(3)
	assert_int(ShiftPolicy.start_gear(spec, 700.0)).is_equal(2)
	assert_int(ShiftPolicy.start_gear(spec, 1000.0)).is_equal(1)
	assert_int(ShiftPolicy.start_gear(spec, 1e6)).is_equal(1)
	# None declared, or D1 declared, is D1.
	for cap in [0, 1]:
		spec.start_gear_max = cap
		assert_int(ShiftPolicy.start_gear(spec, 0.0)).is_equal(1)
	# A lighter pedal launches on less fuel: at half pedal D3 makes 600, D2 800, so a 350 N·m load
	# that starts D3 floored takes D2.
	spec.start_gear_max = 3
	assert_int(ShiftPolicy.start_gear(spec, 350.0)).is_equal(3)
	assert_int(ShiftPolicy.start_gear(spec, 350.0, 0.5)).is_equal(2)
	# Never past the box.
	spec.start_gear_max = 6
	spec.gear_ratios = PackedFloat32Array([3.0, 2.0, 1.5])
	assert_int(ShiftPolicy.start_gear(spec, 0.0)).is_equal(3)


func test_the_standing_load_is_the_grades_pull_plus_the_rolling_resistance() -> void:
	var gravity := Vector3(0.0, -9.8, 0.0)
	# Flat: crr 0.02 on 1000 kg through 0.36 m.
	assert_float(ShiftPolicy.standing_load(gravity, Vector3.UP, Vector3.FORWARD, 0.02, 360.0)) \
			.is_equal_approx(0.02 * 9.8 * 360.0, 1e-3)
	# Nose up a 10 % grade: the pull back down plus the rolling on the plane's share of the weight.
	var tilt := Basis(Vector3.RIGHT, atan(0.1))
	var expected := 9.8 * (sin(atan(0.1)) + 0.02 * cos(atan(0.1))) * 360.0
	assert_float(ShiftPolicy.standing_load(gravity, tilt * Vector3.UP, tilt * Vector3.FORWARD, 0.02,
			360.0)).is_equal_approx(expected, 1e-2)
	# Nose down it pulls the body along: negative.
	assert_float(ShiftPolicy.standing_load(gravity, tilt * Vector3.UP, -(tilt * Vector3.FORWARD),
			0.0, 360.0)).is_less(0.0)


func test_the_road_load_is_the_drive_less_the_mass_times_the_acceleration_filtered() -> void:
	# 1000 N·m passed, 100 kg at 2 m/s² through 0.5 m: 900 resists.
	assert_float(ShiftPolicy.road_load_step(NAN, 1000.0, 100.0, 2.0, 0.5, 1.0 / 60.0)) \
			.is_equal_approx(900.0, 1e-3)
	var one := ShiftPolicy.road_load_step(0.0, 1000.0, 100.0, 2.0, 0.5, 1.0 / 60.0)
	assert_float(one).is_equal_approx(900.0 * (1.0 - exp(-1.0 / 60.0 / ShiftPolicy.LOAD_FILTER_S)),
			1e-3)
	var est := 0.0
	for i in 600:
		est = ShiftPolicy.road_load_step(est, 1000.0, 100.0, 2.0, 0.5, 1.0 / 60.0)
	assert_float(est).is_equal_approx(900.0, 0.1)

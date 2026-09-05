extends GdUnitTestSuite
## Drivetrain math + RAMN gear-byte semantics.
## Pure logic — specs are built inline with round numbers so every expected value
## is hand-checkable; the shipped car spec is only used for the §6 force-hierarchy
## invariants at the bottom.

const DrivetrainScript := preload("res://src/vehicles/base/drivetrain.gd")
const VehicleSpecScript := preload("res://src/vehicles/base/vehicle_spec.gd")
const GroundDriveSpecScript := preload("res://src/vehicles/base/ground_drive_spec.gd")

const GEAR_N := 0x00
const GEAR_R := 0xFF


func _spec() -> VehicleSpecScript:
	var spec: VehicleSpecScript = VehicleSpecScript.new()
	spec.ground_drive = GroundDriveSpecScript.new()
	spec.torque_curve = PackedVector2Array([
		Vector2(1000, 100), Vector2(2000, 200), Vector2(3000, 300), Vector2(4000, 200)])
	spec.idle_rpm = 800.0
	spec.redline_rpm = 4000.0
	spec.gear_ratios = PackedFloat32Array([3.0, 2.0, 1.5, 1.2, 1.0, 0.8])
	spec.reverse_ratio = 3.2
	spec.final_drive = 4.0
	spec.efficiency = 0.9
	spec.shift_up_rpm = 3500.0
	spec.shift_down_rpm = 1500.0
	return spec


# --- sample_curve -----------------------------------------------------------

func test_sample_curve_interpolates_and_clamps() -> void:
	var points := PackedVector2Array([Vector2(1000, 100), Vector2(2000, 200)])
	assert_float(VehicleSpecScript.sample_curve(points, 1500.0)).is_equal_approx(150.0, 0.001)
	assert_float(VehicleSpecScript.sample_curve(points, 1000.0)).is_equal_approx(100.0, 0.001)
	assert_float(VehicleSpecScript.sample_curve(points, 500.0)).is_equal_approx(100.0, 0.001)
	assert_float(VehicleSpecScript.sample_curve(points, 9000.0)).is_equal_approx(200.0, 0.001)
	assert_float(VehicleSpecScript.sample_curve(PackedVector2Array(), 1.0)).is_equal(0.0)


# --- gear byte semantics (RAMN: 0x00=N, 0x01..0x06=D1-D6, 0xFF=R) ------------

func test_gear_byte_classification() -> void:
	assert_bool(DrivetrainScript.is_drive(0)).is_false()
	for byte in range(1, 7):
		assert_bool(DrivetrainScript.is_drive(byte)).is_true()
	assert_bool(DrivetrainScript.is_drive(7)).is_false()
	assert_bool(DrivetrainScript.is_reverse(0xFF)).is_true()
	assert_bool(DrivetrainScript.is_reverse(6)).is_false()


func test_invalid_gear_bytes_normalize_to_neutral() -> void:
	for byte in [7, 100, 254, -1]:
		assert_int(DrivetrainScript.normalize_byte(byte)).is_equal(GEAR_N)
	assert_int(DrivetrainScript.normalize_byte(GEAR_R)).is_equal(GEAR_R)
	assert_int(DrivetrainScript.normalize_byte(3)).is_equal(3)


func test_ratio_for_byte_signed_by_direction() -> void:
	var spec := _spec()
	assert_float(DrivetrainScript.ratio_for_byte(spec, 1)).is_equal_approx(12.0, 0.001)
	assert_float(DrivetrainScript.ratio_for_byte(spec, 6)).is_equal_approx(3.2, 0.001)
	assert_float(DrivetrainScript.ratio_for_byte(spec, GEAR_R)).is_equal_approx(-12.8, 0.001)
	assert_float(DrivetrainScript.ratio_for_byte(spec, GEAR_N)).is_equal(0.0)
	assert_float(DrivetrainScript.ratio_for_byte(spec, 200)).is_equal(0.0)


# --- engine torque ------------------------------------------------------------

func test_engine_torque_is_the_curve_and_nothing_else() -> void:
	# The redline does NOT live here — it is a fuel cut (limiter_cut), so the curve is free to
	# say what the engine makes at its redline. engine_load reads this too, so hiding a cut in
	# here would also lie about the load at a rpm the engine is perfectly happy at.
	var spec := _spec()
	assert_float(DrivetrainScript.engine_torque(spec, 2500.0)).is_equal_approx(250.0, 0.001)
	assert_float(DrivetrainScript.engine_torque(spec, 4000.0)).is_equal_approx(200.0, 0.001)
	assert_float(DrivetrainScript.engine_torque(spec, 5000.0)).is_equal_approx(200.0, 0.001)


func test_limiter_cut_judges_the_unclamped_crank_speed() -> void:
	var spec := _spec()   # redline 4000
	assert_bool(DrivetrainScript.limiter_cut(spec, 3999.0)).is_false()
	assert_bool(DrivetrainScript.limiter_cut(spec, 4000.0)).is_true()
	assert_bool(DrivetrainScript.limiter_cut(spec, 6000.0)).is_true()


func test_wheel_engine_rpm_is_unclamped_and_rpm_from_wheel_is_its_clamp() -> void:
	# 40 rad/s D1 (ratio 12) is ~4584 rpm vs 4000 redline (one bounded, one raw).
	var spec := _spec()
	var raw: float = DrivetrainScript.wheel_engine_rpm(spec, 40.0, 1)
	assert_float(raw).is_equal_approx(40.0 * 12.0 * 60.0 / TAU, 0.01)
	assert_float(raw).is_greater(spec.redline_rpm)
	assert_float(DrivetrainScript.rpm_from_wheel(spec, 40.0, 1)).is_equal(spec.redline_rpm)
	assert_float(DrivetrainScript.wheel_engine_rpm(spec, 500.0, GEAR_N)).is_equal(spec.idle_rpm)


# --- RPM from wheel speed -----------------------------------------------------

func test_rpm_from_wheel_exact_ratio_math() -> void:
	var spec := _spec()
	# 50 rad/s through D3 (1.5 * 4.0 = 6): 300 rad/s engine = 300 * 60 / TAU rpm.
	var expected := 300.0 * 60.0 / TAU
	assert_float(DrivetrainScript.rpm_from_wheel(spec, 50.0, 3)).is_equal_approx(expected, 0.01)


func test_rpm_from_wheel_clamps_idle_and_redline() -> void:
	var spec := _spec()
	assert_float(DrivetrainScript.rpm_from_wheel(spec, 0.1, 1)).is_equal(spec.idle_rpm)
	assert_float(DrivetrainScript.rpm_from_wheel(spec, 1000.0, 1)).is_equal(spec.redline_rpm)
	assert_float(DrivetrainScript.rpm_from_wheel(spec, 500.0, GEAR_N)).is_equal(spec.idle_rpm)


func test_the_limiter_cuts_fuel_past_the_redline() -> void:
	# Can't gate on stored `rpm` (exponential lerp, clamped). Must use unclamped engine speed.
	# Spec curve ends (4000, 200): 200 Nm tail.
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	# D1 (ratio 12) at 40 rad/s of wheel is ~4584 rpm, past the 4000 redline. Bridge mode so the
	# box cannot upshift out of it.
	var torque := 0.0
	for i in 60:
		torque = dt.process(1.0 / 60.0, 1.0, 40.0, 40.0 * spec.ground_drive.wheel_radius, 1, false)
	assert_float(torque).is_equal(0.0)
	# The fuel cut has to reach telemetry too — an engine that is being cut is not making the
	# load the pedal is still asking for (the same rule applied_throttle exists for).
	assert_float(dt.applied_throttle).is_equal(0.0)


func test_the_limiter_does_not_make_the_tacho_read_past_the_redline() -> void:
	# The cut judges the raw wheel-implied rpm; the PUBLISHED rpm (dash + bridge signal) stays
	# the clamped one. A limiter does not move the needle past the red mark.
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 120:
		dt.process(1.0 / 60.0, 1.0, 100.0, 100.0 * spec.ground_drive.wheel_radius, 1, false)
	assert_float(dt.rpm).is_equal_approx(spec.redline_rpm, 0.5)
	assert_float(dt.rpm).is_less_equal(spec.redline_rpm)


func test_below_the_redline_the_engine_still_makes_its_curve() -> void:
	# The other side of the cut: it is a limiter, not a de-rate. 20 rad/s in D1 is ~2292 rpm.
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var torque := 0.0
	for i in 60:
		torque = dt.process(1.0 / 60.0, 1.0, 20.0, 20.0 * spec.ground_drive.wheel_radius, 1, false)
	assert_float(dt.applied_throttle).is_equal(1.0)
	assert_float(absf(torque)).is_greater(0.0)


func test_rpm_positive_in_reverse() -> void:
	var spec := _spec()
	# Reversing: wheel spins backwards, ratio is negative — RPM must still be positive.
	var rpm: float = DrivetrainScript.rpm_from_wheel(spec, -20.0, GEAR_R)
	assert_float(rpm).is_equal_approx(absf(-20.0 * -12.8) * 60.0 / TAU, 0.01)


# --- wheel torque ---------------------------------------------------------------

func test_wheel_torque_product_and_sign() -> void:
	var spec := _spec()
	# 2000 rpm -> 200 Nm engine; D1 ratio 12; efficiency 0.9; half throttle.
	assert_float(DrivetrainScript.wheel_torque(spec, 2000.0, 0.5, 1)) \
			.is_equal_approx(200.0 * 0.5 * 12.0 * 0.9, 0.001)
	assert_float(DrivetrainScript.wheel_torque(spec, 2000.0, 1.0, GEAR_R)) \
			.is_equal_approx(200.0 * -12.8 * 0.9, 0.001)
	assert_float(DrivetrainScript.wheel_torque(spec, 2000.0, 1.0, GEAR_N)).is_equal(0.0)


func test_wheel_torque_clamps_throttle_magnitude() -> void:
	var spec := _spec()
	# Throttle is a 0..1 magnitude — direction comes from the gear, so a
	# stray negative value must never flip the torque sign.
	assert_float(DrivetrainScript.wheel_torque(spec, 2000.0, -1.0, 1)).is_equal(0.0)
	assert_float(DrivetrainScript.wheel_torque(spec, 2000.0, 2.0, 1)) \
			.is_equal_approx(200.0 * 12.0 * 0.9, 0.001)


# --- auto-shift ------------------------------------------------------------------

func test_auto_shift_thresholds() -> void:
	var spec := _spec()
	assert_int(DrivetrainScript.auto_shift(spec, 3, 3500.0)).is_equal(4)
	assert_int(DrivetrainScript.auto_shift(spec, 3, 1500.0)).is_equal(2)
	assert_int(DrivetrainScript.auto_shift(spec, 3, 2500.0)).is_equal(3)


func test_auto_shift_stays_within_gearbox() -> void:
	var spec := _spec()
	assert_int(DrivetrainScript.auto_shift(spec, 6, 4000.0)).is_equal(6)
	assert_int(DrivetrainScript.auto_shift(spec, 1, 800.0)).is_equal(1)


func test_auto_shift_stays_inside_a_short_gearbox() -> void:
	# `ratio_for_byte` INDEXES `gear_ratios[byte - 1]`, so a spec with fewer than TOP_GEAR
	# ratios must not be upshifted to TOP_GEAR — that is an out-of-range read. governed_upshift
	# has guarded this since it was written; auto_shift did not, and this is that hole closed.
	var spec := _spec()
	spec.gear_ratios = PackedFloat32Array([3.0, 2.0, 1.5])
	assert_int(DrivetrainScript.auto_shift(spec, 3, 4000.0)).is_equal(3)
	assert_int(DrivetrainScript.auto_shift(spec, 2, 4000.0)).is_equal(3)
	# The downshift end is untouched by the guard.
	assert_int(DrivetrainScript.auto_shift(spec, 3, 800.0)).is_equal(2)


func test_auto_shift_never_touches_neutral_or_reverse() -> void:
	var spec := _spec()
	assert_int(DrivetrainScript.auto_shift(spec, GEAR_N, 4000.0)).is_equal(GEAR_N)
	assert_int(DrivetrainScript.auto_shift(spec, GEAR_R, 4000.0)).is_equal(GEAR_R)


# --- process (instance tick) ------------------------------------------------------

func test_process_enters_drive_and_delivers_forward_torque() -> void:
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var torque: float = dt.process(1.0 / 60.0, 1.0, 0.0, 0.0, 1, true)
	assert_int(dt.gear_byte).is_equal(1)
	assert_float(torque).is_greater(0.0)


func test_process_reverse_delivers_negative_torque() -> void:
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var torque: float = dt.process(1.0 / 60.0, 1.0, 0.0, 0.0, GEAR_R, true)
	assert_int(dt.gear_byte).is_equal(GEAR_R)
	assert_float(torque).is_less(0.0)


func test_process_exact_mode_adopts_bridge_byte_without_auto_shift() -> void:
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	# Bridge mode (gear owns direction): byte is verbatim even at a wheel
	# speed whose rpm is far above the auto upshift threshold.
	dt.process(1.0 / 60.0, 1.0, 100.0, 100.0 * spec.ground_drive.wheel_radius, 2, false)
	assert_int(dt.gear_byte).is_equal(2)


func test_process_auto_upshifts_at_speed() -> void:
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	dt.process(1.0 / 60.0, 1.0, 0.0, 0.0, 1, true)
	# Road speed giving 40 rad/s of wheel spin (no slip) through D1 (ratio 12) is
	# ~4584 rpm, above shift_up 3500. Auto-shift decides on this road speed, not spin.
	dt.process(1.0 / 60.0, 1.0, 40.0, 40.0 * spec.ground_drive.wheel_radius, 1, true)
	assert_int(dt.gear_byte).is_equal(2)


func test_process_rpm_rests_at_idle() -> void:
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 120:
		dt.process(1.0 / 60.0, 0.0, 0.0, 0.0, GEAR_N, true)
	assert_float(dt.rpm).is_equal_approx(spec.idle_rpm, 1.0)


# --- road-speed governor ------------------------------------------------------------

func test_governor_is_absent_unless_a_limit_is_declared() -> void:
	var spec := _spec()   # speed_limit_kmh defaults to 0
	assert_float(DrivetrainScript.governor_scale(spec, 0.0)).is_equal(1.0)
	assert_float(DrivetrainScript.governor_scale(spec, 200.0)).is_equal(1.0)


func test_governor_fades_across_the_band_and_shuts_at_the_limit() -> void:
	var spec := _spec()
	spec.speed_limit_kmh = 90.0
	var limit := 90.0 / 3.6                        # 25 m/s
	var band: float = DrivetrainScript.GOVERNOR_BAND
	# Wide open well below the limit, shut at and above it, half way at half a band below.
	assert_float(DrivetrainScript.governor_scale(spec, limit - 10.0 * band)).is_equal(1.0)
	assert_float(DrivetrainScript.governor_scale(spec, limit - band * 0.5)).is_equal_approx(0.5, 1e-4)
	assert_float(DrivetrainScript.governor_scale(spec, limit)).is_equal(0.0)
	assert_float(DrivetrainScript.governor_scale(spec, limit + 50.0)).is_equal(0.0)


func test_governor_is_unsigned_so_it_limits_reverse_too() -> void:
	var spec := _spec()
	spec.speed_limit_kmh = 90.0
	var limit := 90.0 / 3.6
	assert_float(DrivetrainScript.governor_scale(spec, -limit)).is_equal(0.0)
	assert_float(DrivetrainScript.governor_scale(spec, -limit + 0.5 * DrivetrainScript.GOVERNOR_BAND)) 			.is_equal_approx(0.5, 1e-4)


func test_process_publishes_the_governed_throttle_not_the_pedal() -> void:
	# Telemetry (engine_load, fuel, coolant) reads governed throttle, not pedal.
	var spec := _spec()
	spec.speed_limit_kmh = 90.0
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	var free := dt.process(1.0 / 60.0, 1.0, 10.0, 5.0, 1, false)
	assert_float(dt.applied_throttle).is_equal(1.0)
	assert_float(free).is_greater(0.0)
	# Same full pedal, now sitting on the limit: no throttle through, no drive torque.
	var governed := dt.process(1.0 / 60.0, 1.0, 10.0, 90.0 / 3.6, 1, false)
	assert_float(dt.applied_throttle).is_equal(0.0)
	assert_float(governed).is_equal(0.0)


func test_a_governed_engine_still_turns_with_the_wheels() -> void:
	# rpm follows the ROAD, not the pedal — a limited truck at 90 km/h is not idling, it is
	# turning at whatever the gearing makes it turn at with the fuel cut.
	var spec := _spec()
	spec.speed_limit_kmh = 90.0
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 240:
		dt.process(1.0 / 60.0, 1.0, 60.0, 90.0 / 3.6, 1, false)
	assert_float(dt.applied_throttle).is_equal(0.0)
	assert_float(dt.rpm).is_greater(spec.idle_rpm)


func test_governed_upshift_takes_the_tallest_gear_that_still_pulls() -> void:
	# The van case: a limit that lands just below the rpm-based upshift point used to strand
	# the box a gear short, and the measure tool reported it as an unreachable ratio.
	var spec := _spec()
	spec.ground_drive.wheel_radius = 0.36
	spec.speed_limit_kmh = 180.0
	var at_limit := 180.0 / 3.6
	var g := DrivetrainScript.governed_upshift(spec, 5, at_limit, spec.ground_drive.wheel_radius)
	assert_int(g).is_equal(spec.gear_ratios.size())


func test_governed_upshift_will_not_lug_the_engine_below_the_downshift_point() -> void:
	# A limiter low enough that top gear would drop the engine under shift_down_rpm must NOT
	# be taken — that is the guard that keeps this from bogging a slow-governed vehicle.
	var spec := _spec()
	spec.ground_drive.wheel_radius = 0.36
	spec.speed_limit_kmh = 12.0
	var g := DrivetrainScript.governed_upshift(spec, 1, 12.0 / 3.6, spec.ground_drive.wheel_radius)
	assert_int(g).is_less(spec.gear_ratios.size())
	assert_float(DrivetrainScript.rpm_from_wheel(spec, (12.0 / 3.6) / spec.ground_drive.wheel_radius, g)) 			.is_greater_equal(spec.idle_rpm)


func test_a_spec_with_no_ground_drive_still_gets_a_gear_selection_scale() -> void:
	# The boat, the drone and the train walk a gearbox and publish the gear byte in `status`
	# without owning a wheel. road_radius is what lets them: with no ground drive to copy a
	# wheel_radius off, Drivetrain declares DEFAULT_ROAD_RADIUS and the shift points stand where
	# they always did. A fallback of 0 here would divide by zero on the very first tick.
	var spec := _spec()
	spec.ground_drive = null
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	assert_float(dt.road_radius).is_equal(DrivetrainScript.DEFAULT_ROAD_RADIUS)
	# And it really is the same scale a wheeled body of that radius would pick.
	var wheeled := _spec()
	wheeled.ground_drive.wheel_radius = DrivetrainScript.DEFAULT_ROAD_RADIUS
	assert_float(DrivetrainScript.new(wheeled).road_radius).is_equal(dt.road_radius)


func test_governed_upshift_reads_the_declared_radius_as_a_pure_scale() -> void:
	# road_radius is DECLARED on the Drivetrain rather than reached for on the spec, so that a
	# wheel-less body (boat, train) keeps its gearing when the wheel fields move to the ground
	# road_radius enters as ground_speed / road_radius (nowhere else); ratio IS selection scale.
	var spec := _spec()
	spec.speed_limit_kmh = 180.0
	var at_limit := 180.0 / 3.6
	var g := DrivetrainScript.governed_upshift(spec, 1, at_limit, 0.36)
	assert_int(DrivetrainScript.governed_upshift(spec, 1, at_limit / 2.0, 0.18)).is_equal(g)
	assert_int(DrivetrainScript.governed_upshift(spec, 1, at_limit * 2.0, 0.72)).is_equal(g)
	# And a Drivetrain copies it off the spec, so nothing about today's gearing moved.
	spec.ground_drive.wheel_radius = 0.36
	assert_float(DrivetrainScript.new(spec).road_radius).is_equal(0.36)


func test_governed_upshift_never_leaves_the_RAMN_drive_range() -> void:
	# 7th ratio: is_drive rejects, ratio_for_byte returns 0.0 (free-wheel). TOP_GEAR is bus number.
	var spec := _spec()
	spec.ground_drive.wheel_radius = 0.36
	spec.speed_limit_kmh = 180.0
	spec.gear_ratios = PackedFloat32Array([4.0, 2.6, 1.8, 1.3, 1.0, 0.8, 0.65])
	var g := DrivetrainScript.governed_upshift(spec, 5, 180.0 / 3.6, spec.ground_drive.wheel_radius)
	assert_int(g).is_less_equal(DrivetrainScript.TOP_GEAR)
	assert_bool(DrivetrainScript.is_drive(g)).is_true()
	assert_float(DrivetrainScript.ratio_for_byte(spec, g)).is_not_equal(0.0)


func test_auto_shift_and_is_drive_agree_with_governed_upshift_on_top_gear() -> void:
	# All three must read TOP_GEAR (is_drive, auto_shift, governed_upshift).
	var spec := _spec()
	spec.gear_ratios = PackedFloat32Array([4.0, 2.6, 1.8, 1.3, 1.0, 0.8, 0.65])
	assert_bool(DrivetrainScript.is_drive(DrivetrainScript.TOP_GEAR)).is_true()
	assert_bool(DrivetrainScript.is_drive(DrivetrainScript.TOP_GEAR + 1)).is_false()
	# At the redline in top, auto-shift holds rather than stepping off the end of the range.
	assert_int(DrivetrainScript.auto_shift(spec, DrivetrainScript.TOP_GEAR, spec.redline_rpm)) \
			.is_equal(DrivetrainScript.TOP_GEAR)


func test_a_governed_vehicle_ends_up_in_top_gear() -> void:
	# End to end through process(): full pedal, sitting on the limit, auto box.
	var spec := _spec()
	spec.ground_drive.wheel_radius = 0.36
	spec.speed_limit_kmh = 180.0
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	dt.gear_byte = 1
	var at_limit := 180.0 / 3.6
	for i in 60:
		dt.process(1.0 / 60.0, 1.0, at_limit / spec.ground_drive.wheel_radius, at_limit, 1, true)
	assert_int(dt.gear_byte).is_equal(spec.gear_ratios.size())
	assert_float(dt.applied_throttle).is_equal(0.0)


# --- peak torque --------------------------------------------------------------------

func test_peak_torque_is_the_highest_point_on_the_curve() -> void:
	# The engine-load denominator (and the garage's headline figure): the most this engine can
	# ever make, wherever on the curve that is — not the value at any particular rpm.
	assert_float(DrivetrainScript.peak_torque(_spec())).is_equal(300.0)
	var flat: VehicleSpecScript = VehicleSpecScript.new()
	flat.torque_curve = PackedVector2Array([Vector2(1000, 50), Vector2(2000, 50)])
	assert_float(DrivetrainScript.peak_torque(flat)).is_equal(50.0)
	var empty: VehicleSpecScript = VehicleSpecScript.new()
	empty.torque_curve = PackedVector2Array()
	assert_float(DrivetrainScript.peak_torque(empty)).is_equal(0.0)


# --- locked differential ----------------------------------------------------------
## Unlocked there is nothing to test: equal torque to both half-shafts IS the open diff's
## torque law, and BaseVehicle already splits that way. Locking is the part the driveline
## could not previously express — one rigid shaft, so one spin speed.

func test_locked_axle_shares_one_spin_speed() -> void:
	# A wheel spinning in mud and a wheel gripping come out on the same shaft speed.
	assert_float(DrivetrainScript.locked_axle_omega(40.0, 10.0)).is_equal_approx(25.0, 1e-6)
	# Symmetric — which wheel is which cannot matter.
	assert_float(DrivetrainScript.locked_axle_omega(10.0, 40.0)) \
			.is_equal(DrivetrainScript.locked_axle_omega(40.0, 10.0))
	# Already matched: a no-op, so an unstuck axle is untouched tick after tick.
	assert_float(DrivetrainScript.locked_axle_omega(12.5, 12.5)).is_equal(12.5)
	# Reverse (both negative) behaves the same way.
	assert_float(DrivetrainScript.locked_axle_omega(-40.0, -10.0)).is_equal_approx(-25.0, 1e-6)


func test_locked_axle_conserves_momentum_and_never_grows_the_spread() -> void:
	# RayWheel is single-inertia, so equal-weight averaging conserves the pair's angular
	# momentum: no energy is injected, which is why this needs no 60 Hz clamp of its own.
	for pair: Array in [[40.0, 10.0], [-5.0, 30.0], [0.0, 0.0], [100.0, -100.0]]:
		var a: float = pair[0]
		var b: float = pair[1]
		var shared := DrivetrainScript.locked_axle_omega(a, b)
		assert_float(shared * 2.0).is_equal_approx(a + b, 1e-6)
		# The coupled speed can never sit outside the pair it came from.
		assert_float(shared).is_between(minf(a, b), maxf(a, b))


# --- §6 force hierarchy on the shipped car spec -----------------------------------

func test_car_spec_brake_stronger_than_accel_stronger_than_handbrake() -> void:
	var spec: VehicleSpecScript = load("res://src/vehicles/kenney/sedan_spec.tres")
	var peak_engine := 0.0
	for p in spec.torque_curve:
		peak_engine = maxf(peak_engine, p.y)
	var max_drive: float = peak_engine * spec.gear_ratios[0] * spec.final_drive * spec.efficiency
	var total_brake: float = spec.ground_drive.brake_torque * spec.ground_drive.wheel_positions.size()
	var total_handbrake: float = spec.ground_drive.handbrake_torque * 2.0
	# Full accel + full brake must come to a stop: brake beats peak drive torque.
	assert_float(total_brake).is_greater(max_drive)
	# Handbrake holds only below ~25% throttle: bracket it against launch
	# torque (idle rpm, D1) at 25% and 50% throttle.
	var drive_25: float = absf(DrivetrainScript.wheel_torque(spec, spec.idle_rpm, 0.25, 1))
	var drive_50: float = absf(DrivetrainScript.wheel_torque(spec, spec.idle_rpm, 0.5, 1))
	assert_float(total_handbrake).is_greater(drive_25)
	assert_float(total_handbrake).is_less(drive_50)

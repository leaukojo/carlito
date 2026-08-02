extends GdUnitTestSuite
## Drivetrain math + RAMN gear-byte semantics.
## Pure logic — specs are built inline with round numbers so every expected value
## is hand-checkable; the shipped car spec is only used for the §6 force-hierarchy
## invariants at the bottom.

const DrivetrainScript := preload("res://src/vehicles/base/drivetrain.gd")
const VehicleSpecScript := preload("res://src/vehicles/base/vehicle_spec.gd")

const GEAR_N := 0x00
const GEAR_R := 0xFF


func _spec() -> VehicleSpecScript:
	var spec: VehicleSpecScript = VehicleSpecScript.new()
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

func test_engine_torque_follows_curve_and_cuts_at_redline() -> void:
	var spec := _spec()
	assert_float(DrivetrainScript.engine_torque(spec, 2500.0)).is_equal_approx(250.0, 0.001)
	assert_float(DrivetrainScript.engine_torque(spec, 4000.0)).is_equal(0.0)
	assert_float(DrivetrainScript.engine_torque(spec, 5000.0)).is_equal(0.0)


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
	dt.process(1.0 / 60.0, 1.0, 100.0, 100.0 * spec.wheel_radius, 2, false)
	assert_int(dt.gear_byte).is_equal(2)


func test_process_auto_upshifts_at_speed() -> void:
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	dt.process(1.0 / 60.0, 1.0, 0.0, 0.0, 1, true)
	# Road speed giving 40 rad/s of wheel spin (no slip) through D1 (ratio 12) is
	# ~4584 rpm, above shift_up 3500. Auto-shift decides on this road speed, not spin.
	dt.process(1.0 / 60.0, 1.0, 40.0, 40.0 * spec.wheel_radius, 1, true)
	assert_int(dt.gear_byte).is_equal(2)


func test_process_rpm_rests_at_idle() -> void:
	var spec := _spec()
	var dt: DrivetrainScript = DrivetrainScript.new(spec)
	for i in 120:
		dt.process(1.0 / 60.0, 0.0, 0.0, 0.0, GEAR_N, true)
	assert_float(dt.rpm).is_equal_approx(spec.idle_rpm, 1.0)


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
	var total_brake: float = spec.brake_torque * spec.wheel_positions.size()
	var total_handbrake: float = spec.handbrake_torque * 2.0
	# Full accel + full brake must come to a stop: brake beats peak drive torque.
	assert_float(total_brake).is_greater(max_drive)
	# Handbrake holds only below ~25% throttle: bracket it against launch
	# torque (idle rpm, D1) at 25% and 50% throttle.
	var drive_25: float = absf(DrivetrainScript.wheel_torque(spec, spec.idle_rpm, 0.25, 1))
	var drive_50: float = absf(DrivetrainScript.wheel_torque(spec, spec.idle_rpm, 0.5, 1))
	assert_float(total_handbrake).is_greater(drive_25)
	assert_float(total_handbrake).is_less(drive_50)

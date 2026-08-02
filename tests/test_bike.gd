extends GdUnitTestSuite
## Bike-specific pure math: the arcade lean model (BikeVehicle.lean_target_deg) and the §6
## force hierarchy on the shipped bike spec (brake > peak drive > handbrake), the same
## discipline as test_drivetrain's car-spec guard.

const BikeScript := preload("res://src/vehicles/bike/bike.gd")
const DrivetrainScript := preload("res://src/vehicles/base/drivetrain.gd")
const VehicleSpecScript := preload("res://src/vehicles/base/vehicle_spec.gd")


# --- arcade lean model --------------------------------------------------------

func test_lean_is_upright_when_still_and_straight() -> void:
	assert_float(BikeScript.lean_target_deg(0.0, 0.0, 0.0)).is_equal(0.0)


func test_lean_follows_lateral_g_into_the_turn() -> void:
	# Turning right pushes lateral accel to the right (+): the bike leans right (+).
	assert_float(BikeScript.lean_target_deg(9.81, 0.0, 0.0)).is_equal_approx(45.0, 1e-3)
	# Symmetric to the left.
	assert_float(BikeScript.lean_target_deg(-9.81, 0.0, 0.0)).is_equal_approx(-45.0, 1e-3)


func test_lean_steer_term_scales_with_speed_and_is_ignored_at_standstill() -> void:
	# At standstill the steer term contributes nothing (no lean from a parked handlebar).
	assert_float(BikeScript.lean_target_deg(0.0, 0.0, 1.0)).is_equal(0.0)
	# At/above the speed ref, full-right steer adds the full steer-gain lean, and the sign
	# matches the lateral-g convention (positive steer = right = +lean).
	assert_float(BikeScript.lean_target_deg(0.0, BikeScript.LEAN_STEER_SPEED_REF, 1.0)) \
			.is_equal_approx(BikeScript.LEAN_STEER_GAIN, 1e-4)
	assert_float(BikeScript.lean_target_deg(0.0, 100.0, -1.0)) \
			.is_equal_approx(-BikeScript.LEAN_STEER_GAIN, 1e-4)


func test_lean_is_clamped_to_the_contract_max() -> void:
	# Huge lateral g plus full steer still saturates at +/- LEAN_MAX_DEG.
	assert_float(BikeScript.lean_target_deg(100.0, 100.0, 1.0)).is_equal(BikeScript.LEAN_MAX_DEG)
	assert_float(BikeScript.lean_target_deg(-100.0, 100.0, -1.0)).is_equal(-BikeScript.LEAN_MAX_DEG)


# --- §6 force hierarchy on every shipped bike spec ----------------------------
## The three bike variants each own a spec (speed / motocross / scooter). All must keep the
## §6 hierarchy (brake > peak drive > handbrake), same guard as the car and Kenney specs.

const BIKE_SPECS := [
	"res://src/vehicles/bike/bike_spec.tres",
	"res://src/vehicles/bike/bike_motocross_spec.tres",
	"res://src/vehicles/bike/bike_scooter_spec.tres",
]

func test_bike_specs_keep_force_hierarchy() -> void:
	for spec_path in BIKE_SPECS:
		var spec: VehicleSpecScript = load(spec_path)
		assert_object(spec).override_failure_message("no spec at " + spec_path).is_not_null()
		var peak_engine := 0.0
		for p in spec.torque_curve:
			peak_engine = maxf(peak_engine, p.y)
		var max_drive: float = peak_engine * spec.gear_ratios[0] * spec.final_drive * spec.efficiency
		var total_brake: float = spec.brake_torque * spec.wheel_positions.size()
		var total_handbrake: float = spec.handbrake_torque * 2.0
		# Full accel + full brake must come to a stop: brake beats peak drive torque.
		assert_float(total_brake).override_failure_message(
				"%s: brake %.0f <= drive %.0f" % [spec_path, total_brake, max_drive]).is_greater(max_drive)
		# Handbrake holds only below ~25% throttle: bracket it against launch torque in D1.
		var drive_25: float = absf(DrivetrainScript.wheel_torque(spec, spec.idle_rpm, 0.25, 1))
		var drive_50: float = absf(DrivetrainScript.wheel_torque(spec, spec.idle_rpm, 0.5, 1))
		assert_float(total_handbrake).override_failure_message(
				"%s: handbrake %.0f <= drive_25 %.0f" % [spec_path, total_handbrake, drive_25]).is_greater(drive_25)
		assert_float(total_handbrake).override_failure_message(
				"%s: handbrake %.0f >= drive_50 %.0f" % [spec_path, total_handbrake, drive_50]).is_less(drive_50)

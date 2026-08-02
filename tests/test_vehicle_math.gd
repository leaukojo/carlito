extends GdUnitTestSuite
## Free-body vehicle math shared by the boat, drone and plane (`VehicleMath`). These
## static fns were duplicated verbatim across the three vehicles and were tested three
## times over; this suite is the union of those cases, so the boat/drone/plane suites
## only cover what is actually their own.
##
## What matters most is the 60 Hz one-tick clamp discipline (RayWheel's rule in a
## free-body flavor): a damper may at most ZERO the motion it opposes within one tick,
## never reverse it, and totals are hard-capped.

const M := preload("res://src/vehicles/base/vehicle_math.gd")

const DELTA := 1.0 / 60.0

# Round numbers so expected values are hand-checkable.
const MASS := 800.0
const INERTIA := 900.0


# --- damped_force: scalar drag / rate damping ----------------------------------

func test_damped_force_opposes_velocity() -> void:
	assert_float(M.damped_force(2.0, 100.0, MASS, DELTA)).is_equal_approx(-200.0, 1e-6)
	assert_float(M.damped_force(-2.0, 100.0, MASS, DELTA)).is_equal_approx(200.0, 1e-6)
	assert_float(M.damped_force(0.0, 100.0, MASS, DELTA)).is_equal(0.0)


func test_damped_force_clamped_to_one_tick_zeroing() -> void:
	# An absurd coefficient may at most ZERO the velocity in one tick, never reverse
	# it (RayWheel's lateral cap — the parked-boat anti-jitter rule).
	var v := 1.5
	var tick_cap := MASS * v / DELTA
	assert_float(M.damped_force(v, 1e12, MASS, DELTA)).is_equal_approx(-tick_cap, 1e-3)


func test_damped_force_used_as_a_torque() -> void:
	# The plane applies the same fn to rotation rates against an inertia.
	assert_float(M.damped_force(2.0, 3.0, INERTIA, DELTA)).is_equal_approx(-6.0, 1e-4)
	var tick_cap := INERTIA * 2.0 / DELTA
	assert_float(M.damped_force(2.0, 1e12, INERTIA, DELTA)).is_equal_approx(-tick_cap, 1e-2)


# --- clamped_damper: the same rule in three dimensions -------------------------

func test_clamped_damper_opposes_velocity() -> void:
	var f := M.clamped_damper(Vector3(2.0, 0.0, 0.0), 3.0, MASS, DELTA)
	assert_vector(f).is_equal_approx(Vector3(-6.0, 0.0, 0.0), Vector3.ONE * 1e-4)


func test_clamped_damper_clamped_to_one_tick_zeroing() -> void:
	var v := Vector3(0.0, 0.0, 1.5)
	var tick_cap := MASS * v.length() / DELTA
	var f := M.clamped_damper(v, 1e12, MASS, DELTA)
	assert_float(f.length()).is_equal_approx(tick_cap, 1e-2)
	# Direction is exactly opposite the velocity (no reversal).
	assert_float(f.normalized().dot(v.normalized())).is_equal_approx(-1.0, 1e-5)


func test_clamped_damper_zero_velocity_is_zero() -> void:
	assert_vector(M.clamped_damper(Vector3.ZERO, 5.0, MASS, DELTA)).is_equal(Vector3.ZERO)


# --- yaw_torque: drives the yaw rate toward target, clamped --------------------

func test_yaw_torque_pushes_toward_target_rate() -> void:
	# Below target: positive torque; above target: negative.
	assert_float(M.yaw_torque(2.0, 0.0, 4.0, 0.6, DELTA, 6.0)).is_greater(0.0)
	assert_float(M.yaw_torque(0.0, 2.0, 4.0, 0.6, DELTA, 6.0)).is_less(0.0)
	# At the target: no torque.
	assert_float(M.yaw_torque(1.5, 1.5, 4.0, 0.6, DELTA, 6.0)).is_equal(0.0)


func test_yaw_torque_capped_and_one_tick_clamped() -> void:
	# A huge gain is capped at max_torque.
	assert_float(M.yaw_torque(5.0, 0.0, 1e6, 0.6, DELTA, 6.0)).is_equal(6.0)
	# With a tiny error the one-tick cap (inertia*err/delta) binds below max_torque.
	var err := 0.001
	var tick_cap := 0.6 * err / DELTA
	assert_float(M.yaw_torque(err, 0.0, 1e6, 0.6, DELTA, 6.0)).is_equal_approx(tick_cap, 1e-4)
	# Same at the plane's scale, where the cap is four orders of magnitude larger.
	var p_err := 0.00001
	var p_cap := INERTIA * p_err / DELTA
	assert_float(M.yaw_torque(p_err, 0.0, 1e9, INERTIA, DELTA, 6000.0)) \
			.is_equal_approx(p_cap, 1e-4)


# --- inertia_of: box footprint, symmetric in its two dimensions ----------------

func test_inertia_of_box_footprint() -> void:
	# m (a^2 + b^2) / 12 with round numbers: 12 * (4 + 2) / 12 = 6.
	assert_float(M.inertia_of(12.0, 2.0, sqrt(2.0))).is_equal_approx(6.0, 1e-5)
	# The boat's hull footprint: 1200 * (16 + 4) / 12 = 2000.
	assert_float(M.inertia_of(1200.0, 4.0, 2.0)).is_equal_approx(2000.0, 1e-6)


func test_inertia_of_is_symmetric_in_its_dimensions() -> void:
	# Why the boat may pass length/width and the flyers width/depth.
	assert_float(M.inertia_of(1200.0, 4.0, 2.0)) \
			.is_equal_approx(M.inertia_of(1200.0, 2.0, 4.0), 1e-6)


# --- pitch / roll extraction (straight from the sim's basis) --------------------

func test_pitch_deg_nose_up_positive() -> void:
	assert_float(M.pitch_deg(Basis.IDENTITY)).is_equal_approx(0.0, 1e-4)
	# Rotating about +X (right axis) lifts the nose/bow (-Z gains +Y).
	assert_float(M.pitch_deg(Basis(Vector3.RIGHT, deg_to_rad(20.0)))) \
			.is_equal_approx(20.0, 1e-4)
	assert_float(M.pitch_deg(Basis(Vector3.RIGHT, deg_to_rad(-35.0)))) \
			.is_equal_approx(-35.0, 1e-4)


func test_roll_deg_starboard_down_positive() -> void:
	assert_float(M.roll_deg(Basis.IDENTITY)).is_equal_approx(0.0, 1e-4)
	# Rotating about the forward axis (-Z) tips the starboard/right side down.
	assert_float(M.roll_deg(Basis(Vector3(0, 0, -1), deg_to_rad(30.0)))) \
			.is_equal_approx(30.0, 1e-4)
	assert_float(M.roll_deg(Basis(Vector3(0, 0, -1), deg_to_rad(-45.0)))) \
			.is_equal_approx(-45.0, 1e-4)
	# atan2 keeps a full capsize/flip readable (contract range -180..180).
	assert_float(absf(M.roll_deg(Basis(Vector3(0, 0, -1), PI)))) \
			.is_equal_approx(180.0, 1e-4)

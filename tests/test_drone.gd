extends GdUnitTestSuite
## Drone flight math. Pure static fns exercised without the physics body — the same
## testing discipline as the boat/RayWheel. What is covered here is what belongs to the
## drone alone: hover equilibrium, the attitude target, self-levelling torque direction,
## arm gating, and the modeled rotor-rpm. The dampers, yaw torque and attitude extraction
## it shares with the boat and plane live in `VehicleMath` — see `test_vehicle_math.gd`.

const D := preload("res://src/vehicles/drone/drone.gd")
const DroneT := preload("res://src/vehicles/drone/drone_telemetry.gd")

# Round numbers so expected values are hand-checkable: a 5 kg drone at g = 10.
const MASS := 5.0
const G := 10.0
const CLIMB_FORCE := 30.0
const MAX_THRUST := 150.0


# --- lift_thrust: hover equilibrium + clamps ----------------------------------

func test_lift_thrust_hovers_against_gravity() -> void:
	# Climb neutral: thrust exactly cancels weight, so a level drone holds altitude.
	assert_float(D.lift_thrust(MASS, G, 0.0, CLIMB_FORCE, MAX_THRUST)).is_equal_approx(MASS * G, 1e-6)


func test_lift_thrust_climb_stick_adds_and_removes_lift() -> void:
	assert_float(D.lift_thrust(MASS, G, 1.0, CLIMB_FORCE, MAX_THRUST)) \
			.is_equal_approx(MASS * G + CLIMB_FORCE, 1e-6)
	assert_float(D.lift_thrust(MASS, G, -1.0, CLIMB_FORCE, MAX_THRUST)) \
			.is_equal_approx(MASS * G - CLIMB_FORCE, 1e-6)


func test_lift_thrust_never_negative_and_hard_capped() -> void:
	# Full-down with a climb force larger than weight still can't suck the drone down.
	assert_float(D.lift_thrust(MASS, G, -1.0, 200.0, MAX_THRUST)).is_equal(0.0)
	# Runaway demand is capped at max_thrust (the max_suspension_force analogue).
	assert_float(D.lift_thrust(MASS, G, 1.0, 1e6, MAX_THRUST)).is_equal(MAX_THRUST)


# --- level_target_up: attitude target ------------------------------------------

func test_level_target_up_level_is_straight_up() -> void:
	assert_vector(D.level_target_up(Basis.IDENTITY, 0.0)).is_equal_approx(Vector3.UP, Vector3.ONE * 1e-5)


func test_level_target_up_positive_tilt_leans_the_up_vector_back() -> void:
	# Facing -Z (north). POSITIVE tilt tips the up-vector backward (+Z) — the nose-up /
	# backward-flight lean (the caller negates throttle, so W maps to negative tilt).
	var up := D.level_target_up(Basis.IDENTITY, deg_to_rad(20.0))
	assert_float(up.z).is_greater(0.0)      # leaned toward +Z (backward)
	assert_float(up.x).is_equal_approx(0.0, 1e-5)  # no roll introduced
	assert_float(up.y).is_equal_approx(cos(deg_to_rad(20.0)), 1e-5)


# --- align_torque: self-levelling direction is correct by construction ---------

func test_align_torque_rotates_body_up_toward_target() -> void:
	# Body rolled so its up leans to +X; target is world up. The torque must rotate the
	# up-vector back toward vertical (a positive rotation about +Z reduces a +X lean).
	var s := sin(deg_to_rad(15.0))
	var c := cos(deg_to_rad(15.0))
	var body_up := Vector3(s, c, 0.0)
	var tau := D.align_torque(body_up, Vector3.UP, 4.0)
	assert_vector(tau).is_equal_approx(Vector3(0.0, 0.0, s * 4.0), Vector3.ONE * 1e-4)
	# Already level: no corrective torque.
	assert_vector(D.align_torque(Vector3.UP, Vector3.UP, 4.0)).is_equal_approx(Vector3.ZERO, Vector3.ONE * 1e-6)


# --- rotor_rpm: honest model + arm gating --------------------------------------

func test_rotor_rpm_zero_when_disarmed() -> void:
	assert_int(D.rotor_rpm(MASS * G, MAX_THRUST, 2600, 12000, false)).is_equal(0)


func test_rotor_rpm_scales_with_thrust_fraction() -> void:
	# Disarmed floor aside, armed rpm interpolates spin_min..spin_max by thrust/max.
	assert_int(D.rotor_rpm(0.0, MAX_THRUST, 2600, 12000, true)).is_equal(2600)
	assert_int(D.rotor_rpm(MAX_THRUST, MAX_THRUST, 2600, 12000, true)).is_equal(12000)
	# Hover thrust (50 of 150 = 1/3) sits a third of the way up.
	assert_int(D.rotor_rpm(50.0, 150.0, 0, 12000, true)).is_equal(4000)


# --- telemetry bridge coverage -------------------------------------------------

func test_drone_telemetry_bridge_dict_adds_flight_fields() -> void:
	var t := DroneT.new()
	t.altitude = 42.0
	t.vspeed = -1.5
	t.rotor_rpm = 8000
	t.armed = true
	t.pitch = 6.0
	t.roll = -3.0
	var d := t.to_bridge_dict()
	assert_float(d["altitude"]).is_equal(42.0)
	assert_float(d["vspeed"]).is_equal(-1.5)
	assert_int(d["rotor_rpm"]).is_equal(8000)
	assert_bool(d["armed"]).is_true()
	assert_float(d["pitch"]).is_equal(6.0)
	assert_float(d["roll"]).is_equal(-3.0)
	# Base fields still ride along (super() first, tractor/boat pattern).
	assert_bool(d.has("speed")).is_true()
	assert_bool(d.has("status")).is_true()

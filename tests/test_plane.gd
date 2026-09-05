extends GdUnitTestSuite
## Plane flight math: lift/stall, control authority, torques, thrust, flap slew.
## Shared systems (dampers, yaw, attitude) in VehicleMath via test_vehicle_math.gd.

const P := preload("res://src/vehicles/plane/plane.gd")
const PlaneSpec := preload("res://src/vehicles/plane/plane_spec.tres")
const PlaneT := preload("res://src/vehicles/plane/plane_telemetry.gd")

const DELTA := 1.0 / 60.0

const IDLE := 1000.0
const REDLINE := 5000.0
const MAX_THRUST := 4000.0
const STALL := 15.0
const FULL_LIFT := 25.0
const INERTIA := 5000.0

const GEAR_N := 0x00
const GEAR_D1 := 0x01
const GEAR_R := 0xFF


# --- prop_rpm_step: spool lag ---------------------------------------------------

func test_prop_rpm_step_moves_toward_target_at_rate() -> void:
	# 1200 rpm/s for one tick = 20 rpm of travel.
	assert_float(P.prop_rpm_step(1000.0, 5000.0, 1200.0, DELTA)).is_equal_approx(1020.0, 1e-4)
	assert_float(P.prop_rpm_step(1000.0, 0.0, 1200.0, DELTA)).is_equal_approx(980.0, 1e-4)


func test_prop_rpm_step_never_overshoots() -> void:
	assert_float(P.prop_rpm_step(4995.0, 5000.0, 1200.0, DELTA)).is_equal(5000.0)


# --- thrust_frac + prop_thrust: rpm-derived, gear owns direction ----------------

func test_thrust_frac_zero_at_idle_full_at_redline() -> void:
	assert_float(P.thrust_frac(IDLE, IDLE, REDLINE)).is_equal(0.0)
	assert_float(P.thrust_frac(REDLINE, IDLE, REDLINE)).is_equal(1.0)
	# Engine stopped (below idle) still reads 0; no negative thrust from dead prop.
	assert_float(P.thrust_frac(0.0, IDLE, REDLINE)).is_equal(0.0)
	# Halfway up: (3000 - 1000) / 4000 = 0.5.
	assert_float(P.thrust_frac(3000.0, IDLE, REDLINE)).is_equal_approx(0.5, 1e-6)


func test_prop_thrust_signed_by_gear() -> void:
	# Full rpm: D = +max, R = -max * reverse_frac, N = none.
	assert_float(P.prop_thrust(REDLINE, IDLE, REDLINE, MAX_THRUST, GEAR_D1, 0.25)) \
			.is_equal_approx(MAX_THRUST, 1e-4)
	assert_float(P.prop_thrust(REDLINE, IDLE, REDLINE, MAX_THRUST, GEAR_R, 0.25)) \
			.is_equal_approx(-MAX_THRUST * 0.25, 1e-4)
	assert_float(P.prop_thrust(REDLINE, IDLE, REDLINE, MAX_THRUST, GEAR_N, 0.25)).is_equal(0.0)


func test_prop_thrust_capped_by_construction() -> void:
	assert_float(P.prop_thrust(1e6, IDLE, REDLINE, MAX_THRUST, GEAR_D1, 0.25)) \
			.is_equal(MAX_THRUST)


# --- flap_slew: travel rate ------------------------------------------------------

func test_flap_slew_moves_at_rate_and_clamps_target() -> void:
	# 0.6/s for one tick = 0.01 of travel.
	assert_float(P.flap_slew(0.0, 1.0, 0.6, DELTA)).is_equal_approx(0.01, 1e-6)
	assert_float(P.flap_slew(1.0, 0.0, 0.6, DELTA)).is_equal_approx(0.99, 1e-6)
	assert_float(P.flap_slew(1.0, 5.0, 0.6, DELTA)).is_equal(1.0)


# --- deflect_rad: cosmetic control-surface travel ---------------------------------

func test_deflect_rad_scales_command_and_is_signed() -> void:
	assert_float(P.deflect_rad(0.0, 20.0)).is_equal(0.0)
	assert_float(P.deflect_rad(1.0, 20.0)).is_equal_approx(deg_to_rad(20.0), 1e-6)
	assert_float(P.deflect_rad(-1.0, 20.0)).is_equal_approx(deg_to_rad(-20.0), 1e-6)
	assert_float(P.deflect_rad(0.5, 20.0)).is_equal_approx(deg_to_rad(10.0), 1e-6)


func test_deflect_rad_clamps_to_authored_travel() -> void:
	assert_float(P.deflect_rad(5.0, 20.0)).is_equal_approx(deg_to_rad(20.0), 1e-6)
	assert_float(P.deflect_rad(-5.0, 20.0)).is_equal_approx(deg_to_rad(-20.0), 1e-6)


# --- lift_frac: the simplified stall curve --------------------------------------

func test_lift_frac_zero_at_stall_full_at_full_lift() -> void:
	assert_float(P.lift_frac(STALL, STALL, FULL_LIFT)).is_equal(0.0)
	assert_float(P.lift_frac(0.0, STALL, FULL_LIFT)).is_equal(0.0)
	assert_float(P.lift_frac(FULL_LIFT, STALL, FULL_LIFT)).is_equal(1.0)
	assert_float(P.lift_frac(100.0, STALL, FULL_LIFT)).is_equal(1.0)
	# Midpoint of the smoothstep: t = 0.5 -> 0.5.
	assert_float(P.lift_frac(20.0, STALL, FULL_LIFT)).is_equal_approx(0.5, 1e-5)


func test_lift_frac_monotonic() -> void:
	var prev := -1.0
	for i in 11:
		var f: float = P.lift_frac(STALL + float(i), STALL, FULL_LIFT)
		assert_float(f).is_greater_equal(prev)
		prev = f


# --- lift_force: speed-squared, capped, forward-only ----------------------------

func test_lift_force_speed_squared() -> void:
	# coeff 10 at 20 m/s, full fraction: 10 * 400 = 4000 N.
	assert_float(P.lift_force(20.0, 10.0, 1e6, 1.0)).is_equal_approx(4000.0, 1e-3)
	# The stall fraction scales it straight down.
	assert_float(P.lift_force(20.0, 10.0, 1e6, 0.5)).is_equal_approx(2000.0, 1e-3)


func test_lift_force_capped_and_no_backward_lift() -> void:
	assert_float(P.lift_force(1000.0, 10.0, 16000.0, 1.0)).is_equal(16000.0)
	# Sliding backward generates no lift (never a tail-slide launch).
	assert_float(P.lift_force(-30.0, 10.0, 16000.0, 1.0)).is_equal(0.0)


# --- control_authority: no airflow = no control ---------------------------------

func test_control_authority_scales_with_airspeed() -> void:
	assert_float(P.control_authority(0.0, 15.0)).is_equal(0.0)
	assert_float(P.control_authority(7.5, 15.0)).is_equal_approx(0.5, 1e-6)
	assert_float(P.control_authority(15.0, 15.0)).is_equal(1.0)
	assert_float(P.control_authority(60.0, 15.0)).is_equal(1.0)
	# Backward airflow still gives authority (absf) — a stalled slide stays recoverable.
	assert_float(P.control_authority(-15.0, 15.0)).is_equal(1.0)


# --- pitch/roll torques: authority-scaled, damped, hard-capped ------------------

func test_pitch_torque_elevator_direction_and_authority() -> void:
	# + elevator = + torque (nose up); zero authority = zero command.
	assert_float(P.pitch_torque(1.0, 1000.0, 1.0, 0.0, 500.0, INERTIA, DELTA, 1e6)) \
			.is_equal_approx(1000.0, 1e-4)
	assert_float(P.pitch_torque(1.0, 1000.0, 0.0, 0.0, 500.0, INERTIA, DELTA, 1e6)).is_equal(0.0)
	# The damper opposes an existing pitch rate.
	assert_float(P.pitch_torque(0.0, 1000.0, 1.0, 2.0, 500.0, INERTIA, DELTA, 1e6)) \
			.is_equal_approx(-1000.0, 1e-4)


func test_pitch_torque_hard_capped() -> void:
	assert_float(P.pitch_torque(1.0, 1e9, 1.0, 0.0, 0.0, INERTIA, DELTA, 12000.0)) \
			.is_equal(12000.0)


func test_roll_torque_springs_toward_target_bank() -> void:
	# Wings level, commanding +30 deg (right side down): positive torque about forward.
	var spring := deg_to_rad(30.0) * 1000.0
	assert_float(P.roll_torque(30.0, 0.0, 1000.0, 1.0, 0.0, 500.0, INERTIA, DELTA, 1e6)) \
			.is_equal_approx(spring, 1e-3)
	# Banked with no command: the spring levels the wings (negative torque).
	assert_float(P.roll_torque(0.0, 30.0, 1000.0, 1.0, 0.0, 500.0, INERTIA, DELTA, 1e6)) \
			.is_equal_approx(-spring, 1e-3)
	# No authority = no spring (a parked plane can't roll itself).
	assert_float(P.roll_torque(30.0, 0.0, 1000.0, 0.0, 0.0, 500.0, INERTIA, DELTA, 1e6)) \
			.is_equal(0.0)


func test_roll_torque_hard_capped() -> void:
	assert_float(P.roll_torque(45.0, -45.0, 1e9, 1.0, 0.0, 0.0, INERTIA, DELTA, 9000.0)) \
			.is_equal(9000.0)


# --- stall_torque: nose drops as lift fades -------------------------------------

func test_stall_torque_zero_with_full_lift_full_gain_stalled() -> void:
	assert_float(P.stall_torque(1.0, 6000.0)).is_equal(0.0)
	# Fully stalled: the whole gain, nose DOWN (negative about body right).
	assert_float(P.stall_torque(0.0, 6000.0)).is_equal(-6000.0)
	assert_float(P.stall_torque(0.5, 6000.0)).is_equal_approx(-3000.0, 1e-4)


# --- telemetry bridge coverage ---------------------------------------------------

func test_plane_telemetry_bridge_dict_adds_flight_fields() -> void:
	var t := PlaneT.new()
	t.altitude = 120.0
	t.vspeed = 2.5
	t.flaps_actual = 40
	t.pitch = 8.0
	t.roll = -12.0
	var d := t.to_bridge_dict()
	assert_float(d["altitude"]).is_equal(120.0)
	assert_float(d["vspeed"]).is_equal(2.5)
	assert_int(d["flaps_actual"]).is_equal(40)
	assert_float(d["pitch"]).is_equal(8.0)
	assert_float(d["roll"]).is_equal(-12.0)
	# Base fields still ride along (super() first) — the plane declares all of these.
	assert_bool(d.has("rpm")).is_true()
	assert_bool(d.has("gear")).is_true()
	assert_bool(d.has("fuel")).is_true()
	assert_bool(d.has("coolant")).is_true()
	assert_bool(d.has("ground")).is_true()
# --- the gearbox that never shifts ------------------------------------------------

## The plane is single-speed by construction, and only because two numbers happen to sit the
## right way round: shift_up_rpm (6000) is ABOVE redline_rpm (5400), and auto_shift decides on
## `rpm_from_wheel`, which is clamped at the redline. So gear 1 is the only gear, and the
## contract's `gear` publishes a constant 1 in D. Nothing else holds that — someone "fixing" the
## shift point to 5000 would give a fixed-pitch light aircraft a working gearbox, change a
## published wire signal and change no physics at all. It fails HERE instead.
func test_the_plane_never_leaves_gear_one() -> void:
	var spec: VehicleSpec = PlaneSpec
	assert_float(spec.shift_up_rpm).override_failure_message(
			"the plane's shift point (%.0f) is at or below its redline (%.0f) — it would now shift"
			% [spec.shift_up_rpm, spec.redline_rpm]).is_greater(spec.redline_rpm)
	# Sweep the whole usable band, endpoints included: gear 1 in, gear 1 out.
	for step in 41:
		var at_rpm: float = lerpf(spec.idle_rpm, spec.redline_rpm, float(step) / 40.0)
		assert_int(Drivetrain.auto_shift(spec, 1, at_rpm)).override_failure_message(
				"the plane upshifted at %.0f rpm" % at_rpm).is_equal(1)


func test_the_planes_published_rpm_cannot_reach_its_shift_point() -> void:
	# The other half: it is the CLAMP that makes the sweep above exhaustive. However fast the
	# wheels turn, the value auto_shift is handed tops out at the redline.
	var spec: VehicleSpec = PlaneSpec
	for omega in [0.0, 50.0, 500.0, 20000.0]:
		var at_rpm := Drivetrain.rpm_from_wheel(spec, omega, 1)
		assert_float(at_rpm).override_failure_message(
				"wheel omega %.0f rad/s reads %.0f rpm, past the %.0f redline"
				% [omega, at_rpm, spec.redline_rpm]).is_less_equal(spec.redline_rpm)
		assert_float(at_rpm).is_less(spec.shift_up_rpm)

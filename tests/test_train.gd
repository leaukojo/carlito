extends GdUnitTestSuite
## Train consist sim + placement + aux-model math. Load-bearing checks: 60 Hz one-tick clamps
## (couplers, brakes) and force hierarchy (brake > traction).

const Sim := preload("res://src/vehicles/train/train_sim.gd")
const Place := preload("res://src/vehicles/train/train_placement.gd")
const TrainT := preload("res://src/vehicles/train/train_telemetry.gd")

const DELTA := 1.0 / 60.0


# --- tractive effort: constant force then constant power ------------------------------------

func test_tractive_effort_constant_below_base_speed() -> void:
	assert_float(Sim.tractive_effort(5.0, 1.0, 10.0, 1000.0, 10000.0)).is_equal_approx(1000.0, 1e-6)
	assert_float(Sim.tractive_effort(0.0, 1.0, 10.0, 1000.0, 10000.0)).is_equal_approx(1000.0, 1e-6)


func test_tractive_effort_power_limited_above_base_speed() -> void:
	# P/v = 10000/20 = 500 at twice base speed.
	assert_float(Sim.tractive_effort(20.0, 1.0, 10.0, 1000.0, 10000.0)).is_equal_approx(500.0, 1e-6)


func test_tractive_effort_signed_by_reverser_not_speed() -> void:
	assert_float(Sim.tractive_effort(5.0, -1.0, 10.0, 1000.0, 10000.0)).is_equal_approx(-1000.0, 1e-6)
	assert_float(Sim.tractive_effort(-5.0, 1.0, 10.0, 1000.0, 10000.0)).is_equal_approx(1000.0, 1e-6)
	assert_float(Sim.tractive_effort(5.0, 0.0, 10.0, 1000.0, 10000.0)).is_equal(0.0)
	assert_float(Sim.tractive_effort(5.0, 0.5, 10.0, 1000.0, 10000.0)).is_equal_approx(500.0, 1e-6)


# --- davis resistance ----------------------------------------------------------------------

func test_davis_resistance_opposes_motion_zero_at_rest() -> void:
	assert_float(Sim.davis_resistance(0.0, 400.0, 15.0, 0.8)).is_equal(0.0)
	# Magnitude: a + b|v| + c v^2
	assert_float(Sim.davis_resistance(10.0, 400.0, 15.0, 0.8)).is_equal_approx(-(400.0 + 150.0 + 80.0), 1e-6)
	assert_float(Sim.davis_resistance(-10.0, 400.0, 15.0, 0.8)).is_equal_approx(400.0 + 150.0 + 80.0, 1e-6)


# --- brake force: opposes velocity, one-tick clamp ------------------------------------------

func test_brake_force_opposes_velocity() -> void:
	assert_float(Sim.brake_force(10.0, 1.0, 0.0, 200.0, 100.0, DELTA)).is_equal_approx(-200.0, 1e-6)
	assert_float(Sim.brake_force(-10.0, 1.0, 0.0, 200.0, 100.0, DELTA)).is_equal_approx(200.0, 1e-6)
	assert_float(Sim.brake_force(10.0, 0.5, 1.0, 200.0, 100.0, DELTA)).is_equal_approx(-200.0, 1e-6)


func test_brake_force_zero_at_standstill() -> void:
	assert_float(Sim.brake_force(0.0, 1.0, 0.0, 200.0, 100.0, DELTA)).is_equal(0.0)


func test_brake_force_clamped_to_one_tick_zeroing() -> void:
	# Clamp: mass*|v|/delta (never reverse, like boat's damped_force).
	var v := 0.001
	var cap := 100.0 * v / DELTA
	assert_float(Sim.brake_force(v, 1.0, 0.0, 1e9, 100.0, DELTA)).is_equal_approx(-cap, 1e-6)


# --- grade holdback ------------------------------------------------------------------------

func test_grade_force_holdback_sign() -> void:
	assert_float(Sim.grade_force(100.0, 0.0, 10.0)).is_equal(0.0)
	# Climbing (+grade in +s) retards; descending assists.
	assert_float(Sim.grade_force(100.0, 0.05, 10.0)).is_equal_approx(-100.0 * 10.0 * sin(atan(0.05)), 1e-6)
	assert_bool(Sim.grade_force(100.0, 0.05, 10.0) < 0.0).is_true()
	assert_bool(Sim.grade_force(100.0, -0.05, 10.0) > 0.0).is_true()


# --- couplers: slack, spring, one-tick damper clamp, hard cap -------------------------------

func test_coupler_free_inside_slack() -> void:
	# Slack deadband carries no force.
	assert_float(Sim.coupler_force(6.03, 6.0, 0.05, 5.0, 1e6, 1e5, 50.0, DELTA, 1e6)).is_equal(0.0)


func test_coupler_spring_beyond_slack_is_tension() -> void:
	# Stretched 0.1 past rest, 0.05 slack -> 0.05 effective.
	assert_float(Sim.coupler_force(6.1, 6.0, 0.05, 0.0, 1e6, 0.0, 50.0, DELTA, 1e9)) \
			.is_equal_approx(1e6 * 0.05, 1e-3)
	assert_bool(Sim.coupler_force(5.9, 6.0, 0.05, 0.0, 1e6, 0.0, 50.0, DELTA, 1e9) < 0.0).is_true()


func test_coupler_damper_clamped_to_one_tick_relative_reversal() -> void:
	# Damper caps at reduced_mass*|rel_vel|/delta.
	var rel := 10.0
	var cap := 50.0 * rel / DELTA
	var f := Sim.coupler_force(6.1, 6.0, 0.05, rel, 1e6, 1e12, 50.0, DELTA, 1e12)
	assert_float(f).is_equal_approx(1e6 * 0.05 + cap, 1e-1)


func test_coupler_force_hard_capped() -> void:
	# Drawbar rating hard cap.
	assert_float(Sim.coupler_force(10.0, 6.0, 0.05, 0.0, 1e6, 0.0, 50.0, DELTA, 500000.0)) \
			.is_equal(500000.0)


# --- integrated sim: hierarchy + stability -------------------------------------------------

func _straight_sim() -> RefCounted:
	var sim: RefCounted = Sim.new()
	sim.setup(PackedFloat64Array([50000.0, 34000.0, 34000.0]),
			PackedFloat64Array([6.5, 6.24]), 0.0, false, 0.0)
	return sim


func _consist_sim() -> RefCounted:
	var sim: RefCounted = Sim.new()
	sim.setup(PackedFloat64Array([50000.0, 34000.0, 34000.0, 34000.0, 34000.0]),
			PackedFloat64Array([6.5, 6.24, 6.24, 6.24]), 0.0, false, 0.0)
	return sim


func test_full_service_brake_capacity_exceeds_traction() -> void:
	# Brake > traction per hierarchy.
	var sim := _consist_sim()
	assert_bool(float(sim.masses.size()) * sim.max_brake > sim.max_tractive).is_true()


func test_full_brake_beats_full_traction() -> void:
	# Braked wagons load drawbar, drag train down.
	var sim := _consist_sim()
	for i in sim.v.size():
		sim.v[i] = 10.0
	for _t in 60:
		sim.step(DELTA, 1.0, 1.0, 0.0, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0]))
	assert_bool(sim.v[0] < 10.0).is_true()


func test_integrator_stable_over_bumpy_grades() -> void:
	var sim := _straight_sim()
	for step in 600:
		var g := 0.03 * sin(float(step) * 0.05)
		sim.step(DELTA, 0.5, 0.0, 0.0, PackedFloat64Array([g, g, g]))
	for i in sim.v.size():
		assert_bool(is_finite(sim.v[i])).is_true()
		assert_bool(absf(sim.v[i]) < 200.0).is_true()


func test_setup_spaces_cars_behind_the_head() -> void:
	var sim := _straight_sim()
	assert_float(sim.s[0]).is_equal(0.0)
	assert_float(sim.s[1]).is_equal_approx(-6.5, 1e-6)
	assert_float(sim.s[2]).is_equal_approx(-6.5 - 6.24, 1e-6)


func test_traction_accelerates_and_grade_holds_back() -> void:
	var flat := _straight_sim()
	for _s in 120:
		flat.step(DELTA, 1.0, 0.0, 0.0, PackedFloat64Array([0.0, 0.0, 0.0]))
	assert_bool(flat.v[0] > 0.5).is_true()
	var hill := _straight_sim()
	for _s in 120:
		hill.step(DELTA, 1.0, 0.0, 0.0, PackedFloat64Array([0.04, 0.04, 0.04]))
	assert_bool(hill.v[0] < flat.v[0]).is_true()


# --- placement: bogie-chord pose -----------------------------------------------------------

func test_pose_from_bogies_midpoint_and_forward() -> void:
	# Origin = bogie midpoint; -Z along chord. Basis orthonormal + right-handed (det +1).
	var t: Transform3D = Place.pose_from_bogies(Vector3(2, 0, 0), Vector3(-2, 0, 0))
	assert_vector(t.origin).is_equal_approx(Vector3.ZERO, Vector3.ONE * 1e-5)
	assert_vector(-t.basis.z).is_equal_approx(Vector3.RIGHT, Vector3.ONE * 1e-5)
	assert_vector(t.basis.y).is_equal_approx(Vector3.UP, Vector3.ONE * 1e-5)
	assert_float(t.basis.determinant()).is_equal_approx(1.0, 1e-5)


func test_car_pose_is_right_handed_on_a_slope() -> void:
	var t: Transform3D = Place.pose_from_bogies(Vector3(3, 1, 0), Vector3(-3, -1, 0))
	assert_float(t.basis.determinant()).is_equal_approx(1.0, 1e-5)
	assert_bool((-t.basis.z).y > 0.0).is_true()


func test_pose_from_bogies_lift_raises_origin() -> void:
	var t: Transform3D = Place.pose_from_bogies(Vector3(2, 5, 0), Vector3(-2, 5, 0), 0.12)
	assert_float(t.origin.y).is_equal_approx(5.12, 1e-5)


func test_car_pose_on_a_circle_is_tangent() -> void:
	var curve := Curve3D.new()
	var r := 40.0
	var segs := 240
	for i in segs:
		var a := TAU * float(i) / float(segs)
		curve.add_point(Vector3(r * cos(a), 0.0, r * sin(a)))
	curve.add_point(Vector3(r, 0.0, 0.0))
	var length := curve.get_baked_length()
	var pose: Transform3D = Place.car_pose(curve, Transform3D.IDENTITY, length * 0.25, 1.2, true, length)
	assert_float(Vector2(pose.origin.x, pose.origin.z).length()).is_equal_approx(r, 0.2)
	var fwd := -pose.basis.z
	assert_float(fwd.y).is_equal_approx(0.0, 1e-3)
	var radial := Vector3(pose.origin.x, 0.0, pose.origin.z).normalized()
	assert_float(fwd.dot(radial)).is_equal_approx(0.0, 1e-2)


# --- aux honest models ---------------------------------------------------------------------

func test_motor_current_from_traction_clamped() -> void:
	assert_float(TrainT.motor_current_amps(320000.0, 1.0 / 320.0, 1500.0)).is_equal_approx(1000.0, 1e-6)
	assert_float(TrainT.motor_current_amps(-1e9, 1.0 / 320.0, 1500.0)).is_equal(1500.0)


func test_catenary_sags_with_current() -> void:
	assert_float(TrainT.catenary_volts_model(0.0, 25000.0, 2.0)).is_equal(25000.0)
	assert_float(TrainT.catenary_volts_model(1000.0, 25000.0, 2.0)).is_equal(23000.0)
	assert_float(TrainT.catenary_volts_model(1e9, 25000.0, 2.0)).is_equal(0.0)


func test_brake_pipe_vents_and_recharges() -> void:
	var vented := TrainT.brake_pipe_step(5.0, 1.0, 1.0, 6.0, 1.5, 3.0)
	assert_bool(vented < 5.0).is_true()
	var recharged := TrainT.brake_pipe_step(2.0, 0.0, 1.0, 6.0, 1.5, 3.0)
	assert_bool(recharged > 2.0).is_true()


func test_train_bridge_dict_has_real_values() -> void:
	var t := TrainT.new()
	t.motor_current = 800.0
	t.catenary_volts = 23400.0
	t.brake_pipe = 4.2
	t.grade = -3
	t.coupler_force = 120.0
	t.pantograph_state = true
	t.doors_state = false
	var d := t.to_bridge_dict()
	assert_float(d["motor_current"]).is_equal(800.0)
	assert_float(d["catenary_volts"]).is_equal(23400.0)
	assert_int(d["grade"]).is_equal(-3)
	assert_bool(d["pantograph_state"]).is_true()
	assert_bool(d.has("speed")).is_true()
	assert_bool(d.has("status")).is_true()

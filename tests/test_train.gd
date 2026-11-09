extends GdUnitTestSuite
## Train consist sim + placement + aux-model math. Load-bearing checks: 60 Hz one-tick clamps
## (couplers, brakes) and force hierarchy (brake > traction).

const Sim := preload("res://src/vehicles/train/train_sim.gd")
const Place := preload("res://src/vehicles/train/train_placement.gd")
const TrainT := preload("res://src/vehicles/train/train_telemetry.gd")
const TrainVeh := preload("res://src/vehicles/train/train.gd")
const ContractScript := preload("res://src/bridge/contract.gd")

const DELTA := 1.0 / 60.0


# --- tractive effort: the grip limit then constant power ------------------------------------

func test_tractive_effort_grip_limited_at_low_speed() -> void:
	assert_float(Sim.tractive_effort(5.0, 1.0, 1000.0, 10000.0)).is_equal_approx(1000.0, 1e-6)
	assert_float(Sim.tractive_effort(0.0, 1.0, 1000.0, 10000.0)).is_equal_approx(1000.0, 1e-6)


func test_tractive_effort_power_limited_at_speed() -> void:
	# P/v = 10000/20 = 500 at twice the 10 m/s corner where P/v meets the grip limit.
	assert_float(Sim.tractive_effort(20.0, 1.0, 1000.0, 10000.0)).is_equal_approx(500.0, 1e-6)


func test_tractive_effort_signed_by_reverser_not_speed() -> void:
	assert_float(Sim.tractive_effort(5.0, -1.0, 1000.0, 10000.0)).is_equal_approx(-1000.0, 1e-6)
	assert_float(Sim.tractive_effort(-5.0, 1.0, 1000.0, 10000.0)).is_equal_approx(1000.0, 1e-6)
	assert_float(Sim.tractive_effort(5.0, 0.0, 1000.0, 10000.0)).is_equal(0.0)
	assert_float(Sim.tractive_effort(5.0, 0.5, 1000.0, 10000.0)).is_equal_approx(500.0, 1e-6)


# --- davis resistance ----------------------------------------------------------------------

func test_davis_resistance_opposes_motion_zero_at_rest() -> void:
	assert_float(Sim.davis_resistance(0.0, 400.0, 15.0, 0.8)).is_equal(0.0)
	# Magnitude: a + b|v| + c v^2
	assert_float(Sim.davis_resistance(10.0, 400.0, 15.0, 0.8)).is_equal_approx(-(400.0 + 150.0 + 80.0), 1e-6)
	assert_float(Sim.davis_resistance(-10.0, 400.0, 15.0, 0.8)).is_equal_approx(400.0 + 150.0 + 80.0, 1e-6)


# --- brake: Coulomb friction applied last ----------------------------------------------------

func test_brake_step_removes_demand_toward_zero() -> void:
	assert_float(Sim.brake_step(10.0, 200.0, 100.0, DELTA)).is_equal_approx(10.0 - 200.0 / 100.0 * DELTA, 1e-9)
	assert_float(Sim.brake_step(-10.0, 200.0, 100.0, DELTA)).is_equal_approx(-10.0 + 200.0 / 100.0 * DELTA, 1e-9)


func test_brake_step_never_reverses() -> void:
	assert_float(Sim.brake_step(0.001, 1e9, 100.0, DELTA)).is_equal(0.0)
	assert_float(Sim.brake_step(-0.001, 1e9, 100.0, DELTA)).is_equal(0.0)


func test_brake_step_without_demand_is_a_no_op() -> void:
	assert_float(Sim.brake_step(3.0, 0.0, 100.0, DELTA)).is_equal(3.0)
	assert_float(Sim.brake_step(0.0, 0.0, 100.0, DELTA)).is_equal(0.0)


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


## The consist TrainVehicle builds (`_build_sim`, through the same `car_masses` / `rest_gaps`) at
## its loco_mass / wagon_mass defaults, so an edit to any of them moves the tests that use it.
func _real_consist_sim() -> RefCounted:
	var loco := TrainVeh.new()
	var m := TrainVeh.car_masses(loco.loco_mass, loco.wagon_mass)
	loco.free()
	var sim: RefCounted = Sim.new()
	sim.setup(m, TrainVeh.rest_gaps(), 0.0, false, 0.0)
	return sim


func test_full_service_brake_capacity_exceeds_traction() -> void:
	# The real consist (`_real_consist_sim`), not sim literals — TrainSim's tuning is its own
	# defaults, never set by TrainVehicle (train_sim.gd header); max_brake and the grip limit are
	# read off it rather than retyped here for the same reason.
	var sim := _real_consist_sim()
	var n: int = sim.masses.size()
	var total_mass := 0.0
	for m in sim.masses:
		total_mass += m
	assert_bool(float(n) * sim.max_brake > sim.adhesion_force()).is_true()
	# ...and by a real margin: full service braking must hold back a meaningful fraction of a g,
	# not an arithmetic coincidence that a heavier wagon could erase.
	var decel_g: float = (float(n) * sim.max_brake) / total_mass / Sim.GRAVITY
	assert_float(decel_g).override_failure_message(
			"full service brake only holds back %.3f g of the consist" % decel_g) \
		.is_greater(0.05)


func test_full_brake_beats_full_traction() -> void:
	# Braked wagons load drawbar, drag train down.
	var sim := _consist_sim()
	for i in sim.v.size():
		sim.v[i] = 10.0
	for _t in 60:
		sim.step(DELTA, 1.0, 1.0, 0.0, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0]))
	assert_bool(sim.v[0] < 10.0).is_true()


func _stop_distance(sim: RefCounted, brake: float) -> float:
	for i in sim.v.size():
		sim.v[i] = 20.0
	var start: float = sim.s[0]
	var grades := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
	for _t in 3000:
		sim.step(DELTA, 0.0, brake, 0.0, grades)
		if sim.v[0] == 0.0:
			break
	return sim.s[0] - start


func test_a_moving_train_still_stops_in_the_same_distance() -> void:
	assert_float(_stop_distance(_consist_sim(), 1.0)).is_equal_approx(81.9, 0.5)


func test_a_braked_train_holds_at_rest_on_a_grade() -> void:
	var sim := _consist_sim()
	var grades := PackedFloat64Array([0.05, 0.05, 0.05, 0.05, 0.05])
	for _t in 600:
		sim.step(DELTA, 0.0, 1.0, 0.0, grades)
	for i in sim.v.size():
		assert_float(sim.v[i]).is_equal(0.0)
	assert_float(sim.loco_accel).is_equal(0.0)


func test_a_weak_brake_lets_the_train_roll_down_a_grade() -> void:
	var sim := _consist_sim()
	sim.max_brake = 1000.0
	var grades := PackedFloat64Array([0.05, 0.05, 0.05, 0.05, 0.05])
	for _t in 600:
		sim.step(DELTA, 0.0, 1.0, 0.0, grades)
	assert_bool(sim.v[0] < -1.0).is_true()


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


func test_adhesion_caps_the_head_pull() -> void:
	var sim := _real_consist_sim()
	var grip: float = sim.mu_adh * sim.masses[0] * Sim.GRAVITY
	assert_float(sim.adhesion_force()).is_equal_approx(grip, 1e-6)
	var flat := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
	sim.step(DELTA, 1.0, 0.0, 0.0, flat)
	assert_float(sim.head_traction).is_equal_approx(grip, 1e-6)
	# Past the corner (P / grip) the pull is the power's, under the grip limit.
	var fast: float = 2.0 * sim.max_power() / grip
	for i in sim.v.size():
		sim.v[i] = fast
	sim.step(DELTA, 1.0, 0.0, 0.0, flat)
	assert_float(sim.head_traction).is_equal_approx(sim.max_power() / fast, 1.0)
	assert_bool(sim.head_traction < grip).is_true()


func test_a_grip_retune_after_setup_takes_effect() -> void:
	var sim := _real_consist_sim()
	sim.mu_adh = 0.2
	sim.step(DELTA, 1.0, 0.0, 0.0, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0]))
	assert_float(sim.head_traction).is_equal_approx(0.2 * sim.masses[0] * Sim.GRAVITY, 1e-6)


func test_the_consist_starts_inside_the_sourced_range() -> void:
	# Starting acceleration: N700 0.72 m/s² (its maximum) to Class 345's 1 m/s² (docs/sources.md,
	# The train's pull), the mean over the first 10 s of a full-throttle start on the flat. The
	# consist's speed is its momentum over its mass, so the couplers' ringing does not move it.
	var sim := _real_consist_sim()
	var flat := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
	for _t in 600:
		sim.step(DELTA, 1.0, 0.0, 0.0, flat)
	var momentum := 0.0
	var total_mass := 0.0
	for i in sim.v.size():
		momentum += sim.masses[i] * sim.v[i]
		total_mass += sim.masses[i]
	var mean_accel: float = momentum / total_mass / (600.0 * DELTA)
	assert_float(mean_accel).override_failure_message(
			"starting acceleration %.3f m/s² outside 0.72-1.0" % mean_accel) \
		.is_between(0.72, 1.0)


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


# --- the brake acts through the pipe ---------------------------------------------------------

func test_pipe_brake_demand_reads_the_pipe() -> void:
	var charged := TrainT.BRAKE_PIPE_CHARGED
	assert_float(TrainT.pipe_brake_demand(charged, 1.5)).is_equal(0.0)
	assert_float(TrainT.pipe_brake_demand(charged - 0.75, 1.5)).is_equal_approx(0.5, 1e-9)
	assert_float(TrainT.pipe_brake_demand(charged - 1.5, 1.5)).is_equal_approx(1.0, 1e-9)
	# An emptied (emergency) pipe stays at full; an overcharged one brakes nothing.
	assert_float(TrainT.pipe_brake_demand(0.0, 1.5)).is_equal(1.0)
	assert_float(TrainT.pipe_brake_demand(charged + 0.5, 1.5)).is_equal(0.0)


## Ticks (at DELTA) until the pipe-read brake demand from `pipe` under the lever `lever` reaches
## `target`; -1 if it does not within 60 s.
func _ticks_to_demand(pipe: float, lever: float, target: float) -> int:
	for t in 3600:
		if is_equal_approx(TrainT.pipe_brake_demand(pipe, TrainVeh.PIPE_APPLY_RANGE), target):
			return t
		pipe = TrainT.brake_pipe_step(pipe, lever, DELTA, TrainVeh.PIPE_DROP_RATE,
				TrainVeh.PIPE_CHARGE_RATE, TrainVeh.PIPE_APPLY_RANGE)
	return -1


func test_full_service_builds_over_the_pipe_drop() -> void:
	var expected := TrainVeh.PIPE_APPLY_RANGE / TrainVeh.PIPE_DROP_RATE / DELTA
	var ticks := _ticks_to_demand(TrainT.BRAKE_PIPE_CHARGED, 1.0, 1.0)
	assert_float(float(ticks)).is_equal_approx(expected, 1.0)


func test_release_lets_go_over_the_pipe_recharge() -> void:
	var expected := TrainVeh.PIPE_APPLY_RANGE / TrainVeh.PIPE_CHARGE_RATE / DELTA
	var full := TrainT.BRAKE_PIPE_CHARGED - TrainVeh.PIPE_APPLY_RANGE
	var ticks := _ticks_to_demand(full, 0.0, 0.0)
	assert_float(float(ticks)).is_equal_approx(expected, 1.0)


func test_full_service_stays_above_the_emergency_warn() -> void:
	var file := FileAccess.open(ContractScript.CONTRACT_PATH, FileAccess.READ)
	var data := ContractScript.ContractData.parse(file.get_as_text())
	var warn := data.get_signal_def("brake_pipe", "out").warn
	assert_float(TrainT.BRAKE_PIPE_CHARGED - TrainVeh.PIPE_APPLY_RANGE).is_greater(warn)


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


# --- the reverser -----------------------------------------------------------------------------

## The reverser rides the gear byte, and an electric loco has no gearbox: the spec's one ratio keeps
## the local driver's D on D1 at any speed, so `gear` and the REVERSER readout never shift.
func test_the_reverser_never_leaves_d1() -> void:
	var spec: VehicleSpec = load("res://src/vehicles/train/train_spec.tres")
	var dt := Drivetrain.new(spec)
	dt.running = true
	for i in 600:
		dt.process(DELTA, 1.0, 0.0, i * 0.1, 1, true)
		assert_int(dt.gear_byte).is_equal(1)


## A bridge `gear` byte with `accel` held: the engaged reverser sets the pull, N gives none.
func _bridge_traction(gear: int) -> float:
	var spec: VehicleSpec = load("res://src/vehicles/train/train_spec.tres")
	var dt := Drivetrain.new(spec)
	dt.running = true
	var input := InputRouter.arbitrate_bridge({"gear": gear, "accel": 1.0}, true)
	for i in 30:
		dt.process(DELTA, absf(input.throttle), 0.0, 0.0, input.gear_request, input.gear_auto)
	var throttle := TrainVeh.reverser_throttle(input.throttle, dt.gear_byte)
	return Sim.tractive_effort(0.0, throttle, 1000.0, 14000.0)


func test_bridge_neutral_gives_no_traction() -> void:
	assert_float(_bridge_traction(InputRouter.GEAR_N)).is_equal(0.0)


func test_bridge_d_and_r_pull_their_own_way() -> void:
	assert_float(_bridge_traction(InputRouter.GEAR_D1)).is_equal_approx(1000.0, 1e-6)
	assert_float(_bridge_traction(InputRouter.GEAR_R)).is_equal_approx(-1000.0, 1e-6)

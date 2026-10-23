extends GdUnitTestSuite
## BalanceModel: the static handling-balance prediction (understeer gradient, LLTD, roll, limit).

const VehicleSpecScript := preload("res://src/vehicles/base/vehicle_spec.gd")


## A 1150 kg body on a 2.5 m wheelbase and 1.5 m tracks, `front_share` of its weight on the front,
## springs per axle off one ride frequency (as the generator derives them), one bar on both axles.
func _spec(front_share: float, sensitivity: float, bar := 10000.0) -> VehicleSpecScript:
	var spec := VehicleSpecScript.new()
	var gd := GroundDriveSpec.new()
	spec.ground_drive = gd
	spec.mass = 1150.0
	gd.wheel_positions = PackedVector3Array([Vector3(-0.75, 0.0, -1.25), Vector3(0.75, 0.0, -1.25),
			Vector3(-0.75, 0.0, 1.25), Vector3(0.75, 0.0, 1.25)])
	spec.center_of_mass = Vector3(0.0, 0.2, 1.25 - front_share * 2.5)
	var omega_sq := pow(TAU * 1.39, 2.0)
	gd.spring_rate = spec.mass * front_share / 2.0 * omega_sq
	gd.spring_rate_rear = spec.mass * (1.0 - front_share) / 2.0 * omega_sq
	gd.anti_roll_rate = bar
	gd.mu_lat = 0.97
	gd.load_sensitivity = sensitivity
	return spec


func test_linear_laws_steer_neutral_whatever_the_weight_split() -> void:
	# Stiffness proportional to load: `Wf / Cf` and `Wr / Cr` are the same peak slip over mu.
	for share: float in [0.4, 0.5, 0.6]:
		var m := BalanceModel.axles(_spec(share, 0.0))
		assert_float(BalanceModel.understeer_gradient(m, 0.2)).is_equal_approx(0.0, 1e-4)


func test_load_sensitivity_tilts_toward_the_heavier_axle() -> void:
	# The heavier axle's tyres carry their load on less mu per newton: understeer front-heavy,
	# oversteer rear-heavy, neutral at 50/50.
	assert_float(BalanceModel.understeer_gradient(BalanceModel.axles(_spec(0.6, 0.1)), 0.15)) \
			.is_greater(0.2)
	assert_float(BalanceModel.understeer_gradient(BalanceModel.axles(_spec(0.4, 0.1)), 0.15)) \
			.is_less(-0.2)
	# At 50/50 only the transfer acts, on both axles alike.
	assert_float(BalanceModel.understeer_gradient(BalanceModel.axles(_spec(0.5, 0.1)), 0.15)) \
			.is_equal_approx(0.0, 0.01)


func test_the_static_split_reproduces_the_hand_figure() -> void:
	# 60/40 at s 0.10, mu 0.97, peak slip 0.12: 0.12 / 0.97 * (1 / 0.9737 - 1 / 1.0322) = 0.41 deg/g at
	# vanishing g; `rear_lat_grip` 1.08 takes it to ~0.92.
	var m := BalanceModel.axles(_spec(0.6, 0.1))
	assert_float(BalanceModel.understeer_gradient(m, 0.001)).is_equal_approx(0.41, 0.01)
	(m["rear"] as Dictionary)["mu"] = 0.97 * 1.08
	assert_float(BalanceModel.understeer_gradient(m, 0.001)).is_equal_approx(0.92, 0.01)


func test_lltd_is_the_roll_stiffness_split_on_equal_tracks() -> void:
	var spec := _spec(0.6, 0.1)
	var gd := spec.ground_drive
	var m := BalanceModel.axles(spec)
	var front := gd.spring_rate / 2.0 + gd.anti_roll_rate
	var rear := gd.rear_spring_rate() / 2.0 + gd.rear_anti_roll_rate()
	assert_float(BalanceModel.lltd(m)).is_equal_approx(front / (front + rear), 1e-5)
	# And the springs carry the side force's moment plus the rolled COM's weight, `m g h phi`: roll
	# comes off the summed stiffness less the weight's.
	var h: float = m["h"]
	var phi := deg_to_rad(BalanceModel.roll_deg(m, 0.5))
	assert_float(phi * (front + rear) * 1.5 * 1.5).is_equal_approx(
			spec.mass * BalanceModel.G * h * (0.5 + phi), 1.0)
	# Which is `phi / ay` over the side force's alone (~8 % at this stiffness).
	assert_float(phi * (front + rear) * 1.5 * 1.5 / (spec.mass * BalanceModel.G * 0.5 * h)) \
			.is_equal_approx(1.0 + phi / 0.5, 1e-5)


func test_a_roll_stiffness_under_the_weights_moment_tips() -> void:
	# `sum(K) <= m g h`: the rolled COM's weight out-turns the springs, so any side force tips it.
	var m := BalanceModel.axles(_spec(0.6, 0.1))
	for key in ["front", "rear"]:
		(m[key] as Dictionary)["spring"] = 1.0
		(m[key] as Dictionary)["bar"] = 0.0
	assert_float(BalanceModel.roll_deg(m, 0.05)).is_equal(INF)


func test_the_hand_figures_for_peak_grip_under_transfer() -> void:
	# At s 0.10 an axle at 1.5x / 0.5x its static load loses ~1.9 % of its peak grip; with
	# the inner wheel lifted, 10 %.
	var ref := 3000.0
	assert_float(BalanceModel.pair_grip(1.0, ref, ref, ref, 0.1) / (2.0 * ref)) \
			.is_equal_approx(0.981, 0.001)
	assert_float(BalanceModel.pair_grip(1.0, ref, 2.0 * ref, ref, 0.1) / (2.0 * ref)) \
			.is_equal_approx(0.9, 1e-5)
	# A transfer past lift-off moves nothing more.
	assert_float(BalanceModel.pair_grip(1.0, ref, 3.0 * ref, ref, 0.1) / (2.0 * ref)) \
			.is_equal_approx(0.9, 1e-5)


func test_a_lifted_axle_hands_the_rest_of_the_moment_to_the_other() -> void:
	# A front bar stiff enough to lift the inner front wheel: the front carries twice its static
	# wheel load across it and no more, the rear the rest of `m ay h` plus the rolled COM's weight
	# `m g h phi`, and the body rolls on the rear.
	var m := BalanceModel.axles(_spec(0.6, 0.1, 400000.0))
	(m["rear"] as Dictionary)["bar"] = 0.0
	var g := 0.9
	var state := BalanceModel._roll_state(m, g)
	var front: Dictionary = m["front"]
	assert_float(float(state["front"])).is_equal_approx(2.0 * float(front["load"]), 1e-3)
	var moment := (float(state["front"]) + float(state["rear"])) * 1.5 / 2.0
	var phi := float(state["phi"])
	assert_float(moment).is_equal_approx(float(m["mass"]) * BalanceModel.G * (g + phi) * float(m["h"]),
			0.5)
	assert_float(BalanceModel.roll_deg(m, g)).is_greater(BalanceModel.roll_deg(m, 0.5) * g / 0.5)


func test_a_lifted_axle_over_springs_under_the_weights_moment_tips() -> void:
	# The stiff front bar lifts the inner front; the rear, its roll stiffness under `m g h`, cannot
	# hold the rolled COM's weight alone, so the body tips. Its own transfer stays far under its
	# cap, so this is the lifted-axle branch, not both axles past theirs.
	var m := BalanceModel.axles(_spec(0.6, 0.1, 400000.0))
	var rear: Dictionary = m["rear"]
	rear["bar"] = 0.0
	rear["spring"] = 1.0
	var weight_h := float(m["mass"]) * BalanceModel.G * float(m["h"])
	assert_float(BalanceModel._roll_stiffness(rear)).is_less(weight_h)
	# Below lift-off the front bar holds it elastically.
	assert_bool(is_finite(BalanceModel.roll_deg(m, 0.1))).is_true()
	assert_float(BalanceModel.roll_deg(m, 1.5)).is_equal(INF)


func test_the_limit_settles_on_the_first_axle_to_saturate() -> void:
	var m := BalanceModel.axles(_spec(0.6, 0.1))
	var lim := BalanceModel.limit(m)
	assert_float(float(lim["g"])).is_equal_approx(minf(lim["front"], lim["rear"]), 1e-4)
	# Front-heavy at s > 0: the front washes out first.
	assert_float(float(lim["margin"])).is_greater(0.0)


func test_the_cornering_load_shape() -> void:
	# Identity at the reference load and when off; it peaks at `peak_load` times the reference.
	assert_float(RayWheel.cornering_load_shape(3000.0, 3000.0, 2.8)).is_equal_approx(1.0, 1e-6)
	assert_float(RayWheel.cornering_load_shape(5000.0, 3000.0, 0.0)).is_equal(1.0)
	var at_peak := RayWheel.cornering_load_shape(2.8 * 3000.0, 3000.0, 2.8)
	assert_float(RayWheel.cornering_load_shape(2.6 * 3000.0, 3000.0, 2.8)).is_less(at_peak)
	assert_float(RayWheel.cornering_load_shape(3.0 * 3000.0, 3000.0, 2.8)).is_less(at_peak)
	# Concave below the peak: an axle's two wheels under transfer give less than twice the static.
	assert_float(RayWheel.cornering_load_shape(4500.0, 3000.0, 2.8)
			+ RayWheel.cornering_load_shape(1500.0, 3000.0, 2.8)).is_less(2.0)


func test_with_the_law_on_the_heavier_axle_loses_stiffness_per_newton() -> void:
	# Equal tyres, no peak-mu law: the load law alone makes a front-heavy body understeer.
	var m := BalanceModel.axles(_spec(0.6, 0.0))
	m["peak_load"] = 2.8
	assert_float(BalanceModel.understeer_gradient(m, 0.15)).is_greater(0.3)


func test_the_runtime_tyre_and_the_model_share_one_law() -> void:
	# `axles` reads the law off the spec, and RayWheel's small-slip side force over its slip is the
	# model's wheel stiffness at every load.
	var spec := _spec(0.6, 0.1)
	spec.ground_drive.cornering_peak_load = 2.56
	var m := BalanceModel.axles(spec)
	assert_float(float(m["peak_load"])).is_equal(2.56)
	var ref: float = m["ref"]
	var mu := 0.97
	for ratio: float in [0.4, 1.0, 1.7, 2.6]:
		var n_load := ratio * ref
		var budget := RayWheel.load_scaled_mu(mu, n_load, ref, 0.1) * n_load
		var side := RayWheel.combined_slip_force(0.0, 0.01, budget, budget,
				spec.ground_drive.grip_curve, RayWheel.lateral_peak_slip(n_load, ref, 0.1, 2.56)).y
		var model := BalanceModel.wheel_stiffness(m, mu, n_load)
		assert_float(side / 0.01).is_equal_approx(model, model * 1e-4)


func test_a_twin_rear_is_two_tyres_at_half_the_load() -> void:
	# RayWheel reads a twin corner's side grip and law at `tyre_share` 0.5 on the whole corner's
	# budget: its small-slip stiffness is two single tyres' at half the load (`2 C(L / 2)`), its peak
	# `1 + load_sensitivity` over one tyre's at the reference, and the model matches both.
	var spec := _spec(0.4, 0.08)
	spec.ground_drive.cornering_peak_load = 1.92
	spec.ground_drive.rear_twin_tyres = true
	var m := BalanceModel.axles(spec)
	assert_float(float((m["rear"] as Dictionary)["share"])).is_equal(0.5)
	assert_float(float((m["front"] as Dictionary)["share"])).is_equal(1.0)
	var ref: float = m["ref"]
	var mu := 0.97
	var curve := spec.ground_drive.grip_curve
	for ratio: float in [0.4, 1.0, 1.7, 2.6]:
		var n_load := ratio * ref
		var budget := RayWheel.load_scaled_mu(mu, n_load * 0.5, ref, 0.08) * n_load
		var pair := RayWheel.combined_slip_force(0.0, 0.01, budget, budget, curve,
				RayWheel.lateral_peak_slip(n_load * 0.5, ref, 0.08, 1.92)).y
		var one_budget := RayWheel.load_scaled_mu(mu, n_load * 0.5, ref, 0.08) * n_load * 0.5
		var one := RayWheel.combined_slip_force(0.0, 0.01, one_budget, one_budget, curve,
				RayWheel.lateral_peak_slip(n_load * 0.5, ref, 0.08, 1.92)).y
		assert_float(pair).is_equal_approx(2.0 * one, absf(pair) * 1e-5)
		var model := BalanceModel.wheel_stiffness(m, mu, n_load, 0.5)
		assert_float(pair / 0.01).is_equal_approx(model, model * 1e-4)
	assert_float(BalanceModel.pair_grip(mu, ref, 0.0, ref, 0.08, 0.5)
			/ BalanceModel.pair_grip(mu, ref, 0.0, ref, 0.08)).is_equal_approx(1.08, 1e-5)


func test_angular_damping_adds_understeer_falling_with_speed() -> void:
	# The moment `I c r` at a steady yaw rate loads the front and unloads the rear: + understeer, and
	# `r = a / v` halves it at twice the speed.
	var m := BalanceModel.axles(_spec(0.5, 0.0))
	m["yaw_inertia"] = 1800.0
	m["yaw_damp"] = 0.1
	var slow := BalanceModel.yaw_damping_gradient(m, 0.15, 30.0 / 3.6)
	assert_float(slow).is_greater(0.0)
	assert_float(BalanceModel.yaw_damping_gradient(m, 0.15, 60.0 / 3.6)).is_equal_approx(slow / 2.0,
			1e-5)
	assert_float(BalanceModel.understeer_gradient(m, 0.15, 30.0 / 3.6)).is_equal_approx(slow, 1e-4)
	m["yaw_damp"] = 0.0
	assert_float(BalanceModel.understeer_gradient(m, 0.15, 30.0 / 3.6)).is_equal_approx(0.0, 1e-4)
	# No damping is no term, whatever the inertia: an undeclared one (NAN) must not poison K.
	m["yaw_inertia"] = NAN
	assert_float(BalanceModel.yaw_damping_gradient(m, 0.15, 30.0 / 3.6)).is_equal(0.0)
	assert_bool(is_nan(BalanceModel.understeer_gradient(m, 0.15, 30.0 / 3.6))).is_false()


func test_bodies_off_two_pairs_are_not_predicted() -> void:
	var spec := _spec(0.6, 0.1)
	spec.ground_drive.wheel_positions[3].z = 1.6  # a staggered rear: no single rear axle
	var m := BalanceModel.axles(spec)
	assert_bool(m.is_empty()).is_true()
	assert_bool(is_nan(BalanceModel.understeer_gradient(m, 0.2))).is_true()


func test_at_rest_the_model_carries_no_downforce() -> void:
	# Speed 0 is the static model exactly: a winged spec reads its weight alone.
	var spec := _spec(0.42, 0.1)
	spec.ground_drive.downforce_area = 2.24
	spec.ground_drive.downforce_front = 0.40
	var m := BalanceModel.axles(spec)
	assert_float(float(m["front"]["aero"])).is_equal(0.0)
	assert_float(float(m["rear"]["aero"])).is_equal(0.0)
	spec.ground_drive.downforce_area = 0.0
	assert_dict(BalanceModel.limit(m)).is_equal(BalanceModel.limit(BalanceModel.axles(spec)))


func test_downforce_splits_by_the_declared_share_and_adds_grip_not_demand() -> void:
	var spec := _spec(0.42, 0.1)
	spec.ground_drive.downforce_area = 2.24
	spec.ground_drive.downforce_front = 0.40
	var still := BalanceModel.axles(spec)
	var fast := BalanceModel.axles(spec, 200.0 / 3.6)
	var f := float(fast["front"]["aero"])
	var r := float(fast["rear"]["aero"])
	assert_float(f / (f + r)).is_equal_approx(0.40, 1e-6)
	assert_float(2.0 * (f + r)).is_equal_approx(
			VehicleMath.aero_downforce(200.0 / 3.6, 2.24), 1e-3)
	# The weight the side force is made against is unchanged; the limit in g of it rises.
	assert_float(float(fast["front"]["load"])).is_equal(float(still["front"]["load"]))
	assert_float(float(BalanceModel.limit(fast)["g"])) \
			.is_greater(float(BalanceModel.limit(still)["g"]))


func test_unset_share_splits_downforce_by_weight() -> void:
	var spec := _spec(0.6, 0.1)
	spec.ground_drive.downforce_area = 2.0
	var fast := BalanceModel.axles(spec, 50.0)
	var f := float(fast["front"]["aero"])
	assert_float(f / (f + float(fast["rear"]["aero"]))).is_equal_approx(0.6, 1e-5)


func test_zero_roll_steer_reproduces_the_model_exactly() -> void:
	# Explicit zeros against a model built without the key: K, LLTD and the limit, bit for bit.
	var m := BalanceModel.axles(_spec(0.6, 0.1))
	var bare := m.duplicate(true)
	(bare["front"] as Dictionary).erase("roll_steer")
	(bare["rear"] as Dictionary).erase("roll_steer")
	assert_float(BalanceModel.roll_steer_gradient(m, 0.15)).is_equal(0.0)
	assert_float(BalanceModel.understeer_gradient(m, 0.15)).is_equal(
			BalanceModel.understeer_gradient(bare, 0.15))
	assert_float(BalanceModel.lltd(m)).is_equal(BalanceModel.lltd(bare))
	assert_dict(BalanceModel.limit(m)).is_equal(BalanceModel.limit(bare))


func test_roll_steer_adds_the_coefficients_times_the_roll_gradient() -> void:
	var spec := _spec(0.6, 0.1)
	var base := BalanceModel.understeer_gradient(BalanceModel.axles(spec), 0.15)
	spec.ground_drive.roll_steer_front = 0.2
	spec.ground_drive.roll_steer_rear = 0.13
	var m := BalanceModel.axles(spec)
	var term := 0.33 * BalanceModel.roll_deg(m, 0.15) / 0.15
	assert_float(BalanceModel.roll_steer_gradient(m, 0.15)).is_equal_approx(term, 1e-9)
	assert_float(BalanceModel.understeer_gradient(m, 0.15)).is_equal_approx(base + term, 1e-9)
	# The same term at speed: it is steady state, not a speed term.
	m["yaw_inertia"] = 1800.0
	m["yaw_damp"] = 0.0
	assert_float(BalanceModel.understeer_gradient(m, 0.15, 30.0 / 3.6)).is_equal_approx(base + term,
			1e-4)


func test_roll_steer_never_moves_the_limit() -> void:
	var spec := _spec(0.6, 0.1)
	var plain := BalanceModel.limit(BalanceModel.axles(spec))
	spec.ground_drive.roll_steer_front = 0.2
	spec.ground_drive.roll_steer_rear = 0.13
	assert_dict(BalanceModel.limit(BalanceModel.axles(spec))).is_equal(plain)


func test_a_tipping_body_reads_infinite_roll_steer_and_none_without_it() -> void:
	# Far past the tipping g both inner wheels are up and roll reads INF: 0 times it must not be NAN.
	var m := BalanceModel.axles(_spec(0.6, 0.1))
	assert_float(BalanceModel.roll_deg(m, 10.0)).is_equal(INF)
	assert_float(BalanceModel.roll_steer_gradient(m, 10.0)).is_equal(0.0)
	assert_bool(is_nan(BalanceModel.understeer_gradient(m, 10.0))).is_false()
	(m["front"] as Dictionary)["roll_steer"] = 0.1
	assert_float(BalanceModel.roll_steer_gradient(m, 10.0)).is_equal(INF)

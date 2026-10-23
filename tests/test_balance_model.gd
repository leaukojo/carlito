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

# --- the corner pass's turn (`corner`, `corner_limit`) ---------------------------------------------

const CORNER_V := 11.11  ## m/s, the corner pass's 40 km/h


## `_spec` driven as the corner pass drives it on `drive` ("front" / "rear"), with a lock, full
## Ackermann and traction control, as every shipped road body (an open diff's light inner wheel caps
## the drive without it; parallel steer loads the outer front, whose rearward pull at the track yaws
## the body out of the turn).
func _driven(front_share: float, sensitivity: float, drive: String, bar := 10000.0) -> Dictionary:
	var spec := _spec(front_share, sensitivity, bar)
	spec.ground_drive.tcs_equipped = true
	spec.ground_drive.ackermann = 1.0
	spec.ground_drive.driven_front = drive == "front"
	spec.ground_drive.driven_rear = drive == "rear"
	spec.ground_drive.max_steer_deg = 35.0
	return BalanceModel.axles(spec, CORNER_V)


## The front tyres' summed side force (N, along each wheel's own side) in a `corner` result.
static func _front_side(turn: Dictionary) -> float:
	var sum := 0.0
	for w: Dictionary in turn["wheels"]:
		if w["axle"] == "front":
			sum += float(w["fy"])
	return sum


func test_a_neutral_turn_at_a_small_steer_is_the_kinematic_one() -> void:
	# Linear laws steer neutral (K 0): at a small angle the yaw rate is `v tan(delta) / L`, and with
	# no rolling resistance or drag the drive is the tyres' tilt alone, a few newtons.
	var m := _driven(0.6, 0.0, "rear")
	var steer := deg_to_rad(0.5)
	var turn := BalanceModel.corner(m, CORNER_V, steer)
	assert_bool(turn.is_empty()).is_false()
	var kinematic := CORNER_V * tan(steer) / 2.5
	assert_float(float(turn["yaw_rate"])).is_equal_approx(kinematic, 0.01 * kinematic)
	assert_float(float(turn["drive"])).is_less(0.002 * float(m["mass"]) * BalanceModel.G)


func test_nothing_driven_holds_no_steady_turn() -> void:
	# With nothing driven the drive unknown moves no force, so nothing balances the rolling drag and
	# the tyres' tilt: the solve has no steady turn (`_solve_corner`'s `drive`).
	var m := _driven(0.6, 0.1, "rear")
	(m["rear"] as Dictionary)["driven"] = false
	assert_bool(BalanceModel.corner(m, CORNER_V, deg_to_rad(2.0)).is_empty()).is_true()
	assert_str(str(BalanceModel._solve_corner(m, CORNER_V, deg_to_rad(2.0)).get("fails", ""))) \
			.is_equal("drive")


func test_at_a_small_steer_the_shares_are_the_demand_over_the_capacity() -> void:
	# Near straight the drive is a few newtons, so each axle's ellipse share is its side force over
	# its grip (`axle_capacity_g` at that g): `limit`'s picture, which `corner` reduces to.
	var m := _driven(0.6, 0.1, "rear")
	var turn := BalanceModel.corner(m, CORNER_V, deg_to_rad(2.0))
	var g := float(turn["lat_g"])
	var caps := BalanceModel.axle_capacity_g(m, g)
	# Both axles carry `g` of their own weight (yaw balance), so each share is `g / capacity`.
	assert_float(float(turn["front"])).is_equal_approx(g / caps.x, 0.02 * g / caps.x)
	assert_float(float(turn["rear"])).is_equal_approx(g / caps.y, 0.02 * g / caps.y)


func test_a_steered_front_carries_its_share_over_the_cosine() -> void:
	# Rear-driven: the front's side force must still make its static share of `m a`, but across the
	# body only its cosine counts, so it carries `m a (b / L) / cos(delta)` to the track moments' 1 %.
	# A tight slow turn, where the cosine is 5 % of it.
	var m := _driven(0.6, 0.0, "rear")
	var turn := BalanceModel.corner(m, 6.0, deg_to_rad(18.0))
	var demand := float(m["mass"]) * float(turn["lat_g"]) * BalanceModel.G * 0.6
	var tilt := 1.0 / cos(deg_to_rad(18.0))
	assert_float(_front_side(turn)).is_between(demand * tilt, demand * (tilt + 0.03))


func test_a_driven_front_carries_side_force_on_its_drive() -> void:
	# The same turn front-driven: the drive's tilt `Fx sin(delta)` carries part of the side force.
	var steer := deg_to_rad(8.0)
	var rear := BalanceModel.corner(_driven(0.6, 0.0, "rear"), CORNER_V, steer)
	var front := BalanceModel.corner(_driven(0.6, 0.0, "front"), CORNER_V, steer)
	var per_g_rear := _front_side(rear) / float(rear["lat_g"])
	var per_g_front := _front_side(front) / float(front["lat_g"])
	assert_float(float(front["drive_front"])).is_greater(100.0)
	assert_float(per_g_front).is_less(per_g_rear)
	# To 5 %: the rest is the two turns' slightly different loads and slips.
	var tilt := float(front["drive_front"]) * sin(steer) / float(front["lat_g"])
	assert_float(per_g_rear - per_g_front).is_equal_approx(tilt, 0.05 * tilt)


func test_the_drive_spends_the_driven_axles_ellipse() -> void:
	# The turn's drive (the front's tilted side force) spends the ellipse of the axle that makes it:
	# per g, the rear's share is higher driven on the rear than on the front.
	var steer := deg_to_rad(8.0)
	var front := BalanceModel.corner(_driven(0.6, 0.1, "front"), CORNER_V, steer)
	var rear := BalanceModel.corner(_driven(0.6, 0.1, "rear"), CORNER_V, steer)
	assert_float(float(rear["drive_rear"])).is_greater(500.0)
	assert_float(float(rear["rear"]) / float(rear["lat_g"])) \
			.is_greater(float(front["rear"]) / float(front["lat_g"]))


func test_the_drive_slip_carries_the_target_on_the_runtime_law() -> void:
	# One law: the slip `corner` solves for gives the target back through `combined_slip_force`, on
	# the rising side and past a side peak alike; a target no slip carries returns the most it pulls.
	var curve := GroundDriveSpec.new().grip_curve
	for side: float in [0.0, 0.05, 0.2]:
		var k := BalanceModel._drive_slip(1500.0, side, 5000.0, 4500.0, curve, 1.0, 0.12)
		var fx := RayWheel.combined_slip_force(k, side, 5000.0, 4500.0, curve, 1.0).x
		assert_float(fx).is_equal_approx(1500.0, 1.5)
	var most := BalanceModel._drive_slip(9000.0, 0.05, 5000.0, 4500.0, curve, 1.0, 0.12)
	assert_float(RayWheel.combined_slip_force(most, 0.05, 5000.0, 4500.0, curve, 1.0).x) \
			.is_less(5000.0)


func test_the_corner_limit_calls_the_front_on_a_front_heavy_body() -> void:
	# Front-heavy, load-sensitive and front-driven: the front saturates first, as `limit` reads it.
	var m := _driven(0.6, 0.1, "front")
	var turn := BalanceModel.corner_limit(m, CORNER_V)
	assert_float(float(turn["margin"])).is_greater(0.0)
	assert_float(float(BalanceModel.limit(m)["margin"])).is_greater(0.0)
	assert_float(float(turn["front"])).is_greater(0.95)
	assert_bool(bool(turn["at_lock"])).is_false()


## A driven front pair for `_split_drive`, inner first as `_corner_state` builds it: the inner wheel
## light (`inner_budget` N along it), both at a little side slip.
static func _front_pair(inner_budget: float) -> Array[Dictionary]:
	var pair: Array[Dictionary] = []
	for w: Array in [[true, 10.5, inner_budget], [false, 11.0, 6000.0]]:
		pair.append({"axle": "front", "inner": w[0], "v_long": w[1], "slip_lat": 0.02,
				"budget_long": w[2], "budget_lat": 0.94 * float(w[2]), "lat_peak": 1.0})
	return pair


func test_traction_control_holds_the_light_inner_wheel_and_leaves_its_partner_its_half() -> void:
	# An open diff splits 1600 N evenly; the inner wheel cannot carry its 800 N, so the hold keeps it
	# at TCS_SLIP and takes the rest off, while the outer carries its whole 800 N.
	var m := _driven(0.6, 0.0, "front")
	var pair := _front_pair(700.0)
	BalanceModel._split_drive(m, pair, 1600.0)
	var curve: PackedVector2Array = m["grip_curve"]
	assert_bool(bool(pair[0]["tc"])).is_true()
	assert_float(float(pair[0]["kappa"])).is_equal(RayWheel.TCS_SLIP)
	assert_float(float(pair[0]["target"])).is_equal(800.0)
	assert_bool(bool(pair[1]["tc"])).is_false()
	assert_float(float(pair[1]["target"])).is_equal(800.0)
	assert_float(RayWheel.combined_slip_force(float(pair[1]["kappa"]), 0.02, 6000.0, 5640.0, curve,
			1.0).x).is_equal_approx(800.0, 0.8)


func test_a_lifted_driven_wheel_is_held_and_its_partner_keeps_its_half() -> void:
	# No load, no budget: the wheel spins up to the hold (the runtime's ceiling), carrying nothing.
	var m := _driven(0.6, 0.0, "front")
	var pair := _front_pair(0.0)
	BalanceModel._split_drive(m, pair, 1600.0)
	assert_bool(bool(pair[0]["tc"])).is_true()
	assert_float(float(pair[0]["kappa"])).is_equal(RayWheel.TCS_SLIP)
	assert_float(float(pair[1]["target"])).is_equal(800.0)
	# Without traction control the lifted wheel holds nothing, which is no steady drive.
	m["tcs"] = false
	BalanceModel._split_drive(m, pair, 1600.0)
	assert_bool(bool(pair[0]["tc"])).is_false()


func test_a_biased_diff_sends_the_drive_outward_past_a_wheel_on_its_traction_slip() -> void:
	# The held inner wheel spins at TCS_SLIP over the road, faster than the loaded outer: the slow
	# side is the outer, which takes `bias / (1 + bias)` of the axle's drive.
	var m := _driven(0.6, 0.0, "front")
	(m["front"] as Dictionary)["diff_bias"] = 3.0
	var pair := _front_pair(200.0)
	BalanceModel._split_drive(m, pair, 1600.0)
	assert_bool(bool(pair[0]["tc"])).is_true()
	assert_float(float(pair[0]["target"])).is_equal_approx(400.0, 1e-6)
	assert_float(float(pair[1]["target"])).is_equal_approx(1200.0, 1e-6)
	var spin_in := 10.5 * (1.0 + float(pair[0]["kappa"]))
	assert_float(11.0 * (1.0 + float(pair[1]["kappa"]))).is_less(spin_in)


func test_a_turn_holds_on_a_lifted_driven_wheel_under_traction_control() -> void:
	# A tall body on a stiff front bar and no rear one lifts its inner front before the front
	# saturates: the turn carries on to the front's grip on the outer wheel alone, the rear still
	# holding the body up.
	var m := _driven(0.6, 0.1, "front", 60000.0)
	(m["rear"] as Dictionary)["bar"] = 0.0
	m["h"] = 0.7
	var turn := BalanceModel.corner_limit(m, CORNER_V)
	assert_bool(bool(turn["tips"])).is_false()
	var inner: Dictionary = turn["wheels"][0]
	var outer: Dictionary = turn["wheels"][1]
	assert_float(float(inner["load"])).is_equal(0.0)
	assert_bool(bool(inner["tc"])).is_true()
	assert_float(float(inner["fx"])).is_equal(0.0)
	assert_float(float(outer["fx"])).is_equal_approx(float(outer["target"]),
			1e-3 * float(outer["target"]))
	assert_float(float(turn["front"])).is_greater(0.98)


func test_the_corner_limit_reads_a_tip_under_its_peak() -> void:
	# On a stiff front bar, raise the COM and the model tips under its peak; the plain body never does.
	var m := _driven(0.6, 0.1, "front", 60000.0)
	var low := BalanceModel.corner_limit(m, CORNER_V)
	assert_bool(bool(low["tips"])).is_false()
	assert_float(float(low["tip_g"])).is_greater(float(low["lat_g"]))
	m["h"] = 1.0
	var tall := BalanceModel.corner_limit(m, CORNER_V)
	assert_bool(bool(tall["tips"])).is_true()
	# `tip_g` is where the roll law first reads INF, to its 1e-4 g bisection.
	var tip := float(tall["tip_g"])
	assert_bool(is_finite(BalanceModel.roll_deg(m, tip - 2e-4))).is_true()
	assert_float(BalanceModel.roll_deg(m, tip)).is_equal(INF)
	# Past the tip no turn is steady: the sweep ends on it, its last turn at it (the roll reads the
	# lateral `v r cos(beta)`, a hair under the turn's `v r`).
	assert_str(str(tall["end"])).is_equal("tip")
	assert_float(float(tall["lat_g"])).is_equal_approx(tip, 0.01)
	assert_bool(BalanceModel.corner(m, CORNER_V, float(tall["steer"]) + deg_to_rad(1.0)).is_empty()) \
			.is_true()


func test_a_cold_call_holds_wherever_the_sweep_does() -> void:
	# A tall body whose turn kinks as its inner wheels lift: called cold at any steer the sweep
	# reaches, `corner` winds on to it (halving its step where one fails, as the sweep does) and lands
	# on the turn a call continued from its neighbour finds.
	var m := _driven(0.6, 0.0, "front", 60000.0)
	m["h"] = 1.0
	var top := float(BalanceModel.corner_limit(m, CORNER_V)["steer"])
	var prev := {}
	var steer := deg_to_rad(0.37)
	while steer < top:
		var continued := BalanceModel.corner(m, CORNER_V, steer, prev)
		var cold := BalanceModel.corner(m, CORNER_V, steer)
		assert_bool(cold.is_empty()).override_failure_message(
				"no cold turn at %.2f deg" % rad_to_deg(steer)).is_false()
		if cold.is_empty() or continued.is_empty():
			return
		assert_float(float(cold["lat_g"])).is_equal_approx(float(continued["lat_g"]), 1e-3)
		assert_float(float(cold["beta"])).is_equal_approx(float(continued["beta"]), 1e-4)
		prev = continued
		steer += deg_to_rad(0.37)


func test_roll_steer_in_the_turn_adds_its_angle_to_the_steer() -> void:
	# At one g the tyres need the same slips, so the mean steer rises by the roll-steer angle each
	# axle's suspension roll gives it: the front out of the turn, the rear into it (both understeer).
	var g := 0.5
	for key: String in ["front", "rear"]:
		var m := _driven(0.6, 0.1, "rear")
		var plain := BalanceModel.corner_at(m, CORNER_V, g)
		(m[key] as Dictionary)["roll_steer"] = 0.1
		var steered := BalanceModel.corner_at(m, CORNER_V, g)
		var rolled := BalanceModel._axle_rolled(m, key, BalanceModel._roll_state(m, g))
		var angle := 0.1 * atan(rolled / float((m[key] as Dictionary)["track"]))
		assert_float(float(steered["steer"]) - float(plain["steer"])).is_equal_approx(angle, 0.05 * angle)
	# No coefficient, no angle: the same turn to the bit.
	var bare := _driven(0.6, 0.1, "rear")
	var zeroed := _driven(0.6, 0.1, "rear")
	(zeroed["front"] as Dictionary)["roll_steer"] = 0.0
	(zeroed["rear"] as Dictionary)["roll_steer"] = 0.0
	assert_float(float(BalanceModel.corner(zeroed, CORNER_V, deg_to_rad(6.0))["steer"])) \
			.is_equal(float(BalanceModel.corner(bare, CORNER_V, deg_to_rad(6.0))["steer"]))
	assert_float(float(BalanceModel.corner(zeroed, CORNER_V, deg_to_rad(6.0))["beta"])) \
			.is_equal(float(BalanceModel.corner(bare, CORNER_V, deg_to_rad(6.0))["beta"]))


func test_the_axles_roll_reads_its_rays_until_the_inner_one_leaves_the_road() -> void:
	# Both corners loaded, an axle's compressions part by the body's roll over its track. Its inner
	# corner unloaded, the bar still holds that ray on the road (the outer at
	# `(k + bar) c_o - bar c_i` = the axle's load), so the roll steer keeps reading the body's roll,
	# no step at the lift; once the ray would leave, full droop: the outer alone on its spring.
	var m := BalanceModel.axles(_spec(0.6, 0.1, 400000.0))
	(m["rear"] as Dictionary)["bar"] = 0.0
	var front: Dictionary = m["front"]
	var track := float(front["track"])
	var state := BalanceModel._roll_state(m, 0.3)
	for key: String in ["front", "rear"]:
		assert_float(BalanceModel._axle_rolled(m, key, state)).is_equal_approx(
				float((m[key] as Dictionary)["track"]) * float(state["phi"]), 1e-6)
	# The lift: bisect the g where the front's transfer reaches its cap.
	var cap := 2.0 * float(front["load"])
	var lo := 0.3
	var hi := 1.5
	for _i in 40:
		var mid := (lo + hi) / 2.0
		if float(BalanceModel._roll_state(m, mid)["front"]) < cap:
			lo = mid
		else:
			hi = mid
	var below := BalanceModel._axle_rolled(m, "front", BalanceModel._roll_state(m, lo))
	var above := BalanceModel._axle_rolled(m, "front", BalanceModel._roll_state(m, hi))
	assert_float(above).is_equal_approx(below, 1e-4)
	# Further on, while the body still stands on its rear, the inner ray leaves: full droop.
	var spring := float(front["spring"])
	var bar := float(front["bar"])
	var g := hi
	var gone := false
	while g < BalanceModel.tip_g(m):
		var phi := float(BalanceModel._roll_state(m, g)["phi"])
		if (cap - bar * track * phi) / spring <= track * phi:
			gone = true
			break
		g += 0.01
	assert_bool(gone).is_true()
	assert_float(BalanceModel._axle_rolled(m, "front", BalanceModel._roll_state(m, g))) \
			.is_equal_approx(cap / spring, 1e-6)


func test_corner_at_lands_on_the_asked_g_and_is_empty_past_the_peak() -> void:
	var m := _driven(0.6, 0.1, "rear")
	for g: float in [0.3, 0.6]:
		assert_float(float(BalanceModel.corner_at(m, CORNER_V, g)["lat_g"])).is_equal_approx(g, 1e-3)
	var peak := float(BalanceModel.corner_limit(m, CORNER_V)["lat_g"])
	assert_bool(BalanceModel.corner_at(m, CORNER_V, peak + 0.05).is_empty()).is_true()


func test_a_right_turn_is_not_modelled() -> void:
	# `corner` is a left turn on a steer >= 0; the pass's right turn is its mirror.
	var m := _driven(0.6, 0.1, "rear")
	assert_bool(BalanceModel.corner(m, CORNER_V, -0.05).is_empty()).is_true()

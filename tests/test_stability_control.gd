extends GdUnitTestSuite
## StabilityControl: the yaw reference and its bound, the body-slip estimate, and the one wheel
## braked against the error, stepped by hand at 60 Hz on a car-sized body.

const TICK := 1.0 / 60.0
const SPEED := 25.0
const WHEELBASE := 2.6
const YAW_INERTIA := 2500.0
const HALF_TRACK := Vector2(0.78, 0.78)
const RADIUS := Vector2(0.33, 0.33)
const BRAKE := Vector2(1500.0, 900.0)
const FULL := Vector4(1500.0, 1500.0, 900.0, 900.0)
const FL := 0
const FR := 1
const RL := 2
const RR := 3


## One `intervention` on the car above.
static func _iv(ref_yaw: float, yaw_rate: float, slip := 0.0, prev := Vector4.ZERO,
		speed := SPEED) -> Dictionary:
	return StabilityControl.intervention(speed, ref_yaw, yaw_rate, slip, YAW_INERTIA, HALF_TRACK,
			RADIUS, BRAKE, prev, TICK)


## The single corner braked, or -1 if none (fails on two).
func _braked(result: Dictionary) -> int:
	var t: Vector4 = result["torques"]
	var found := -1
	for i in 4:
		if t[i] > 0.0:
			assert_int(found).is_equal(-1)
			found = i
	return found


# --- the reference -----------------------------------------------------------------------------

func test_a_neutral_body_asks_the_kinematic_yaw() -> void:
	assert_float(StabilityControl.reference_yaw(SPEED, 0.03, WHEELBASE, 0.0, 10.0)) \
			.is_equal_approx(SPEED * 0.03 / WHEELBASE, 1e-9)


func test_understeer_gradient_lowers_the_reference() -> void:
	var k := deg_to_rad(2.0) / StabilityControl.G
	var expected := SPEED * 0.03 / (WHEELBASE + k * SPEED * SPEED)
	var r := StabilityControl.reference_yaw(SPEED, 0.03, WHEELBASE, 2.0, 10.0)
	assert_float(r).is_equal_approx(expected, 1e-9)
	assert_float(r).is_less(SPEED * 0.03 / WHEELBASE)


func test_the_reference_is_bounded_by_the_measured_lateral_acceleration() -> void:
	var bound := (2.0 + StabilityControl.BOUND_MARGIN_G * StabilityControl.G) / SPEED
	assert_float(StabilityControl.reference_yaw(SPEED, 0.1, WHEELBASE, 0.0, 2.0)) \
			.is_equal_approx(bound, 1e-9)
	# Either sign of turn, either sign of the accelerometer.
	assert_float(StabilityControl.reference_yaw(SPEED, -0.1, WHEELBASE, 0.0, -2.0)) \
			.is_equal_approx(-bound, 1e-9)


func test_standstill_asks_nothing() -> void:
	assert_float(StabilityControl.reference_yaw(0.0, 0.3, WHEELBASE, 2.0, 0.0)).is_equal(0.0)


func test_reference_k_interpolates_and_holds_its_ends() -> void:
	var points := PackedVector2Array([Vector2(0.1, 1.5), Vector2(0.5, 2.5)])
	assert_float(StabilityControl.reference_k(points, 0.3)).is_equal_approx(2.0, 1e-5)
	assert_float(StabilityControl.reference_k(points, -0.3)).is_equal_approx(2.0, 1e-5)
	assert_float(StabilityControl.reference_k(points, 0.0)).is_equal_approx(1.5, 1e-5)
	assert_float(StabilityControl.reference_k(points, 0.9)).is_equal_approx(2.5, 1e-5)
	var one := PackedVector2Array([Vector2(0.3, 1.8)])
	assert_float(StabilityControl.reference_k(one, 0.0)).is_equal_approx(1.8, 1e-5)
	assert_float(StabilityControl.reference_k(one, 0.8)).is_equal_approx(1.8, 1e-5)
	# An empty table logs its error (expected in the run's output).
	assert_bool(is_nan(StabilityControl.reference_k(PackedVector2Array(), 0.3))).is_true()


# --- the slip estimate -------------------------------------------------------------------------

func test_a_steady_turn_holds_no_slip() -> void:
	var beta := 0.0
	for _i in 60:
		beta = StabilityControl.slip_step(beta, 5.0, 5.0 / SPEED, SPEED, TICK)
	assert_float(beta).is_equal_approx(0.0, 1e-9)


func test_yawing_faster_than_the_path_swings_the_velocity_right_of_the_nose() -> void:
	var beta := StabilityControl.slip_step(0.0, 5.0, 0.3, SPEED, TICK)
	assert_float(beta).is_equal_approx((0.2 - 0.3) * TICK * exp(-TICK / StabilityControl.SLIP_LEAK_S),
			1e-9)
	assert_float(beta).is_less(0.0)


func test_the_estimate_leaks_away() -> void:
	var beta := 0.1
	for _i in 120:
		beta = StabilityControl.slip_step(beta, 0.0, 0.0, SPEED, TICK)
	assert_float(beta).is_equal_approx(0.1 * exp(-2.0 / StabilityControl.SLIP_LEAK_S), 1e-6)


func test_the_estimate_resets_below_the_speed_floor() -> void:
	assert_float(StabilityControl.slip_step(0.1, 5.0, 0.0, 5.0, TICK)).is_equal(0.0)


# --- the intervention --------------------------------------------------------------------------

func test_inside_the_deadband_it_does_nothing() -> void:
	var ref := 0.155
	assert_float(StabilityControl.yaw_moment(ref, ref + 0.03, 0.0, YAW_INERTIA)).is_equal(0.0)
	var out := _iv(ref, ref + 0.03, deg_to_rad(4.0))
	assert_int(_braked(out)).is_equal(-1)
	assert_float(out["throttle_cap"]).is_equal(1.0)


func test_oversteer_brakes_the_outer_front() -> void:
	assert_int(_braked(_iv(0.15, 0.4))).is_equal(FR)    # left turn
	assert_int(_braked(_iv(-0.15, -0.4))).is_equal(FL)  # right turn


func test_understeer_brakes_the_inner_rear() -> void:
	assert_int(_braked(_iv(0.4, 0.15))).is_equal(RL)
	assert_int(_braked(_iv(-0.4, -0.15))).is_equal(RR)
	# Ploughing straight on with the steer in: still the inner rear.
	assert_int(_braked(_iv(0.4, 0.0))).is_equal(RL)


func test_a_countersteered_spin_brakes_the_front_opposite_the_yaw() -> void:
	# Yawing left with the steer to the right.
	assert_int(_braked(_iv(-0.1, 0.5))).is_equal(FR)


func test_slip_alone_acts_with_the_yaw_inside_its_deadband() -> void:
	# A left turn, the yaw on its reference, the rear stepping out: velocity right of the nose.
	assert_int(_braked(_iv(0.15, 0.15, -deg_to_rad(8.0)))).is_equal(FR)


func test_the_torque_never_passes_the_declared_brake() -> void:
	var front: Vector4 = _iv(0.0, 5.0, 0.0, FULL)["torques"]
	assert_float(front[FR]).is_equal_approx(BRAKE.x, 1e-3)
	var rear: Vector4 = _iv(5.0, 0.1, 0.0, Vector4(0.0, 0.0, BRAKE.y, BRAKE.y))["torques"]
	assert_float(rear[RL]).is_equal_approx(BRAKE.y, 1e-3)


func test_a_yaw_rate_crossing_zero_keeps_the_braked_axle() -> void:
	# Recovering a left spin: the yaw has just crossed to the right, the moment still asks right.
	var held := Vector4(0.0, 300.0, 0.0, 0.0)
	assert_int(_braked(_iv(-0.1, -0.01, 0.0, held))).is_equal(FR)
	# Fresh, the same state reads understeer: the inner rear.
	assert_int(_braked(_iv(-0.1, -0.01))).is_equal(RR)


func test_the_moment_converts_through_the_track() -> void:
	# Below the brake, the modulator's rates out of reach: T = M_z R / (t / 2).
	var moment := StabilityControl.yaw_moment(0.15, 0.25, 0.0, YAW_INERTIA)
	var t: Vector4 = StabilityControl.intervention(SPEED, 0.15, 0.25, 0.0, YAW_INERTIA, HALF_TRACK,
			RADIUS, BRAKE, FULL, TICK, 1e-6, 1e-6)["torques"]
	assert_float(t[FR]).is_equal_approx(-moment * RADIUS.x / HALF_TRACK.x, 1e-2)
	assert_float(t[FR]).is_less(BRAKE.x)


func test_the_rise_and_the_release_are_rate_limited() -> void:
	var t: Vector4 = _iv(0.0, 5.0)["torques"]
	assert_float(t[FR]).is_equal_approx(BRAKE.x / StabilityControl.RISE_S * TICK, 1e-3)
	# The error gone: the held corner releases at its rate, never past 0.
	var step := BRAKE.x / StabilityControl.RELEASE_S * TICK
	var held := Vector4(0.0, 500.0, 0.0, 0.0)
	var out := _iv(0.15, 0.15, 0.0, held)
	assert_int(_braked(out)).is_equal(FR)
	assert_float((out["torques"] as Vector4)[FR]).is_equal_approx(500.0 - step, 1e-3)
	# Still braking, so still trimming the engine.
	assert_float(out["throttle_cap"]).is_less(1.0)
	held[FR] = 0.5 * step
	assert_int(_braked(_iv(0.15, 0.15, 0.0, held))).is_equal(-1)


func test_nothing_below_twenty_kmh() -> void:
	var out := _iv(0.0, 5.0, deg_to_rad(20.0), FULL, 19.0 / 3.6)
	assert_int(_braked(out)).is_equal(-1)
	assert_float(out["throttle_cap"]).is_equal(1.0)


func test_the_engine_trim_is_proportional_to_the_most_braked_corner() -> void:
	# Just past the dead-band: a small torque, as small a trim.
	var ref := 0.155
	var small := _iv(ref, ref + StabilityControl.deadband(ref) + 0.001)
	assert_int(_braked(small)).is_equal(FR)
	var t: Vector4 = small["torques"]
	assert_float(small["throttle_cap"]).is_equal_approx(1.0 - t[FR] / BRAKE.x, 1e-6)
	assert_float(small["throttle_cap"]).is_greater(0.99)
	# At the full brake, the engine is cut off.
	assert_float(_iv(0.0, 5.0, 0.0, FULL)["throttle_cap"]).is_equal_approx(0.0, 1e-6)


func test_a_moment_changing_side_dumps_the_other_side_at_once() -> void:
	# FR braked against a left spin; the body overshoots and the moment now asks left: FR dumps,
	# the left side rises, never both sides at once.
	var held := Vector4(0.0, 1200.0, 0.0, 0.0)
	var out := _iv(0.15, -0.3, 0.0, held)
	var t: Vector4 = out["torques"]
	assert_float(t[FR]).is_equal(0.0)
	assert_float(t[FL] + t[RL]).is_greater(0.0)
	# The same side still asking keeps the rate-limited release.
	assert_float((_iv(0.15, 0.15, 0.0, held)["torques"] as Vector4)[FR]).is_greater(0.0)


# --- roll stability ----------------------------------------------------------------------------

const LIFT := 0.45


## One `roll_application` at `speed`; the modulator's rates out of reach unless `rated`.
static func _roll(lat_g: float, prev := 0.0, speed := SPEED, rated := false) -> float:
	if rated:
		return StabilityControl.roll_application(speed, lat_g, LIFT, prev, TICK)
	return StabilityControl.roll_application(speed, lat_g, LIFT, prev, TICK, 1e-6, 1e-6)


func test_roll_lift_interpolates_on_the_load_and_holds_its_ends() -> void:
	var points := PackedVector2Array([Vector2(8000.0, 0.6), Vector2(14000.0, 0.45)])
	assert_float(StabilityControl.roll_lift_g(points, 11000.0)).is_equal_approx(0.525, 1e-5)
	assert_float(StabilityControl.roll_lift_g(points, 5000.0)).is_equal_approx(0.6, 1e-5)
	assert_float(StabilityControl.roll_lift_g(points, 20000.0)).is_equal_approx(0.45, 1e-5)
	# No table: no roll stability.
	assert_float(StabilityControl.roll_lift_g(PackedVector2Array(), 11000.0)).is_equal(INF)


func test_the_asked_g_is_the_steady_turn_unsigned() -> void:
	var neutral := SPEED * SPEED * 0.03 / WHEELBASE / StabilityControl.G
	assert_float(StabilityControl.asked_lat_g(SPEED, 0.03, WHEELBASE, 0.0, 10.0)) \
			.is_equal_approx(neutral, 1e-6)
	assert_float(StabilityControl.asked_lat_g(SPEED, -0.03, WHEELBASE, 0.0, -10.0)) \
			.is_equal_approx(neutral, 1e-6)
	# Understeer asks less.
	assert_float(StabilityControl.asked_lat_g(SPEED, 0.03, WHEELBASE, 2.0, 10.0)).is_less(neutral)
	assert_float(StabilityControl.asked_lat_g(0.0, 0.3, WHEELBASE, 2.0, 0.0)).is_equal(0.0)


func test_the_asked_g_leads_the_measured_by_at_most_the_margin() -> void:
	# A steer far past what the road carries (ice: 1 m/s² measured) asks the measured plus the margin.
	var bounded := 1.0 / StabilityControl.G + StabilityControl.BOUND_MARGIN_G
	assert_float(StabilityControl.asked_lat_g(SPEED, 0.3, WHEELBASE, 2.0, 1.0)) \
			.is_equal_approx(bounded, 1e-6)
	# Past an oversteering body's critical speed: the bound, never a blow-up.
	assert_float(StabilityControl.asked_lat_g(SPEED, 0.03, WHEELBASE, -50.0, 1.0)) \
			.is_equal_approx(bounded, 1e-6)


func test_under_the_share_of_the_lift_roll_stability_does_nothing() -> void:
	assert_float(_roll(StabilityControl.ROLL_SHARE * LIFT - 0.001)).is_equal(0.0)


func test_roll_application_rises_linearly_to_the_full_brake_at_the_lift() -> void:
	var start := StabilityControl.ROLL_SHARE * LIFT
	assert_float(_roll(0.5 * (start + LIFT))).is_equal_approx(0.5, 1e-5)
	assert_float(_roll(LIFT)).is_equal_approx(1.0, 1e-5)
	assert_float(_roll(LIFT + 0.2)).is_equal_approx(1.0, 1e-5)
	# Either side of the turn.
	assert_float(_roll(-LIFT)).is_equal_approx(1.0, 1e-5)


func test_roll_application_rise_and_release_are_rate_limited() -> void:
	assert_float(_roll(LIFT, 0.0, SPEED, true)).is_equal_approx(TICK / StabilityControl.RISE_S, 1e-6)
	assert_float(_roll(0.0, 0.5, SPEED, true)) \
			.is_equal_approx(0.5 - TICK / StabilityControl.RELEASE_S, 1e-6)
	# Never under 0.
	assert_float(_roll(0.0, 0.01, SPEED, true)).is_equal(0.0)


func test_roll_stability_releases_below_twenty_kmh_and_is_off_with_no_table() -> void:
	# Under the floor the target is 0, released at the rate: no one-tick drop from full braking.
	assert_float(_roll(LIFT, 0.8, 19.0 / 3.6, true)) \
			.is_equal_approx(0.8 - TICK / StabilityControl.RELEASE_S, 1e-6)
	assert_float(_roll(LIFT, 0.0, 19.0 / 3.6, true)).is_equal(0.0)
	assert_float(StabilityControl.roll_application(SPEED, 1.0, INF, 0.8, TICK)).is_equal(0.0)


func test_the_yaw_torque_survives_a_full_roll_application() -> void:
	# FR braked by the yaw controller, roll at full: the front axle's roll part stops where FR meets
	# the brake, so FR - FL stays the yaw's torque; the rear, no yaw, takes the whole roll.
	var t := StabilityControl.corner_torques(1.0, Vector4(0.0, 400.0, 0.0, 0.0), BRAKE)
	assert_float(t[FR]).is_equal_approx(BRAKE.x, 1e-3)
	assert_float(t[FR] - t[FL]).is_equal_approx(400.0, 1e-3)
	assert_float(t[RL]).is_equal_approx(BRAKE.y, 1e-3)
	assert_float(t[RR]).is_equal_approx(BRAKE.y, 1e-3)
	# Under the headroom, the roll part is its share of each axle's brake.
	var half := StabilityControl.corner_torques(0.5, Vector4.ZERO, BRAKE)
	assert_float(half[FL]).is_equal_approx(0.5 * BRAKE.x, 1e-3)
	assert_float(half[RR]).is_equal_approx(0.5 * BRAKE.y, 1e-3)
	# No roll: exactly the yaw's.
	assert_that(StabilityControl.corner_torques(0.0, Vector4(0.0, 400.0, 0.0, 0.0), BRAKE)) \
			.is_equal(Vector4(0.0, 400.0, 0.0, 0.0))


# --- the brake-light request -------------------------------------------------------------------

const LOAD_KG := 2000.0


## The request roll stability's `roll_app` with the yaw's `yaw` asks on the car above.
static func _request(roll_app: float, yaw := Vector4.ZERO) -> bool:
	return StabilityControl.brake_light_request(_retardation(roll_app, yaw))


static func _retardation(roll_app: float, yaw := Vector4.ZERO) -> float:
	return StabilityControl.roll_retardation(StabilityControl.corner_torques(roll_app, yaw, BRAKE),
			yaw, PackedInt32Array([FL, FR, RL, RR]), RADIUS, LOAD_KG)


func test_idle_or_yaw_braking_alone_requests_no_brake_light() -> void:
	assert_bool(_request(0.0)).is_false()
	# Selective braking (R13 5.2.1.30.6): the whole brake on one corner, still no request.
	assert_float(_retardation(0.0, Vector4(0.0, BRAKE.x, 0.0, 0.0))).is_equal(0.0)
	assert_bool(_request(0.0, Vector4(0.0, BRAKE.x, 0.0, 0.0))).is_false()


func test_roll_braking_requests_the_brake_light_from_the_lamp_floor() -> void:
	# Full roll: every corner's brake over its radius, over the load.
	var full := 2.0 * (BRAKE.x + BRAKE.y) / RADIUS.x / LOAD_KG
	assert_float(_retardation(1.0)).is_equal_approx(full, 1e-4)
	var at_floor := StabilityControl.LAMP_DECEL / full
	assert_bool(_request(at_floor * 0.98)).is_false()
	assert_bool(_request(at_floor * 1.02)).is_true()


func test_a_lit_request_holds_down_to_the_release_floor() -> void:
	var on := StabilityControl.LAMP_DECEL
	var off := StabilityControl.LAMP_RELEASE_DECEL
	assert_float(off).is_less(on)
	# Dark, it waits for the lamp floor; lit, it holds under it until the release floor.
	assert_bool(StabilityControl.brake_light_request(0.5 * (on + off), false)).is_false()
	assert_bool(StabilityControl.brake_light_request(0.5 * (on + off), true)).is_true()
	assert_bool(StabilityControl.brake_light_request(off * 0.99, true)).is_false()
	assert_bool(StabilityControl.brake_light_request(on, false)).is_true()


func test_the_yaw_priority_cap_lowers_the_roll_retardation() -> void:
	# FR's yaw torque leaves the front axle's roll part short of the brake.
	var yaw := Vector4(0.0, 400.0, 0.0, 0.0)
	assert_float(_retardation(1.0, yaw)).is_equal_approx(
			(2.0 * (BRAKE.x - 400.0) + 2.0 * BRAKE.y) / RADIUS.x / LOAD_KG, 1e-4)


# --- trailer roll-over control -----------------------------------------------------------------

const Stage := StabilityControl.TrailerStage
const PULSE := Vector2(StabilityControl.TRAILER_PULSE, StabilityControl.TRAILER_PULSE)
## Past the pulse window at 60 Hz.
const PULSE_TICKS := 30


## The crossing g at LIFT with nothing learned.
static func _threshold() -> float:
	return StabilityControl.trailer_roll_threshold(LIFT, 0.0)


## `state` settled at `lat_g`: its rise rate 0, so the next tick's step there is a slow one.
static func _settled(lat_g: float, state := StabilityControl.trailer_roll_state()) -> Dictionary:
	var s := state.duplicate()
	s["last_g"] = absf(lat_g)
	s["rate"] = 0.0
	return s


## `ticks` steps at a held `lat_g` from `state`; the last result.
static func _tr_hold(state: Dictionary, lat_g: float, ticks: int, left := SPEED, right := SPEED,
		speed := SPEED, lift := LIFT) -> Dictionary:
	var r := {"state": state, "cmd": Vector2.ZERO}
	for i in ticks:
		r = StabilityControl.trailer_roll_step(r["state"], speed, lat_g, lift, left, right, TICK)
	return r


func test_below_the_trailer_threshold_it_asks_nothing() -> void:
	var g := _threshold() - 0.001
	var r := _tr_hold(_settled(g), g, 120)
	assert_that(r["cmd"]).is_equal(Vector2.ZERO)
	assert_int(r["state"]["stage"]).is_equal(Stage.IDLE)


func test_a_slow_crossing_fires_one_pulse() -> void:
	var g := _threshold() + 0.001
	var r := _tr_hold(_settled(g), g, 1)
	assert_int(r["state"]["stage"]).is_equal(Stage.PULSE)
	assert_that(r["cmd"]).is_equal(PULSE)
	# Still wheels through the window: the crossing is spent.
	r = _tr_hold(r["state"], g, PULSE_TICKS)
	assert_int(r["state"]["stage"]).is_equal(Stage.SPENT)
	assert_that(r["cmd"]).is_equal(Vector2.ZERO)
	# Held above the threshold: no second pulse.
	r = _tr_hold(r["state"], g, 120)
	assert_that(r["cmd"]).is_equal(Vector2.ZERO)
	# Under the release level it re-arms; the next crossing (past the learned raise) pulses again.
	r = _tr_hold(r["state"], StabilityControl.TRAILER_RELEASE_SHARE * LIFT - 0.001, 1)
	assert_int(r["state"]["stage"]).is_equal(Stage.IDLE)
	var again := StabilityControl.trailer_roll_threshold(LIFT, r["state"]["raise"]) + 0.001
	r = _tr_hold(_settled(again, r["state"]), again, 1)
	assert_that(r["cmd"]).is_equal(PULSE)


func test_inside_wheels_slowing_under_the_pulse_bring_the_full_outside_application() -> void:
	var g := _threshold() + 0.001
	# A left turn: the left wheels inside, the right outside.
	var r := _tr_hold(_tr_hold(_settled(g), g, 1)["state"], g, 1, 0.9 * SPEED, SPEED)
	assert_int(r["state"]["stage"]).is_equal(Stage.FULL)
	assert_that(r["cmd"]).is_equal(Vector2(StabilityControl.TRAILER_PULSE, 1.0))
	# A right turn mirrors it.
	r = _tr_hold(_tr_hold(_settled(-g), -g, 1)["state"], -g, 1, SPEED, 0.9 * SPEED)
	assert_that(r["cmd"]).is_equal(Vector2(1.0, StabilityControl.TRAILER_PULSE))
	# The turn's own inside-wheel deficit, held from the crossing, is no reaction.
	r = _tr_hold(_settled(g), g, PULSE_TICKS, 0.9 * SPEED, SPEED)
	assert_int(r["state"]["stage"]).is_equal(Stage.SPENT)


func test_still_wheels_raise_the_threshold_up_to_its_ceiling() -> void:
	var g := _threshold() + 0.001
	var r := _tr_hold(_settled(g), g, PULSE_TICKS)
	assert_float(r["state"]["raise"]).is_equal_approx(StabilityControl.TRAILER_LEARN_G, 1e-6)
	# A g back under the release level mid-pulse is no verdict: idle, nothing learned.
	var brief := _tr_hold(_tr_hold(_settled(g), g, 1)["state"], 0.0, 1)
	assert_int(brief["state"]["stage"]).is_equal(Stage.IDLE)
	assert_float(brief["state"]["raise"]).is_equal(0.0)
	# Re-armed, the g that fired before no longer does.
	r = _tr_hold(r["state"], 0.0, 1)
	r = _tr_hold(_settled(g, r["state"]), g, 60)
	assert_int(r["state"]["stage"]).is_equal(Stage.IDLE)
	# The learned raise stops at TRAILER_MAX_SHARE of the lift.
	var ceiling := StabilityControl.TRAILER_MAX_SHARE * LIFT
	assert_float(StabilityControl.trailer_roll_threshold(LIFT, 1.0)).is_equal_approx(ceiling, 1e-6)
	var near := _settled(ceiling)
	near["raise"] = ceiling - _threshold() - 0.01
	r = _tr_hold(near, ceiling, PULSE_TICKS + 1)
	assert_float(StabilityControl.trailer_roll_threshold(LIFT, r["state"]["raise"])) \
			.is_equal_approx(ceiling, 1e-6)


func test_a_rapid_rise_brakes_without_a_pulse() -> void:
	# 3 g/s from straight running.
	var r := {"state": StabilityControl.trailer_roll_state(), "cmd": Vector2.ZERO}
	var g := 0.0
	while r["state"]["stage"] == Stage.IDLE:
		g += 3.0 * TICK
		assert_float(g).is_less(LIFT)
		r = StabilityControl.trailer_roll_step(r["state"], SPEED, g, LIFT, SPEED, SPEED, TICK)
	assert_int(r["state"]["stage"]).is_equal(Stage.FULL)
	assert_that(r["cmd"]).is_equal(Vector2(StabilityControl.TRAILER_PULSE, 1.0))


func test_the_trailer_function_never_passes_the_declared_brake() -> void:
	for start: Dictionary in [_settled(5.0), StabilityControl.trailer_roll_state()]:
		var r := {"state": start, "cmd": Vector2.ZERO}
		for i in 60:
			var inside := SPEED if i < 3 else 0.5 * SPEED
			r = StabilityControl.trailer_roll_step(r["state"], SPEED, 5.0, LIFT, inside, SPEED, TICK)
			assert_float(maxf(r["cmd"].x, r["cmd"].y)).is_less_equal(1.0)


func test_a_heavier_load_lowers_the_trailer_threshold() -> void:
	var points := PackedVector2Array([Vector2(8000.0, 0.6), Vector2(14000.0, 0.45)])
	var g := 0.36
	var heavy := _tr_hold(_settled(g), g, 1, SPEED, SPEED, SPEED,
			StabilityControl.roll_lift_g(points, 14000.0))
	var light := _tr_hold(_settled(g), g, 1, SPEED, SPEED, SPEED,
			StabilityControl.roll_lift_g(points, 8000.0))
	assert_that(heavy["cmd"]).is_equal(PULSE)
	assert_that(light["cmd"]).is_equal(Vector2.ZERO)


func test_the_trailer_function_is_off_below_fifteen_kmh_and_releases_once_non_critical() -> void:
	var g := _threshold() + 0.001
	assert_that(_tr_hold(_settled(g), g, 1, SPEED, SPEED, 14.0 / 3.6)["cmd"]).is_equal(Vector2.ZERO)
	assert_that(_tr_hold(_settled(g), g, 1, SPEED, SPEED, 16.0 / 3.6)["cmd"]).is_equal(PULSE)
	# No lift table: off.
	assert_that(_tr_hold(_settled(g), g, 1, SPEED, SPEED, SPEED, INF)["cmd"]).is_equal(Vector2.ZERO)
	var full := _tr_hold(_tr_hold(_settled(g), g, 1)["state"], g, 1, 0.5 * SPEED, SPEED)
	assert_int(full["state"]["stage"]).is_equal(Stage.FULL)
	var release := StabilityControl.TRAILER_RELEASE_SHARE * LIFT
	assert_int(_tr_hold(full["state"], release + 0.001, 1)["state"]["stage"]).is_equal(Stage.FULL)
	var off := _tr_hold(full["state"], release - 0.001, 1)
	assert_int(off["state"]["stage"]).is_equal(Stage.IDLE)
	assert_that(off["cmd"]).is_equal(Vector2.ZERO)
	# Slowing under the floor mid-application drops it at once (the chambers' lag is the release).
	assert_that(_tr_hold(full["state"], g, 1, SPEED, SPEED, 14.0 / 3.6)["cmd"]).is_equal(Vector2.ZERO)

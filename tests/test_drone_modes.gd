extends GdUnitTestSuite
## Drone flight modes: mode resolution, altitude cascade, position control, RTL, geofence.
## Pins contract enums against the ladder and DroneModes against InputRouter's
## FLIGHT_MODE_COUNT; router carries own copy, so both must stay in sync.

const M := preload("res://src/vehicles/drone/drone_modes.gd")
const D := preload("res://src/vehicles/drone/drone.gd")
const S := preload("res://src/vehicles/drone/drone_sensors.gd")
const Router := preload("res://src/input/input_router.gd")

const DELTA := 1.0 / 60.0

## The shipped airframe, in round-enough numbers to check by hand: 5 kg at 9.8 m/s^2 against
## 150 N of thrust, 45 N of climb trim, 6.5 N per m/s of vertical drag, 32 degrees of tilt.
const MASS := 5.0
const G := 9.8
const MAX_THRUST := 150.0
const CLIMB_FORCE := 45.0
const V_DRAG := 6.5
const MAX_TILT_RAD := 0.5585053606381855  ## deg_to_rad(32)

## The hover collective and the HUMAN's full-climb collective — the two numbers DroneVehicle
## derives at _ready by calling lift_thrust, computed the same way here so the test cannot drift
## from the vehicle by hand-typing either.
func _hover() -> float:
	return D.lift_thrust(MASS, G, 0.0, CLIMB_FORCE, MAX_THRUST) / MAX_THRUST


func _ceiling() -> float:
	return D.lift_thrust(MASS, G, 1.0, CLIMB_FORCE, MAX_THRUST) / MAX_THRUST


## `resolve_mode` takes the DEBOUNCED position-fix predicate rather than a fix type, so every case
## below runs its fix through `has_pos_fix`. That keeps the FIX_3D threshold under test here
## instead of being replaced by a hand-typed bool the moment the signature changed.
func _fix(fix_type: int) -> bool:
	return M.has_pos_fix(fix_type)


# --- the ladder, and the three places it is written down ------------------------

func test_the_ladder_ordinals_are_dense_and_ordered() -> void:
	assert_int(M.STABILIZE).is_equal(0)
	assert_int(M.ALT_HOLD).is_equal(1)
	assert_int(M.LOITER).is_equal(2)
	assert_int(M.RTL).is_equal(3)
	assert_int(M.LAND).is_equal(4)
	assert_int(M.COUNT).is_equal(5)
	for mode in M.COUNT:
		assert_bool(M.is_valid(mode)).is_true()
	assert_bool(M.is_valid(-1)).is_false()
	assert_bool(M.is_valid(M.COUNT)).is_false()


## Request and readback must decode identically (two contract enum tables, one table).
func test_both_contract_enum_tables_match_the_ladder_and_each_other() -> void:
	var request: RefCounted = Contract.data.get_signal_def("flight_mode", "in")
	var actual: RefCounted = Contract.data.get_signal_def("mode_actual", "out")
	assert_object(request).is_not_null()
	assert_object(actual).is_not_null()
	var labels := ["STABILIZE", "ALT HOLD", "LOITER", "RTL", "LAND"]
	for mode in M.COUNT:
		assert_str(request.enum_label(mode)) \
			.override_failure_message("flight_mode label for mode %d" % mode) \
			.is_equal(labels[mode])
		assert_str(actual.enum_label(mode)) \
			.override_failure_message("mode_actual label for mode %d" % mode) \
			.is_equal(labels[mode])
	# No range: would become a meaningless 0-4 bar (layout regression).
	assert_int(actual.range.size()).is_equal(0)
	assert_str(actual.flavor).is_equal("dronecan")


func test_the_cycle_walks_the_whole_ladder_and_wraps() -> void:
	var mode := M.STABILIZE
	var seen := [mode]
	for _i in M.COUNT:
		mode = M.cycle(mode)
		seen.append(mode)
	assert_array(seen).is_equal([M.STABILIZE, M.ALT_HOLD, M.LOITER, M.RTL, M.LAND, M.STABILIZE])
	# Out-of-range modes land inside the ladder (posmod, not %).
	for mode_in in [-7, -1, 5, 99]:
		assert_int(M.cycle(mode_in)) \
			.override_failure_message("cycle(%d) escaped the ladder" % mode_in) \
			.is_between(0, M.COUNT - 1)


## Router mirrors the ladder (can't depend on a vehicle class); both asserted over full range.
func test_the_router_mirrors_the_ladder() -> void:
	assert_int(Router.FLIGHT_MODE_COUNT) \
		.override_failure_message("InputRouter.FLIGHT_MODE_COUNT has not followed DroneModes.COUNT") \
		.is_equal(M.COUNT)
	for mode in range(-8, 16):
		assert_int(M.cycle(mode)) \
			.override_failure_message("DroneModes.cycle and InputRouter.cycle_flight_mode disagree at %d" % mode) \
			.is_equal(Router.cycle_flight_mode(mode))


# --- resolve_mode: every refusal and every override ----------------------------

func test_a_disarmed_craft_is_always_stabilize() -> void:
	for mode in M.COUNT:
		assert_int(M.resolve_mode(mode, _fix(S.FIX_3D), false, false, false)) \
			.override_failure_message("disarmed, request %d" % mode) \
			.is_equal(M.STABILIZE)
	# ...even with a fence breach latched: nothing autonomous runs on stopped motors.
	assert_int(M.resolve_mode(M.LOITER, _fix(S.FIX_3D), true, false, true)).is_equal(M.STABILIZE)


func test_an_unknown_request_lands_on_the_safe_pose() -> void:
	for mode in [-1, M.COUNT, 99, 255]:
		assert_int(M.resolve_mode(mode, _fix(S.FIX_3D), false, true, false)) \
			.override_failure_message("unknown request %d" % mode) \
			.is_equal(M.STABILIZE)


func test_a_granted_request_is_simply_the_request() -> void:
	for mode in M.COUNT:
		if mode == M.RTL:
			continue  # RTL's landing leg is its own case below
		assert_int(M.resolve_mode(mode, _fix(S.FIX_3D), false, true, false)).is_equal(mode)
	assert_int(M.resolve_mode(M.RTL, _fix(S.FIX_3D), false, true, false)).is_equal(M.RTL)


## The refusal that pressing Y during a loiter produces. Both position modes need four
## satellites; STABILIZE, ALT_HOLD and LAND do not and must be untouched by the fix.
func test_the_position_modes_need_a_3d_fix_and_the_others_do_not() -> void:
	for fix in [S.FIX_NONE, S.FIX_TIME_ONLY, S.FIX_2D]:
		assert_int(M.resolve_mode(M.LOITER, _fix(fix), false, true, false)) \
			.override_failure_message("LOITER at fix %d" % fix).is_equal(M.ALT_HOLD)
		assert_int(M.resolve_mode(M.RTL, _fix(fix), false, true, false)) \
			.override_failure_message("RTL at fix %d" % fix).is_equal(M.ALT_HOLD)
		assert_int(M.resolve_mode(M.STABILIZE, _fix(fix), false, true, false)).is_equal(M.STABILIZE)
		assert_int(M.resolve_mode(M.ALT_HOLD, _fix(fix), false, true, false)).is_equal(M.ALT_HOLD)
		assert_int(M.resolve_mode(M.LAND, _fix(fix), false, true, false)).is_equal(M.LAND)
	assert_int(M.resolve_mode(M.LOITER, _fix(S.FIX_3D), false, true, false)).is_equal(M.LOITER)


func test_a_fence_breach_commands_rtl_over_the_top_of_a_selection() -> void:
	assert_int(M.resolve_mode(M.STABILIZE, _fix(S.FIX_3D), true, true, false)).is_equal(M.RTL)
	assert_int(M.resolve_mode(M.ALT_HOLD, _fix(S.FIX_3D), true, true, false)).is_equal(M.RTL)
	assert_int(M.resolve_mode(M.LOITER, _fix(S.FIX_3D), true, true, false)).is_equal(M.RTL)
	# ...but RTL and LAND are not modes a fence needs to correct, so it leaves them alone.
	assert_int(M.resolve_mode(M.RTL, _fix(S.FIX_3D), true, true, false)).is_equal(M.RTL)
	assert_int(M.resolve_mode(M.LAND, _fix(S.FIX_3D), true, true, false)).is_equal(M.LAND)


## A breach WITHOUT a fix degrades honestly rather than pretending to fly home — the fix refusal
## is applied after the fence override on purpose, and this is the case that proves the order.
func test_a_fence_breach_with_no_fix_still_falls_back_to_alt_hold() -> void:
	assert_int(M.resolve_mode(M.STABILIZE, _fix(S.FIX_2D), true, true, false)).is_equal(M.ALT_HOLD)
	assert_int(M.resolve_mode(M.LOITER, _fix(S.FIX_NONE), true, true, false)).is_equal(M.ALT_HOLD)


func test_rtls_landing_leg_reads_as_land() -> void:
	assert_int(M.resolve_mode(M.RTL, _fix(S.FIX_3D), false, true, true)).is_equal(M.LAND)
	assert_int(M.resolve_mode(M.STABILIZE, _fix(S.FIX_3D), true, true, true)).is_equal(M.LAND)
	# The latch means nothing to a mode that is not returning home.
	assert_int(M.resolve_mode(M.LOITER, _fix(S.FIX_3D), false, true, true)).is_equal(M.LOITER)


# --- the debounced fix the mode decides on -------------------------------------

func test_the_fix_threshold_is_owned_in_one_place() -> void:
	assert_bool(M.has_pos_fix(S.FIX_3D)).is_true()
	for fix in [S.FIX_NONE, S.FIX_TIME_ONLY, S.FIX_2D]:
		assert_bool(M.has_pos_fix(fix)) \
			.override_failure_message("fix %d claimed a position solution" % fix).is_false()


## The case this exists for: the sky sweep turns over four of sixteen rays a tick, so a craft at
## the edge of a shed crosses the satellite threshold in both directions within a few ticks. Fed
## raw into resolve_mode that is a mode change per tick — and a mode change re-seats the hold
## targets, so the "position hold" would walk with the craft. Alternating input, held output.
func test_a_flickering_fix_never_moves_the_mode() -> void:
	var held := true
	var hold := 0.0
	var raw := true
	for _i in 600:  # 10 s of tick-rate chatter
		raw = not raw
		hold = M.fix_hold_step(hold, raw, held, DELTA)
		held = M.held_fix_ok(raw, held, hold)
		assert_bool(held).override_failure_message("the mode's fix followed the chatter").is_true()


## ...but a change that STANDS gets through, in FIX_DEBOUNCE and not before. This is the half that
## keeps killing the GNSS node visible.
func test_a_standing_fix_change_gets_through_after_the_debounce() -> void:
	var held := true
	var hold := 0.0
	var elapsed := 0.0
	for _i in 600:
		hold = M.fix_hold_step(hold, false, held, DELTA)
		var next: bool = M.held_fix_ok(false, held, hold)
		if held and not next:
			elapsed = hold
		held = next
	assert_bool(held).is_false()
	assert_float(elapsed) \
		.override_failure_message("the fix flipped after %f s, not FIX_DEBOUNCE" % elapsed) \
		.is_equal_approx(M.FIX_DEBOUNCE, DELTA * 1.5)
	# Symmetric: a reacquisition is trusted on the same terms, so a mode cannot flicker back
	# faster than it dropped.
	hold = 0.0
	elapsed = 0.0
	for _i in 600:
		hold = M.fix_hold_step(hold, true, held, DELTA)
		var next: bool = M.held_fix_ok(true, held, hold)
		if not held and next:
			elapsed = hold
		held = next
	assert_bool(held).is_true()
	assert_float(elapsed).is_equal_approx(M.FIX_DEBOUNCE, DELTA * 1.5)
	# Agreement zeroes the accumulator, so it measures a STANDING change and never a total.
	assert_float(M.fix_hold_step(0.9, true, true, DELTA)).is_equal(0.0)
	# A zero or negative delta cannot advance it.
	assert_float(M.fix_hold_step(0.5, false, true, 0.0)).is_equal(0.5)
	assert_float(M.fix_hold_step(0.5, false, true, -1.0)).is_equal(0.5)


# --- the two auto latches ------------------------------------------------------

func test_the_fence_latch_holds_until_the_craft_is_disarmed() -> void:
	var home := Vector3.ZERO
	var inside := Vector3(10.0, 5.0, 0.0)
	var outside := Vector3(M.GEOFENCE_RADIUS + 1.0, 5.0, 0.0)
	var r := M.GEOFENCE_RADIUS
	var c := M.GEOFENCE_CEILING
	assert_bool(M.fence_latch(false, true, inside, home, r, c)).is_false()
	assert_bool(M.fence_latch(false, true, outside, home, r, c)).is_true()
	# It holds once set: the RTL it commands flies the craft back inside, which would otherwise
	# release the command that was flying it there.
	assert_bool(M.fence_latch(true, true, inside, home, r, c)).is_true()
	# Disarming clears it, breached or not.
	assert_bool(M.fence_latch(true, false, outside, home, r, c)).is_false()


## The pilot's cancel is what makes the fence releasable from OUTSIDE it, and this is the state
## that carries it past the tick it happened on — the vehicle releases `_fence_rtl` and calls
## `fence_latch` on that same tick, so with nothing held the very breach just cancelled commands
## RTL straight back.
func test_an_answered_fence_breach_holds_until_the_craft_is_back_inside() -> void:
	var home := Vector3.ZERO
	var inside := Vector3(10.0, 5.0, 0.0)
	var outside := Vector3(M.GEOFENCE_RADIUS + 1.0, 5.0, 0.0)
	var r := M.GEOFENCE_RADIUS
	var c := M.GEOFENCE_CEILING
	# It never SETS itself — only the pilot's mode change does, and it holds while the craft is out.
	assert_bool(M.fence_answered(false, true, outside, home, r, c)).is_false()
	assert_bool(M.fence_answered(true, true, outside, home, r, c)).is_true()
	# Re-entering spends it, so the next breach commands again. So does a disarm.
	assert_bool(M.fence_answered(true, true, inside, home, r, c)).is_false()
	assert_bool(M.fence_answered(true, false, outside, home, r, c)).is_false()


## The latch reads the resolved mode. Keyed off the request instead, a craft near
## home with an RTL selected but refused for want of a fix still latches — fly away, restore the
## receiver, and the first tick with a fix reads LAND and puts the aircraft down where it stands.
func test_the_landing_leg_latches_off_the_flown_mode_and_not_the_request() -> void:
	assert_bool(M.rtl_landing_latch(false, true, M.RTL, M.RTL_LAND)).is_true()
	# The refused case: the FC is in ALT_HOLD, so there is no landing leg to be on.
	assert_bool(M.rtl_landing_latch(false, true, M.ALT_HOLD, M.RTL_LAND)).is_false()
	# ...and neither cruise nor climb latches, whatever the mode.
	for phase in [M.RTL_CLIMB, M.RTL_CRUISE]:
		assert_bool(M.rtl_landing_latch(false, true, M.RTL, phase)) \
			.override_failure_message("RTL phase %d latched the landing leg" % phase).is_false()
	# It HOLDS once set — a craft drifting back outside the arrival radius during its own descent
	# would otherwise climb away and come back, forever.
	assert_bool(M.rtl_landing_latch(true, true, M.RTL, M.RTL_CRUISE)).is_true()
	# Disarming clears it.
	assert_bool(M.rtl_landing_latch(true, false, M.RTL, M.RTL_LAND)).is_false()


## The refusal-then-restore sequence, run end to end: the bug this pairs against put the craft
## down 500 m from home the instant its receiver came back.
func test_a_refused_rtl_near_home_does_not_arm_a_landing_for_later() -> void:
	var latched := false
	# Armed over home with the GNSS node killed and RTL selected: refused to ALT_HOLD.
	var mode := M.resolve_mode(M.RTL, _fix(S.FIX_NONE), false, true, latched)
	assert_int(mode).is_equal(M.ALT_HOLD)
	latched = M.rtl_landing_latch(latched, true, mode, M.RTL_LAND)
	assert_bool(latched).is_false()
	# Fly 500 m out, restore the receiver: a real RTL, on its CRUISE leg, not a landing.
	mode = M.resolve_mode(M.RTL, _fix(S.FIX_3D), false, true, latched)
	assert_int(mode).is_equal(M.RTL)
	latched = M.rtl_landing_latch(latched, true, mode, M.RTL_CRUISE)
	assert_bool(latched).is_false()
	# ...and it only hands over to LAND once it is actually home.
	latched = M.rtl_landing_latch(latched, true, mode, M.RTL_LAND)
	assert_int(M.resolve_mode(M.RTL, _fix(S.FIX_3D), false, true, latched)).is_equal(M.LAND)


## Which modes may CARRY the climb-rate trim across a change: the four that share the cascade.
func test_only_stabilize_is_outside_the_cascade() -> void:
	assert_bool(M.uses_cascade(M.STABILIZE)).is_false()
	for mode in [M.ALT_HOLD, M.LOITER, M.RTL, M.LAND]:
		assert_bool(M.uses_cascade(mode)) \
			.override_failure_message("mode %d left the cascade" % mode).is_true()
	# An out-of-range mode is not a cascade mode either, so an unknown byte cannot carry a trim.
	for mode in [-1, M.COUNT, 99]:
		assert_bool(M.uses_cascade(mode)).is_false()


# --- the altitude cascade ------------------------------------------------------

func test_the_rate_target_is_clamped_to_what_the_stick_could_ask() -> void:
	assert_float(M.alt_rate_target(0.0, 0.0)).is_equal(0.0)
	# A big error saturates at the stick's own ceiling rather than commanding a dive.
	assert_float(M.alt_rate_target(100.0, 0.0)).is_equal(M.ALT_RATE_MAX)
	assert_float(M.alt_rate_target(-100.0, 0.0)).is_equal(-M.ALT_RATE_MAX)
	assert_float(M.alt_rate_target(0.0, 99.0)).is_equal(M.ALT_RATE_MAX)
	# With no error the stick's feedforward passes straight through.
	assert_float(M.alt_rate_target(0.0, 1.5)).is_equal_approx(1.5, 1e-6)
	# ...and the P term is ALT_KP per metre.
	assert_float(M.alt_rate_target(1.0, 0.0)).is_equal_approx(M.ALT_KP, 1e-6)


func test_the_integrator_is_bounded_both_ways() -> void:
	var integ := 0.0
	for _i in 6000:  # 100 s of a sustained error, far past any real saturation
		integ = M.alt_integ_step(integ, 5.0, DELTA)
	assert_float(integ).is_equal_approx(M.RATE_I_MAX, 1e-6)
	for _i in 12000:
		integ = M.alt_integ_step(integ, -5.0, DELTA)
	assert_float(integ).is_equal_approx(-M.RATE_I_MAX, 1e-6)
	# A zero delta cannot move it, and a negative one cannot run it backwards.
	assert_float(M.alt_integ_step(0.05, 5.0, 0.0)).is_equal(0.05)
	assert_float(M.alt_integ_step(0.05, 5.0, -1.0)).is_equal(0.05)


## The cap that matters: an autonomous mode may not out-climb the pilot it stands in for. Swept
## rather than spot-checked, because the ceiling is what a saturating loop pushes against every
## time it is asked for a brisk climb.
func test_the_auto_collective_never_exceeds_what_a_human_can_command() -> void:
	var ceiling := _ceiling()
	assert_float(ceiling).is_equal_approx((MASS * G + CLIMB_FORCE) / MAX_THRUST, 1e-6)
	for rate_err in [-100.0, -10.0, -3.0, -0.5, 0.0, 0.5, 3.0, 10.0, 100.0]:
		for integ in [-M.RATE_I_MAX, 0.0, M.RATE_I_MAX]:
			var c: float = M.alt_hold_collective(_hover(), rate_err, integ, ceiling)
			assert_float(c) \
				.override_failure_message("collective %f at rate_err %f, integ %f" % [c, rate_err, integ]) \
				.is_between(0.0, ceiling)


func test_a_settled_hover_asks_for_exactly_the_hover_collective() -> void:
	assert_float(M.alt_hold_collective(_hover(), 0.0, 0.0, _ceiling())) \
		.is_equal_approx(_hover(), 1e-9)


## The CI-visible half of "tune against wind": the loop has to hold its altitude against a steady
## disturbance, which is the whole reason the rate integrator exists. Flown as a vertical point
## mass with the drone's own numbers — thrust, weight, vertical drag — plus 6 N of downdraft,
## which is what ~6 m/s of horizontal wind costs the craft in tilt terms.
func test_the_altitude_cascade_rejects_a_steady_disturbance() -> void:
	var y := 0.0
	var v := 0.0
	var integ := 0.0
	var worst := 0.0
	for _i in 1800:  # 30 s
		var rate_target: float = M.alt_rate_target(0.0 - y, 0.0)
		var rate_err := rate_target - v
		integ = M.alt_integ_step(integ, rate_err, DELTA)
		var coll: float = M.alt_hold_collective(_hover(), rate_err, integ, _ceiling())
		var force := coll * MAX_THRUST - MASS * G - V_DRAG * v - 6.0
		v += force / MASS * DELTA
		y += v * DELTA
		worst = maxf(worst, absf(y))
	assert_float(absf(y)) \
		.override_failure_message("held %f m off target against a steady 6 N downdraft" % y) \
		.is_less(0.25)
	# It gets there without diving for it, and the trim it settles on is the disturbance itself:
	# 6 N of 150 N = 0.04 of collective.
	assert_float(worst).is_less(2.0)
	assert_float(integ).is_equal_approx(6.0 / MAX_THRUST, 0.01)


# --- the position controller ---------------------------------------------------

## A sign error here flies the craft away from the point it is holding, and every axis has its
## own convention to get wrong, so all four directions are pinned. The return is in
## level_target_up's tilt convention, where +x leans BACKWARD and +y leans to starboard.
func test_the_position_demand_leans_toward_the_target() -> void:
	# Target ahead -> lean forward (negative x).
	assert_float(M.position_tilt_demand(Vector2(5.0, 0.0), Vector2.ZERO, MAX_TILT_RAD).x).is_less(0.0)
	# Target behind -> lean back.
	assert_float(M.position_tilt_demand(Vector2(-5.0, 0.0), Vector2.ZERO, MAX_TILT_RAD).x).is_greater(0.0)
	# Target to starboard -> lean right; to port -> lean left.
	assert_float(M.position_tilt_demand(Vector2(0.0, 5.0), Vector2.ZERO, MAX_TILT_RAD).y).is_greater(0.0)
	assert_float(M.position_tilt_demand(Vector2(0.0, -5.0), Vector2.ZERO, MAX_TILT_RAD).y).is_less(0.0)
	# On the anchor with no drift, it asks for level.
	assert_vector(M.position_tilt_demand(Vector2.ZERO, Vector2.ZERO, MAX_TILT_RAD)).is_equal(Vector2.ZERO)


func test_the_damping_term_opposes_the_drift() -> void:
	# Drifting forward off a held anchor: lean BACK to stop, whichever way the error points.
	assert_float(M.position_tilt_demand(Vector2.ZERO, Vector2(2.0, 0.0), MAX_TILT_RAD).x).is_greater(0.0)
	assert_float(M.position_tilt_demand(Vector2.ZERO, Vector2(0.0, 2.0), MAX_TILT_RAD).y).is_less(0.0)
	# The loop balances where POS_KP * err == POS_KD * vel, which is the approach profile: the
	# demand is exactly zero at v = (POS_KP / POS_KD) * err.
	var err := 10.0
	var v := M.POS_KP / M.POS_KD * err
	assert_vector(M.position_tilt_demand(Vector2(err, err), Vector2(v, v), MAX_TILT_RAD)) \
		.is_equal_approx(Vector2.ZERO, Vector2.ONE * 1e-6)


## The tilt is limited as a vector, so a diagonal cannot make 45 degrees out of two 32-degree
## axes. That is the position controller's half of "an autonomous mode may not exceed what a
## human can command".
func test_the_position_demand_never_out_leans_the_stick() -> void:
	for err in [Vector2(1000.0, 0.0), Vector2(0.0, -1000.0), Vector2(1000.0, 1000.0),
			Vector2(-700.0, 700.0)]:
		var d: Vector2 = M.position_tilt_demand(err, Vector2.ZERO, MAX_TILT_RAD)
		assert_float(d.length()) \
			.override_failure_message("error %s produced a %f rad lean" % [err, d.length()]) \
			.is_less_equal(MAX_TILT_RAD + 1e-6)
	# A zero ceiling is a craft that may not lean at all, not a division by it.
	assert_vector(M.position_tilt_demand(Vector2(1000.0, 1000.0), Vector2.ZERO, 0.0)) \
		.is_equal(Vector2.ZERO)


# --- home, RTL and the fence ---------------------------------------------------

func test_home_distance_is_horizontal() -> void:
	var home := Vector3(10.0, 5.0, -20.0)
	# Straight overhead is AT home, however high.
	assert_float(M.home_distance(Vector3(10.0, 400.0, -20.0), home)).is_equal_approx(0.0, 1e-6)
	assert_float(M.home_distance(Vector3(13.0, 5.0, -16.0), home)).is_equal_approx(5.0, 1e-6)


func test_rtl_climbs_where_it_is_then_cruises_then_lands() -> void:
	var home := Vector3(0.0, 100.0, 0.0)
	var far_low := Vector3(200.0, 105.0, 0.0)
	assert_int(M.rtl_phase_of(far_low, home, M.RTL_ALT, M.RTL_ARRIVE_M)).is_equal(M.RTL_CLIMB)
	# ...and the climb leg goes straight UP from where the craft is, not diagonally through
	# whatever is between here and home.
	assert_vector(M.rtl_target(home, far_low, M.RTL_CLIMB, M.RTL_ALT)) \
		.is_equal(Vector3(200.0, 140.0, 0.0))

	var far_high := Vector3(200.0, 145.0, 0.0)
	assert_int(M.rtl_phase_of(far_high, home, M.RTL_ALT, M.RTL_ARRIVE_M)).is_equal(M.RTL_CRUISE)
	assert_vector(M.rtl_target(home, far_high, M.RTL_CRUISE, M.RTL_ALT)) \
		.is_equal(Vector3(0.0, 140.0, 0.0))

	# Over home is the landing leg whatever the altitude — there is nothing left to climb for.
	var overhead := Vector3(2.0, 300.0, 0.0)
	assert_int(M.rtl_phase_of(overhead, home, M.RTL_ALT, M.RTL_ARRIVE_M)).is_equal(M.RTL_LAND)
	assert_vector(M.rtl_target(home, overhead, M.RTL_LAND, M.RTL_ALT)).is_equal(home)


func test_the_climb_leg_has_a_tolerance_so_it_cannot_chatter() -> void:
	var home := Vector3.ZERO
	# Just inside the tolerance band counts as at altitude; clearly below it does not.
	var just_under := Vector3(50.0, M.RTL_ALT - M.RTL_ALT_TOL + 0.1, 0.0)
	assert_int(M.rtl_phase_of(just_under, home, M.RTL_ALT, M.RTL_ARRIVE_M)).is_equal(M.RTL_CRUISE)
	var well_under := Vector3(50.0, M.RTL_ALT - M.RTL_ALT_TOL - 0.1, 0.0)
	assert_int(M.rtl_phase_of(well_under, home, M.RTL_ALT, M.RTL_ARRIVE_M)).is_equal(M.RTL_CLIMB)


func test_the_fence_trips_on_radius_and_on_ceiling_independently() -> void:
	var home := Vector3.ZERO
	var r := M.GEOFENCE_RADIUS
	var c := M.GEOFENCE_CEILING
	assert_bool(M.geofence_breach(Vector3(r - 1.0, c - 1.0, 0.0), home, r, c)).is_false()
	assert_bool(M.geofence_breach(Vector3(r + 1.0, 0.0, 0.0), home, r, c)).is_true()
	assert_bool(M.geofence_breach(Vector3(0.0, c + 1.0, 0.0), home, r, c)).is_true()
	# Exactly on either limit is inside it — the fence is crossed, not touched.
	assert_bool(M.geofence_breach(Vector3(r, 0.0, 0.0), home, r, c)).is_false()
	assert_bool(M.geofence_breach(Vector3(0.0, c, 0.0), home, r, c)).is_false()


## The ceiling is measured from home, not from sea level. A launch on level 2's mountain would
## otherwise be permanently outside its own fence and fly an RTL it could never satisfy.
func test_the_fence_is_measured_from_home_and_not_from_the_world_origin() -> void:
	var home := Vector3(500.0, 300.0, -500.0)
	assert_bool(M.geofence_breach(home, home, M.GEOFENCE_RADIUS, M.GEOFENCE_CEILING)).is_false()
	assert_bool(M.geofence_breach(home + Vector3(0.0, M.GEOFENCE_CEILING - 1.0, 0.0), home,
			M.GEOFENCE_RADIUS, M.GEOFENCE_CEILING)).is_false()
	assert_bool(M.geofence_breach(home + Vector3(0.0, M.GEOFENCE_CEILING + 1.0, 0.0), home,
			M.GEOFENCE_RADIUS, M.GEOFENCE_CEILING)).is_true()
	# ...and the same craft at the world origin's altitude is far BELOW home, which is not a
	# breach either: the fence has no floor.
	assert_bool(M.geofence_breach(Vector3(500.0, 0.0, -500.0), home,
			M.GEOFENCE_RADIUS, M.GEOFENCE_CEILING)).is_false()


## The bar is scaled to the fence, so the contract's range top IS the radius and the warn has to
## sit in the high half of it or the dashboard reads a distance from home as a LOW-side danger.
func test_home_dist_is_scaled_to_the_geofence() -> void:
	var sig: RefCounted = Contract.data.get_signal_def("home_dist", "out")
	assert_object(sig).is_not_null()
	assert_float(float(sig.range[0])).is_equal(0.0)
	assert_float(float(sig.range[1])) \
		.override_failure_message("home_dist's range top is not the geofence radius") \
		.is_equal(M.GEOFENCE_RADIUS)
	assert_bool(sig.has_warn()).is_true()
	assert_bool(sig.warn_is_low()) \
		.override_failure_message("home_dist's warn fell into the low half of its range") \
		.is_false()
	assert_float(sig.warn).is_less(M.GEOFENCE_RADIUS)


# --- the tilt frame the modes and the manual path share ------------------------

## Today's single-axis form, reproduced here so the generalized level_target_up is checked
## against the ROLE it replaced rather than against itself.
func _legacy_target_up(basis: Basis, tilt: float) -> Vector3:
	var fwd := -basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var right := flat.cross(Vector3.UP).normalized()
	return Vector3.UP.rotated(right, tilt)


func test_a_fore_aft_only_tilt_is_the_manual_path_unchanged() -> void:
	for yaw_deg in [0.0, 37.0, 90.0, -145.0, 180.0]:
		var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
		for tilt in [-MAX_TILT_RAD, -0.2, 0.0, 0.2, MAX_TILT_RAD]:
			assert_vector(D.level_target_up(basis, Vector2(tilt, 0.0))) \
				.override_failure_message("yaw %f, tilt %f" % [yaw_deg, tilt]) \
				.is_equal_approx(_legacy_target_up(basis, tilt), Vector3.ONE * 1e-6)


func test_the_total_lean_is_the_demands_own_length() -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(23.0))
	for tilt in [Vector2(0.3, 0.0), Vector2(0.0, -0.3), Vector2(0.3, 0.4), Vector2(-0.2, 0.2)]:
		var up: Vector3 = D.level_target_up(basis, tilt)
		assert_float(up.length()).is_equal_approx(1.0, 1e-6)
		assert_float(Vector3.UP.angle_to(up)) \
			.override_failure_message("tilt %s leaned %f rad" % [tilt, Vector3.UP.angle_to(up)]) \
			.is_equal_approx(tilt.length(), 1e-6)
	assert_vector(D.level_target_up(basis, Vector2.ZERO)).is_equal(Vector3.UP)


## The lateral half of the convention, which nothing else pins: +y leans the up-vector to
## STARBOARD, so the thrust it carries pushes the craft right. Checked in world terms at a yaw
## where "right" is unambiguous.
func test_a_lateral_tilt_leans_toward_starboard() -> void:
	# Facing world -Z, so the craft's right is world +X.
	var basis := Basis.IDENTITY
	assert_float(D.level_target_up(basis, Vector2(0.0, 0.3)).x).is_greater(0.0)
	assert_float(D.level_target_up(basis, Vector2(0.0, -0.3)).x).is_less(0.0)
	# Yawed 90 degrees left (facing world -X), the same demand pushes toward world -Z.
	var yawed := Basis(Vector3.UP, deg_to_rad(90.0))
	assert_float(D.level_target_up(yawed, Vector2(0.0, 0.3)).z).is_less(0.0)


func test_the_heading_frame_is_orthonormal_and_level() -> void:
	for yaw_deg in [0.0, 45.0, 137.0, -90.0]:
		var frame: Basis = D.heading_frame(Basis(Vector3.UP, deg_to_rad(yaw_deg)))
		assert_vector(frame.y).is_equal_approx(Vector3.UP, Vector3.ONE * 1e-6)
		assert_float(frame.x.y).is_equal_approx(0.0, 1e-6)
		assert_float(frame.z.y).is_equal_approx(0.0, 1e-6)
		assert_float(frame.x.dot(frame.z)).is_equal_approx(0.0, 1e-6)
	# A nose-vertical craft still yields a usable frame rather than a zero vector: the up-axis'
	# own heading takes over, and world up is the last resort.
	var nose_up := Basis(Vector3.RIGHT, deg_to_rad(90.0))
	assert_float(D.heading_frame(nose_up).x.length()).is_equal_approx(1.0, 1e-6)

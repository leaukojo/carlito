extends GdUnitTestSuite
## The boat's autopilot: mode resolution, the wrapped heading error, the PD, and the closed loop
## it makes with the hull. Pins the contract enum against the ladder and BoatAutopilot.cycle
## against InputRouter's own copy — the router carries a second cycle, so both must stay in sync.

const AP := preload("res://src/vehicles/boat/boat_autopilot.gd")
const Router := preload("res://src/input/input_router.gd")
const Counts := preload("res://src/input/subsystem_counts.gd")
const ContractScript := preload("res://src/bridge/contract.gd")

const DELTA := 1.0 / 60.0

## The shipped boat-speed-a, the hull the closed-loop cases below are flown on: 600 kg over a
## probe span of 3.235 x 1.799 m, 6500 N*m of rudder against 3800 N*m per rad/s of yaw damping,
## rudder axis slewing at 2.8 units/s.
const HULL_INERTIA := 685.2
const RUDDER_TORQUE := 6500.0
const DRAG_YAW := 3800.0
const STEER_SPEED := 2.8
const AUTHORITY := 0.6   ## a typical rudder authority at cruise (flow over the blade plus wash)


# --- the ladder ---------------------------------------------------------------

func test_the_ladder_is_the_contract_enum() -> void:
	assert_int(AP.STANDBY).is_equal(0)
	assert_int(AP.HEADING_HOLD).is_equal(1)
	assert_int(AP.COUNT).is_equal(2)
	assert_int(AP.COUNT).is_equal(Counts.NAV_MODES)
	for mode in AP.COUNT:
		assert_bool(AP.is_valid(mode)).is_true()
	for mode in [-1, AP.COUNT, 99, 255]:
		assert_bool(AP.is_valid(mode)).is_false()


## The router must not learn a vehicle class, so it carries its own copy of the walk. Grow one
## without the other and the local key silently stops reaching the new position while the bridge
## can still command it.
func test_cycle_matches_the_routers_own_copy() -> void:
	assert_int(Router.NAV_MODE_COUNT) \
		.override_failure_message("InputRouter.NAV_MODE_COUNT has not followed BoatAutopilot.COUNT") \
		.is_equal(AP.COUNT)
	for mode in AP.COUNT:
		assert_int(AP.cycle(mode)) \
			.override_failure_message("BoatAutopilot.cycle and InputRouter.cycle_nav_mode disagree at %d" % mode) \
			.is_equal(Router.cycle_nav_mode(mode))
	# The walk closes, and a negative starting mode still lands inside the ladder.
	assert_int(AP.cycle(AP.STANDBY)).is_equal(AP.HEADING_HOLD)
	assert_int(AP.cycle(AP.HEADING_HOLD)).is_equal(AP.STANDBY)
	assert_int(AP.cycle(-1)).is_between(0, AP.COUNT - 1)


# --- resolve_mode -------------------------------------------------------------

func test_an_out_of_range_request_lands_on_standby() -> void:
	# A peer describing a pilot with more modes than this one is describing a different pilot.
	for mode in [-1, AP.COUNT, 99, 255]:
		assert_int(AP.resolve_mode(mode, 0.0)).is_equal(AP.STANDBY)


func test_a_hand_on_the_helm_outranks_the_request() -> void:
	assert_int(AP.resolve_mode(AP.HEADING_HOLD, 0.0)).is_equal(AP.HEADING_HOLD)
	# Rest slop does not knock the pilot out; a deliberate nudge does, either way.
	assert_int(AP.resolve_mode(AP.HEADING_HOLD, AP.HELM_DEADBAND)).is_equal(AP.HEADING_HOLD)
	assert_int(AP.resolve_mode(AP.HEADING_HOLD, 0.4)).is_equal(AP.STANDBY)
	assert_int(AP.resolve_mode(AP.HEADING_HOLD, -0.4)).is_equal(AP.STANDBY)
	# Not latched: it is the same call every tick, so releasing the helm re-engages.
	assert_int(AP.resolve_mode(AP.HEADING_HOLD, 0.0)).is_equal(AP.HEADING_HOLD)


# --- heading_error ------------------------------------------------------------

func test_heading_error_is_zero_on_the_course() -> void:
	assert_float(AP.heading_error(90.0, 90.0)).is_equal_approx(0.0, 1e-6)
	assert_float(AP.heading_error(0.0, 360.0)).is_equal_approx(0.0, 1e-6)


func test_heading_error_is_positive_to_starboard() -> void:
	assert_float(AP.heading_error(100.0, 90.0)).is_equal_approx(10.0, 1e-6)
	assert_float(AP.heading_error(80.0, 90.0)).is_equal_approx(-10.0, 1e-6)


## The wrap is the whole reason this is a function: 359 -> 1 is two degrees to starboard, not 358
## to port, and a pilot that took the long way round would spin the boat at the north mark.
func test_heading_error_takes_the_short_way_round_the_compass() -> void:
	assert_float(AP.heading_error(1.0, 359.0)).is_equal_approx(2.0, 1e-6)
	assert_float(AP.heading_error(359.0, 1.0)).is_equal_approx(-2.0, 1e-6)
	# Dead astern is a legal error and lands on one end of the range rather than wrapping to zero.
	assert_float(absf(AP.heading_error(270.0, 90.0))).is_equal_approx(180.0, 1e-6)
	for pair in [[0.0, 90.0], [10.0, 350.0], [200.0, 20.0], [123.0, 45.0]]:
		var e: float = AP.heading_error(pair[0], pair[1])
		assert_float(e).is_between(-180.0, 180.0)


# --- turn_rate_deg ------------------------------------------------------------

## The sign convention, stated once here and once in the module: a positive yaw rate about the
## body up axis swings the bow to PORT, so the compass rate is its negative. Getting this backwards
## turns the damping term into positive feedback, which is silent until the boat oscillates.
func test_a_positive_yaw_rate_is_a_swing_to_port() -> void:
	assert_float(AP.turn_rate_deg(1.0)).is_equal_approx(-rad_to_deg(1.0), 1e-6)
	assert_float(AP.turn_rate_deg(0.0)).is_equal(0.0)


# --- autopilot_rudder ---------------------------------------------------------

func test_the_rudder_goes_the_way_the_error_points() -> void:
	assert_float(AP.autopilot_rudder(10.0, 0.0, AP.KP, AP.KD)).is_greater(0.0)
	assert_float(AP.autopilot_rudder(-10.0, 0.0, AP.KP, AP.KD)).is_less(0.0)
	assert_float(AP.autopilot_rudder(0.0, 0.0, AP.KP, AP.KD)).is_equal(0.0)


func test_the_derivative_term_opposes_the_swing() -> void:
	# On course but swinging to starboard: the pilot steers back to port to stop the swing.
	assert_float(AP.autopilot_rudder(0.0, 10.0, AP.KP, AP.KD)).is_less(0.0)
	# Approaching the course from port, the swing takes rudder OFF before the error reaches zero.
	var undamped := AP.autopilot_rudder(10.0, 0.0, AP.KP, AP.KD)
	assert_float(AP.autopilot_rudder(10.0, 5.0, AP.KP, AP.KD)).is_less(undamped)


func test_the_rudder_saturates_rather_than_running_past_the_stops() -> void:
	assert_float(AP.autopilot_rudder(179.0, 0.0, AP.KP, AP.KD)).is_equal(1.0)
	assert_float(AP.autopilot_rudder(-179.0, 0.0, AP.KP, AP.KD)).is_equal(-1.0)
	assert_float(AP.autopilot_rudder(0.0, -999.0, AP.KP, AP.KD)).is_equal(1.0)


# --- the closed loop ----------------------------------------------------------

## The gains are derived against the shipped hulls' own numbers (see the module header), and this
## is what that derivation claims: from a big error the pilot converges and does not ring. Run at
## 60 Hz per standing rule 9, through the same rudder slew the hand goes through.
func test_the_loop_converges_from_a_large_error_without_limit_cycling() -> void:
	var run := _fly(60.0, 20.0)
	assert_float(absf(run["error"])) \
		.override_failure_message("20 s was not enough to settle a 60 degree turn") \
		.is_less(1.0)
	# An overdamped loop crosses the course once at most; a ringing one crosses over and over.
	assert_int(run["crossings"]) \
		.override_failure_message("the rudder is limit-cycling: %d overshoots" % run["crossings"]) \
		.is_less_equal(1)


func test_the_loop_holds_across_the_north_wrap() -> void:
	# Target 002, boat on 358: two degrees to starboard, not 356 to port. A pilot that took the
	# long way round would be at full rudder here for several seconds.
	var run := _fly(-4.0, 10.0, 358.0)
	assert_float(absf(run["error"])).is_less(1.0)
	assert_float(run["peak_rudder"]) \
		.override_failure_message("full rudder for a 4 degree error means the wrap was missed") \
		.is_less(0.9)


func test_a_settled_pilot_leaves_the_rudder_near_amidships() -> void:
	var run := _fly(0.0, 5.0)
	assert_float(absf(run["rudder"])).is_less(0.02)


## One hull, one pilot, `seconds` of 60 Hz. `error_deg` is how far off the course it starts.
## The plant is BoatVehicle's own yaw model — rudder torque against `drag_yaw` over the hull's
## inertia — and the rudder rides the same move_toward slew BaseVehicle gives the helm.
##
## The yaw damper is written here WITHOUT `VehicleMath.damped_force`'s one-tick clamp, and that is
## exact rather than a simplification: the clamp binds when `drag_yaw > inertia / delta`, which the
## yaw rate cancels out of, and every shipped hull clears that threshold by 11-13x (see
## boat_autopilot.gd's header). Take a hull past it and this plant stops being the shipped one.
func _fly(error_deg: float, seconds: float, target := 90.0) -> Dictionary:
	var heading := fposmod(target - error_deg, 360.0)
	var yaw_rate := 0.0   ## rad/s about the body up axis (positive swings the bow to port)
	var rudder := 0.0
	var crossings := 0
	var peak := 0.0
	var prev_error := AP.heading_error(target, heading)
	for _i in int(seconds / DELTA):
		var err := AP.heading_error(target, heading)
		if signf(err) != signf(prev_error) and absf(prev_error) > 0.1:
			crossings += 1
		prev_error = err
		var demand := AP.autopilot_rudder(err, AP.turn_rate_deg(yaw_rate), AP.KP, AP.KD)
		rudder = move_toward(rudder, demand, STEER_SPEED * DELTA)
		peak = maxf(peak, absf(rudder))
		# boat.gd: apply_torque(up * -_steer * rudder_torque * authority), damped by drag_yaw.
		var torque := -rudder * RUDDER_TORQUE * AUTHORITY - DRAG_YAW * yaw_rate
		yaw_rate += torque / HULL_INERTIA * DELTA
		heading = fposmod(heading + AP.turn_rate_deg(yaw_rate) * DELTA, 360.0)
	return {
		"error": AP.heading_error(target, heading), "rudder": rudder,
		"crossings": crossings, "peak_rudder": peak,
	}


# --- the contract -------------------------------------------------------------

## The enum ordinals are the wire, so the ladder and the contract cannot be allowed to drift.
func test_the_contract_enum_matches_the_ladder() -> void:
	var data := ContractScript.ContractData.parse(
			FileAccess.open(ContractScript.CONTRACT_PATH, FileAccess.READ).get_as_text())
	assert_array(data.errors).is_empty()
	for entry: Array in [["nav_mode", "in"], ["nav_mode_actual", "out"]]:
		var sig := data.get_signal_def(entry[0], entry[1])
		assert_object(sig).override_failure_message("missing %s/%s" % entry).is_not_null()
		assert_str(sig.enum_label(AP.STANDBY)) \
			.override_failure_message("%s/%s: 0 is not STANDBY" % entry).is_equal("STANDBY")
		assert_str(sig.enum_label(AP.HEADING_HOLD)) \
			.override_failure_message("%s/%s: 1 is not HEADING HOLD" % entry).is_equal("HEADING HOLD")

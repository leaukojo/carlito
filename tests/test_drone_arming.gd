extends GdUnitTestSuite
## Drone arming: state machine, pre-arm checks, failsafes. Three pins tie this to
## external rules: contract enum tables, the seven pre-arm bits (PA_ALL), and the
## failsafe ladder's mode mapping. Cases exhaustively test bitfield combinations.

const A := preload("res://src/vehicles/drone/drone_arming.gd")
const M := preload("res://src/vehicles/drone/drone_modes.gd")
const B := preload("res://src/vehicles/drone/drone_bus.gd")

const DELTA := 1.0 / 60.0


## A snapshot of an aircraft that passes EVERY check: level, charged, whole bus, stick centred,
## nothing forced, and a 3D fix in hand. Every case below starts here and breaks exactly one
## thing, which is what makes the bit it sets attributable.
func _ok() -> A.Snapshot:
	var s := A.Snapshot.new()
	s.pitch = 0.0
	s.roll = 0.0
	s.soc = 100.0
	s.node_fail = 0
	s.ahrs_node = B.index_of("AHRS")
	s.climb = 0.0
	s.pos_fix = true
	s.mode_want = M.STABILIZE
	s.fence_rtl = false
	s.failsafe = A.FS_NONE
	return s


## The roster bit for a node, by NAME — so a reordered roster moves the test with it rather than
## silently testing the wrong node (the whole reason DroneBus.index_of exists).
func _bit(node_name: String) -> int:
	return 1 << B.index_of(node_name)


# --- the two enums, and the three places they are written down ------------------

func test_the_arming_ordinals_are_dense_and_ordered() -> void:
	assert_int(A.DISARMED).is_equal(0)
	assert_int(A.BLOCKED).is_equal(1)
	assert_int(A.ARMED).is_equal(2)


func test_the_failsafe_ordinals_are_the_wire_enum() -> void:
	assert_int(A.FS_NONE).is_equal(0)
	assert_int(A.FS_BATT_LOW).is_equal(1)
	assert_int(A.FS_BATT_CRIT).is_equal(2)
	assert_int(A.FS_GPS_LOST).is_equal(3)
	assert_int(A.FS_GEOFENCE).is_equal(4)
	assert_int(A.FS_MOTOR).is_equal(5)


## Contract tables must not carry a range (would create a meaningless bar UI).
func test_the_contract_enum_tables_match_the_enums() -> void:
	var arming: RefCounted = Contract.data.get_signal_def("arming_state", "out")
	var fs: RefCounted = Contract.data.get_signal_def("failsafe", "out")
	assert_object(arming).is_not_null()
	assert_object(fs).is_not_null()
	var arm_labels := ["DISARMED", "BLOCKED", "ARMED"]
	for i in arm_labels.size():
		assert_str(arming.enum_label(i)) \
			.override_failure_message("arming_state label for %d" % i) \
			.is_equal(arm_labels[i])
	var fs_labels := ["NONE", "BATT LOW", "BATT CRIT", "GPS LOST", "GEOFENCE", "MOTOR"]
	for i in fs_labels.size():
		assert_str(fs.enum_label(i)) \
			.override_failure_message("failsafe label for %d" % i) \
			.is_equal(fs_labels[i])
	assert_int(arming.range.size()).is_equal(0)
	assert_int(fs.range.size()).is_equal(0)
	assert_str(arming.flavor).is_equal("dronecan")
	assert_str(fs.flavor).is_equal("dronecan")


## `prearm_fail` is a u16 bitfield (not an enum, not a range; bitwise combinations).
func test_prearm_fail_is_a_plain_bitfield_on_the_bus() -> void:
	var sig: RefCounted = Contract.data.get_signal_def("prearm_fail", "out")
	assert_object(sig).is_not_null()
	assert_str(sig.type).is_equal("u16")
	assert_int(sig.range.size()).is_equal(0)
	assert_bool(sig.has_enum()).is_false()
	# ...and every bit this airframe can set has to fit in that u16.
	assert_int(A.PA_ALL).is_less_equal(0xFFFF)


## Low-battery threshold and soc bar's warn are tied: JSON cannot read GDScript.
func test_the_low_battery_threshold_is_the_soc_bar_warn() -> void:
	var soc: RefCounted = Contract.data.get_signal_def("soc", "out")
	assert_object(soc).is_not_null()
	assert_bool(soc.has_warn()).is_true()
	assert_float(soc.warn).is_equal_approx(A.SOC_LOW, 0.001)
	# Battery thresholds ordered: ARM_SOC_MIN > SOC_LOW > SOC_CRIT.
	assert_bool(A.ARM_SOC_MIN > A.SOC_LOW).is_true()
	assert_bool(A.SOC_CRIT < A.SOC_LOW).is_true()


func test_every_prearm_bit_is_distinct_and_listed_in_pa_all() -> void:
	var bits := [A.PA_ATTITUDE, A.PA_BATTERY, A.PA_ESC, A.PA_AHRS, A.PA_STICK, A.PA_FAILSAFE,
			A.PA_GPS]
	var seen := 0
	for b in bits:
		# One bit each, and no two the same — a doubled bit makes two checks indistinguishable.
		assert_int(b & (b - 1)).override_failure_message("bit %d is not a single bit" % b).is_equal(0)
		assert_int(seen & b).override_failure_message("bit %d is already taken" % b).is_equal(0)
		seen |= b
	assert_int(seen).override_failure_message("PA_ALL has not followed a new check bit").is_equal(A.PA_ALL)


# --- the pre-arm checks, one at a time ------------------------------------------

func test_a_clean_aircraft_fails_nothing() -> void:
	assert_int(A.prearm_fail(_ok())).is_equal(0)


func test_attitude_refuses_past_the_limit_on_either_axis_and_either_sign() -> void:
	for axis in ["pitch", "roll"]:
		for sign_of in [1.0, -1.0]:
			var s := _ok()
			s.set(axis, sign_of * (A.ARM_TILT_DEG + 0.1))
			assert_int(A.prearm_fail(s)) \
				.override_failure_message("%s at %f should refuse" % [axis, s.get(axis)]) \
				.is_equal(A.PA_ATTITUDE)
			# ...and AT the limit it passes: the check is "past", not "at".
			var ok := _ok()
			ok.set(axis, sign_of * A.ARM_TILT_DEG)
			assert_int(A.prearm_fail(ok)) \
				.override_failure_message("%s exactly at the limit should pass" % axis) \
				.is_equal(0)


func test_a_flat_pack_refuses_and_a_full_one_does_not() -> void:
	var s := _ok()
	s.soc = A.ARM_SOC_MIN - 0.1
	# Under ARM_SOC_MIN (but above SOC_LOW), tests the gap between thresholds.
	assert_int(A.prearm_fail(s)).is_equal(A.PA_BATTERY)
	s.soc = A.ARM_SOC_MIN
	assert_int(A.prearm_fail(s)).is_equal(0)


func test_any_offline_esc_refuses_and_so_does_the_ahrs() -> void:
	for name_of in ["ESC1", "ESC2", "ESC3", "ESC4"]:
		var s := _ok()
		s.node_fail = _bit(name_of)
		# Offline ESC: both ESC and MOTOR failsafe bits set (see drone_arming.gd).
		s.failsafe = A.failsafe_of(s)
		assert_int(A.prearm_fail(s)) \
			.override_failure_message("%s offline" % name_of) \
			.is_equal(A.PA_ESC | A.PA_FAILSAFE)
	var ahrs := _ok()
	ahrs.node_fail = _bit("AHRS")
	# AHRS: no motor, no failsafe, standalone bit.
	ahrs.failsafe = A.failsafe_of(ahrs)
	assert_int(A.prearm_fail(ahrs)).is_equal(A.PA_AHRS)


## Non-AHRS sensors have no pre-arm check; GNSS reaches arming via mode-gated fix check.
func test_the_other_sensor_nodes_do_not_block_a_stabilize_takeoff() -> void:
	for name_of in ["GNSS", "POWER", "RANGE"]:
		var s := _ok()
		s.node_fail = _bit(name_of)
		s.failsafe = A.failsafe_of(s)
		assert_int(A.prearm_fail(s)) \
			.override_failure_message("%s offline blocked a STABILIZE takeoff" % name_of) \
			.is_equal(0)


func test_a_deflected_climb_stick_refuses() -> void:
	for stick in [1.0, -1.0, M.STICK_DEADBAND + 0.01, -(M.STICK_DEADBAND + 0.01)]:
		var s := _ok()
		s.climb = stick
		assert_int(A.prearm_fail(s)) \
			.override_failure_message("climb %f should refuse" % stick) \
			.is_equal(A.PA_STICK)
	# Inside deadband is centred, same as flight modes use.
	var ok := _ok()
	ok.climb = M.STICK_DEADBAND
	assert_int(A.prearm_fail(ok)).is_equal(0)


## GPS check is mode-gated: STABILIZE/ALT_HOLD don't need fix; LOITER/RTL do.
func test_the_gps_check_only_applies_to_the_modes_that_need_a_fix() -> void:
	for mode in M.COUNT:
		var s := _ok()
		s.pos_fix = false
		s.mode_want = mode
		s.failsafe = A.failsafe_of(s)
		var want := 0
		if M.needs_pos_fix(mode):
			want |= A.PA_GPS
		if M.uses_pos_fix(mode):
			want |= A.PA_FAILSAFE
		assert_int(A.prearm_fail(s)) \
			.override_failure_message("mode %d with no fix" % mode) \
			.is_equal(want)
	for mode in M.COUNT:
		var s := _ok()
		s.mode_want = mode
		s.failsafe = A.failsafe_of(s)
		assert_int(A.prearm_fail(s)) \
			.override_failure_message("mode %d with a fix" % mode) \
			.is_equal(0)


func test_an_active_failsafe_is_its_own_refusal() -> void:
	for fs in [A.FS_BATT_LOW, A.FS_BATT_CRIT, A.FS_GPS_LOST, A.FS_GEOFENCE, A.FS_MOTOR]:
		var s := _ok()
		s.failsafe = fs
		assert_int(A.prearm_fail(s)) \
			.override_failure_message("failsafe %d" % fs) \
			.is_equal(A.PA_FAILSAFE)


## All checks failing at once must set every bit (tests for early return vs |=).
func test_every_check_failing_at_once_sets_every_bit() -> void:
	var s := _ok()
	s.pitch = 45.0
	s.roll = -45.0
	s.soc = 0.0
	s.node_fail = B.roster_mask()
	s.climb = 1.0
	s.pos_fix = false
	s.mode_want = M.LOITER
	s.failsafe = A.failsafe_of(s)
	assert_int(A.prearm_fail(s)).is_equal(A.PA_ALL)


# --- the failsafe priority ------------------------------------------------------

func test_each_failsafe_alone() -> void:
	var motor := _ok()
	motor.node_fail = _bit("ESC3")
	assert_int(A.failsafe_of(motor)).is_equal(A.FS_MOTOR)

	var crit := _ok()
	crit.soc = A.SOC_CRIT - 0.1
	assert_int(A.failsafe_of(crit)).is_equal(A.FS_BATT_CRIT)

	var low := _ok()
	low.soc = A.SOC_LOW - 0.1
	assert_int(A.failsafe_of(low)).is_equal(A.FS_BATT_LOW)

	var fence := _ok()
	fence.fence_rtl = true
	assert_int(A.failsafe_of(fence)).is_equal(A.FS_GEOFENCE)

	var gps := _ok()
	gps.pos_fix = false
	gps.mode_want = M.LOITER
	assert_int(A.failsafe_of(gps)).is_equal(A.FS_GPS_LOST)

	assert_int(A.failsafe_of(_ok())).is_equal(A.FS_NONE)


## Thresholds are "below" not "at-or-below" (at-the-line is not yet a failsafe).
func test_the_battery_thresholds_are_strict() -> void:
	var s := _ok()
	s.soc = A.SOC_LOW
	assert_int(A.failsafe_of(s)).is_equal(A.FS_NONE)
	s.soc = A.SOC_CRIT
	assert_int(A.failsafe_of(s)).is_equal(A.FS_BATT_LOW)


## Severity by action forced, not ordinal. Tested by enabling all and disabling top-down.
func test_the_most_severe_condition_wins() -> void:
	var s := _ok()
	s.node_fail = _bit("ESC1")
	s.soc = 0.0
	s.fence_rtl = true
	s.pos_fix = false
	s.mode_want = M.LOITER
	assert_int(A.failsafe_of(s)).is_equal(A.FS_MOTOR)
	s.node_fail = 0
	assert_int(A.failsafe_of(s)).is_equal(A.FS_BATT_CRIT)
	s.soc = A.SOC_LOW - 0.1
	assert_int(A.failsafe_of(s)).is_equal(A.FS_BATT_LOW)
	s.soc = 100.0
	assert_int(A.failsafe_of(s)).is_equal(A.FS_GEOFENCE)
	s.fence_rtl = false
	assert_int(A.failsafe_of(s)).is_equal(A.FS_GPS_LOST)
	s.pos_fix = true
	assert_int(A.failsafe_of(s)).is_equal(A.FS_NONE)


## Landing without receiver: degrades to GPS_LOST (LAND not refused by pre-arm).
func test_a_drifting_land_raises_gps_lost() -> void:
	var s := _ok()
	s.pos_fix = false
	s.mode_want = M.LAND
	assert_int(A.failsafe_of(s)).is_equal(A.FS_GPS_LOST)
	# STABILIZE/ALT_HOLD don't use a fix.
	for mode in [M.STABILIZE, M.ALT_HOLD]:
		var q := _ok()
		q.pos_fix = false
		q.mode_want = mode
		assert_int(A.failsafe_of(q)) \
			.override_failure_message("mode %d without a fix" % mode) \
			.is_equal(A.FS_NONE)


# --- what a failsafe forces, and how it reaches mode_actual ---------------------

func test_each_failsafe_forces_the_documented_mode() -> void:
	assert_int(A.failsafe_mode(A.FS_MOTOR)).is_equal(M.LAND)
	assert_int(A.failsafe_mode(A.FS_BATT_CRIT)).is_equal(M.LAND)
	assert_int(A.failsafe_mode(A.FS_BATT_LOW)).is_equal(M.RTL)
	# GEOFENCE and GPS_LOST force nothing (action already in resolve_mode).
	assert_int(A.failsafe_mode(A.FS_GEOFENCE)).is_equal(-1)
	assert_int(A.failsafe_mode(A.FS_GPS_LOST)).is_equal(-1)
	assert_int(A.failsafe_mode(A.FS_NONE)).is_equal(-1)


func test_a_low_pack_flies_the_craft_home_over_the_top_of_the_pilot() -> void:
	for requested in [M.STABILIZE, M.ALT_HOLD, M.LOITER]:
		assert_int(M.resolve_mode(requested, true, false, true, false,
				A.failsafe_mode(A.FS_BATT_LOW))) \
			.override_failure_message("BATT_LOW over request %d" % requested) \
			.is_equal(M.RTL)


func test_a_critical_pack_and_a_dead_motor_both_land_it() -> void:
	for fs in [A.FS_BATT_CRIT, A.FS_MOTOR]:
		for requested in M.COUNT:
			assert_int(M.resolve_mode(requested, true, false, true, false, A.failsafe_mode(fs))) \
				.override_failure_message("failsafe %d over request %d" % [fs, requested]) \
				.is_equal(M.LAND)


## Forced mode may only escalate (won't interrupt landing).
func test_an_rtl_failsafe_cannot_interrupt_a_landing() -> void:
	assert_int(M.resolve_mode(M.LAND, true, false, true, false, A.failsafe_mode(A.FS_BATT_LOW))) \
		.is_equal(M.LAND)


## Forced mode still falls back if the pre-arm check it requires fails.
func test_a_forced_rtl_with_no_fix_still_falls_back_to_alt_hold() -> void:
	assert_int(M.resolve_mode(M.STABILIZE, false, false, true, false,
			A.failsafe_mode(A.FS_BATT_LOW))).is_equal(M.ALT_HOLD)
	assert_int(M.resolve_mode(M.STABILIZE, false, false, true, false,
			A.failsafe_mode(A.FS_BATT_CRIT))).is_equal(M.LAND)


## Nothing autonomous runs on stopped motors, forced or not.
func test_a_disarmed_craft_ignores_a_forced_mode() -> void:
	for fs in [A.FS_BATT_LOW, A.FS_BATT_CRIT, A.FS_MOTOR]:
		assert_int(M.resolve_mode(M.LOITER, true, false, false, false, A.failsafe_mode(fs))) \
			.override_failure_message("disarmed with failsafe %d" % fs) \
			.is_equal(M.STABILIZE)


## Out-of-range forced mode is ignored (same tolerance as out-of-range request).
func test_an_invalid_forced_mode_changes_nothing() -> void:
	for forced in [-1, -9, M.COUNT, 99]:
		assert_int(M.resolve_mode(M.ALT_HOLD, true, false, true, false, forced)) \
			.override_failure_message("forced %d" % forced) \
			.is_equal(M.ALT_HOLD)


# --- the arming state machine ---------------------------------------------------

func test_the_key_gates_everything() -> void:
	# Unpowered, nothing arms.
	assert_bool(A.arm_step(false, true, false, false, 0, true, false)).is_false()
	# Armed FLYING craft is cut instantly when power goes.
	assert_bool(A.arm_step(true, true, true, false, 0, false, false)).is_false()


func test_arming_needs_a_rising_edge_with_every_check_passing() -> void:
	# Rising edge arms.
	assert_bool(A.arm_step(false, true, false, true, 0, true, false)).is_true()
	# Same edge with failed check: refused.
	assert_bool(A.arm_step(false, true, false, true, A.PA_ATTITUDE, true, false)).is_false()
	# Switch already up is not an edge (prevents auto-disarm re-arming on next tick).
	assert_bool(A.arm_step(false, true, true, true, 0, true, false)).is_false()
	# Switch down asks for nothing.
	assert_bool(A.arm_step(false, false, false, true, 0, true, false)).is_false()


func test_a_disarm_is_refused_in_flight_and_granted_on_the_ground() -> void:
	# Airborne with switch down: motors keep running.
	assert_bool(A.arm_step(true, false, true, true, 0, false, false)).is_true()
	# Lands and settles: disarms.
	assert_bool(A.arm_step(true, false, true, true, 0, true, false)).is_false()
	# Switch UP on ground: stays armed (landing is not a disarm).
	assert_bool(A.arm_step(true, true, true, true, 0, true, false)).is_true()


## Failed check does not disarm flying aircraft (gates transition, not state).
func test_a_failed_check_in_flight_does_not_disarm() -> void:
	assert_bool(A.arm_step(true, true, true, true, A.PA_ALL, false, false)).is_true()


func test_the_post_landing_timer_measures_a_standing_state() -> void:
	var hold := 0.0
	for _i in 10:
		hold = A.disarm_hold_step(hold, true, true, DELTA)
	assert_float(hold).is_equal_approx(10.0 * DELTA, 1e-6)
	# Lifting off zeroes it (standing state, not cumulative).
	assert_float(A.disarm_hold_step(hold, true, false, DELTA)).is_equal(0.0)
	# Disarming zeroes it too.
	assert_float(A.disarm_hold_step(hold, false, true, DELTA)).is_equal(0.0)
	# Negative delta does not wind it backwards (landing-hold rule).
	assert_float(A.disarm_hold_step(1.0, true, true, -5.0)).is_equal(1.0)


func test_the_craft_disarms_itself_a_few_seconds_after_landing() -> void:
	var armed := true
	var hold := 0.0
	var ticks := 0
	# Auto-disarm (switch stays UP, pilot doesn't move it).
	while armed and ticks < 600:
		hold = A.disarm_hold_step(hold, armed, true, DELTA)
		armed = A.arm_step(armed, true, true, true, 0, true, A.auto_disarm_due(hold))
		ticks += 1
	assert_bool(armed).is_false()
	assert_float(float(ticks) * DELTA).is_equal_approx(A.AUTO_DISARM_S, 2.0 * DELTA)
	# Stays disarmed (arming needs rising edge).
	for _i in 60:
		armed = A.arm_step(armed, true, true, true, 0, true, false)
	assert_bool(armed).is_false()
	assert_bool(A.arm_step(false, true, false, true, 0, true, false)).is_true()


## Auto-disarm never fires in-flight (timer only runs while landed).
func test_the_auto_disarm_cannot_fire_in_the_air() -> void:
	var armed := true
	var hold := 0.0
	for _i in 1200:
		hold = A.disarm_hold_step(hold, armed, false, DELTA)
		armed = A.arm_step(armed, true, true, true, 0, false, A.auto_disarm_due(hold))
	assert_bool(armed).is_true()
	assert_float(hold).is_equal(0.0)


# --- what the bus sees ----------------------------------------------------------

func test_the_arming_state_reads_the_difference_between_nobody_asking_and_a_refusal() -> void:
	assert_int(A.state_of(true, true, true, 0)).is_equal(A.ARMED)
	# Flying aircraft is ARMED, even with live check bits set.
	assert_int(A.state_of(true, false, true, A.PA_ALL)).is_equal(A.ARMED)
	# Asked and refused (BLOCKED).
	assert_int(A.state_of(false, true, true, A.PA_BATTERY)).is_equal(A.BLOCKED)
	assert_int(A.state_of(false, false, true, A.PA_BATTERY)).is_equal(A.DISARMED)
	# Asked, nothing wrong (waiting on switch edge).
	assert_int(A.state_of(false, true, true, 0)).is_equal(A.DISARMED)
	# Unpowered is never BLOCKED (no FC judgment).
	assert_int(A.state_of(false, true, false, A.PA_ALL)).is_equal(A.DISARMED)


## Published checks go dark in-flight (else a leaning aircraft lights bits through maneuvers).
func test_the_published_checks_go_dark_in_flight() -> void:
	assert_int(A.published_fail(false, A.PA_ATTITUDE | A.PA_STICK)) \
		.is_equal(A.PA_ATTITUDE | A.PA_STICK)
	assert_int(A.published_fail(true, A.PA_ATTITUDE | A.PA_STICK)).is_equal(0)

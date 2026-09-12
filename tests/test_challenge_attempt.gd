extends GdUnitTestSuite
## ChallengeAttempt: the ordered goals, the constraints judged first, the par, and the resets —
## the respawn mid-attempt included.

const S := ChallengeCheck.Status
const DT := 1.0 / 60.0

const AT_A := Vector3(0, 0, 0)
const AT_B := Vector3(0, 0, -20)
const IN_PIT := Vector3(0, -10, 0)
const NOWHERE := Vector3(50, 0, 50)


func _zones() -> Dictionary[StringName, ZoneShape]:
	return {
		&"A": ZoneShape.box(Transform3D(Basis.IDENTITY, AT_A), Vector3(2, 2, 2)),
		&"B": ZoneShape.box(Transform3D(Basis.IDENTITY, AT_B), Vector3(2, 2, 2)),
		&"Pit": ZoneShape.box(Transform3D(Basis.IDENTITY, IN_PIT), Vector3(100, 4, 100)),
		&"Ring": ZoneShape.ring(Transform3D(Basis.IDENTITY, Vector3(0, 0, 100)), 10.0, 20.0),
	}


func _reach(zone: StringName) -> ReachZoneGoal:
	var g := ReachZoneGoal.new()
	g.zone = zone
	return g


func _def(goals: Array[ChallengeGoal], constraints: Array[ChallengeConstraint] = [],
		par_s := 0.0) -> ChallengeDef:
	var d := ChallengeDef.new()
	d.id = "test"
	d.goals = goals
	d.constraints = constraints
	d.par_s = par_s
	return d


func _frame(pos: Vector3, signals := {}) -> ChallengeFrame:
	var f := ChallengeFrame.new()
	f.pose = Transform3D(Basis.IDENTITY, pos)
	f.signals = signals
	return f


func _on_ring(deg: float) -> ChallengeFrame:
	var a := deg_to_rad(deg)
	return _frame(Vector3(15.0 * cos(a), 0, 100.0 + 15.0 * sin(a)))


func _sweep(attempt: ChallengeAttempt, from_deg: int, to_deg: int) -> int:
	var s := S.RUNNING
	for deg in range(from_deg, to_deg + 1):
		s = attempt.step(_on_ring(deg), DT)
		if s != S.RUNNING:
			return s
	return s


func test_goals_run_in_order() -> void:
	var a := ChallengeAttempt.new(_def([_reach(&"A"), _reach(&"B")]), _zones())
	assert_array(a.problems).is_empty()
	assert_int(a.step(_frame(AT_B), DT)).is_equal(S.RUNNING)
	assert_int(a.goal_index).is_equal(0)
	assert_int(a.step(_frame(AT_A), DT)).is_equal(S.RUNNING)
	assert_int(a.goal_index).is_equal(1)
	assert_int(a.step(_frame(AT_B), DT)).is_equal(S.PASS)
	assert_int(a.goal_index).is_equal(a.goal_count())
	assert_object(a.current_goal()).is_null()


func test_a_finished_attempt_keeps_its_result_and_stops_the_clock() -> void:
	var a := ChallengeAttempt.new(_def([_reach(&"A")]), _zones())
	a.step(_frame(NOWHERE), DT)
	assert_int(a.step(_frame(AT_A), DT)).is_equal(S.PASS)
	var t := a.elapsed
	assert_int(a.step(_frame(NOWHERE), DT)).is_equal(S.PASS)
	assert_float(a.elapsed).is_equal(t)


## A pass needs every constraint to hold through the tick it happens on.
func test_a_constraint_breaking_on_the_passing_tick_fails() -> void:
	var limit := SignalLimitConstraint.new()
	limit.signal_name = "accLat"
	limit.high = 4.0
	limit.absolute = true
	var a := ChallengeAttempt.new(_def([_reach(&"A")], [limit]), _zones())
	assert_int(a.step(_frame(AT_A, {"accLat": 5.0}), DT)).is_equal(S.FAIL)
	assert_str(a.message).contains("accLat")


## A 1 s par allows exactly 60 ticks, though 60 x (1/60) sums a hair over 1.0.
func test_over_par_fails_on_the_tick_after_par() -> void:
	var a := ChallengeAttempt.new(_def([_reach(&"B")], [], 1.0), _zones())
	for _i in 60:
		assert_int(a.step(_frame(NOWHERE), DT)).is_equal(S.RUNNING)
	assert_int(a.step(_frame(NOWHERE), DT)).is_equal(S.FAIL)
	assert_str(a.message).contains("par")


func test_a_goal_met_on_the_par_tick_passes() -> void:
	var a := ChallengeAttempt.new(_def([_reach(&"B")], [], 3.0), _zones())
	for _i in 179:
		a.step(_frame(NOWHERE), DT)
	assert_int(a.step(_frame(AT_B), DT)).is_equal(S.PASS)


## Boat 1's shape: goal 0 engages HEADING HOLD, and only from then on is leaving it a failure.
func test_a_constraint_is_judged_from_its_goal_on() -> void:
	var engage := SignalReachGoal.new()
	engage.signal_name = "nav_mode_actual"
	engage.low = 1.0
	engage.high = 1.0
	var hold := ForbiddenValueConstraint.new()
	hold.signal_name = "nav_mode_actual"
	hold.values = PackedInt32Array([0])
	hold.from_goal = 1
	var a := ChallengeAttempt.new(_def([engage, _reach(&"B")], [hold]), _zones())
	assert_int(a.step(_frame(NOWHERE, {"nav_mode_actual": 0}), DT)).is_equal(S.RUNNING)
	assert_int(a.step(_frame(NOWHERE, {"nav_mode_actual": 1}), DT)).is_equal(S.RUNNING)
	assert_int(a.goal_index).is_equal(1)
	assert_int(a.step(_frame(NOWHERE, {"nav_mode_actual": 0}), DT)).is_equal(S.FAIL)


func test_a_fail_zone_resets_the_attempt_with_its_warning() -> void:
	var pit := FailZoneConstraint.new()
	pit.zone = &"Pit"
	pit.warning = "Into the pit"
	var a := ChallengeAttempt.new(_def([_reach(&"A"), _reach(&"B")], [pit]), _zones())
	a.step(_frame(AT_A), DT)
	a.step(_frame(NOWHERE), DT)
	assert_int(a.goal_index).is_equal(1)
	assert_int(a.step(_frame(IN_PIT), DT)).is_equal(S.RESET)
	assert_str(a.message).is_equal("Into the pit")
	assert_int(a.goal_index).is_equal(0)
	assert_float(a.elapsed).is_equal(0.0)
	assert_int(a.status).is_equal(S.RUNNING)
	# B alone no longer passes: A has to be reached again.
	assert_int(a.step(_frame(AT_B), DT)).is_equal(S.RUNNING)
	assert_int(a.goal_index).is_equal(0)


## A respawn mid-attempt: half a lap is forgotten, and the car comes back somewhere else. A kept
## sweep or last angle would pass at 270 more degrees, or count the teleport as rotation.
func test_a_respawn_mid_attempt_clears_half_done_goals() -> void:
	var lap := RingLapGoal.new()
	lap.zone = &"Ring"
	var a := ChallengeAttempt.new(_def([lap]), _zones())
	assert_int(_sweep(a, 0, 180)).is_equal(S.RUNNING)
	a.reset()
	assert_float(a.elapsed).is_equal(0.0)
	assert_int(_sweep(a, 90, 449)).is_equal(S.RUNNING)
	assert_int(a.step(_on_ring(450), DT)).is_equal(S.PASS)


func test_attempts_share_no_state_and_leave_the_def_untouched() -> void:
	var lap := RingLapGoal.new()
	lap.zone = &"Ring"
	var d := _def([lap])
	var first := ChallengeAttempt.new(d, _zones())
	_sweep(first, 0, 300)
	var second := ChallengeAttempt.new(d, _zones())
	assert_int(_sweep(second, 0, 100)).is_equal(S.RUNNING)
	assert_float(lap.swept()).is_equal(0.0)
	assert_int(_sweep(first, 301, 400)).is_equal(S.PASS)


func test_a_broken_def_fails_at_once() -> void:
	var a := ChallengeAttempt.new(_def([_reach(&"Nope")]), _zones())
	assert_array(a.problems).is_not_empty()
	assert_int(a.status).is_equal(S.FAIL)
	assert_int(a.step(_frame(AT_A), DT)).is_equal(S.FAIL)
	var empty: Array[ChallengeGoal] = []
	assert_array(ChallengeAttempt.new(_def(empty), _zones()).problems).contains(["no goals"])

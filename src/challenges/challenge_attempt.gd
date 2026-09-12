class_name ChallengeAttempt
extends RefCounted
## One run at a ChallengeDef as pure logic: the clock, the ordered goals, the constraints and the
## par. The runner node builds a ChallengeFrame each physics tick, calls `step`, and acts on what
## comes back: PASS and FAIL end the attempt, RESET means respawn with `message` as the notice.
## Any respawn, whatever caused it, calls `reset()`.
##
## Works on `duplicate()` copies of the def's checks, so the def (a cached resource the select
## screen also reads) holds no state and two attempts never share any.

var def: ChallengeDef
var elapsed := 0.0     ## s since the attempt last (re)started
var goal_index := 0    ## the goal being stepped; equals `goal_count()` once the last one passed
var status: ChallengeCheck.Status = ChallengeCheck.Status.RUNNING
var message := ""      ## why it failed or reset
## What is wrong with the def against this course. Non-empty fails the attempt on the spot; the
## suite's registry validation is what keeps a shipped def from ever getting here.
var problems := PackedStringArray()

var _goals: Array[ChallengeGoal] = []
var _constraints: Array[ChallengeConstraint] = []


func _init(p_def: ChallengeDef, zones: Dictionary[StringName, ZoneShape]) -> void:
	def = p_def
	for g in def.goals:
		if g != null:
			_goals.append(g.duplicate() as ChallengeGoal)
	for c in def.constraints:
		if c != null:
			_constraints.append(c.duplicate() as ChallengeConstraint)
	if _goals.is_empty():
		problems.append("no goals")
	for check in _checks():
		problems.append_array(check.bind(zones))
	reset()


## Back to the start: clock, goal index and every check's state.
func reset() -> void:
	elapsed = 0.0
	goal_index = 0
	status = ChallengeCheck.Status.RUNNING
	message = ""
	for check in _checks():
		check.reset()
	if not problems.is_empty():
		_finish(ChallengeCheck.Status.FAIL, "challenge is broken: " + problems[0])


## One tick. The order is:
## 1. Constraints, from their `from_goal` on. They go first so a pass needs every constraint to
##    hold through the tick it happens on.
## 2. The par. It carries the hold slack, so a 1 s par allows exactly 60 ticks whichever way the
##    float sum rounds.
## 3. The current goal. Its PASS moves on to the next goal, which is first stepped on the
##    following tick.
## A finished attempt keeps answering its result.
func step(frame: ChallengeFrame, delta: float) -> ChallengeCheck.Status:
	if status != ChallengeCheck.Status.RUNNING:
		return status
	elapsed += delta
	for c in _constraints:
		if goal_index < c.from_goal:
			continue
		var s := c.step(frame, delta)
		if s == ChallengeCheck.Status.FAIL:
			return _finish(s, c.message)
		if s == ChallengeCheck.Status.RESET:
			var why := c.message
			reset()
			message = why
			return s
	if def.par_s > 0.0 and elapsed > def.par_s + ChallengeCheck.HOLD_EPS:
		return _finish(ChallengeCheck.Status.FAIL, "over par (%s s)" % String.num(def.par_s, 1))
	var g := _goals[goal_index]
	var gs := g.step(frame, delta)
	if gs == ChallengeCheck.Status.FAIL:
		return _finish(gs, g.message)
	if gs == ChallengeCheck.Status.PASS:
		goal_index += 1
		if goal_index >= _goals.size():
			return _finish(gs, "")
	return ChallengeCheck.Status.RUNNING


func goal_count() -> int:
	return _goals.size()


## The goal being stepped, or null once the attempt has passed.
func current_goal() -> ChallengeGoal:
	return _goals[goal_index] if goal_index < _goals.size() else null


func _finish(s: ChallengeCheck.Status, why: String) -> ChallengeCheck.Status:
	status = s
	message = why
	return s


func _checks() -> Array[ChallengeCheck]:
	var out: Array[ChallengeCheck] = []
	out.append_array(_goals)
	out.append_array(_constraints)
	return out

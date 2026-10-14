extends GdUnitTestSuite
## HillHold: hill-start assist and the powershift tractor's hill hold, pure statics. The grade's
## pull, the release on the drive, and each kind's latch, stepped by hand at 60 Hz.

const TICK := 1.0 / 60.0
const ASSIST := HillHold.Kind.ASSIST
const STANDSTILL := HillHold.Kind.STANDSTILL


## One `HillHold.step` with the defaults a held body at rest in gear sees. Its Vector2 is float32,
## so a held pedal other than 0 or 1 compares approximately.
static func _step(kind: HillHold.Kind, held: Vector2, pedal := 0.0, throttle := 0.0,
		at_rest := true, in_gear := true, drives := false, timeout_s := 1.0) -> Vector2:
	return HillHold.step(kind, timeout_s, held.x, held.y, pedal, throttle, at_rest, in_gear,
			drives, TICK)


# --- the grade ----------------------------------------------------------------------------------

func test_level_ground_pulls_nothing_however_the_body_pitches() -> void:
	var g := Vector3(0.0, -9.8, 0.0)
	var pitched := Vector3(0.0, 0.1, -1.0).normalized()
	assert_float(HillHold.pull_torque(g, Vector3.UP, pitched, 1000.0)).is_equal_approx(0.0, 1e-9)


func test_a_grade_pulls_back_nose_up_and_forward_nose_down() -> void:
	var g := Vector3(0.0, -9.8, 0.0)
	var a := deg_to_rad(10.0)
	# The ground rises toward -Z (the body's forward): its normal leans back toward +Z.
	var normal := Vector3(0.0, cos(a), sin(a))
	var lever := 1500.0 * 0.36
	var expected := 9.8 * sin(a) * lever
	assert_float(HillHold.pull_torque(g, normal, Vector3.FORWARD, lever)) \
			.is_equal_approx(-expected, 1e-3)
	assert_float(HillHold.pull_torque(g, normal, Vector3.BACK, lever)) \
			.is_equal_approx(expected, 1e-3)
	# Across the slope the heading takes none of it.
	assert_float(HillHold.pull_torque(g, normal, Vector3.RIGHT, lever)).is_equal_approx(0.0, 1e-6)


func test_the_drive_holds_once_it_meets_the_pull_in_the_gear_s_direction() -> void:
	# D up a hill: the drive must make up the pull.
	assert_bool(HillHold.drive_holds(1.0, 499.0, -500.0)).is_false()
	assert_bool(HillHold.drive_holds(1.0, 500.0, -500.0)).is_true()
	# R with the nose down the hill (reversing up it): the drive is negative, the pull positive.
	assert_bool(HillHold.drive_holds(-1.0, -499.0, 500.0)).is_false()
	assert_bool(HillHold.drive_holds(-1.0, -500.0, 500.0)).is_true()
	# Down the hill, and on the flat, it holds at once.
	assert_bool(HillHold.drive_holds(1.0, 0.0, 500.0)).is_true()
	assert_bool(HillHold.drive_holds(1.0, 0.0, 0.0)).is_true()
	assert_bool(HillHold.drive_holds(0.0, 1000.0, 0.0)).is_false()


# --- hill-start assist --------------------------------------------------------------------------

func test_assist_latches_the_pedal_at_rest_and_follows_a_reapplied_one() -> void:
	var held := _step(ASSIST, Vector2.ZERO, 0.6)
	assert_float(held.x).is_equal_approx(0.6, 1e-6)
	held = _step(ASSIST, held, 0.3)
	assert_float(held.x).is_equal_approx(0.3, 1e-6)
	# Released: the last application stays on.
	held = _step(ASSIST, held)
	assert_float(held.x).is_equal_approx(0.3, 1e-6)


func test_assist_lets_go_once_the_drive_holds_the_grade() -> void:
	var held := _step(ASSIST, _step(ASSIST, Vector2.ZERO, 1.0))
	assert_float(held.x).is_equal(1.0)
	assert_float(_step(ASSIST, held, 0.0, 0.5, true, true, true).x).is_equal(0.0)


func test_assist_times_out_whatever_the_drive_carries() -> void:
	var held := _step(ASSIST, Vector2.ZERO, 1.0)
	var ticks := 0
	while held.x > 0.0 and ticks < 1000:
		held = _step(ASSIST, held)
		ticks += 1
	# Held for the timeout, the release tick then lets go: 60 ticks at 60 Hz, give or take one for
	# the float sum.
	assert_int(ticks).is_between(60, 62)


func test_assist_never_arms_moving_out_of_gear_or_with_the_engine_off() -> void:
	assert_float(_step(ASSIST, Vector2.ZERO, 1.0, 0.0, false).x).is_equal(0.0)
	assert_float(_step(ASSIST, Vector2.ZERO, 1.0, 0.0, true, false).x).is_equal(0.0)
	# Latched, leaving gear (N, P, the key off, airborne) lets go.
	assert_float(_step(ASSIST, Vector2(1.0, 0.2), 0.0, 0.0, true, false).x).is_equal(0.0)


func test_assist_never_arms_without_the_foot_brake() -> void:
	assert_float(_step(ASSIST, Vector2.ZERO).x).is_equal(0.0)


# --- the powershift hill hold -------------------------------------------------------------------

func test_standstill_arms_at_rest_in_gear_with_the_pedal_up_and_never_times_out() -> void:
	var held := _step(STANDSTILL, Vector2.ZERO)
	assert_float(held.x).is_equal(1.0)
	for i in 600:
		held = _step(STANDSTILL, held)
	assert_float(held.x).is_equal(1.0)
	assert_float(held.y).is_greater(9.9)


func test_standstill_lets_go_only_on_the_pedal_with_the_drive_holding() -> void:
	var held := _step(STANDSTILL, Vector2.ZERO)
	# The flat: the drive holds with the pedal up, and the hold stays (no flicker).
	assert_float(_step(STANDSTILL, held, 0.0, 0.0, true, true, true).x).is_equal(1.0)
	# The pedal down while the clutch ramps short of the grade: still held.
	assert_float(_step(STANDSTILL, held, 0.0, 0.4, true, true, false).x).is_equal(1.0)
	assert_float(_step(STANDSTILL, held, 0.0, 0.4, true, true, true).x).is_equal(0.0)


func test_standstill_never_arms_moving_or_on_the_pedal() -> void:
	assert_float(_step(STANDSTILL, Vector2.ZERO, 0.0, 0.0, false).x).is_equal(0.0)
	assert_float(_step(STANDSTILL, Vector2.ZERO, 0.0, 0.5).x).is_equal(0.0)
	assert_float(_step(STANDSTILL, Vector2.ZERO, 0.0, 0.0, true, false).x).is_equal(0.0)


func test_none_never_holds() -> void:
	assert_float(_step(HillHold.Kind.NONE, Vector2.ZERO, 1.0).x).is_equal(0.0)
	assert_float(_step(HillHold.Kind.NONE, Vector2(1.0, 0.0)).x).is_equal(0.0)

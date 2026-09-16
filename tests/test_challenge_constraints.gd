extends GdUnitTestSuite
## Challenge constraints: judged every tick, RUNNING while they hold, FAIL (or RESET for a fail
## zone) on the tick they break.

const S := ChallengeCheck.Status
const DT := 1.0 / 60.0


func _frame(signals: Dictionary, pos := Vector3.ZERO) -> ChallengeFrame:
	var f := ChallengeFrame.new()
	f.signals = signals
	f.pose = Transform3D(Basis.IDENTITY, pos)
	return f


func test_signal_limit_absolute_bounds_both_directions_inclusively() -> void:
	var c := SignalLimitConstraint.new()
	c.signal_name = "accLat"
	c.high = 4.0
	c.absolute = true
	assert_int(c.step(_frame({"accLat": -3.9}), DT)).is_equal(S.RUNNING)
	assert_int(c.step(_frame({"accLat": -4.0}), DT)).is_equal(S.RUNNING)
	assert_int(c.step(_frame({"accLat": 4.0}), DT)).is_equal(S.RUNNING)
	assert_int(c.step(_frame({"accLat": -4.1}), DT)).is_equal(S.FAIL)
	assert_str(c.message).contains("accLat")


func test_signal_limit_signed_floor() -> void:
	var c := SignalLimitConstraint.new()
	c.signal_name = "air_primary"
	c.low = 5.0
	assert_int(c.step(_frame({"air_primary": 8.0}), DT)).is_equal(S.RUNNING)
	assert_int(c.step(_frame({"air_primary": 4.9}), DT)).is_equal(S.FAIL)


## A flag that must never be set: a bool reads 0/1.
func test_forbidden_value_catches_a_flag() -> void:
	var c := ForbiddenValueConstraint.new()
	c.signal_name = "trailer_abs"
	c.values = PackedInt32Array([1])
	assert_int(c.step(_frame({"trailer_abs": false}), DT)).is_equal(S.RUNNING)
	assert_int(c.step(_frame({"trailer_abs": true}), DT)).is_equal(S.FAIL)


func test_forbidden_value_catches_a_mode() -> void:
	var c := ForbiddenValueConstraint.new()
	c.signal_name = "mode_actual"
	c.values = PackedInt32Array([DroneModes.LOITER, DroneModes.RTL])
	assert_int(c.step(_frame({"mode_actual": DroneModes.ALT_HOLD}), DT)).is_equal(S.RUNNING)
	assert_int(c.step(_frame({"mode_actual": DroneModes.RTL}), DT)).is_equal(S.FAIL)


func test_fail_zone_resets_with_its_warning() -> void:
	var c := FailZoneConstraint.new()
	c.zone = &"Drop"
	c.warning = "Off the causeway"
	var zones: Dictionary[StringName, ZoneShape] = {
		&"Drop": ZoneShape.box(Transform3D(Basis.IDENTITY, Vector3(0, -10, 0)), Vector3(100, 10, 100)),
	}
	assert_array(c.bind(zones)).is_empty()
	assert_int(c.step(_frame({}, Vector3(0, 1, 0)), DT)).is_equal(S.RUNNING)
	assert_int(c.step(_frame({}, Vector3(0, -8, 0)), DT)).is_equal(S.RESET)
	assert_str(c.message).is_equal("Off the causeway")


func test_fail_zone_reports_a_missing_zone() -> void:
	var c := FailZoneConstraint.new()
	c.zone = &"Nope"
	var none: Dictionary[StringName, ZoneShape] = {}
	assert_array(c.bind(none)).has_size(1)


## Built for Tractor 4 (tractor_auto_steer): hand steering never sets guidance_curvature, so
## the presence rule (0 is a legal curvature, absent is the sentinel) is what fails it.
func test_input_present_fails_while_the_field_sits_on_its_sentinel() -> void:
	var c := InputPresentConstraint.new()
	c.field = &"guidance_curvature"
	var f := ChallengeFrame.new()
	f.pose = Transform3D.IDENTITY
	assert_int(c.step(f, DT)).is_equal(S.FAIL)
	assert_str(c.message).contains("guidance_curvature")


func test_input_present_holds_once_a_real_command_arrives() -> void:
	var c := InputPresentConstraint.new()
	c.field = &"guidance_curvature"
	var f := ChallengeFrame.new()
	f.pose = Transform3D.IDENTITY
	# Dead straight (0) is a real command, same presence rule as heading_cmd.
	f.input.guidance_curvature = 0.0
	assert_int(c.step(f, DT)).is_equal(S.RUNNING)
	f.input.guidance_curvature = -40.0
	assert_int(c.step(f, DT)).is_equal(S.RUNNING)

extends GdUnitTestSuite
## TouchControls: the driving layer (joystick + bottom-right cluster) must stay down for the
## whole of a challenge attempt. boot.gd's `set_driving_locked`/`set_challenge_mode` are the only
## calls meant to move it; this pins the invariant across the paths that could plausibly undo it
## without going through them — a rebuild (`_build_widgets`, what a resize or theme change
## triggers), a mid-attempt vehicle change (`set_capabilities`, what boot.gd's `_on_vehicle_changed`
## calls), and F4 itself.

func _touch() -> TouchControls:
	var t: TouchControls = auto_free(TouchControls.new())
	add_child(t)
	return t


func _toggle_touch_event() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = &"toggle_touch"
	ev.pressed = true
	return ev


func test_driving_layer_stays_hidden_through_a_challenge_attempt() -> void:
	var t := _touch()
	t.set_driving_locked(true)
	assert_bool(t._driving.visible).is_false()

	# A rebuild (window resize, theme change) must not forget the lock.
	t._build_widgets()
	assert_bool(t._driving.visible).is_false()

	# A mid-attempt vehicle change (boot.gd _on_vehicle_changed -> _bind_hud -> set_capabilities)
	# must not bring it back either.
	t.set_capabilities({"tows": true, "pto": true})
	assert_bool(t._driving.visible).is_false()

	# Unlocking (the attempt ends) restores it — F4 was never pressed, so still shown.
	t.set_driving_locked(false)
	assert_bool(t._driving.visible).is_true()


## F4 toggles the flag the lock multiplies against, but the visible result stays down.
func test_toggle_touch_key_has_no_effect_while_locked() -> void:
	var t := _touch()
	assert_bool(t._driving.visible).is_true()  # unlocked default
	t.set_driving_locked(true)
	assert_bool(t._driving.visible).is_false()
	t._unhandled_input(_toggle_touch_event())  # F4 press #1
	assert_bool(t._driving.visible).is_false()
	t._unhandled_input(_toggle_touch_event())  # F4 press #2
	assert_bool(t._driving.visible).is_false()


## RETRY/INFO carry no ActionRegistry row (the registry has no challenge concept), so they are
## gated by `set_challenge_mode` directly and must survive a rebuild the same way the lock does.
func test_challenge_pads_show_only_while_an_attempt_runs() -> void:
	var t := _touch()
	assert_int(t._challenge_pads.size()).is_equal(2)
	for p in t._challenge_pads:
		assert_bool((p as Control).visible).is_false()

	t.set_challenge_mode(true)
	for p in t._challenge_pads:
		assert_bool((p as Control).visible).is_true()

	t._build_widgets()  # a rebuild must not forget challenge mode either
	assert_int(t._challenge_pads.size()).is_equal(2)
	for p in t._challenge_pads:
		assert_bool((p as Control).visible).is_true()

	t.set_challenge_mode(false)
	for p in t._challenge_pads:
		assert_bool((p as Control).visible).is_false()


func test_challenge_pads_emit_retry_and_info() -> void:
	var t := _touch()
	var fired := []
	t.retry_pressed.connect(func() -> void: fired.append("retry"))
	t.info_pressed.connect(func() -> void: fired.append("info"))
	for p in t._challenge_pads:
		p.held.emit(true)
		p.held.emit(false)
	assert_array(fired).contains_exactly_in_any_order(["retry", "info"])

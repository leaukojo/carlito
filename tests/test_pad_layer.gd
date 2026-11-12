extends GdUnitTestSuite
## PadLayer: raw pad buttons -> injected actions. Every test stubs the pad, the context and the
## injection, so a controller on the machine running the suite reads as nothing.


## Records what it would inject; L1, pause and the vehicle are whatever the test sets.
class _StubLayer extends PadLayer:
	var l1 := false  ## every pad's L1
	var l1_pads := {}  ## device -> true: just these pads' L1
	var paused := false
	var family := "car"
	var caps := {}
	var emitted: Array[String] = []
	var devices: Array[int] = []  ## the device each emitted action carried

	func _l1_held(device: int) -> bool:
		return l1 or l1_pads.has(device)

	func _paused() -> bool:
		return paused

	func _context() -> Dictionary:
		return ActionRegistry.context(family, false, caps)

	func _emit(action: StringName, pressed: bool, device: int) -> void:
		emitted.append(("+" if pressed else "-") + String(action))
		devices.append(device)


func _layer() -> _StubLayer:
	return auto_free(_StubLayer.new())


func _button(layer: PadLayer, index: JoyButton, pressed: bool, device := 0) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = index
	ev.pressed = pressed
	ev.device = device
	layer._input(ev)


func test_a_held_button_presses_and_releases_its_action() -> void:
	var layer := _layer()
	_button(layer, JOY_BUTTON_A, true)
	_button(layer, JOY_BUTTON_A, false)
	assert_array(layer.emitted).contains_exactly(["+handbrake", "-handbrake"])


## L1 going down mid-hold must not drop the handbrake nor fire the L1 layer's action.
func test_l1_mid_hold_releases_what_the_press_took() -> void:
	var layer := _layer()
	layer.family = "tractor"
	layer.caps = {"scv": true}
	_button(layer, JOY_BUTTON_A, true)
	layer.l1 = true
	_button(layer, JOY_BUTTON_A, false)
	assert_array(layer.emitted).contains_exactly(["+handbrake", "-handbrake"])


func test_l1_picks_the_vehicle_layer() -> void:
	var layer := _layer()
	layer.family = "drone"
	layer.l1 = true
	_button(layer, JOY_BUTTON_X, true)
	_button(layer, JOY_BUTTON_X, false)
	assert_array(layer.emitted).contains_exactly(["+arm", "-arm"])


## Nothing on L1 there: the button does its own job, so L1 never makes a button dead.
func test_a_button_with_nothing_on_l1_falls_back_to_its_own() -> void:
	var layer := _layer()
	layer.l1 = true
	_button(layer, JOY_BUTTON_X, true)  # L1+square on a car: the lights
	_button(layer, JOY_BUTTON_X, false)
	_button(layer, JOY_BUTTON_START, true)  # L1+Options: the menu
	_button(layer, JOY_BUTTON_START, false)
	_button(layer, JOY_BUTTON_LEFT_SHOULDER, true)  # L1 alone is the layer, not a slot
	assert_array(layer.emitted).contains_exactly(
			["+headlights", "-headlights", "+to_menu", "-to_menu"])


## A boat has no handbrake and nothing on L1+Cross: still nothing.
func test_a_button_with_nothing_here_injects_nothing() -> void:
	var layer := _layer()
	layer.family = "boat"
	layer.l1 = true
	_button(layer, JOY_BUTTON_A, true)
	_button(layer, JOY_BUTTON_A, false)
	assert_array(layer.emitted).is_empty()


## Two pads: each has its own L1, each action carries its pad, and the legend stays up until no
## pad holds L1.
func test_two_pads_keep_their_own_layer_and_device() -> void:
	var layer := _layer()
	layer.family = "drone"
	var seen: Array[bool] = []
	layer.layer_changed.connect(func(held: bool) -> void: seen.append(held))
	layer.l1_pads = {1: true}
	_button(layer, JOY_BUTTON_LEFT_SHOULDER, true, 1)
	_button(layer, JOY_BUTTON_X, true, 0)  # pad 0, L1 up: the lights
	_button(layer, JOY_BUTTON_X, true, 1)  # pad 1, L1 down: arm
	_button(layer, JOY_BUTTON_X, false, 0)
	_button(layer, JOY_BUTTON_X, false, 1)
	_button(layer, JOY_BUTTON_LEFT_SHOULDER, true, 0)
	_button(layer, JOY_BUTTON_LEFT_SHOULDER, false, 1)
	_button(layer, JOY_BUTTON_LEFT_SHOULDER, false, 0)
	assert_array(layer.emitted).contains_exactly(
			["+headlights", "+arm", "-headlights", "-arm"])
	assert_array(layer.devices).contains_exactly([0, 1, 0, 1])
	assert_array(seen).contains_exactly([true, false])


func test_paused_only_options_and_create_answer() -> void:
	var layer := _layer()
	layer.paused = true
	_button(layer, JOY_BUTTON_X, true)
	_button(layer, JOY_BUTTON_X, false)
	_button(layer, JOY_BUTTON_START, true)
	_button(layer, JOY_BUTTON_START, false)
	_button(layer, JOY_BUTTON_BACK, true)
	_button(layer, JOY_BUTTON_BACK, false)
	assert_array(layer.emitted) \
		.contains_exactly(["+to_menu", "-to_menu", "+garage", "-garage"])


## Under a menu Cross accepts the focused control and Circle backs out, and neither is the handbrake.
func test_paused_cross_accepts_and_circle_goes_back() -> void:
	var layer := _layer()
	layer.paused = true
	_button(layer, JOY_BUTTON_A, true)
	_button(layer, JOY_BUTTON_A, false)
	_button(layer, JOY_BUTTON_B, true)
	_button(layer, JOY_BUTTON_B, false)
	assert_array(layer.emitted) \
		.contains_exactly(["+ui_accept", "-ui_accept", "+to_menu", "-to_menu"])


## A Cross that closed the menu is still held when the game resumes: its release lets go of the
## accept it pressed, and it never becomes a handbrake press.
func test_a_cross_held_across_the_menu_closing_is_not_a_handbrake() -> void:
	var layer := _layer()
	layer.paused = true
	_button(layer, JOY_BUTTON_A, true)
	layer.paused = false
	_button(layer, JOY_BUTTON_A, true)  # key repeat / a second event while held
	_button(layer, JOY_BUTTON_A, false)
	assert_array(layer.emitted).contains_exactly(["+ui_accept", "-ui_accept"])


## L1 is the layer, reported for the legend: down, up, and up again when its pad goes.
func test_l1_reports_the_layer() -> void:
	var layer := _layer()
	var seen: Array[bool] = []
	layer.layer_changed.connect(func(held: bool) -> void: seen.append(held))
	_button(layer, JOY_BUTTON_LEFT_SHOULDER, true)
	_button(layer, JOY_BUTTON_LEFT_SHOULDER, false)
	_button(layer, JOY_BUTTON_LEFT_SHOULDER, true)
	layer._on_joy_connection_changed(0, false)
	assert_array(seen).contains_exactly([true, false, true, false])


## A pad lost mid-hold sends no release: the layer lets go itself, and the next press is fresh.
func test_a_lost_pad_lets_go_of_what_it_held() -> void:
	var layer := _layer()
	_button(layer, JOY_BUTTON_A, true)
	layer._on_joy_connection_changed(0, false)
	_button(layer, JOY_BUTTON_A, true)
	assert_array(layer.emitted).contains_exactly(["+handbrake", "-handbrake", "+handbrake"])

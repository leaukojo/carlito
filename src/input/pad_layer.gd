class_name PadLayer
extends Node
## Gamepad buttons -> game actions. InputMap cannot say "cross only while L1 is up", so no game
## action binds a pad button there (tests/test_action_registry.gd guards it): this node reads each
## button event, picks the layer by L1, resolves the slot against the current vehicle
## (`ActionRegistry.pad_press`) and injects that action as an InputEventAction, which every
## consumer (LocalSource, boot.gd, level.gd) already reads. The raw event is never consumed, so
## menus keep Godot's `ui_*` D-pad and stick navigation; under a menu Cross and Circle are injected
## as `ui_accept` / `to_menu` (Godot binds no pad button to either). Shell-composed (it needs the
## shell's capability dict) and runs while paused, so Options closes the menu it opened.
## Per pad throughout: each pad has its own L1, and an injected action carries its pad's `device`,
## so Input holds the action until every pad pressing it lets go.

## Button -> slot name, as the registry's `pad` field spells it. L1 is the layer, not a slot.
const BUTTONS := {
	JOY_BUTTON_A: "cross",
	JOY_BUTTON_B: "circle",
	JOY_BUTTON_X: "square",
	JOY_BUTTON_Y: "triangle",
	JOY_BUTTON_BACK: "create",
	JOY_BUTTON_START: "options",
	JOY_BUTTON_LEFT_STICK: "l3",
	JOY_BUTTON_RIGHT_STICK: "r3",
	JOY_BUTTON_RIGHT_SHOULDER: "r1",
	JOY_BUTTON_DPAD_UP: "dpad_up",
	JOY_BUTTON_DPAD_DOWN: "dpad_down",
	JOY_BUTTON_DPAD_LEFT: "dpad_left",
	JOY_BUTTON_DPAD_RIGHT: "dpad_right",
}
const LAYER_PREFIX := "l1+"
## Slot -> its name on screen (CONTROLS sheet, L1 legend), in the legend's order: main, second,
## third, then the rest. Text, not the face glyphs: the UI font (Barlow) has none of them.
const SLOT_NAMES := {
	"square": "Square",
	"circle": "Circle",
	"cross": "Cross",
	"triangle": "Triangle",
	"dpad_up": "D-pad up",
	"dpad_down": "D-pad down",
	"dpad_left": "D-pad left",
	"dpad_right": "D-pad right",
	"r1": "R1",
	"r3": "R3",
	"l3": "L3",
	"create": "Create",
	"options": "Options",
}
## How the layer reads on screen ("L1 + Square").
const LAYER_NAME := "L1 + "

## Some pad now holds L1 (true), or none does: the shell shows the layer's legend meanwhile.
signal layer_changed(held: bool)

## The shell's capability read (boot.gd `_capabilities`), called on each press so it is never stale.
var capabilities: Callable

## (device, button) -> the action its press injected. The release lets go of that action, so a
## held handbrake survives L1 going down mid-hold.
var _held := {}
## Devices whose L1 is down, as a set: the legend shows while any pad holds it.
var _l1_devices := {}


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## A pad lost mid-hold sends no release: let go of what it held, or the action stays pressed and
## the stale entry swallows that button's next press after a reconnect.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		return
	_set_l1(device, false)
	for key: Vector2i in _held.keys():
		if key.x == device:
			_emit(_held[key], false, device)
			_held.erase(key)


func _input(event: InputEvent) -> void:
	var button := event as InputEventJoypadButton
	if button == null:
		return
	if button.button_index == JOY_BUTTON_LEFT_SHOULDER:
		_set_l1(button.device, button.pressed)
		return
	if not BUTTONS.has(button.button_index):
		return
	var key := Vector2i(button.device, button.button_index)
	if not button.pressed:
		if _held.has(key):
			_emit(_held[key], false, button.device)
			_held.erase(key)
		return
	if _held.has(key):
		return
	var action := ActionRegistry.pad_press(String(BUTTONS[button.button_index]),
			_l1_held(button.device), _context(), _paused())
	if action != &"":
		_held[key] = action
		_emit(action, true, button.device)


## Whether some pad holds L1, for the shell to re-show the legend after what hid or outdated it.
func layer_held() -> bool:
	return not _l1_devices.is_empty()


## Record `device`'s L1 and tell the shell when "some pad holds L1" flips.
func _set_l1(device: int, down: bool) -> void:
	var was := not _l1_devices.is_empty()
	if down:
		_l1_devices[device] = true
	else:
		_l1_devices.erase(device)
	if was != (not _l1_devices.is_empty()):
		layer_changed.emit(not was)


func _context() -> Dictionary:
	var caps: Dictionary = capabilities.call() if capabilities.is_valid() else {}
	return ActionRegistry.context(GameState.current_vehicle, Bridge.is_active(), caps,
			InputRouter.bridge_drives())


func _paused() -> bool:
	return is_inside_tree() and get_tree().paused


func _l1_held(device: int) -> bool:
	return Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER)


## A fresh event each time: Input refuses the same object twice in one frame. `device` keeps one
## pad's release from letting go of an action another pad still holds.
func _emit(action: StringName, pressed: bool, device: int) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	ev.device = device
	Input.parse_input_event(ev)

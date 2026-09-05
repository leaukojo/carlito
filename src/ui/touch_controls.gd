class_name TouchControls
extends Control
## On-screen touch controls, registered on InputRouter as a second local source: steering
## joystick, gas/brake pedals, left-edge button stack. Reports raw intents via poll() like
## local_source.gd — arbitration stays in InputRouter. Plain text, no emoji.
##
## The button stack is generated from ActionRegistry (buttons, captions, gating, raw-intent key
## all come from that table). Widgets (joystick, pedals, flight pads) are hand-built, but the
## registry still decides whether each is shown.

signal menu_pressed
signal garage_pressed
signal respawn_pressed
signal next_attachment_pressed
signal camera_pressed
signal day_night_pressed

## Widget metrics in logical px, put through UiTheme.px before use.
const JOY_RADIUS := 90.0
const KNOB_SIZE := 66.0
const BTN_SIZE := Vector2(96, 44)
const PEDAL_SIZE := Vector2(110, 150)
const FLIGHT_PAD_SIZE := Vector2(110, 68)
const EDGE := 40.0        ## joystick/pedal inset from the window edge
const STACK_TOP := 10.0   ## same top inset DebugOverlay uses on the other edge
const STACK_GAP := 8.0

## Extra size the overlay takes on a pointer display only, on top of the theme scale (which is
## sized for a fingertip and leaves a mouse-aimed desktop window a small island of pads).
## Touchscreens keep 1.0 regardless of resolution. Ramps from 1.0 at PAD_SCALE_REF logical px.
const PAD_SCALE_REF := 540.0
const PAD_SCALE_MAX := 2.0

var _scale := 1.0  ## cached UI scale; a change to it rebuilds the widgets
var _pad_scale := 1.0  ## cached desktop pad multiplier (see PAD_SCALE_REF); rebuilds the widgets
var _capacity := 0  ## buttons one stack column holds at the size last built for

## Raw intent, keyed by the registry's `poll_key` so poll() is one loop. `_held` carries levels
## a pad or widget holds down; `_edges` carries one-shot toggle edges a tap latches, drained by
## poll(). Key names match local_source.gd's, so InputRouter's toggle owners (_lights, _pto,
## _hitch_up, ...) are shared by keyboard and touch rather than duplicated per source.
var _held: Dictionary[StringName, Variant] = {}
var _edges: Dictionary[StringName, Variant] = {}

var _joy_knob: Panel
var _joy_center := Vector2.ZERO
## Screen-up positive. Not written into the intent as it moves (see _joy_pitch_into): a
## joystick release would otherwise zero a key a second thumb is still holding.
var _joy_y := 0.0
var _day_night_label: Label  ## kept across rebuilds so it never comes back saying the opposite of the truth
var _is_night := false
var _gated: Array[Dictionary] = []  ## {node, id}: everything whose visibility the registry decides
var _caps := {}  ## vehicle capabilities from the shell (boot.gd _capabilities)
var _ctx := {}            ## cached ActionRegistry context; rebuilt only when its inputs move
var _ctx_family := ""
var _ctx_bridge := false


## Tracks which pointer is holding it (finger index, or MOUSE) so several pads can be held at
## once — a plain Button cannot, since on mobile it only sees the mouse events Godot emulates
## from touch, mirroring a single finger. Emulated events are ignored to avoid double-counting.
class Pad extends Panel:
	signal held(down: bool)
	signal moved(local_pos: Vector2)

	const NONE := -99
	const MOUSE := -1

	var _pointer := NONE

	func _gui_input(event: InputEvent) -> void:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		var id := NONE
		var pressed := false
		if event is InputEventScreenTouch:
			id = event.index
			pressed = event.pressed
		elif event is InputEventMouseButton:
			if event.button_index != MOUSE_BUTTON_LEFT:
				return
			id = MOUSE
			pressed = event.pressed
		elif event is InputEventScreenDrag:
			if event.index == _pointer:
				moved.emit(event.position)
			return
		elif event is InputEventMouseMotion:
			if _pointer == MOUSE:
				moved.emit(event.position)
			return
		else:
			return

		if pressed:
			if _pointer == NONE:
				_pointer = id
				held.emit(true)
				moved.emit(event.position)
		elif id == _pointer:
			_pointer = NONE
			held.emit(false)

	## A pad hidden or removed mid-press never gets its release event; drop the hold.
	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and _pointer != NONE:
			_pointer = NONE
			held.emit(false)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # only the widgets capture input
	_scale = UiTheme.scale_of(self)
	_pad_scale = _compute_pad_scale()
	_build_widgets()
	visible = _should_show()
	GameState.night_changed.connect(_on_night_changed)
	InputRouter.set_touch_source(self)


## A resize alone can need a rebuild too: the UI scale is clamped at both ends off the short
## edge, so a window can lose the height that decides column capacity without the scale moving.
## Guarded on one of the two actually changing, or every window-edge drag rebuilds the pads.
func _notification(what: int) -> void:
	if not is_inside_tree():
		return
	if what == NOTIFICATION_RESIZED:
		var pads := _compute_pad_scale()
		if is_equal_approx(pads, _pad_scale) and _capacity == _column_capacity():
			return
		_pad_scale = pads
		_build_widgets()
		return
	if what != NOTIFICATION_THEME_CHANGED:
		return
	var s := UiTheme.scale_of(self)
	if is_equal_approx(s, _scale):
		return
	_scale = s
	_build_widgets()


func _build_widgets() -> void:
	for c in get_children():
		remove_child(c)  # not just queue_free: a deferred free leaves the old pads pressable for a frame
		c.queue_free()
	_gated.clear()
	_day_night_label = null  # freed with the old pads; _build_button_stack re-finds it
	_held.clear()
	_edges.clear()
	_joy_y = 0.0
	_capacity = _column_capacity()
	_build_joystick()
	_build_handbrake()
	_build_pedals()
	_build_button_stack()


func _exit_tree() -> void:
	InputRouter.clear_touch_source(self)


func set_active(active: bool) -> void:
	visible = active and _should_show()


## Capability-keyed registry rows (ATTACH, PTO, TIP, DIFF, MFWD, BODY) can't be family-gated
## like PANTO/FLAPS: machines within a family disagree (the semi tows, the garbage truck
## doesn't). Re-called on every attachment cycle, not just on vehicle bind.
func set_capabilities(caps: Dictionary) -> void:
	_caps = caps
	_ctx = {}  # force the cached gate context to rebuild


## Drained of its one-shot toggle edges. Contributes nothing while hidden: a pad hidden
## mid-press (e.g. F4 while holding GAS) never gets its release, so its held state would stick.
func poll() -> Dictionary[StringName, Variant]:
	if not visible:
		return {}
	var out := _held.duplicate()
	for k in _edges:
		out[k] = _edges[k]
		_edges[k] = false
	_joy_pitch_into(out)
	return out


## Merged over the pads rather than written by _move_knob: a stick released while the other
## thumb holds UP or GAS must not zero it.
##   plane - a real yoke, inverted: stick back (screen-down) is nose UP.
##   drone - the right stick tilts rather than climbs; screen-up rides `accel`/`brake_reverse`
##           (the throttle axis), not `climb`.
func _joy_pitch_into(out: Dictionary[StringName, Variant]) -> void:
	if is_zero_approx(_joy_y) or not ActionRegistry.applies(&"climb", _gate_context()):
		return
	if _ctx_family == "drone":
		if _joy_y > 0.0:
			out[&"accel"] = maxf(float(out.get(&"accel", 0.0)), _joy_y)
		else:
			out[&"brake_reverse"] = maxf(float(out.get(&"brake_reverse", 0.0)), -_joy_y)
		return
	var v := clampf(float(out.get(&"climb", 0.0)) - _joy_y, -1.0, 1.0)
	out[&"climb"] = v
	out[&"elevator"] = v


func _process(_dt: float) -> void:
	var ctx := _gate_context()
	for g in _gated:
		g["node"].visible = ActionRegistry.applies(g["id"], ctx)


func _gate_context() -> Dictionary:
	var family: String = GameState.current_vehicle
	var bridge := Bridge.is_active()
	if _ctx.is_empty() or family != _ctx_family or bridge != _ctx_bridge:
		_ctx_family = family
		_ctx_bridge = bridge
		_ctx = ActionRegistry.context(family, bridge, _caps)
	return _ctx


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_touch"):
		visible = not visible


## On by default everywhere, desktop included. F4 (toggle_touch) still hides them.
func _should_show() -> bool:
	return true


# --- handbrake (latching) ----------------------------------------------------

## Latches (a parking brake stays set). Its x is the joystick's footprint, not a parent-child
## relation: the joystick is gated off on the train and the handbrake is not.
func _build_handbrake() -> void:
	var pad := _latch_button("HAND", &"handbrake")
	var pad_size := Vector2(_px(FLIGHT_PAD_SIZE.x), _px(FLIGHT_PAD_SIZE.y))
	pad.custom_minimum_size = pad_size
	pad.size = pad_size
	pad.anchor_top = 1.0
	pad.anchor_bottom = 1.0
	pad.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pad.position = Vector2(_px(EDGE + JOY_RADIUS * 2.0 + STACK_GAP), -pad_size.y - _px(EDGE))
	add_child(pad)
	_gated.append({"node": pad, "id": &"handbrake"})


# --- joystick (steer, plus the aircraft pitch axis — see _joy_pitch_into) ---

func _build_joystick() -> void:
	var radius := _px(JOY_RADIUS)
	var knob := _px(KNOB_SIZE)
	var edge := _px(EDGE)
	var base := Pad.new()
	base.custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	base.size = base.custom_minimum_size
	base.anchor_top = 1.0
	base.anchor_bottom = 1.0
	base.grow_vertical = Control.GROW_DIRECTION_BEGIN
	base.position = Vector2(edge, -radius * 2.0 - edge)
	base.add_theme_stylebox_override("panel", _ring_style(radius))
	base.moved.connect(_move_knob)
	base.held.connect(func(down: bool) -> void:
		if not down:
			_held[&"steer"] = 0.0
			_joy_y = 0.0
			_reset_knob()
	)
	add_child(base)
	_joy_center = Vector2(radius, radius)
	_held[&"steer"] = 0.0
	_gated.append({"node": base, "id": &"steer"})

	_joy_knob = Panel.new()
	_joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE  # let presses on the knob reach the base Pad
	_joy_knob.size = Vector2(knob, knob)
	_joy_knob.add_theme_stylebox_override("panel",
			_ring_style(knob * 0.5, Color(0.30, 0.34, 0.42, 0.95)))
	base.add_child(_joy_knob)
	_reset_knob()


func _move_knob(local_pos: Vector2) -> void:
	var radius := _px(JOY_RADIUS)
	var knob := _px(KNOB_SIZE)
	var offset := (local_pos - _joy_center).limit_length(radius)
	_joy_knob.position = _joy_center + offset - Vector2(knob, knob) * 0.5
	_held[&"steer"] = clampf(offset.x / radius, -1.0, 1.0)  # steering is the horizontal axis
	# Screen-up positive; what an aircraft DOES with it is decided in poll() (see _joy_pitch_into).
	_joy_y = clampf(-offset.y / radius, -1.0, 1.0)


func _reset_knob() -> void:
	var knob := _px(KNOB_SIZE)
	_joy_knob.position = _joy_center - Vector2(knob, knob) * 0.5


# --- pedals (gas / brake+reverse, lights / horn, flight pads) ----------------

func _build_pedals() -> void:
	var edge := _px(EDGE)
	var pedal := Vector2(_px(PEDAL_SIZE.x), _px(PEDAL_SIZE.y))
	var flight := Vector2(_px(FLIGHT_PAD_SIZE.x), _px(FLIGHT_PAD_SIZE.y))
	# LIGHTS/HORN sits on top of the pedal row so nothing reaches into the pedals the thumb aims at.
	var cluster := VBoxContainer.new()
	cluster.add_theme_constant_override("separation", int(_px(STACK_GAP)))
	cluster.anchor_left = 1.0
	cluster.anchor_right = 1.0
	cluster.anchor_top = 1.0
	cluster.anchor_bottom = 1.0
	cluster.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cluster.grow_vertical = Control.GROW_DIRECTION_BEGIN
	cluster.position = Vector2(-edge, -edge)
	add_child(cluster)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", int(_px(STACK_GAP)))  # matches the LIGHTS/HORN row so columns line up

	var panto := _tap_button("PANTO", &"pantograph_toggle")
	panto.custom_minimum_size = pedal
	row.add_child(panto)
	_gated.append({"node": panto, "id": &"pantograph"})

	var brake := _hold_button("BRAKE\nREV", &"brake_reverse")
	brake.custom_minimum_size = pedal
	row.add_child(brake)

	var gas := _hold_button("GAS", &"accel")
	gas.custom_minimum_size = pedal
	row.add_child(gas)

	# LIGHTS/HORN sit with the pedals, not the settings stack, since they're used while driving.
	var aux := HBoxContainer.new()
	aux.add_theme_constant_override("separation", int(_px(STACK_GAP)))
	aux.alignment = BoxContainer.ALIGNMENT_END
	# Only one of ARM/FLAPS/DOORS is ever visible — the three families are mutually exclusive.
	var arm := _tap_button("ARM", &"arm_toggle")
	arm.custom_minimum_size = Vector2(pedal.x, flight.y)
	aux.add_child(arm)
	_gated.append({"node": arm, "id": &"arm"})
	# Cycles the ladder rather than latching; the cluster's MODE chip is the FC's own answer.
	var mode := _tap_button("MODE", &"flight_mode_cycle")
	mode.custom_minimum_size = Vector2(pedal.x, flight.y)
	aux.add_child(mode)
	_gated.append({"node": mode, "id": &"flight_mode"})
	var flaps := _tap_button("FLAPS", &"flaps_toggle")
	flaps.custom_minimum_size = Vector2(pedal.x, flight.y)
	aux.add_child(flaps)
	_gated.append({"node": flaps, "id": &"flaps"})
	var doors := _tap_button("DOORS", &"doors_toggle")
	doors.custom_minimum_size = Vector2(pedal.x, flight.y)
	aux.add_child(doors)
	_gated.append({"node": doors, "id": &"doors"})
	var lights := _tap_button("LIGHTS", &"lights_cycle")
	lights.custom_minimum_size = Vector2(pedal.x, flight.y)
	aux.add_child(lights)
	_gated.append({"node": lights, "id": &"headlights"})
	var horn := _hold_button("HORN", &"horn")
	horn.custom_minimum_size = Vector2(pedal.x, flight.y)
	aux.add_child(horn)
	_gated.append({"node": horn, "id": &"horn"})
	cluster.add_child(aux)
	cluster.add_child(row)

	# One vertical axis published under two keys (plane elevator / drone climb), like local_source.gd.
	var col := VBoxContainer.new()
	var up := _hold_pad("UP", func(down: bool) -> void: _set_vert(1.0 if down else minf(_vert(), 0.0)))
	up.custom_minimum_size = flight
	col.add_child(up)
	var down_pad := _hold_pad("DOWN",
			func(down: bool) -> void: _set_vert(-1.0 if down else maxf(_vert(), 0.0)))
	down_pad.custom_minimum_size = flight
	col.add_child(down_pad)
	row.add_child(col)
	row.move_child(col, 0)
	_set_vert(0.0)
	_gated.append({"node": col, "id": &"climb"})


func _vert() -> float:
	return float(_held.get(&"climb", 0.0))


func _set_vert(v: float) -> void:
	_held[&"climb"] = v
	_held[&"elevator"] = v


# --- left-edge button stack --------------------------------------------------

## Split by ActionRegistry.is_universal — outer column is every vehicle's, the ones beside it
## only this machine's. A group can run to more than one column: past what the band between
## STACK_TOP and the joystick holds, it wraps into a further column instead of running off
## the bottom of the screen.
func _build_button_stack() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(_px(STACK_GAP)))
	row.grow_horizontal = Control.GROW_DIRECTION_END
	row.position = Vector2(_px(10.0), _px(STACK_TOP))
	add_child(row)

	var shell := _shell_signals()
	var vehicle_pads: Array[Pad] = []
	var universal_pads: Array[Pad] = []
	for entry in ActionRegistry.entries():
		var kind: int = entry.get("touch", ActionRegistry.Touch.NONE)
		var pad: Pad = null
		match kind:
			ActionRegistry.Touch.HOLD:
				pad = _hold_button(String(entry["touch_label"]), StringName(entry["poll_key"]))
			ActionRegistry.Touch.TAP:
				pad = _tap_button(String(entry["touch_label"]), StringName(entry["poll_key"]))
			ActionRegistry.Touch.SHELL_SIGNAL:
				if not shell.has(entry["id"]):
					# The registry gained a control this overlay was not taught.
					push_error("touch controls: no shell signal for action row '%s'" % entry["id"])
					continue
				pad = _tap_pad(String(entry["touch_label"]), shell[entry["id"]])
				if entry["id"] == &"day_night":
					# Caption names what the press will do, so it tracks the level's state
					# rather than its own taps (N key, new level).
					_day_night_label = pad.get_child(0) as Label
					_apply_night_caption()
			_:
				continue  # NONE (keyboard only) and WIDGET (built by hand, gated above)
		if ActionRegistry.is_universal(entry):
			universal_pads.append(pad)
		else:
			vehicle_pads.append(pad)
		_gated.append({"node": pad, "id": entry["id"]})

	for col in _columns_for(universal_pads) + _columns_for(vehicle_pads):
		row.add_child(col)


func _on_night_changed(is_night: bool) -> void:
	_is_night = is_night
	_apply_night_caption()


## Names the result of pressing it, not the current state: dark out, it offers DAY.
func _apply_night_caption() -> void:
	if _day_night_label != null:
		_day_night_label.text = "DAY" if _is_night else "NIGHT"


## A method rather than a local so the test suite can check keys against the registry's
## SHELL_SIGNAL rows without building an overlay.
func _shell_signals() -> Dictionary:
	return {
		&"camera_view": func() -> void: camera_pressed.emit(),
		&"day_night": func() -> void: day_night_pressed.emit(),
		&"garage": func() -> void: garage_pressed.emit(),
		&"next_attachment": func() -> void: next_attachment_pressed.emit(),
		&"respawn": func() -> void: respawn_pressed.emit(),
		&"to_menu": func() -> void: menu_pressed.emit(),
	}


## Deal `pads` into as many columns as the band between STACK_TOP and the joystick holds.
## Sized for every pad being visible at once — which ones are gated off changes as you drive.
func _columns_for(pads: Array[Pad]) -> Array[VBoxContainer]:
	var out: Array[VBoxContainer] = []
	if pads.is_empty():
		return out
	var per_col := _capacity
	var col := _stack_column()
	for pad in pads:
		if col.get_child_count() >= per_col:
			out.append(col)
			col = _stack_column()
		col.add_child(pad)
	out.append(col)
	return out


## Measures the viewport, not the overlay's own `size`, which isn't settled on the frame it's built in.
func _column_capacity() -> int:
	var step := _px(maxf(BTN_SIZE.y, UiTheme.TOUCH_MIN)) + _px(STACK_GAP)
	var band := get_viewport_rect().size.y - _px(STACK_TOP) - _px(JOY_RADIUS * 2.0 + EDGE)
	return maxi(1, int(band / step))


func _stack_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(_px(STACK_GAP)))
	return col


# --- widget helpers ----------------------------------------------------------

## Releasing writes 0, and so does hiding the pad mid-press (Pad drops its pointer on losing
## visibility) — stops GAS or HORN sticking when the bridge goes live or F4 hides the overlay.
func _hold_button(text: String, key: StringName) -> Pad:
	_held[key] = 0.0
	return _hold_pad(text, func(down: bool) -> void: _held[key] = 1.0 if down else 0.0)


## An on/off switch, not a pedal: level stays 1.0 until tapped again. Not the toggle-edge form
## (_tap_button) — InputRouter owns that edge's state, while this level is read straight out of
## the merged intent. Amber panel + "HAND ON" caption while engaged, colour and text both.
func _latch_button(text: String, key: StringName) -> Pad:
	_held[key] = 0.0
	var pad := _make_button(text)
	pad.held.connect(func(down: bool) -> void:
		if down:
			_set_latch(pad, text, key, float(_held.get(key, 0.0)) <= 0.0)
	)
	# Gated off, it must not leave the level held down for whatever is driven next.
	pad.visibility_changed.connect(func() -> void:
		if not pad.visible:
			_set_latch(pad, text, key, false)
	)
	return pad


func _set_latch(pad: Pad, text: String, key: StringName, on: bool) -> void:
	_held[key] = 1.0 if on else 0.0
	var label := pad.get_child(0) as Label
	label.text = text + " ON" if on else text
	pad.add_theme_stylebox_override("panel", _ring_style(_px(UiTheme.RADIUS),
			Color(0.62, 0.36, 0.06, 0.92) if on else Color(0.16, 0.18, 0.22, 0.75)))


## Latches a one-shot edge, drained by the next poll(). Fires on the press edge.
func _tap_button(text: String, key: StringName) -> Pad:
	_edges[key] = false
	return _tap_pad(text, func() -> void: _edges[key] = true)


func _hold_pad(text: String, on_change: Callable) -> Pad:
	var b := _make_button(text)
	b.held.connect(func(down: bool) -> void: on_change.call(down))
	return b


func _tap_pad(text: String, on_tap: Callable) -> Pad:
	var b := _make_button(text)
	b.held.connect(func(down: bool) -> void:
		if down:
			on_tap.call()
	)
	return b


func _make_button(text: String) -> Pad:
	var b := Pad.new()
	# Never below the fingertip floor, however small the scale gets.
	b.custom_minimum_size = Vector2(_px(BTN_SIZE.x),
			maxf(_px(BTN_SIZE.y), _px(UiTheme.TOUCH_MIN)))
	b.add_theme_stylebox_override("panel", _ring_style(_px(UiTheme.RADIUS)))
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(label)
	# Pads are bare Panels, so press feedback is ours to draw.
	b.held.connect(func(down: bool) -> void:
		b.modulate = Color(1.5, 1.5, 1.5) if down else Color.WHITE
	)
	return b


func _ring_style(radius: float, color := Color(0.16, 0.18, 0.22, 0.75)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(int(radius))
	return s


## A logical-px metric at the overlay's current UI scale, times the desktop pad multiplier.
func _px(logical: float) -> float:
	return roundf(logical * _scale * _pad_scale)


## How much bigger than the theme scale the widgets are drawn (see PAD_SCALE_REF). 1.0 on any
## touchscreen — there the theme scale's fingertip sizing is already the right answer.
func _compute_pad_scale() -> float:
	if UiScale.is_touch_display():
		return 1.0
	return clampf(UiScale.logical_short_edge(get_window()) / PAD_SCALE_REF, 1.0, PAD_SCALE_MAX)

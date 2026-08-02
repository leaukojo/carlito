class_name TouchControls
extends Control
## On-screen touch controls, registered on the InputRouter as a second local source: a steering
## joystick (bottom-left), gas/brake pedals (bottom-right), and a left-edge button stack. It
## reports raw intents via poll() exactly like local_source.gd — arbitration stays in InputRouter.
## Plain text, no emoji.
##
## THE BUTTON STACK IS GENERATED FROM ActionRegistry, not written here: which buttons exist, what
## they say, when they are shown and which raw-intent key they write all come from that one table,
## which the pause menu's CONTROLS sheet reads too. So a control cannot be on screen without being
## documented, or documented without being reachable. The hand-written stack this replaces had
## drifted to six bound actions with no button at all.
##
## Split into columns by ActionRegistry.is_universal: the outer one is what every vehicle has, the
## ones beside it only what the machine you are driving has. Fifteen buttons in a single column was
## a wall on a phone, and the split is derived from the gate rather than declared, so a button's
## column cannot disagree with whether it is vehicle-specific. Either group wraps into a further
## column when the window is too short to hold it (see _columns_for).
##
## Widgets (joystick, HAND beside it, pedals, flight pads, the ARM/FLAPS/DOORS/LIGHTS/HORN row
## above them and PANTO in the pedal row) are
## still built by hand — they are not stack buttons — but the
## registry decides whether each is shown, so the train loses its steering and only aircraft get
## the UP/DOWN pads without this file naming a family.

signal menu_pressed
signal garage_pressed
signal respawn_pressed
signal next_attachment_pressed
signal camera_pressed
signal day_night_pressed

## Widget metrics in LOGICAL px — every one is put through UiTheme.px before use, so the
## overlay grows with the theme scale. A finger is a fixed physical size, so a phone gets the
## larger targets and a big desktop window does not get a wall of huge pads.
const JOY_RADIUS := 90.0
const KNOB_SIZE := 66.0
const BTN_SIZE := Vector2(96, 44)
const PEDAL_SIZE := Vector2(110, 150)
const FLIGHT_PAD_SIZE := Vector2(110, 68)
const EDGE := 40.0        ## joystick/pedal inset from the window edge
## Where the left-edge button column starts — the same top inset the debug overlay uses on the
## other edge (DebugOverlay._apply_metrics), since nothing sits above it on this side any more.
const STACK_TOP := 10.0
const STACK_GAP := 8.0

## Extra size the overlay takes ON A POINTER DISPLAY ONLY, on top of the theme scale. The theme
## scale is sized for a fingertip, which is a fixed physical size — right on a phone, but on a
## fullscreen desktop it leaves the pads a small island in a huge window, aimed with a mouse that
## has none of a finger's imprecision. So a non-touch display ramps the widgets with the short edge
## up to PAD_SCALE_MAX; a touchscreen keeps 1.0 whatever its resolution, or a big tablet would get
## pads far larger than the hand using them. Ramps from 1.0 at PAD_SCALE_REF logical px.
const PAD_SCALE_REF := 540.0
const PAD_SCALE_MAX := 2.0

var _scale := 1.0  ## cached UI scale; a change to it rebuilds the widgets
var _pad_scale := 1.0  ## cached desktop pad multiplier (see PAD_SCALE_REF); rebuilds the widgets
var _capacity := 0  ## buttons one stack column holds at the size last built for

## Raw intent, keyed by the registry's `poll_key` so poll() is one loop rather than a hand-written
## dict that a new control can be left out of. `_held` carries levels a pad or widget holds down;
## `_edges` carries one-shot toggle edges a tap latches, DRAINED by poll(). Key names match
## local_source.gd's, deliberately: that is what makes InputRouter's toggle owners (_lights, _pto,
## _hitch_up, ...) shared by keyboard and touch rather than duplicated per source.
var _held := {}
var _edges := {}

var _joy_knob: Panel
var _joy_center := Vector2.ZERO
## The joystick's vertical deflection, screen-up positive. NOT written into the intent as it moves
## (see _joy_pitch_into): the pads own those keys, and a joystick release would zero one a second
## thumb is still holding.
var _joy_y := 0.0
## The day/night button's caption and the state it names. Kept across rebuilds (a scale change
## re-creates the label) so the button never comes back saying the opposite of the truth.
var _day_night_label: Label
var _is_night := false
## Everything whose visibility the registry decides: {node, id}. Buttons AND widgets, so the
## per-frame gating is one loop over this rather than a line per control.
var _gated: Array[Dictionary] = []
## The vehicle's capabilities, handed over by the shell (boot.gd _capabilities). The overlay never
## learns what a trailer, an implement or a refuse body is — only that some machines have one, and
## that cycling a semi's trailer can change the answer without changing the body.
var _caps := {}
var _ctx := {}            ## cached ActionRegistry context; rebuilt only when its inputs move
var _ctx_family := ""
var _ctx_bridge := false


## Touch-first press widget. It tracks WHICH pointer is holding it (a finger index, or
## MOUSE for a desktop click) so several pads can be held at the same time. A plain
## Button cannot: on mobile a Button only ever sees the mouse events Godot emulates from
## touch, and that emulation mirrors a single finger — hold GAS and the joystick goes
## deaf. Emulated events (device == DEVICE_ID_EMULATION) are ignored here so a real
## finger is never counted twice.
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

	## A pad hidden or removed mid-press never gets its release event; drop the hold so it
	## cannot stick once it comes back.
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


## Persistent overlay: when UiScale rebuilds the theme at a new scale, rebuild the widgets at
## the new metrics. Held state is dropped by the rebuild, which is the same thing that happens
## when a pad is hidden mid-press (see Pad._notification) and is correct — the finger is no
## longer on the pad that existed.
##
## A RESIZE ALONE CAN ALSO NEED IT, and only for the button stack: the UI scale comes off the
## SHORT edge and is clamped at both ends, so a window can lose the height that decides how many
## buttons a column holds without the scale moving at all — and the desktop pad multiplier comes
## off the same short edge, so it moves on a resize the theme scale sleeps through. Guarded on one
## of the two actually changing, or every drag of a window edge would rebuild the pads under the
## player's finger.
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
		remove_child(c)  # not just queue_free: a deferred free would leave the old pads
		c.queue_free()   # live and pressable for a frame alongside the new ones
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


## Shell gate: show the controls while a level is being played (see _should_show — every config).
func set_active(active: bool) -> void:
	visible = active and _should_show()


## What the active vehicle can do, from the shell (boot.gd _capabilities) — the gate behind the
## capability-keyed registry rows: ATTACH, PTO, TIP, DIFF, MFWD, BODY. Those cannot be family-gated
## the way PANTO and FLAPS are, because within one family the machines disagree: the semi tows and
## the garbage truck does not, only the garbage truck has a body, and cycling a semi's trailer
## swaps a driven one for an undriven one without the body changing. Hence re-called on every
## attachment cycle, not just on a vehicle bind — a stale PTO button is a control that does nothing.
func set_capabilities(caps: Dictionary) -> void:
	_caps = caps
	_ctx = {}  # force the cached gate context to rebuild


## The raw intent dict InputRouter merges with the keyboard each tick (same keys as
## local_source.gd), drained of its one-shot toggle edges. Contributes nothing while hidden: a pad
## hidden mid-press (e.g. F4 while holding GAS) never gets its release, so its held state would
## otherwise leak through merge_local's max and stick.
func poll() -> Dictionary:
	if not visible:
		return {}
	var out := _held.duplicate()
	for k in _edges:
		out[k] = _edges[k]
		_edges[k] = false
	_joy_pitch_into(out)
	return out


## The joystick's vertical axis, folded into the intent an aircraft reads — so a plane or a drone
## is flown with one thumb rather than a thumb per axis. Merged over the pads rather than written
## by _move_knob, exactly as InputRouter.merge_local folds two sources: a stick released while the
## other thumb holds UP or GAS must not zero it.
##
## The two families answer the stick DIFFERENTLY, which is why this is not one axis with a sign:
##   plane - a real yoke, so it is INVERTED: stick back (screen-down) is nose UP.
##   drone - the right stick of a quad: it does not climb, it TILTS. Screen-up leans the nose
##           forward and flies forward, which is the throttle axis (drone.gd reads input.throttle
##           for the commanded tilt), so it rides `accel` / `brake_reverse` and not `climb` at all.
## Gated on the same registry row as the UP/DOWN pads, so the stick cannot fly what they hide.
func _joy_pitch_into(out: Dictionary) -> void:
	if is_zero_approx(_joy_y) or not ActionRegistry.applies(&"climb", _gate_context()):
		return
	if _ctx_family == "drone":
		if _joy_y > 0.0:
			out["accel"] = maxf(float(out.get("accel", 0.0)), _joy_y)
		else:
			out["brake_reverse"] = maxf(float(out.get("brake_reverse", 0.0)), -_joy_y)
		return
	var v := clampf(float(out.get("climb", 0.0)) - _joy_y, -1.0, 1.0)
	out["climb"] = v
	out["elevator"] = v


func _process(_dt: float) -> void:
	var ctx := _gate_context()
	for g in _gated:
		g["node"].visible = ActionRegistry.applies(g["id"], ctx)


## The registry context, rebuilt only when something in it actually moves — the gate runs every
## frame over every widget, and the family and bridge state change a handful of times a session.
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


## The overlay is on by default EVERYWHERE, desktop included: the buttons are the only on-screen
## record of what the machine you are driving can do, and a desktop player has no reason to know
## they exist if they never appear. F4 (toggle_touch) still hides them.
func _should_show() -> bool:
	return true


# --- handbrake (latching) ----------------------------------------------------

## The parking brake, bottom-left beside the steering joystick — deliberately AWAY from the pedal
## cluster and the dashboard, both of which it crowded. It LATCHES: you set a parking brake and
## leave it, so a pad you have to keep a finger on would be the wrong control. Its x is the
## joystick's footprint, not a parent-child relation: the joystick is gated off on the train and
## the handbrake is not.
func _build_handbrake() -> void:
	var pad := _latch_button("HAND", "handbrake")
	var pad_size := Vector2(_px(FLIGHT_PAD_SIZE.x), _px(FLIGHT_PAD_SIZE.y))
	pad.custom_minimum_size = pad_size
	pad.size = pad_size
	pad.anchor_top = 1.0
	pad.anchor_bottom = 1.0
	pad.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pad.position = Vector2(_px(EDGE + JOY_RADIUS * 2.0 + STACK_GAP), -pad_size.y - _px(EDGE))
	add_child(pad)
	_gated.append({"node": pad, "id": &"handbrake"})


# --- joystick (steer, plus the aircraft pitch axis — see _joy_pitch_into) --------------------------------------------------------

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
			_held["steer"] = 0.0
			_joy_y = 0.0
			_reset_knob()
	)
	add_child(base)
	_joy_center = Vector2(radius, radius)
	_held["steer"] = 0.0
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
	_held["steer"] = clampf(offset.x / radius, -1.0, 1.0)  # steering is the horizontal axis
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
	# The whole bottom-right cluster: the LIGHTS/HORN row sits ON TOP of the pedal row rather than
	# beside it, so nothing reaches into the pedals the thumb is aiming at.
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
	row.alignment = BoxContainer.ALIGNMENT_END  # stays against the edge if the row above is wider
	# Same separation as the LIGHTS/HORN row above it, or the two rows do not line up: the pads are
	# the same width, so only the gap between them can push them out of column.
	row.add_theme_constant_override("separation", int(_px(STACK_GAP)))

	var panto := _tap_button("PANTO", "pantograph_toggle")
	panto.custom_minimum_size = pedal
	row.add_child(panto)
	_gated.append({"node": panto, "id": &"pantograph"})

	var brake := _hold_button("BRAKE\nREV", "brake_reverse")
	brake.custom_minimum_size = pedal
	row.add_child(brake)

	var gas := _hold_button("GAS", "accel")
	gas.custom_minimum_size = pedal
	row.add_child(gas)

	# LIGHTS and HORN sit with the pedals rather than in the settings stack: they are used WHILE
	# driving, so they belong under the hand that is already on the gas. Built by hand like the
	# pedals, gated by their registry rows (Touch.WIDGET) exactly as the joystick and flight pads
	# are. Right-aligned over the pedals, so they line up with GAS rather than floating.
	var aux := HBoxContainer.new()
	aux.add_theme_constant_override("separation", int(_px(STACK_GAP)))
	aux.alignment = BoxContainer.ALIGNMENT_END
	# The machine controls used WHILE driving ride this row and the pedal row below it, rather than
	# the settings stack: ARM (drone) / FLAPS (plane) and DOORS beside LIGHTS, PANTO beside BRAKE.
	# They keep the pedal cluster's own pad height, so nothing here stretches GAS or BRAKE. Only one
	# of ARM / FLAPS / DOORS is ever visible — the three families are mutually exclusive.
	var arm := _tap_button("ARM", "arm_toggle")
	arm.custom_minimum_size = Vector2(pedal.x, flight.y)
	aux.add_child(arm)
	_gated.append({"node": arm, "id": &"arm"})
	var flaps := _tap_button("FLAPS", "flaps_toggle")
	flaps.custom_minimum_size = Vector2(pedal.x, flight.y)
	aux.add_child(flaps)
	_gated.append({"node": flaps, "id": &"flaps"})
	var doors := _tap_button("DOORS", "doors_toggle")
	doors.custom_minimum_size = Vector2(pedal.x, flight.y)
	aux.add_child(doors)
	_gated.append({"node": doors, "id": &"doors"})
	var lights := _tap_button("LIGHTS", "lights_cycle")
	lights.custom_minimum_size = Vector2(pedal.x, flight.y)
	aux.add_child(lights)
	_gated.append({"node": lights, "id": &"headlights"})
	var horn := _hold_button("HORN", "horn")
	horn.custom_minimum_size = Vector2(pedal.x, flight.y)
	aux.add_child(horn)
	_gated.append({"node": horn, "id": &"horn"})
	cluster.add_child(aux)
	cluster.add_child(row)

	# Flight vertical pads (plane elevator / drone climb) extend the pedal row leftward. ONE
	# vertical axis published under two keys, exactly as local_source.gd does it: the families are
	# mutually exclusive, so each aircraft reads only its own field.
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
	return float(_held.get("climb", 0.0))


func _set_vert(v: float) -> void:
	_held["climb"] = v
	_held["elevator"] = v


# --- left-edge button stack --------------------------------------------------

## Built entirely from ActionRegistry: order, captions, gating and the raw-intent key each button
## writes all come from the table. Split by ActionRegistry.is_universal — the outer column is what
## every vehicle has, the ones beside it only this machine's, which is what keeps a tractor from
## stacking a dozen buttons down one edge of a phone.
##
## A GROUP CAN RUN TO MORE THAN ONE COLUMN. The stack is pinned between STACK_TOP and the joystick,
## and the number of buttons is not ours to choose — a tractor with an implement declares six of
## its own on top of the seven every machine has. Past what that band holds, a group wraps into a
## further column rather than running off the bottom of the screen, which is what a short window
## used to do (found in the Phase 7 three-sizes sweep — the same class of bug as the tell-tale row
## overflowing sideways, in the other axis).
func _build_button_stack() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(_px(STACK_GAP)))
	# Grows rightward from the left edge, so the outer column stays pinned there however many
	# buttons the machine you are driving puts beside it.
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
				pad = _hold_button(String(entry["touch_label"]), String(entry["poll_key"]))
			ActionRegistry.Touch.TAP:
				pad = _tap_button(String(entry["touch_label"]), String(entry["poll_key"]))
			ActionRegistry.Touch.SHELL_SIGNAL:
				if not shell.has(entry["id"]):
					# A SHELL_SIGNAL row with nothing to emit: the registry gained a control this
					# overlay was not taught. Say so rather than crashing on the missing key.
					push_error("touch controls: no shell signal for action row '%s'" % entry["id"])
					continue
				pad = _tap_pad(String(entry["touch_label"]), shell[entry["id"]])
				if entry["id"] == &"day_night":
					# The one caption that is not fixed: it names what the press will DO, so it
					# tracks the level's state rather than its own taps (N key, new level).
					_day_night_label = pad.get_child(0) as Label
					_apply_night_caption()
			_:
				continue  # NONE (keyboard only) and WIDGET (built by hand, gated above)
		if ActionRegistry.is_universal(entry):
			universal_pads.append(pad)
		else:
			vehicle_pads.append(pad)
		_gated.append({"node": pad, "id": entry["id"]})

	# Universal columns first so they stay outermost, against the left edge.
	for col in _columns_for(universal_pads) + _columns_for(vehicle_pads):
		row.add_child(col)


func _on_night_changed(is_night: bool) -> void:
	_is_night = is_night
	_apply_night_caption()


## The button names the RESULT of pressing it, not the current state: dark out, it offers DAY.
func _apply_night_caption() -> void:
	if _day_night_label != null:
		_day_night_label.text = "DAY" if _is_night else "NIGHT"


## The only place left that knows a shell signal exists, keyed by the registry row it serves.
## Everything else a button can do is a raw-intent key the registry names, so it needs no code
## here at all. A method rather than a local so the test suite can check the keys against the
## registry's SHELL_SIGNAL rows without building an overlay.
func _shell_signals() -> Dictionary:
	return {
		&"camera_view": func() -> void: camera_pressed.emit(),
		&"day_night": func() -> void: day_night_pressed.emit(),
		&"garage": func() -> void: garage_pressed.emit(),
		&"next_attachment": func() -> void: next_attachment_pressed.emit(),
		&"respawn": func() -> void: respawn_pressed.emit(),
		&"to_menu": func() -> void: menu_pressed.emit(),
	}


## Deal `pads` into as many columns as the band between STACK_TOP and the joystick will hold. Sized
## for every pad being visible at once — most are gated off for any one machine, but which ones
## changes as you drive, and a layout that only fits the vehicle you happen to be in is not a
## layout.
func _columns_for(pads: Array[Pad]) -> Array[VBoxContainer]:
	var out: Array[VBoxContainer] = []
	if pads.is_empty():
		return out
	var per_col := _capacity  # measured once per rebuild, in _build_widgets
	var col := _stack_column()
	for pad in pads:
		if col.get_child_count() >= per_col:
			out.append(col)
			col = _stack_column()
		col.add_child(pad)
	out.append(col)
	return out  # the group's FIRST column stays outermost (leftmost); overflow wraps inward


## How many buttons one column of the stack holds: the band between STACK_TOP and the joystick,
## which is what the stack now shares its edge with. The overlay is full-rect but its own `size`
## is not settled on the frame it is built in, so the viewport is what this measures.
func _column_capacity() -> int:
	var step := _px(maxf(BTN_SIZE.y, UiTheme.TOUCH_MIN)) + _px(STACK_GAP)
	var band := get_viewport_rect().size.y - _px(STACK_TOP) - _px(JOY_RADIUS * 2.0 + EDGE)
	return maxi(1, int(band / step))


func _stack_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(_px(STACK_GAP)))
	return col


# --- widget helpers ----------------------------------------------------------

## A pad holding a raw-intent LEVEL down while pressed. Releasing writes 0 — and so does hiding
## the pad mid-press, because Pad drops its pointer on losing visibility and emits the release
## itself. That is what stops GAS or HORN sticking when the bridge goes live or F4 hides the
## overlay, and it is why the held state lives under the pad rather than beside it.
func _hold_button(text: String, key: String) -> Pad:
	_held[key] = 0.0
	return _hold_pad(text, func(down: bool) -> void: _held[key] = 1.0 if down else 0.0)


## A pad holding a raw-intent LEVEL at 1.0 until it is tapped again — an ON/OFF switch rather than
## a pedal. It is NOT the toggle-edge form (_tap_button): those latch an edge InputRouter owns the
## state for, while this level is read straight out of the merged intent, so the pad owning it is
## the whole state. Visual feedback is the pad's own: an amber panel and a "HAND ON" caption while
## engaged, because a latched control that looks like an idle button is a control you leave on by
## accident. Colour AND text, so it does not rely on colour alone.
func _latch_button(text: String, key: String) -> Pad:
	_held[key] = 0.0
	var pad := _make_button(text)
	pad.held.connect(func(down: bool) -> void:
		if down:
			_set_latch(pad, text, key, float(_held.get(key, 0.0)) <= 0.0)
	)
	# Gated off (the bridge takes the control, or the machine has no handbrake) it must not leave
	# the level held down for whatever is driven next.
	pad.visibility_changed.connect(func() -> void:
		if not pad.visible:
			_set_latch(pad, text, key, false)
	)
	return pad


func _set_latch(pad: Pad, text: String, key: String, on: bool) -> void:
	_held[key] = 1.0 if on else 0.0
	var label := pad.get_child(0) as Label
	label.text = text + " ON" if on else text
	pad.add_theme_stylebox_override("panel", _ring_style(_px(UiTheme.RADIUS),
			Color(0.62, 0.36, 0.06, 0.92) if on else Color(0.16, 0.18, 0.22, 0.75)))


## A pad latching a one-shot EDGE, drained by the next poll(). Fires on the press edge — snappier
## than waiting for the release, and the pad has no "click cancelled by sliding off" notion.
func _tap_button(text: String, key: String) -> Pad:
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
	if DisplayServer.is_touchscreen_available():
		return 1.0
	return clampf(UiScale.logical_short_edge(get_window()) / PAD_SCALE_REF, 1.0, PAD_SCALE_MAX)

class_name TouchControls
extends Control
## On-screen touch controls, registered on InputRouter as a second local source. Reports raw
## intents via poll() like local_source.gd — arbitration stays in InputRouter. Plain text, no
## emoji.
##
## Two layers, hidden independently: IMPORTANT (the top-left column every vehicle has — MENU,
## GARAGE, LEVEL, VIEW, CHALLENGE; F5) and DRIVING (joystick and the bottom-right cluster; F4). The cluster
## is three tiers, most-used nearest the thumb: the pedal row (GAS, BRAKE, UP/DOWN, PANTO), one
## QUICK row of short buttons spanning exactly the pedal row's width (LIGHTS, HORN, the family's
## extra, then its safety latch HAND/ARM always above GAS), and the machine's equipment in an
## EQUIP drawer, closed by default, above them. The stack buttons are generated from
## ActionRegistry (captions, gating, raw-intent key all come from that table); `is_universal`
## decides the layer. Widgets (joystick, pedals, flight pads) are hand-built, but the registry
## still decides whether each is shown.
##
## RETRY and INFO join the important column only while a challenge attempt is running
## (`set_challenge_mode`, alongside `set_driving_locked`) — they carry no ActionRegistry row of
## their own, since the registry has no notion of challenge state.

signal menu_pressed
signal garage_pressed
signal level_pressed
signal challenge_pressed
signal next_attachment_pressed
signal camera_pressed
signal retry_pressed
signal info_pressed

## Widget metrics in logical px, put through UiTheme.px before use.
const JOY_RADIUS := 90.0
const KNOB_SIZE := 66.0
const BTN_SIZE := Vector2(96, 44)
## The top-left column. Drawn at the theme scale alone, never DESKTOP_PAD_SCALE: the way out of a
## level stays the easiest thing on screen to hit, on every display.
const MENU_BTN_SIZE := Vector2(128, 56)
## The bottom-right lattice: UP/DOWN pads, the QUICK row's height, EQUIP, every drawer button. A
## pedal spans two rows of it plus the gap between, so the drawer's rows, bottom-aligned beside
## the drive block, line up with DOWN, UP, the QUICK row and EQUIP.
const CELL_SIZE := Vector2(110, 68)
const QUICK_MIN_W := 56.0  ## a QUICK button's floor; the row splits the pedal row's width equally
const EDGE := 40.0        ## joystick/pedal inset from the window edge
const STACK_TOP := 10.0   ## same top inset DebugOverlay uses on the other edge
const STACK_GAP := 8.0
## Shell buttons that head the stack in this order, whatever the registry's order; the rest of
## the universal column follows.
const STACK_HEAD: Array[StringName] = [
	&"to_menu", &"garage", &"level_select", &"camera_view", &"challenge_select",
]

## Size the overlay takes on a pointer display, on top of the theme scale (which is sized for a
## fingertip): a mouse aims far finer, and the keyboard carries every control anyway, so the
## pads give the 3D view back. Touchscreens keep 1.0.
const DESKTOP_PAD_SCALE := 0.8

## Panel colours by tier: the pedals carry colour so they read before their captions do.
const COL_PAD := Color(0.16, 0.18, 0.22, 0.75)
const COL_GAS := Color(0.12, 0.34, 0.18, 0.85)
const COL_BRAKE := Color(0.40, 0.12, 0.11, 0.85)
const COL_ON := Color(0.62, 0.36, 0.06, 0.92)  ## a latched switch (HAND ON, PTO ON), with its caption
const COL_DRAWER := Color(0.14, 0.24, 0.38, 0.85)  ## EQUIP while its drawer is open
const COL_MENU := Color(0.10, 0.12, 0.16, 0.90)  ## the top-left column, under its accent rim
## Keycap rims (UiTheme.keycap) for the coloured panels above; every other pad takes UiTheme.RIM.
const RIM_GAS := Color(0.30, 0.68, 0.40)
const RIM_BRAKE := Color(0.80, 0.30, 0.26)
const RIM_ON := Color(0.90, 0.60, 0.15)

var _scale := 1.0  ## cached UI scale; a change to it rebuilds the widgets
var _pad_scale := 1.0  ## cached desktop pad multiplier (see DESKTOP_PAD_SCALE); rebuilds the widgets
var _capacity := 0  ## buttons one important column holds at the size last built for
var _equip_rows := 0  ## ...and rows the EQUIP drawer holds above the cluster before it widens
## The two layers (see the header), rebuilt with the widgets. Their shown flags outlive a
## rebuild, so a resize never brings back a layer F4/F5 put away; the drawer's open flag too.
var _important: Control
var _driving: Control
var _important_shown := true
var _driving_shown := true
var _equip_open := false
## A challenge is bridge-only: the driving layer stays down whatever F4 says. The important
## column stays, since MENU is the way out.
var _driving_locked := false
## Shown in the important column only while an attempt is running (boot.gd `set_challenge_mode`
## calls, alongside `set_driving_locked`); hidden again once the result panel takes over.
var _challenge_mode := false
var _challenge_pads: Array[Pad] = []
var _pedal_cluster: HBoxContainer  ## bottom-right: the EQUIP drawer, then the drive block
var _drive_block: VBoxContainer  ## EQUIP button, QUICK row, pedal row
var _equip_grid: GridContainer
var _equip_toggle: Pad
var _equip_pads: Array[Pad] = []
## {pad, text, field, on}: switches whose caption shows the router's state (registry `touch_state`)
var _stateful: Array[Dictionary] = []

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
	InputRouter.set_touch_source(self)


## A resize alone can need a rebuild too: the UI scale is clamped at both ends off the short
## edge, so a window can lose the height that decides column capacity without the scale moving.
## Guarded on one of the two actually changing, or every window-edge drag rebuilds the pads.
func _notification(what: int) -> void:
	if not is_inside_tree():
		return
	if what == NOTIFICATION_RESIZED:
		var pads := _compute_pad_scale()
		if is_equal_approx(pads, _pad_scale) and _capacity == _column_capacity() \
				and _equip_rows == _equip_row_capacity():
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
	_equip_pads.clear()
	_challenge_pads.clear()
	_stateful.clear()
	_held.clear()
	_edges.clear()
	_joy_y = 0.0
	_capacity = _column_capacity()
	_equip_rows = _equip_row_capacity()
	_important = _layer(_important_shown)
	_driving = _layer(_driving_shown and not _driving_locked)
	_build_joystick()
	_build_pedals()
	_build_button_stack()


## A full-rect, click-through container; only the pads inside it take input.
func _layer(shown: bool) -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.visible = shown
	add_child(layer)
	return layer


func _exit_tree() -> void:
	InputRouter.clear_touch_source(self)


func set_active(active: bool) -> void:
	visible = active and _should_show()


## Hides the driving layer for a challenge (Pad drops anything held as it hides).
func set_driving_locked(on: bool) -> void:
	_driving_locked = on
	_driving.visible = _driving_shown and not _driving_locked


## RETRY/INFO in the important column: only worth pressing while an attempt is actually
## running, so they hide again once the result panel takes over (boot.gd `_on_challenge_finished`)
## and reappear on a retry.
func set_challenge_mode(on: bool) -> void:
	_challenge_mode = on
	for pad in _challenge_pads:
		pad.visible = on


## Capability-keyed registry rows (ATTACH, PTO, TIP, DIFF, MFWD, BODY) can't be family-gated
## like PANTO/FLAPS: machines within a family disagree (the semi tows, the garbage truck
## doesn't). Re-called on every attachment cycle, not just on vehicle bind.
func set_capabilities(caps: Dictionary) -> void:
	_caps = caps
	_ctx = {}  # force the cached gate context to rebuild


## Drained of its one-shot toggle edges. Contributes nothing while the overlay or its driving
## layer is hidden: a pad hidden mid-press (e.g. F4 while holding GAS) never gets its release,
## so its held state would stick. The important layer writes no intent — its buttons are shell
## signals — so hiding only that one changes nothing here.
func poll() -> Dictionary[StringName, Variant]:
	if not visible or not _driving.visible:
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
	_fit_equip_drawer()
	var vi := InputRouter.get_vehicle_input()
	for s in _stateful:
		var on := bool(vi.get(s["field"]))
		if on != s["on"]:
			s["on"] = on
			_show_on(s["pad"], s["text"], on)


## EQUIP appears only while the drawer has something in it; the grid holds `_equip_rows` rows
## and widens leftward past that. Counted from what is visible NOW, so a machine's buttons sit
## packed rather than in the slots of buttons it does not have.
func _fit_equip_drawer() -> void:
	var n := 0
	for p in _equip_pads:
		if p.visible:
			n += 1
	_equip_toggle.visible = n > 0
	var cols := maxi(1, ceili(float(n) / float(_equip_rows)))
	if cols != _equip_grid.columns:
		_equip_grid.columns = cols


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
		_driving_shown = not _driving_shown
		_driving.visible = _driving_shown and not _driving_locked
	elif event.is_action_pressed("toggle_important"):
		_important_shown = not _important_shown
		_important.visible = _important_shown


## On by default everywhere, desktop included. F4 (toggle_touch) hides the driving layer, F5
## (toggle_important) the important one.
func _should_show() -> bool:
	return true


# --- handbrake (latching) ----------------------------------------------------

## Latches (a parking brake stays set). Sits at the QUICK row's GAS end, so the left side
## holds only the joystick.
func _build_handbrake() -> Pad:
	var pad := _latch_button("HAND", &"handbrake")
	_gated.append({"node": pad, "id": &"handbrake"})
	return pad


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
	_driving.add_child(base)
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


# --- pedals (gas / brake+reverse, the QUICK row, flight pads) -----------------

## The cluster is an HBox: the EQUIP drawer (built with the stack buttons) on the left, bottom-
## aligned, and the drive block on the right — EQUIP button, QUICK row, pedal row. The drive
## block is sized by its pedal row alone, so the QUICK row spans exactly the pedals whatever the
## family, and an open drawer never pushes the pedals off where the thumb expects them.
func _build_pedals() -> void:
	var edge := _px(EDGE)
	var gap := int(_px(STACK_GAP))
	var flight := _cell()
	var pedal := Vector2(flight.x, flight.y * 2.0 + gap)
	var cluster := HBoxContainer.new()
	cluster.add_theme_constant_override("separation", gap)
	cluster.anchor_left = 1.0
	cluster.anchor_right = 1.0
	cluster.anchor_top = 1.0
	cluster.anchor_bottom = 1.0
	cluster.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cluster.grow_vertical = Control.GROW_DIRECTION_BEGIN
	cluster.position = Vector2(-edge, -edge)
	_driving.add_child(cluster)
	_pedal_cluster = cluster

	var drive := VBoxContainer.new()
	drive.add_theme_constant_override("separation", gap)
	drive.size_flags_vertical = Control.SIZE_SHRINK_END
	cluster.add_child(drive)
	_drive_block = drive

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", gap)

	var panto := _tap_button("PANTO", &"pantograph_toggle")
	panto.custom_minimum_size = pedal
	row.add_child(panto)
	_gated.append({"node": panto, "id": &"pantograph"})
	_track_state(panto, "PANTO", &"pantograph")

	var brake := _hold_button("BRAKE\nREV", &"brake_reverse")
	brake.custom_minimum_size = pedal
	brake.add_theme_stylebox_override("panel", _pad_style(COL_BRAKE, RIM_BRAKE))
	row.add_child(brake)

	var gas := _hold_button("GAS", &"accel")
	gas.custom_minimum_size = pedal
	gas.add_theme_stylebox_override("panel", _pad_style(COL_GAS, RIM_GAS))
	row.add_child(gas)

	# QUICK: used while driving, so it sits on the pedals rather than in the EQUIP drawer. Same
	# order on every machine — LIGHTS, HORN, the family's extra (MODE / FLAPS / DOORS), then the
	# safety latch (HAND / ARM) above GAS. The families make each slot hold at most one button.
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", gap)
	var lights := _tap_button("LIGHTS", &"lights_cycle")
	_gated.append({"node": lights, "id": &"headlights"})
	var horn := _hold_button("HORN", &"horn")
	_gated.append({"node": horn, "id": &"horn"})
	# Cycles the ladder rather than latching; the cluster's MODE chip is the FC's own answer.
	var mode := _tap_button("MODE", &"flight_mode_cycle")
	_gated.append({"node": mode, "id": &"flight_mode"})
	var flaps := _tap_button("FLAPS", &"flaps_toggle")
	_gated.append({"node": flaps, "id": &"flaps"})
	_track_state(flaps, "FLAPS", &"flaps")
	var doors := _tap_button("DOORS", &"doors_toggle")
	_gated.append({"node": doors, "id": &"doors"})
	_track_state(doors, "DOORS", &"doors")
	var arm := _tap_button("ARM", &"arm_toggle")
	_gated.append({"node": arm, "id": &"arm"})
	_track_state(arm, "ARM", &"arm")
	for pad: Pad in [lights, horn, mode, flaps, doors, _build_handbrake(), arm]:
		pad.custom_minimum_size = Vector2(_px(QUICK_MIN_W), flight.y)
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quick.add_child(pad)
	drive.add_child(quick)
	drive.add_child(row)

	# One vertical axis published under two keys (plane elevator / drone climb), like local_source.gd.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", gap)
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


# --- button stacks -------------------------------------------------------------

## Split by ActionRegistry.is_universal: every vehicle's buttons go top-left on the important
## layer; this machine's own go in the EQUIP drawer beside the pedals. The important column
## wraps into a further column past what its band holds; the drawer widens leftward instead.
func _build_button_stack() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(_px(STACK_GAP)))
	row.grow_horizontal = Control.GROW_DIRECTION_END
	row.position = Vector2(_px(10.0), _px(STACK_TOP))
	_important.add_child(row)

	var shell := _shell_signals()
	var vehicle_pads: Array[Pad] = []
	var universal_pads: Array[Pad] = []
	var head_pads := {}  ## STACK_HEAD id -> pad
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
			_:
				continue  # NONE (keyboard only) and WIDGET (built by hand, gated above)
		_track_state(pad, String(entry["touch_label"]), entry["id"])
		if STACK_HEAD.has(entry["id"]):
			head_pads[entry["id"]] = pad
			_style_menu_button(pad)
		elif ActionRegistry.is_universal(entry):
			universal_pads.append(pad)
			_style_menu_button(pad)
		else:
			vehicle_pads.append(pad)
		_gated.append({"node": pad, "id": entry["id"]})

	# RETRY/INFO: challenge-only, so gated by `_challenge_mode` rather than an ActionRegistry
	# row (the registry knows families/capabilities, never challenge state) — kept off `_gated`
	# for the same reason, or the per-frame gating loop would hide them as an unknown id.
	var retry_pad := _tap_pad("RETRY", func() -> void: retry_pressed.emit())
	var info_pad := _tap_pad("INFO", func() -> void: info_pressed.emit())
	for pad: Pad in [retry_pad, info_pad]:
		_style_menu_button(pad)
		pad.visible = _challenge_mode
		_challenge_pads.append(pad)

	var ordered: Array[Pad] = []
	for id: StringName in STACK_HEAD:
		if head_pads.has(id):
			ordered.append(head_pads[id])
	ordered.append(retry_pad)
	ordered.append(info_pad)
	for col in _columns_for(ordered + universal_pads, _capacity):
		row.add_child(col)
	for pad in vehicle_pads:
		pad.custom_minimum_size = _cell()

	# A GridContainer lays out only its visible children, so a machine's buttons pack together;
	# `_fit_equip_drawer` sets the column count from how many there are.
	var gap := int(_px(STACK_GAP))
	_equip_grid = GridContainer.new()
	_equip_grid.add_theme_constant_override("h_separation", gap)
	_equip_grid.add_theme_constant_override("v_separation", gap)
	_equip_grid.size_flags_vertical = Control.SIZE_SHRINK_END
	_equip_grid.visible = _equip_open
	for pad in vehicle_pads:
		_equip_grid.add_child(pad)
	_equip_pads = vehicle_pads
	_pedal_cluster.add_child(_equip_grid)
	_pedal_cluster.move_child(_equip_grid, 0)

	_equip_toggle = _tap_pad("EQUIP", func() -> void:
		_equip_open = not _equip_open
		_equip_grid.visible = _equip_open
		_show_equip_toggle()
	)
	_equip_toggle.custom_minimum_size = _cell()
	_equip_toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	_show_equip_toggle()
	_drive_block.add_child(_equip_toggle)
	_drive_block.move_child(_equip_toggle, 0)
	_fit_equip_drawer()


## The top-left column: a keycap at the theme scale, on a more opaque panel than the driving pads.
func _style_menu_button(pad: Pad) -> void:
	pad.custom_minimum_size = Vector2(_ui_px(MENU_BTN_SIZE.x), _ui_px(MENU_BTN_SIZE.y))
	pad.add_theme_stylebox_override("panel", UiTheme.keycap(COL_MENU, UiTheme.RIM, _scale))
	(pad.get_child(0) as Label).add_theme_font_size_override("font_size",
			int(_ui_px(UiTheme.FS_TITLE)))


## Caption and colour both say whether the drawer is open (no emoji arrows: the font has none).
func _show_equip_toggle() -> void:
	(_equip_toggle.get_child(0) as Label).text = "CLOSE" if _equip_open else "EQUIP"
	_equip_toggle.add_theme_stylebox_override("panel", _pad_style(COL_DRAWER, UiTheme.ACCENT)
			if _equip_open else _pad_style(COL_PAD))


## A method rather than a local so the test suite can check keys against the registry's
## SHELL_SIGNAL rows without building an overlay.
func _shell_signals() -> Dictionary:
	return {
		&"camera_view": func() -> void: camera_pressed.emit(),
		&"garage": func() -> void: garage_pressed.emit(),
		&"level_select": func() -> void: level_pressed.emit(),
		&"challenge_select": func() -> void: challenge_pressed.emit(),
		&"next_attachment": func() -> void: next_attachment_pressed.emit(),
		&"to_menu": func() -> void: menu_pressed.emit(),
	}


## Deal `pads` into columns of `per_col`. Sized for every pad being visible at once — which
## ones are gated off changes as you drive.
func _columns_for(pads: Array[Pad], per_col: int) -> Array[VBoxContainer]:
	var out: Array[VBoxContainer] = []
	if pads.is_empty():
		return out
	var col := _stack_column()
	for pad in pads:
		if col.get_child_count() >= per_col:
			out.append(col)
			col = _stack_column()
		col.add_child(pad)
	out.append(col)
	return out


## Buttons per important column: the band between STACK_TOP and the joystick. Measures the
## viewport, not the overlay's own `size`, which isn't settled on the frame it's built in.
func _column_capacity() -> int:
	var band := get_viewport_rect().size.y - _px(STACK_TOP) - _px(JOY_RADIUS * 2.0 + EDGE)
	return maxi(1, int(band / (_ui_px(MENU_BTN_SIZE.y) + _px(STACK_GAP))))


## Rows the EQUIP drawer holds: it stands beside the drive block, bottom-aligned with the
## pedals, so its band runs from the bottom EDGE up to STACK_TOP.
func _equip_row_capacity() -> int:
	var step := _cell().y + _px(STACK_GAP)
	var band := get_viewport_rect().size.y - _px(STACK_TOP) - _px(EDGE) + _px(STACK_GAP)
	return maxi(1, int(band / step))


## One lattice cell (CELL_SIZE), never under the fingertip floor.
func _cell() -> Vector2:
	return Vector2(_px(CELL_SIZE.x), maxf(_px(CELL_SIZE.y), _px(UiTheme.TOUCH_MIN)))


## A logical-px metric at the theme scale alone — what the top-left column is sized in.
func _ui_px(logical: float) -> float:
	return roundf(logical * _scale)


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
	_show_on(pad, text, on)


## One look for every engaged switch: amber panel and an " ON" caption, colour and text both.
func _show_on(pad: Pad, text: String, on: bool) -> void:
	(pad.get_child(0) as Label).text = text + " ON" if on else text
	pad.add_theme_stylebox_override("panel", _pad_style(COL_ON, RIM_ON) if on else _pad_style(COL_PAD))


## A tap switch whose state InputRouter owns shows it, read back from the merged VehicleInput
## field its registry row names (`touch_state`) — the router's toggle, not a copy kept here.
func _track_state(pad: Pad, text: String, id: StringName) -> void:
	var field := String(ActionRegistry.find(id).get("touch_state", ""))
	if field != "":
		_stateful.append({"pad": pad, "text": text, "field": StringName(field), "on": false})


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
	b.add_theme_stylebox_override("panel", _pad_style(COL_PAD))
	var label := Label.new()
	label.text = text
	# Sized with the pads, not the theme, so a caption keeps fitting its pad at DESKTOP_PAD_SCALE.
	label.add_theme_font_size_override("font_size", int(_px(UiTheme.FS_BODY)))
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


## A pad's keycap (UiTheme.keycap) at the pads' own scale, desktop multiplier included.
func _pad_style(color: Color, rim := UiTheme.RIM) -> StyleBoxFlat:
	return UiTheme.keycap(color, rim, _scale * _pad_scale)


## The joystick's flat disc: a ring to thumb, not a key to press.
func _ring_style(radius: float, color := COL_PAD) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(int(radius))
	return s


## A logical-px metric at the overlay's current UI scale, times the desktop pad multiplier.
func _px(logical: float) -> float:
	return roundf(logical * _scale * _pad_scale)


## The widgets' size relative to the theme scale (see DESKTOP_PAD_SCALE). 1.0 on any
## touchscreen — there the theme scale's fingertip sizing is already the right answer.
func _compute_pad_scale() -> float:
	return 1.0 if UiScale.is_touch_display() else DESKTOP_PAD_SCALE

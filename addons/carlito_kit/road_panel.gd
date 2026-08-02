@tool
extends VBoxContainer
## Road-draw panel: the inspector-side toggle for the draw-on-terrain road tool.
## Off/Draw mode buttons only — clearance lives on the RoadPath node itself
## (draw_clearance), matching where a ScatterCanvas keeps its knobs. UI only; the
## viewport/edit logic lives in road_draw_tool.gd (the editor/runtime split).
## Modes are index-matched to the plugin's expectation (0 = Off, 1 = Draw).

signal mode_changed(mode: int)
signal close_requested
signal smooth_corners_changed(on: bool)
signal snap_ports_changed(on: bool)
signal snap_ends_requested
signal reverse_requested
signal draw_submode_changed(mode: int)
signal angle_snap_changed(step_deg: float)
signal rail_toggled(on: bool)

const MODE_LABELS := ["Off", "Draw"]
const SUBMODE_LABELS := ["Free", "Straight", "Arc"]
const SUBMODE_TOOLTIPS := [
	"Each click appends a point; Smooth corners Catmull-Rom-smooths the previous one.",
	"Each click appends an exact straight segment (zero handles). Corners sharper "
			+ "than the fold limit are refused - draw those as arcs.",
	"Circular arc: click start, tangent direction, end. A start point with an "
			+ "out-handle (a previous arc) reuses it as the tangent; right-click "
			+ "re-picks a pending tangent.",
]
const SNAP_STEPS := [0.0, 45.0, 15.0]
const SNAP_LABELS := ["Off", "45°", "15°"]

var _status: Label
var _mode_group := ButtonGroup.new()
var _mode_buttons: Array[Button] = []
var _submode_group := ButtonGroup.new()
var _submode_buttons: Array[Button] = []
var _submode := 0
var _angle_snap: OptionButton
var _radius: Label
var _smooth: CheckBox
var _snap_ports: CheckBox
var _rail: CheckBox
var _close: Button
var _snap_ends: Button
var _reverse: Button
var _has_road := false


func _init() -> void:
	name = "Roads"
	add_theme_constant_override("separation", 6)
	_build()
	set_has_road(false)


func _build() -> void:
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	var heading := Label.new()
	heading.text = "Mode"
	heading.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	add_child(heading)

	var row := HBoxContainer.new()
	add_child(row)
	for i in MODE_LABELS.size():
		var b := Button.new()
		b.text = MODE_LABELS[i]
		b.toggle_mode = true
		b.button_group = _mode_group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == 0:
			b.button_pressed = true
		b.pressed.connect(func(): mode_changed.emit(i))
		_mode_buttons.append(b)
		row.add_child(b)

	var shape_heading := Label.new()
	shape_heading.text = "Draw shape"
	shape_heading.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	add_child(shape_heading)

	var shape_row := HBoxContainer.new()
	add_child(shape_row)
	for i in SUBMODE_LABELS.size():
		var b := Button.new()
		b.text = SUBMODE_LABELS[i]
		b.tooltip_text = SUBMODE_TOOLTIPS[i]
		b.toggle_mode = true
		b.button_group = _submode_group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == 0:
			b.button_pressed = true
		b.pressed.connect(func():
			_submode = i
			draw_submode_changed.emit(i)
			_update_smooth_enabled())
		_submode_buttons.append(b)
		shape_row.add_child(b)

	var snap_row := HBoxContainer.new()
	add_child(snap_row)
	var snap_label := Label.new()
	snap_label.text = "Angle snap"
	snap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	snap_row.add_child(snap_label)
	_angle_snap = OptionButton.new()
	for s in SNAP_LABELS:
		_angle_snap.add_item(s)
	_angle_snap.tooltip_text = "Snap Straight/Arc directions to this heading step."
	_angle_snap.item_selected.connect(func(i: int): angle_snap_changed.emit(SNAP_STEPS[i]))
	snap_row.add_child(_angle_snap)

	_radius = Label.new()
	_radius.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_radius)
	set_radius_display("", false)

	_smooth = CheckBox.new()
	_smooth.text = "Smooth corners (Free)"
	_smooth.button_pressed = true
	_smooth.tooltip_text = "Give each drawn point Catmull-Rom handles. Off: the road " \
			+ "follows the clicks exactly, with angled connections at the corners."
	_smooth.toggled.connect(func(on: bool): smooth_corners_changed.emit(on))
	add_child(_smooth)

	_snap_ports = CheckBox.new()
	_snap_ports.text = "Snap to ports"
	_snap_ports.button_pressed = true
	_snap_ports.tooltip_text = "Drawn end points near an open city-tile edge — or " \
			+ "another RoadPath's endpoint — capture onto it with the tangent locked " \
			+ "along the outward face/road direction (a seamless join); arriving at " \
			+ "one ends the draw."
	_snap_ports.toggled.connect(func(on: bool): snap_ports_changed.emit(on))
	add_child(_snap_ports)

	_rail = CheckBox.new()
	_rail.text = "Rail"
	_rail.tooltip_text = "Swap this road's profile to the rail preset (ballast + two " \
			+ "rails); unticking restores the profile it replaced (the city default if " \
			+ "this session doesn't remember one). Everything else — Draw, Drape, " \
			+ "Smooth, Conform, the bake — works the same either way; a rail is just a " \
			+ "road with a different cross-section."
	_rail.toggled.connect(func(on: bool): rail_toggled.emit(on))
	add_child(_rail)

	_close = Button.new()
	_close.text = "Close loop"
	_close.tooltip_text = "Append a point on the first point with a smooth seam, then exit Draw."
	_close.pressed.connect(func(): close_requested.emit())
	add_child(_close)

	_snap_ends = Button.new()
	_snap_ends.text = "Snap ends to ports"
	_snap_ends.tooltip_text = "Snap the road's first/last points to the nearest open " \
			+ "tile port (within 6 m) and lock their tangents — the fixup after " \
			+ "dragging an end with the gizmo. One undo step."
	_snap_ends.pressed.connect(func(): snap_ends_requested.emit())
	add_child(_snap_ends)

	_reverse = Button.new()
	_reverse.text = "Reverse direction"
	_reverse.tooltip_text = "Reverse the curve's point order so Draw continues from " \
			+ "the other end (the ribbon itself is unchanged). One undo step."
	_reverse.pressed.connect(func(): reverse_requested.emit())
	add_child(_reverse)

	var hint := Label.new()
	hint.text = "Select a RoadPath, pick Draw, then click the ground in the 3D view " \
			+ "to append curve points (each click is one undo step). Shapes: Free " \
			+ "smooths as you click, Straight adds exact chords, Arc is start / " \
			+ "tangent / end (chained arcs reuse the previous end tangent; " \
			+ "right-click re-picks a pending tangent). The ghost shows the ribbon " \
			+ "edges and turns red when the turn is too tight to extrude. " \
			+ "Right-click or Escape exits; Close loop joins the road back to its " \
			+ "first point. Clearance is draw_clearance on the node; Drape and " \
			+ "Conform buttons are on its inspector."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.add_theme_font_size_override("font_size", 11)
	add_child(hint)


# ------------------------------------------------------------------ plugin API

## Draw-tool feedback on the status line (refused clicks). Empty restores the ready
## text — the tool emits "" after every successful commit.
func show_warning(text: String) -> void:
	if text.is_empty():
		_status.text = "RoadPath selected — ready to draw."
		_status.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	else:
		_status.text = text
		_status.add_theme_color_override("font_color", Color(0.95, 0.6, 0.3))


## Live min-turn-radius readout from the draw ghost ("" = idle; warn tints red).
func set_radius_display(text: String, warn: bool) -> void:
	if text.is_empty():
		_radius.text = "min radius: —"
		_radius.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	else:
		_radius.text = text
		_radius.add_theme_color_override("font_color",
				Color(0.95, 0.4, 0.3) if warn else Color(0.75, 0.75, 0.75))


## Reflect a tool-driven exit (RMB/Escape) without re-emitting mode_changed — the
## plugin already knows (programmatic button_pressed doesn't emit `pressed`).
func show_off() -> void:
	if not _mode_buttons.is_empty():
		_mode_buttons[0].button_pressed = true


## Reflect the selected road's profile. set_pressed_no_signal, NOT button_pressed:
## unlike `pressed`, `toggled` DOES fire on a programmatic set, and that would swap the
## profile of the road the user just selected.
func set_rail(on: bool) -> void:
	_rail.set_pressed_no_signal(on)


func _update_smooth_enabled() -> void:
	_smooth.disabled = not _has_road or _submode != 0


func set_has_road(has: bool) -> void:
	_has_road = has
	for b in _mode_buttons:
		b.disabled = not has
	for b in _submode_buttons:
		b.disabled = not has
	_angle_snap.disabled = not has
	_update_smooth_enabled()
	_snap_ports.disabled = not has
	_rail.disabled = not has
	_close.disabled = not has
	_snap_ends.disabled = not has
	_reverse.disabled = not has
	set_radius_display("", false)
	if has:
		_status.text = "RoadPath selected — ready to draw."
		_status.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	else:
		_status.text = "No RoadPath selected."
		_status.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4))
		# Snap back to Off so a stale mode can't act on the next selected road (the
		# scatter panel pattern: programmatic button_pressed doesn't emit, so emit).
		if not _mode_buttons.is_empty() and not _mode_buttons[0].button_pressed:
			_mode_buttons[0].button_pressed = true
			mode_changed.emit(0)

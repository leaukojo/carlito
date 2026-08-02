@tool
extends VBoxContainer
## Terrain-brush panel: the inspector-side controls for the
## sculpt/paint brush. Mode buttons, radius/strength/falloff spinners, a brush shape picker,
## and mode-specific rows that appear only in the mode they serve (the flatten target, the
## ramp hint, the paint channel + fill bucket) — so the panel stays scannable. UI only: the
## viewport/edit logic lives in terrain_brush.gd (the editor/runtime split). Modes are
## index-matched to terrain_brush.gd's enum (0 = Off .. 6 = Paint).

signal mode_changed(mode: int)
signal channel_changed(channel: int)
signal params_changed(radius: float, strength: float, falloff: float)
signal flatten_changed(fixed: bool, height: float, step: float)
signal pick_requested()
signal shape_changed(square: bool)
signal grid_snap_changed(on: bool)
signal fill_requested()

const MODE_LABELS := ["Off", "Raise", "Lower", "Smooth", "Flatten", "Ramp", "Paint"]
const MODE_TOOLTIPS := [
	"Brush disabled. Click another mode to start editing.",
	"Drag in the 3D view to pull the ground up. Hold Ctrl to push down instead, " \
			+ "Shift to smooth.",
	"Drag in the 3D view to push the ground down. Hold Ctrl to pull up instead, " \
			+ "Shift to smooth.",
	"Averages out bumps and jaggies. Use it to soften an area you overdid.",
	"Levels the ground to the height where your drag STARTED — good for building pads " \
			+ "and fields. (Smooth rounds things; Flatten makes them level.) " \
			+ "Hold Shift to smooth.",
	"Click a start point and an end point to cut a straight, even slope between them — " \
			+ "the way onto a plateau. The brush size sets how wide it is.",
	"Colors the ground with the selected channel instead of changing its shape.",
]
# Named because the buttons are index-matched to the brush enum: adding a mode shifts every
# index after it, and these are the places that care.
const MODE_OFF := 0
const MODE_FLATTEN := 4
const MODE_RAMP := 5
const MODE_PAINT := 6
const CHANNEL_COUNT := 8
const SWATCH_PX := 14
## The roads palette cell is 12 x 3 x 12 m, so a 12 m square brush stamps exactly one cell
## and a 3 m snap step matches its vertical spacing.
const GRIDMAP_CELL_M := 12.0

var _status: Label
var _mode_group := ButtonGroup.new()
var _mode_buttons: Array[Button] = []
var _channel_box: OptionButton
var _channel_row: HBoxContainer
var _fill_row: HBoxContainer
var _flatten_box: VBoxContainer
var _fixed_check: CheckBox
var _fixed_height: SpinBox
var _snap_step: SpinBox
var _ramp_hint: Label
var _shape_row: HBoxContainer
var _shape_box: OptionButton
var _snap_grid_row: HBoxContainer
var _snap_grid_check: CheckBox
var _radius: SpinBox
var _strength: SpinBox
var _falloff: SpinBox


func _init() -> void:
	name = "Terrain"
	add_theme_constant_override("separation", 6)
	_build()
	set_has_terrain(false)


func _build() -> void:
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	add_child(_heading("Mode"))
	var grid := GridContainer.new()
	grid.columns = 3
	add_child(grid)
	for i in MODE_LABELS.size():
		var b := Button.new()
		b.text = MODE_LABELS[i]
		b.toggle_mode = true
		b.button_group = _mode_group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = MODE_TOOLTIPS[i]
		if i == 0:
			b.button_pressed = true
		b.pressed.connect(func(): mode_changed.emit(i))
		_mode_buttons.append(b)
		grid.add_child(b)

	_build_flatten_box()

	_ramp_hint = Label.new()
	_ramp_hint.text = "Click the start, then the end. Right-click cancels."
	_ramp_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ramp_hint.add_theme_color_override("font_color", Color(0.85, 0.55, 1.0))  # the ramp cursor's tint
	add_child(_ramp_hint)

	_channel_row = HBoxContainer.new()
	add_child(_channel_row)
	var ch_label := Label.new()
	ch_label.text = "Channel"
	ch_label.tooltip_text = "Which ground color to paint."
	_channel_row.add_child(ch_label)
	_channel_box = OptionButton.new()
	_channel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_channel_box.tooltip_text = "Which ground color to paint. Names and colors are the " \
			+ "terrain's own — rename them on the node, recolor them on its material."
	_channel_box.item_selected.connect(func(i): channel_changed.emit(i))
	_channel_row.add_child(_channel_box)
	set_channels(HeightmapTerrain.default_channel_names(), PackedColorArray())

	_fill_row = HBoxContainer.new()
	add_child(_fill_row)
	var fill_btn := Button.new()
	fill_btn.text = "Fill entire terrain"
	fill_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill_btn.tooltip_text = "Paints the whole terrain the selected channel in one go, " \
			+ "wiping every other color. Strength and edge softness are ignored — a fill " \
			+ "is a fill. Undoable."
	fill_btn.pressed.connect(func(): fill_requested.emit())
	_fill_row.add_child(fill_btn)

	add_child(HSeparator.new())
	_radius = _spinner("Radius", 0.5, 512.0, 0.5, 8.0,
			"Brush size in meters. The car is 1.8 m long; a two-lane road is ~12 m wide. " \
			+ "[ and ] change it while brushing.")
	_strength = _spinner("Strength", 0.0, 1.0, 0.05, 0.5,
			"How much each stroke changes things. Low = gentle passes, high = fast.")
	_falloff = _spinner("Edge softness", 0.0, 1.0, 0.05, 0.5,
			"How the effect fades toward the brush rim. 0 = hard-edged stamp, " \
			+ "1 = smooth dome that fades from the center.")
	_build_shape_row()
	_build_snap_grid_row()

	var hint := Label.new()
	hint.text = "Select a HeightmapTerrain, pick a mode, then drag in the 3D view.\n" \
			+ "[ and ] shrink / grow the brush. Ctrl inverts, Shift smooths."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.add_theme_font_size_override("font_size", 11)
	add_child(hint)

	_show_rows(MODE_OFF)


## Flatten's target controls: level to a height you type (or eyedrop off the ground) instead
## of wherever the drag happened to start, optionally quantized.
func _build_flatten_box() -> void:
	_flatten_box = VBoxContainer.new()
	add_child(_flatten_box)

	var row := HBoxContainer.new()
	_flatten_box.add_child(row)
	_fixed_check = CheckBox.new()
	_fixed_check.text = "Fixed height"
	_fixed_check.tooltip_text = "Off: level to the height where your drag starts.\n" \
			+ "On: level to exactly this height (world Y, in meters), wherever you drag.\n" \
			+ "Note the heightmap stores 8-bit heights, so the result quantizes to steps of " \
			+ "the terrain's height / 255."
	_fixed_check.toggled.connect(func(_on): _emit_flatten())
	row.add_child(_fixed_check)
	_fixed_height = SpinBox.new()
	_fixed_height.min_value = -1000.0
	_fixed_height.max_value = 1000.0
	_fixed_height.step = 0.1
	_fixed_height.suffix = "m"
	_fixed_height.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fixed_height.tooltip_text = _fixed_check.tooltip_text
	_fixed_height.value_changed.connect(func(_v): _emit_flatten())
	row.add_child(_fixed_height)
	var pick := Button.new()
	pick.text = "Pick"
	pick.tooltip_text = "Eyedropper: click a spot in the 3D view to copy its height into " \
			+ "the field (that click won't edit anything). Turns on Fixed height."
	pick.pressed.connect(func(): pick_requested.emit())
	row.add_child(pick)

	var snap_row := HBoxContainer.new()
	_flatten_box.add_child(snap_row)
	var snap_label := Label.new()
	snap_label.text = "Snap step"
	snap_label.custom_minimum_size = Vector2(70, 0)
	snap_row.add_child(snap_label)
	_snap_step = SpinBox.new()
	_snap_step.min_value = 0.0
	_snap_step.max_value = 100.0
	_snap_step.step = 0.5
	_snap_step.suffix = "m"
	_snap_step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_snap_step.tooltip_text = "Rounds the flatten height to a multiple of this (0 = off), " \
			+ "so neighbouring pads land at heights that match. 3 = the road GridMap's " \
			+ "vertical cell size."
	snap_label.tooltip_text = _snap_step.tooltip_text
	_snap_step.value_changed.connect(func(_v): _emit_flatten())
	snap_row.add_child(_snap_step)


## Brush footprint + the one-click GridMap-cell preset.
func _build_shape_row() -> void:
	_shape_row = HBoxContainer.new()
	add_child(_shape_row)
	var label := Label.new()
	label.text = "Shape"
	label.custom_minimum_size = Vector2(70, 0)
	label.tooltip_text = "Round is the general-purpose brush; Square stamps pads that meet " \
			+ "flush, with no scalloped edges between passes."
	_shape_row.add_child(label)
	_shape_box = OptionButton.new()
	_shape_box.add_item("Round")
	_shape_box.add_item("Square")
	_shape_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shape_box.tooltip_text = label.tooltip_text
	_shape_box.item_selected.connect(func(i): shape_changed.emit(i == 1))
	_shape_row.add_child(_shape_box)
	var preset := Button.new()
	preset.text = "12 m (GridMap cell)"
	preset.tooltip_text = "Sets a 12 m square brush — exactly one road GridMap cell, so a " \
			+ "flattened pad lines up with the tiles you drop on it."
	preset.pressed.connect(_use_gridmap_cell)
	_shape_row.add_child(preset)


## Snap the brush onto the road GridMap's cell lattice — so you don't have to aim each stamp
## onto a cell. Applies to every editing mode.
func _build_snap_grid_row() -> void:
	_snap_grid_row = HBoxContainer.new()
	add_child(_snap_grid_row)
	_snap_grid_check = CheckBox.new()
	_snap_grid_check.text = "Snap to grid"
	_snap_grid_check.tooltip_text = "Locks the brush centre onto the road GridMap's cells " \
			+ "(12 m), so pads and ramps line up with the tiles you drop on them. With no " \
			+ "road GridMap placed yet, it snaps to a 12 m grid at the origin. Also sets " \
			+ "Flatten's snap step to the cell height."
	_snap_grid_check.toggled.connect(func(on): grid_snap_changed.emit(on))
	_snap_grid_row.add_child(_snap_grid_check)


## The GridMap-cell preset: a square, hard-edged brush whose footprint is exactly one 12 m
## cell, snapped to the lattice — the align-to-GridMap workflow in one click. Edge softness
## goes to 0 so abutting cells tile flush (a soft rim fades to nothing and leaves a seam).
func _use_gridmap_cell() -> void:
	_shape_box.select(1)
	shape_changed.emit(true)
	_falloff.set_value_no_signal(0.0)
	_radius.value = GRIDMAP_CELL_M * 0.5  # value_changed re-emits params (radius + the falloff)
	_snap_grid_check.set_pressed_no_signal(true)
	grid_snap_changed.emit(true)



func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	return l


func _spinner(label: String, lo: float, hi: float, step: float, value: float,
		tooltip: String) -> SpinBox:
	var row := HBoxContainer.new()
	add_child(row)
	var l := Label.new()
	l.text = label
	l.tooltip_text = tooltip
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = value
	sb.tooltip_text = tooltip
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.value_changed.connect(func(_v): _emit_params())
	row.add_child(sb)
	return sb


func _emit_params() -> void:
	params_changed.emit(_radius.value, _strength.value, _falloff.value)


func _emit_flatten() -> void:
	flatten_changed.emit(_fixed_check.button_pressed, _fixed_height.value, _snap_step.value)


## Show only the rows that belong to `mode` — the panel's whole scannability trick. Shape is
## the exception: it applies to every stamping mode, so it hides only for Off and Ramp (whose
## width comes from the radius but whose shape is its own swept form).
func _show_rows(mode: int) -> void:
	_flatten_box.visible = mode == MODE_FLATTEN
	_ramp_hint.visible = mode == MODE_RAMP
	_channel_row.visible = mode == MODE_PAINT
	_fill_row.visible = mode == MODE_PAINT
	_shape_row.visible = mode != MODE_OFF and mode != MODE_RAMP
	_snap_grid_row.visible = mode != MODE_OFF


# ------------------------------------------------------------------ plugin API

## Called by the plugin when a mode button is pressed, so the panel can reveal that mode's
## controls (the flatten target, the ramp hint, the channel picker + fill).
func on_mode(mode: int) -> void:
	_show_rows(mode)


## The eyedropper landed: show the sampled height and switch Flatten onto it, since picking a
## height you then don't use would be a no-op the author has to chase.
func set_picked_height(y: float) -> void:
	_fixed_height.set_block_signals(true)
	_fixed_height.value = y
	_fixed_height.set_block_signals(false)
	_fixed_check.set_pressed_no_signal(true)
	_emit_flatten()


## Fill the channel picker from the selected terrain: its eight display names, each with a
## swatch of that channel's color (both are per-level data — see HeightmapTerrain). Pass an
## empty `colors` for a plain, iconless list. The selection survives the refill, so
## re-selecting a terrain never silently switches which channel the brush paints.
func set_channels(names: PackedStringArray, colors: PackedColorArray) -> void:
	var selected := maxi(_channel_box.selected, 0)
	_channel_box.clear()
	for i in CHANNEL_COUNT:
		var label: String = HeightmapTerrain.DEFAULT_CHANNEL_NAMES[i]
		if i < names.size() and not names[i].is_empty():
			label = names[i]
		if i < colors.size():
			_channel_box.add_icon_item(_swatch(colors[i]), label)
		else:
			_channel_box.add_item(label)
	_channel_box.select(mini(selected, CHANNEL_COUNT - 1))


## A flat color chip, used as a channel's icon in the picker.
func _swatch(color: Color) -> ImageTexture:
	var img := Image.create(SWATCH_PX, SWATCH_PX, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## Set the flatten vertical snap step (metres) and push it to the brush — called when snap-to-
## grid turns on, so pads also land on the GridMap's height cells. Stays editable afterward.
func set_snap_step(m: float) -> void:
	_snap_step.value = m  # value_changed re-emits flatten_changed


## Reflect a bracket-key radius change without re-emitting params_changed.
func set_radius_display(r: float) -> void:
	_radius.set_block_signals(true)
	_radius.value = r
	_radius.set_block_signals(false)


func set_has_terrain(has: bool) -> void:
	for b in _mode_buttons:
		b.disabled = not has
	_channel_box.disabled = not has
	if has:
		_status.text = "Terrain selected — ready to brush."
		_status.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	else:
		_status.text = "No HeightmapTerrain selected."
		_status.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4))
		# Snap back to Off so a stale mode can't act on the next selected terrain.
		# Setting button_pressed programmatically does NOT emit `pressed`, so emit
		# mode_changed ourselves — otherwise the brush keeps its old mode and would
		# sculpt the next selected terrain even though the panel reads "Off".
		if not _mode_buttons.is_empty() and not _mode_buttons[0].button_pressed:
			_mode_buttons[0].button_pressed = true
			_show_rows(MODE_OFF)
			mode_changed.emit(MODE_OFF)

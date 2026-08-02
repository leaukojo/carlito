@tool
extends VBoxContainer
## Scatter-brush panel: the inspector-side controls for the
## paint/erase scatter brush. Mode buttons (Off/Paint/Erase) and a Radius spinner. UI only — the
## viewport/edit logic lives in scatter_brush.gd (the editor/runtime split). Density, spacing,
## and the yaw/scale/slope jitter knobs live on the selected ScatterCanvas node itself (its
## inspector), matching where a ScatterRegion keeps them. Modes are index-matched to
## scatter_brush.gd's enum (0 = Off, 1 = Paint, 2 = Erase).

signal mode_changed(mode: int)
signal radius_changed(radius: float)

const MODE_LABELS := ["Off", "Paint", "Erase", "Rect"]

var _status: Label
var _mode_group := ButtonGroup.new()
var _mode_buttons: Array[Button] = []
var _radius: SpinBox


func _init() -> void:
	name = "Scatter"
	add_theme_constant_override("separation", 6)
	_build()
	set_has_canvas(false)


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

	add_child(HSeparator.new())
	var rrow := HBoxContainer.new()
	add_child(rrow)
	var rl := Label.new()
	rl.text = "Radius"
	rl.custom_minimum_size = Vector2(70, 0)
	rrow.add_child(rl)
	_radius = SpinBox.new()
	_radius.min_value = 0.5
	_radius.max_value = 512.0
	_radius.step = 0.5
	_radius.value = 8.0
	_radius.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_radius.value_changed.connect(func(v): radius_changed.emit(v))
	rrow.add_child(_radius)

	var hint := Label.new()
	hint.text = "Select a ScatterCanvas, pick Paint, then drag in the 3D view.\n" \
			+ "[ and ] shrink / grow the brush. Density, spacing and jitter are on the " \
			+ "canvas node's inspector.\n" \
			+ "Rect: click two corners to fill that area (Esc or right-click cancels); the " \
			+ "area is filled at whatever height the ground is under it.\n" \
			+ "Set the canvas's Paint Pattern to \"grid\" for lattice placement (corn rows, " \
			+ "grass patches) — Grid Step replaces density and spacing, and the lattice is " \
			+ "world-anchored so Paint and Rect continue the same grid."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.add_theme_font_size_override("font_size", 11)
	add_child(hint)


# ------------------------------------------------------------------ plugin API

## Reflect a bracket-key radius change without re-emitting radius_changed.
func set_radius_display(r: float) -> void:
	_radius.set_block_signals(true)
	_radius.value = r
	_radius.set_block_signals(false)


func set_has_canvas(has: bool) -> void:
	for b in _mode_buttons:
		b.disabled = not has
	if has:
		_status.text = "ScatterCanvas selected — ready to paint."
		_status.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	else:
		_status.text = "No ScatterCanvas selected."
		_status.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4))
		# Snap back to Off so a stale mode can't act on the next selected canvas (mirrors the
		# terrain brush panel: programmatic button_pressed doesn't emit `pressed`, so emit).
		if not _mode_buttons.is_empty() and not _mode_buttons[0].button_pressed:
			_mode_buttons[0].button_pressed = true
			mode_changed.emit(0)

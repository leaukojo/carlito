class_name PadDiagram
extends Control
## A generic two-stick gamepad drawn in code, each control's callout generated from ActionRegistry
## for the current vehicle (`callouts`): the plain set, or with `layer` the set L1 holds, read
## from `ActionRegistry.pad_layer_rows` as the L1 legend is. The position names the button, so an
## Xbox and a PlayStation pad read alike. A callout the bridge owns right now is greyed, as its row
## is on the sheet. The CONTROLS sheet falls back to its text column (PadLayer.SLOT_NAMES) where
## `needed_width` does not fit. Theme colours, no image asset; not focusable. No emoji.

## Where each control sits, in pad units (100 wide, x right, y down). Keys are PadLayer.BUTTONS'
## slot names plus L1, the triggers and the sticks; a stick's press shares its stick's spot
## (`STICK_PRESS`). Under x 50 is the left half, whose callouts go left.
const SPOTS := {
	"l2": Vector2(20, 3), "l1": Vector2(20, 10.5), "r2": Vector2(80, 3), "r1": Vector2(80, 10.5),
	"dpad_up": Vector2(24, 22), "dpad_down": Vector2(24, 34),
	"dpad_left": Vector2(18, 28), "dpad_right": Vector2(30, 28),
	"triangle": Vector2(76, 22), "cross": Vector2(76, 34),
	"square": Vector2(70, 28), "circle": Vector2(82, 28),
	"create": Vector2(40, 22), "options": Vector2(60, 22),
	"l_stick": Vector2(37, 44), "r_stick": Vector2(63, 44),
}
## A stick's press -> the stick it presses.
const STICK_PRESS := {"l3": "l_stick", "r3": "r_stick"}
## `ActionRegistry.pad_axes` names -> spot; a typed `pad_axis` matches by its start
## ("Left stick up / down").
const AXIS_SPOTS := {"Left stick": "l_stick", "Right stick": "r_stick", "L2": "l2", "R2": "r2"}
## A stick's press reads "Press: Horn" under the stick's own callout.
const PRESS_PREFIX := "Press: "
## L1's callout on the plain set when the vehicle has an L1 layer.
const LAYER_HINT := "Hold: the L1 set"

const PAD_W := 300.0     ## logical px, the pad's drawn width
const PAD_UNITS := 100.0
const PAD_BOTTOM := 61.0  ## pad units: the grips' lowest point
const COLUMN_GAP := 28.0  ## logical px between the pad and a callout column
const LINE_GAP := 3.0     ## logical px between two callout blocks
const STROKE := 1.5       ## logical px

## Each callout: {spot, text, entry}; `entry` is {} for the L1 hint.
var _callouts: Array[Dictionary] = []
var _ctx := {}
var _layer := false
## Laid out by `_layout` at the current scale: per spot, its block's text top-left in px.
var _blocks := {}
var _unit := 1.0
var _origin := Vector2.ZERO
var _line_h := 0.0
var _font_size := 0


## What to draw: the plain set for `ctx` (ActionRegistry.context), or with `layer` the L1 set.
func setup(ctx: Dictionary, layer: bool) -> void:
	_ctx = ctx
	_layer = layer
	_callouts = callouts(ctx, layer)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if is_inside_tree():
		_layout()


## Each control's callouts in `ctx`: {spot, text, entry}, in ActionRegistry order. The plain set
## is every row the vehicle can use (`relevant_entry`) on an unlayered button or an axis, plus
## L1's hint when the layer is not empty; the L1 set is `ActionRegistry.pad_layer_rows`, the L1
## legend's own list.
static func callouts(ctx: Dictionary, layer: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var layer_rows := ActionRegistry.pad_layer_rows(ctx)
	if layer:
		for entry in layer_rows:
			for slot: String in entry.get("pad", []):
				if slot.begins_with(PadLayer.LAYER_PREFIX):
					_add(out, slot.trim_prefix(PadLayer.LAYER_PREFIX), entry)
		return out
	for entry in ActionRegistry.entries():
		if not ActionRegistry.relevant_entry(entry, ctx):
			continue
		for slot: String in entry.get("pad", []):
			if not slot.begins_with(PadLayer.LAYER_PREFIX):
				_add(out, slot, entry)
		for axis in ActionRegistry.pad_axes(entry):
			for prefix: String in AXIS_SPOTS:
				if axis.begins_with(prefix):
					_add(out, String(AXIS_SPOTS[prefix]), entry)
	if not layer_rows.is_empty():
		out.append({"spot": "l1", "text": LAYER_HINT, "entry": {}})
	return out


static func _add(out: Array[Dictionary], slot: String, entry: Dictionary) -> void:
	var text := String(entry["label"])
	if STICK_PRESS.has(slot):
		text = PRESS_PREFIX + text
	var spot := String(STICK_PRESS.get(slot, slot))
	for c in out:
		if c["spot"] == spot and c["text"] == text:
			return  # a row on both directions of one stick
	out.append({"spot": spot, "text": text, "entry": entry})


## Why each greyed callout is greyed (ActionRegistry.gate_note), once each, for the sheet's line
## under the diagram.
func greyed_notes() -> PackedStringArray:
	var notes := PackedStringArray()
	for c in _callouts:
		var note := _note(c)
		if note != "" and not notes.has(note):
			notes.append(note)
	return notes


## The width the diagram needs at the current scale, for the sheet's fit test.
func needed_width() -> float:
	_layout()
	return custom_minimum_size.x


func _ready() -> void:
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_inside_tree():
		_layout()


func _note(c: Dictionary) -> String:
	var entry: Dictionary = c["entry"]
	return "" if entry.is_empty() else ActionRegistry.gate_note(entry, _ctx)


func _font() -> Font:
	return get_theme_font(&"font", &"Label")


## Callout blocks (one per spot, a line per callout) sit in a column each side of the pad, each
## level with its control or pushed down below the block above; the pad is centred between two
## equal columns so the drawing stays centred on the sheet.
func _layout() -> void:
	_font_size = get_theme_font_size(&"font_size", &"Dim")
	var font := _font()
	_line_h = font.get_height(_font_size)
	_unit = UiTheme.px(self, PAD_W) / PAD_UNITS
	var gap := UiTheme.px(self, COLUMN_GAP)
	var lines := {}  ## spot -> its texts (an Array: a PackedStringArray read out is a copy)
	var column_w := 0.0
	for c in _callouts:
		var spot: String = c["spot"]
		if not lines.has(spot):
			lines[spot] = []
		(lines[spot] as Array).append(String(c["text"]))
		column_w = maxf(column_w, font.get_string_size(String(c["text"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x)
	_origin = Vector2(column_w + gap, _line_h * 0.5)
	var bottom := _origin.y + PAD_BOTTOM * _unit
	_blocks.clear()
	for left in [true, false]:
		var side: Array = lines.keys().filter(func(s: String) -> bool:
			return (SPOTS[s].x < 50.0) == left)
		# Top to bottom; level spots nearest their column first, so leader lines do not cross.
		side.sort_custom(func(a: String, b: String) -> bool:
			var pa: Vector2 = SPOTS[a]
			var pb: Vector2 = SPOTS[b]
			if pa.y != pb.y:
				return pa.y < pb.y
			return (pa.x < pb.x) == left)
		var next_top := 0.0
		for spot: String in side:
			var h := _line_h * (lines[spot] as Array).size()
			var top := maxf(_spot_px(spot).y - h * 0.5, next_top)
			var x := 0.0 if left else _origin.x + PAD_UNITS * _unit + gap
			_blocks[spot] = {"pos": Vector2(x, top), "lines": lines[spot], "w": column_w,
					"left": left}
			next_top = top + h + UiTheme.px(self, LINE_GAP)
			bottom = maxf(bottom, top + h)
	custom_minimum_size = Vector2(2.0 * (column_w + gap) + PAD_UNITS * _unit, ceilf(bottom))
	queue_redraw()


func _spot_px(spot: String) -> Vector2:
	return _origin + (SPOTS[spot] as Vector2) * _unit


func _draw() -> void:
	var stroke := maxf(1.0, UiTheme.px(self, STROKE))
	var used := {}  ## spot -> some callout there applies (true) or all are greyed (false)
	for c in _callouts:
		used[c["spot"]] = bool(used.get(c["spot"], false)) or _note(c) == ""
	_draw_body(stroke, used)
	for spot: String in ["dpad_up", "dpad_down", "dpad_left", "dpad_right"]:
		_draw_key(Rect2(_spot_px(spot) - Vector2(2.6, 2.6) * _unit, Vector2(5.2, 5.2) * _unit),
				spot, used, stroke, 0.8)
	for spot: String in ["triangle", "cross", "square", "circle"]:
		_draw_round_key(spot, 3.2, used, stroke)
	for spot: String in ["create", "options"]:
		_draw_key(Rect2(_spot_px(spot) - Vector2(2.6, 1.6) * _unit, Vector2(5.2, 3.2) * _unit),
				spot, used, stroke, 1.6)
	for spot: String in ["l_stick", "r_stick"]:
		draw_circle(_spot_px(spot), 6.5 * _unit, UiTheme.SURFACE_LO)
		draw_arc(_spot_px(spot), 6.5 * _unit, 0.0, TAU, 40, UiTheme.BORDER, stroke, true)
		_draw_round_key(spot, 4.4, used, stroke)
	_draw_callouts(stroke)


## Shoulders behind the shell, then the shell: a border pass grown by the stroke and a fill pass
## over it, so the bar and the two grips read as one outline.
func _draw_body(stroke: float, used: Dictionary) -> void:
	for spot: String in ["l2", "r2"]:
		_draw_key(Rect2(_spot_px(spot) - Vector2(8, 3) * _unit, Vector2(16, 6) * _unit),
				spot, used, stroke, 2.5)
	for spot: String in ["l1", "r1"]:
		_draw_key(Rect2(_spot_px(spot) - Vector2(9, 2.5) * _unit, Vector2(18, 5) * _unit),
				spot, used, stroke, 2.5)
	var bar := Rect2(_origin + Vector2(8, 14) * _unit, Vector2(84, 32) * _unit)
	var grips := [_origin + Vector2(23, 46) * _unit, _origin + Vector2(77, 46) * _unit]
	var grip_r := 15.0 * _unit
	for pass_i in 2:
		var grow := stroke if pass_i == 0 else 0.0
		var color := UiTheme.BORDER if pass_i == 0 else UiTheme.SURFACE
		draw_style_box(_box(color, Color.TRANSPARENT, 0.0, 12.0 * _unit + grow), bar.grow(grow))
		for g: Vector2 in grips:
			draw_circle(g, grip_r + grow, color)


func _draw_key(rect: Rect2, spot: String, used: Dictionary, stroke: float,
		radius_units: float) -> void:
	var colors := _key_colors(spot, used)
	draw_style_box(_box(colors[0], colors[1], stroke, radius_units * _unit), rect)


func _draw_round_key(spot: String, radius_units: float, used: Dictionary, stroke: float) -> void:
	var colors := _key_colors(spot, used)
	draw_circle(_spot_px(spot), radius_units * _unit, colors[0])
	draw_arc(_spot_px(spot), radius_units * _unit, 0.0, TAU, 32, colors[1], stroke, true)


## [fill, rim]: L1 held on the L1 set in the accent; a control with a live callout raised; one
## whose callouts are all greyed, or that has none, recessed.
func _key_colors(spot: String, used: Dictionary) -> PackedColorArray:
	if _layer and spot == "l1":
		return PackedColorArray([UiTheme.ACCENT, UiTheme.ACCENT])
	if bool(used.get(spot, false)):
		return PackedColorArray([UiTheme.SURFACE_HI, UiTheme.TEXT_DIM])
	return PackedColorArray([UiTheme.SURFACE_LO, UiTheme.BORDER])


func _draw_callouts(stroke: float) -> void:
	var font := _font()
	var ascent := font.get_ascent(_font_size)
	var lit := {}  ## text -> its callout applies
	for c in _callouts:
		lit[c["text"]] = _note(c) == ""
	for spot: String in _blocks:
		var block: Dictionary = _blocks[spot]
		var pos: Vector2 = block["pos"]
		var left: bool = block["left"]
		var block_lines: Array = block["lines"]
		var mid := pos.y + _line_h * block_lines.size() * 0.5
		var gap := UiTheme.px(self, COLUMN_GAP)
		var end := Vector2(pos.x + float(block["w"]) + gap * 0.25 if left else pos.x - gap * 0.25,
				mid)
		draw_line(end, _spot_px(spot), UiTheme.TEXT_MUTED, stroke, true)
		draw_circle(_spot_px(spot), stroke * 1.5, UiTheme.TEXT_MUTED)
		for i in block_lines.size():
			var text := String(block_lines[i])
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
			var x := pos.x + float(block["w"]) - w if left else pos.x
			draw_string(font, Vector2(x, pos.y + _line_h * i + ascent), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size,
					UiTheme.TEXT if bool(lit[text]) else UiTheme.TEXT_MUTED)


static func _box(bg: Color, rim: Color, width: float, radius: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = rim
	s.set_border_width_all(int(roundf(width)))
	s.set_corner_radius_all(int(roundf(radius)))
	s.anti_aliasing = true
	return s

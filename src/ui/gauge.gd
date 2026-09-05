class_name Gauge
extends Control
## Hand-built radial gauge. Exactly two on the dash (speedometer, tachometer), one bespoke
## widget instanced twice. The dashboard configures min/max and redline from the contract and
## feeds `value` every frame.
##
## Geometry: a 270° arc with the 90° gap at the bottom (min at 7:30, clockwise to max at 4:30).
## Gauge text lives in that gap so the needle never crosses it. Plain text + color only, no emoji.

const START_DEG := 135.0  ## min value, lower-left (7:30) — draw_arc angle, y-down screen space
const SWEEP_DEG := 270.0  ## clockwise to lower-right (4:30)

const TRACK_COLOR := Color(0.30, 0.32, 0.36)
const REDLINE_COLOR := Color(0.90, 0.20, 0.16)
const TICK_COLOR := Color(0.55, 0.58, 0.63)
const NEEDLE_COLOR := Color(0.92, 0.94, 0.98)
const VALUE_COLOR := Color(0.95, 0.96, 1.0)
const UNITS_COLOR := Color(0.60, 0.63, 0.68)

var min_value := 0.0
var max_value := 100.0
var redline := NAN         ## value where the red zone starts; NAN = no redline
var units := ""            ## drawn small under the number (e.g. "km/h")
var caption := ""          ## drawn above center (e.g. "RPM x1000") — static label
var major_ticks := 8
var value := 0.0: set = _set_value
var center_text := "": set = _set_center_text  ## overrides the number when non-empty (e.g. gear)


func _set_value(v: float) -> void:
	value = v
	queue_redraw()


func _set_center_text(t: String) -> void:
	if t == center_text:
		return
	center_text = t
	queue_redraw()


func _norm(v: float) -> float:
	if max_value <= min_value:
		return 0.0
	return clampf((v - min_value) / (max_value - min_value), 0.0, 1.0)


## Point on the dial at normalized position `n` (0=min, 1=max) at the given radius.
func _point(center: Vector2, n: float, radius: float) -> Vector2:
	var t := deg_to_rad(START_DEG + SWEEP_DEG * n)
	return center + Vector2(cos(t), sin(t)) * radius


## Redraw when the UI scale changes: every stroke width and font size below is in logical px
## scaled through the theme, so a resize that rebuilds the theme has to reach the canvas.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	# Stroke widths and text are logical px through the theme scale; the dial geometry stays
	# proportional to the widget, which the dashboard already sizes in the same units.
	var s := UiTheme.scale_of(self)
	var center := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 6.0 * s
	var start := deg_to_rad(START_DEG)
	var end := deg_to_rad(START_DEG + SWEEP_DEG)

	draw_arc(center, r, start, end, 96, TRACK_COLOR, 5.0 * s, true)

	if not is_nan(redline):
		var nr := _norm(redline)
		draw_arc(center, r, deg_to_rad(START_DEG + SWEEP_DEG * nr), end, 48, REDLINE_COLOR, 5.0 * s, true)

	for i in major_ticks + 1:
		var n := float(i) / major_ticks
		draw_line(_point(center, n, r - 9.0 * s), _point(center, n, r), TICK_COLOR, 2.0 * s)

	var needle_col := NEEDLE_COLOR
	if not is_nan(redline) and value >= redline:
		needle_col = REDLINE_COLOR
	draw_line(center, _point(center, _norm(value), r * 0.80), needle_col, 3.0 * s)
	draw_circle(center, 5.0 * s, needle_col)

	var font := get_theme_default_font()
	var small := int(UiTheme.px(self, 11.0))
	if not caption.is_empty():
		_draw_centered(font, center + Vector2(0.0, -r * 0.38), caption, small, UNITS_COLOR)
	# Value / gear text in the bottom gap.
	var big := center_text if not center_text.is_empty() else str(roundi(value))
	_draw_centered(font, center + Vector2(0.0, r * 0.44), big, int(UiTheme.px(self, 22.0)), VALUE_COLOR)
	if center_text.is_empty() and not units.is_empty():
		_draw_centered(font, center + Vector2(0.0, r * 0.44 + 15.0 * s), units, small, UNITS_COLOR)


func _draw_centered(font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(font, at - Vector2(w * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

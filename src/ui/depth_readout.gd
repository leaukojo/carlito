class_name DepthReadout
extends Control
## Hand-built echo sounder, built like Gauge and AttitudeIndicator: one instance, shown only
## where the vehicle declares 'depth' (boat), configured from that signal's contract metadata
## and fed the reading per frame.
##
## IT EXISTS FOR THE SENTINEL. 'depth' publishes -1 with no bottom under the transducer and the
## contract puts that value INSIDE the range so the bar and the bridge agree on it — which on a
## generated bar pins the fill at the low end of a LOW-side warn and reads as a permanent shoal
## alarm over open water. Here the sentinel BLANKS the number to "---" instead of colouring it,
## and it is taken from the contract's own range floor rather than typed in, so the two cannot
## drift apart. Everything below the sentinel is likewise not a depth.
##
## The scale starts at 0 rather than at the range floor: a water column has no negative side,
## and the reading is under-keel clearance from the probe plane the hull floats on.
##
## Plain text + color only, no emoji.

const TRACK_COLOR := Color(0.20, 0.22, 0.26)
const WATER_COLOR := Color(0.24, 0.48, 0.68)
const WARN_COLOR := Color(0.90, 0.35, 0.18)
const BED_COLOR := Color(0.62, 0.52, 0.34)
const TEXT_COLOR := Color(0.95, 0.96, 1.0)
const MUTED_COLOR := Color(0.55, 0.58, 0.63)

const TRACK_W := 16.0     ## logical px, the water column's width
const BLANK := "---"      ## what an invalid sounding reads as

var value := 0.0: set = _set_value  ## m under the transducer, contract 'depth'
var max_value := 10.0     ## scale bottom, contract range[1]
var invalid := -1.0       ## contract range[0]: at or below this there is no bottom
var warn := NAN           ## shoal threshold; NAN = none
var warn_is_low := true   ## contract warn_side; low is the dangerous side for water
var caption := ""


func _set_value(v: float) -> void:
	value = v
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


# --- pure logic (unit-tested) -------------------------------------------------

## No bottom under the transducer. At OR below the sentinel, because a sounding is clamped at 0
## and nothing legitimate can land under the range floor.
static func is_invalid(v: float, sentinel: float) -> bool:
	return v <= sentinel + 0.001


## The DashBar comparison, except that an invalid reading is never an alarm — which is the whole
## reason this widget exists.
static func in_warn(v: float, threshold: float, is_low: bool, sentinel: float) -> bool:
	if is_nan(threshold) or is_invalid(v, sentinel):
		return false
	return v <= threshold if is_low else v >= threshold


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	var s := UiTheme.scale_of(self)
	var font := get_theme_default_font()
	var bad := is_invalid(value, invalid)
	var alarm := in_warn(value, warn, warn_is_low, invalid)

	var small := int(UiTheme.px(self, 10.0))
	if not caption.is_empty():
		_draw_centered(font, Vector2(size.x * 0.5, 12.0 * s), caption, small, MUTED_COLOR)

	# The water column: the surface at the top, the bed where the sounding says it is.
	var top := 22.0 * s
	var bottom := size.y - 40.0 * s
	var track := Rect2(size.x * 0.5 - TRACK_W * 0.5 * s, top, TRACK_W * s, maxf(bottom - top, 1.0))
	draw_rect(track, TRACK_COLOR)
	if not bad and max_value > 0.0:
		var n := clampf(value / max_value, 0.0, 1.0)
		var bed_y := track.position.y + track.size.y * n
		draw_rect(Rect2(track.position, Vector2(track.size.x, bed_y - track.position.y)),
				WARN_COLOR if alarm else WATER_COLOR)
		draw_line(Vector2(track.position.x - 3.0 * s, bed_y),
				Vector2(track.end.x + 3.0 * s, bed_y), BED_COLOR, 2.0 * s)
	# The shoal threshold, drawn whatever the reading — a static mark, like DashBar's warn tick.
	if not is_nan(warn) and max_value > 0.0:
		var wy := track.position.y + track.size.y * clampf(warn / max_value, 0.0, 1.0)
		draw_line(Vector2(track.position.x - 5.0 * s, wy), Vector2(track.end.x + 5.0 * s, wy),
				WARN_COLOR, 1.5 * s)

	var text := BLANK if bad else "%.1f" % value
	var col := MUTED_COLOR if bad else (WARN_COLOR if alarm else TEXT_COLOR)
	_draw_centered(font, Vector2(size.x * 0.5, size.y - 20.0 * s), text,
			int(UiTheme.px(self, 20.0)), col)
	_draw_centered(font, Vector2(size.x * 0.5, size.y - 6.0 * s), "m", small, MUTED_COLOR)


func _draw_centered(font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(font, at - Vector2(w * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			font_size, color)

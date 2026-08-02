class_name DashBar
extends Control
## Labeled horizontal bar for one ranged signal on the dashboard. The dashboard
## *generates* one of these per contract "out" signal that carries both a range and a
## 'warn' threshold ("the bars are generated from contract signal metadata —
## name, range, warn thresholds"). Everything here is driven by that metadata; there is
## no per-signal special-casing.
##
## Plain text + color only — no emoji.

const TRACK_COLOR := Color(0.20, 0.22, 0.26)
const FILL_COLOR := Color(0.42, 0.68, 0.55)
const WARN_COLOR := Color(0.90, 0.35, 0.18)
const LABEL_COLOR := Color(0.72, 0.75, 0.80)
const VALUE_COLOR := Color(0.92, 0.94, 0.98)

const LABEL_W := 58.0   ## logical px reserved on the left for the caption
const VALUE_W := 52.0   ## logical px reserved on the right for the number

var label := ""
var units := ""
var min_value := 0.0
var max_value := 100.0
var warn := NAN         ## danger threshold; NAN = no warn band
var warn_is_low := false  ## true: warn when value <= warn (low fuel); false: value >= warn
var value := 0.0: set = _set_value


func _set_value(v: float) -> void:
	value = v
	queue_redraw()


func _in_warn() -> bool:
	if is_nan(warn):
		return false
	return value <= warn if warn_is_low else value >= warn


## Redraw when the UI scale changes — the metrics below are logical px through the theme.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	# Everything here is a logical-px metric scaled through the theme, so the bar keeps its
	# proportions against the text beside it at any UI scale.
	var s := UiTheme.scale_of(self)
	var font := get_theme_default_font()
	var fs := int(UiTheme.px(self, 13.0))
	var label_w := LABEL_W * s
	var value_w := VALUE_W * s
	var mid := size.y * 0.5
	draw_string(font, Vector2(0.0, mid + 5.0 * s), label, HORIZONTAL_ALIGNMENT_LEFT, label_w, fs, LABEL_COLOR)

	var track := Rect2(label_w, mid - 5.0 * s, size.x - label_w - value_w, 10.0 * s)
	draw_rect(track, TRACK_COLOR)

	var span := max_value - min_value
	var n := clampf((value - min_value) / span, 0.0, 1.0) if span > 0.0 else 0.0
	var fill := Rect2(track.position, Vector2(track.size.x * n, track.size.y))
	draw_rect(fill, WARN_COLOR if _in_warn() else FILL_COLOR)

	# warn tick on the track
	if not is_nan(warn) and span > 0.0:
		var wn := clampf((warn - min_value) / span, 0.0, 1.0)
		var wx := track.position.x + track.size.x * wn
		draw_line(Vector2(wx, track.position.y - 2.0 * s), Vector2(wx, track.end.y + 2.0 * s),
				WARN_COLOR, 1.5 * s)

	var txt := "%d%s" % [roundi(value), units]
	var col := WARN_COLOR if _in_warn() else VALUE_COLOR
	draw_string(font, Vector2(size.x - value_w, mid + 5.0 * s), txt,
			HORIZONTAL_ALIGNMENT_RIGHT, value_w, fs, col)

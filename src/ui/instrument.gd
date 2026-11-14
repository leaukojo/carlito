class_name Instrument
extends Control
## A cluster instrument fed one `value` per frame (Gauge, DashBar, DepthReadout): it redraws only
## when the value moves. Also the cluster's one centred-text draw, for any instrument.
## It draws the value as given, with no lag or held number: a reading that flickers shows the sim
## flickering. A real sender's filter is a labelled model on the signal, with a sourced figure
## (`test_no_instrument_smooths_its_value`).

var value := 0.0: set = _set_value


func _set_value(v: float) -> void:
	if v == value:
		return
	value = v
	queue_redraw()


## Draw `text` on `ci` centred horizontally on `at` (baseline at `at.y`).
static func draw_centered(ci: CanvasItem, font: Font, at: Vector2, text: String, font_size: int,
		color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	ci.draw_string(font, at - Vector2(w * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			font_size, color)

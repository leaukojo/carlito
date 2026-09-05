class_name NoticeLine
extends Label
## The sim's transient message line ("no room to couple"), raised by GameState.notice and
## dwelled/hidden by the shell. Red on a dark panel, centred, plain text, no emoji — colour
## is semantic, so it's a node override rather than theme. Sits above screen middle, not the
## top edge, so it isn't missed while watching the road.
##
## Lays itself out rather than fixed boot.tscn offsets: those clipped against the Title
## font's theme-scaled height, and a full-width line ran under the touch overlay's buttons.
## The inset stays symmetric (line is centred) — insetting only the button side would knock
## text off-centre everywhere to buy clearance on one edge.

## Top edge, as a share of screen height. Above the middle so it doesn't cover the vehicle.
const TOP_RATIO := 0.34
## Logical px (scaled). Padding inside the box; also the floor the line height is measured against.
const TOP := 14.0
const PAD_X := 22.0
const PAD_Y := 10.0
## Clearance for the touch stack (two BTN_SIZE.x columns + gap + inset). A clearance, not the
## stack's own metric, so it holds whether or not the overlay is on screen right now.
const RESERVE := 220.0
## Cap on how much width the reserve may take — the message must stay readable on a narrow screen.
const MAX_INSET_RATIO := 0.22
## Lines the box fits; 2 so long notices autowrap instead of clipping.
const LINES := 2


## Re-entry guard: _layout installs a stylebox override, which itself raises
## NOTIFICATION_THEME_CHANGED — without this the two call each other forever.
var _laying_out := false


func _ready() -> void:
	var parent := get_parent() as Control
	if parent != null:
		parent.resized.connect(_layout)  # the inset is a share of the width available
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_inside_tree():
		_layout()


func _layout() -> void:
	if _laying_out:
		return
	_laying_out = true
	var ui_scale := UiTheme.scale_of(self)
	var area := get_parent_area_size()
	var inset := minf(roundf(RESERVE * ui_scale), area.x * MAX_INSET_RATIO)
	offset_left = inset
	offset_right = -inset
	offset_top = roundf(area.y * TOP_RATIO)
	var pad_y := roundf(PAD_Y * ui_scale)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.04, 0.05, 0.82)
	box.border_color = Color(0.90, 0.16, 0.16, 1.0)
	box.set_border_width_all(int(maxf(2.0, roundf(2.0 * ui_scale))))
	box.set_corner_radius_all(int(roundf(6.0 * ui_scale)))
	box.content_margin_left = roundf(PAD_X * ui_scale)
	box.content_margin_right = box.content_margin_left
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	add_theme_stylebox_override(&"normal", box)
	# Height from the font it is ACTUALLY drawn in, resolved through the Title variation, so it
	# cannot go stale against the type scale the way a hardcoded box did.
	var font := get_theme_font(&"font")
	var line_h := 0.0 if font == null else font.get_height(get_theme_font_size(&"font_size"))
	offset_bottom = offset_top + roundf(maxf(line_h, TOP) * float(LINES)) + pad_y * 2.0
	_laying_out = false

class_name NoticeLine
extends Label
## The sim's transient message line across the top of the screen ("no room to couple"), raised
## by GameState.notice and dwelled/hidden by the shell. Red on a dark panel, centred, plain text,
## no emoji — the colour is SEMANTIC (this is a warning), which is why it stays an override on the
## node rather than moving into the theme. It sits above the middle of the screen rather than at
## the top edge: a line in the top margin was being missed while the driver watched the road.
##
## IT LAYS ITSELF OUT rather than carrying fixed offsets in boot.tscn, and both reasons were
## found in the Phase 7 sweep:
##
## - Its offsets were RAW pixels while everything around them scaled with UiTheme. The box was
##   40 px tall for a Title-sized font that is 22 px at scale 1.0 and 44 px at the scale a phone
##   gets — so the message clipped exactly where it matters most.
## - It ran the full width of the screen, straight under the touch overlay's button columns (then
##   on the right edge, now on the left). The inset that fixes it is SYMMETRIC because the line is
##   centred: insetting only
##   the side the buttons are on would knock the text off-centre on every screen to buy clearance
##   on one.

## Where the box's top edge sits, as a share of the screen height. Above the middle, so the
## message is in the eye's centre without covering the vehicle itself.
const TOP_RATIO := 0.34
## Logical px (scaled through the inherited theme). Padding inside the box; also the floor the
## line height is measured against.
const TOP := 14.0
## Box padding, logical px (scaled). Horizontal is wider so short messages still read as a box.
const PAD_X := 22.0
const PAD_Y := 10.0
## The width the notice must not reach into: the touch stack is two columns of
## TouchControls.BTN_SIZE.x plus its gap and edge inset. Named here rather than imported because
## this is a CLEARANCE, not the stack's own metric — the notice must clear that region whether or
## not the overlay is currently on screen (it appears and disappears with F4 and with the device).
const RESERVE := 220.0
## Never give more than this share of the width away to the reserve. On a narrow screen the
## buttons and the message cannot both have what they want, and the message is the one you have
## to be able to read.
const MAX_INSET_RATIO := 0.22
## Lines the box is tall enough for. Two: long notices autowrap, and a box sized to one line
## clips the second rather than growing.
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
	# Padding scales with the theme like everything else here, so the box grows with the text
	# instead of clipping it on a phone.
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

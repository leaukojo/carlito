class_name NoticeLine
extends Label
## The sim's transient message line ("no room to couple"), raised by GameState.notice and
## dwelled here; the shell shows and hides it with the HUD (`set_shown`). Red on a dark panel,
## centred, plain text, no emoji — colour is semantic, so it's a node override rather than theme. Sits above screen middle, not the
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
## Seconds a GameState.notice stays on screen. Long enough to read while still driving.
const NOTICE_DWELL_S := 3.0


## Re-entry guard: _layout installs a stylebox override, which itself raises
## NOTIFICATION_THEME_CHANGED — without this the two call each other forever.
var _laying_out := false
## Sticky notice texts still up, oldest first; the newest shows whenever no transient one does.
var _sticky_notices: Array[String] = []


func _ready() -> void:
	GameState.notice.connect(_show_notice)
	GameState.notice_cleared.connect(_clear_notice)
	var parent := get_parent() as Control
	if parent != null:
		parent.resized.connect(_layout)  # the inset is a share of the width available
	_layout()


## The HUD showing or hiding as a whole: back up on the newest sticky notice, if any.
func set_shown(v: bool) -> void:
	if v:
		_restore_sticky_notice()
	else:
		visible = false


## Show a message from the sim (GameState.notice). Re-showing restarts the dwell instead of
## queueing, so holding E against a wall reads as one steady message. A sticky one starts no
## timer and stays listed until cleared; a transient one hands back to it when its dwell ends.
func _show_notice(notice_text: String, dwell_s: float) -> void:
	text = notice_text
	visible = true
	var token := notice_text + str(Time.get_ticks_msec())
	set_meta("token", token)
	if dwell_s == GameState.NOTICE_STICKY:
		_sticky_notices.erase(notice_text)
		_sticky_notices.append(notice_text)
		return
	var dwell := dwell_s if dwell_s > 0.0 else NOTICE_DWELL_S
	await get_tree().create_timer(dwell).timeout
	if get_meta("token", "") == token:
		_restore_sticky_notice()


## Take a notice down early once what it warned about is fixed. Matches on text so it only
## ever hides its own message; a later notice keeps the rest of its dwell.
func _clear_notice(notice_text: String) -> void:
	_sticky_notices.erase(notice_text)
	if visible and text == notice_text:
		_restore_sticky_notice()


## Show the newest sticky notice still up, or hide the line if there is none.
func _restore_sticky_notice() -> void:
	if _sticky_notices.is_empty():
		visible = false
		return
	text = _sticky_notices.back()
	visible = true
	set_meta("token", "")


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

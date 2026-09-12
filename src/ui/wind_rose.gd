class_name WindRose
extends Control
## Hand-built wind and track rose, the marine counterpart of Gauge and AttitudeIndicator and
## built the same way: one instance, shown only where the vehicle declares the whole wind/track
## set (boat). The dashboard feeds the readings per frame and reads nothing off the contract but
## the fact that they are declared.
##
## HEADING-UP: the bow index is fixed at the top and the compass card turns under it, which is
## what makes the two angles this instrument exists for READ AS ANGLES rather than as numbers —
## the apparent wind sits where it blows from relative to the bow, and the gap between the track
## needle and the fixed bow index IS the crab angle (contract: cog minus heading is leeway plus
## the set of the tide).
##
## Conventions are the contract's, verbatim: 'awa' 0 = dead ahead and negative = from port, so
## starboard is screen-right; 'twd' and 'cog' are absolute compass bearings converted here to
## relative ones. Either sign backwards makes an instrument worse than none — pinned in
## tests/test_dashboard.gd via `needle_dir` / `relative_bearing`.
##
## TWO ANGLES HERE ARE UNDEFINED AT ZERO SPEED and both read 0, a perfectly good bearing: 'awa'
## when the relative air is calm, and 'cog' with no way on. Each is gated on its own speed
## reading and reads "---" instead — the same trap 'depth' answers with its -1.
##
## Plain text + color only, no emoji.

const DISC_INSET := 6.0        ## disc inset from the widget's short edge, for the bezel stroke
const CARD_STEP := 30          ## compass card ticks, degrees
const CARDINALS := {0: "N", 90: "E", 180: "S", 270: "W"}
## Speed over ground below which there is no course to draw (contract: 'cog' reads 0 there).
const TRACK_MIN_SOG := 0.15
## ...and the wind speed below which there is no wind bearing, apparent or true, for the same
## reason.
const WIND_MIN_AWS := 0.05

const BEZEL_COLOR := Color(0.30, 0.32, 0.36)
const CARD_COLOR := Color(0.55, 0.58, 0.63)
const CARD_TEXT := Color(0.72, 0.75, 0.80)
const BOW_COLOR := Color(1.0, 0.78, 0.10)    ## the fixed hull index, amber like the horizon's
const APPARENT_COLOR := Color(0.45, 0.72, 1.0)
const TRUE_COLOR := Color(0.60, 0.63, 0.68)
const TRACK_COLOR := Color(0.35, 0.85, 0.45)
const TEXT_COLOR := Color(0.95, 0.96, 1.0)
## What an undefined angle reads as, the echo sounder's answer to the same problem.
const BLANK := "---"

var awa := 0.0      ## deg, contract 'awa' (0 = dead ahead, - = from port)
var aws := 0.0      ## m/s, contract 'aws'
var twd := 0.0      ## deg, contract 'twd' (the bearing it comes FROM)
var tws := 0.0      ## m/s, contract 'tws'
var cog := 0.0      ## deg, contract 'cog' (the bearing actually travelled)
var sog := 0.0      ## m/s, contract 'sog'
var heading := 0.0  ## deg, shared 'heading' — what the card is turned by
var caption := ""   ## static label drawn under the top bezel


## One setter for the whole reading: seven fields arrive together every frame, and seven
## setters would queue seven redraws for one tick.
func set_reading(awa_deg: float, aws_ms: float, twd_deg: float, tws_ms: float,
		cog_deg: float, sog_ms: float, heading_deg: float) -> void:
	awa = awa_deg
	aws = aws_ms
	twd = twd_deg
	tws = tws_ms
	cog = cog_deg
	sog = sog_ms
	heading = heading_deg
	queue_redraw()


## Redraw when the UI scale changes — every stroke/font size below is logical px, like Gauge.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


# --- pure geometry (unit-tested) ---------------------------------------------

## An absolute compass bearing as a RELATIVE one, signed and wrapped to [-180, 180): + to
## starboard, - to port, the same convention 'awa' already arrives in. Dead astern lands on
## -180, which is the half wrapf keeps and the same bearing as +180.
static func relative_bearing(bearing_deg: float, heading_deg: float) -> float:
	return wrapf(bearing_deg - heading_deg, -180.0, 180.0)


## Unit vector for a relative bearing on the heading-up card. y is DOWN on a canvas, so dead
## ahead is (0, -1) and starboard is screen-right.
static func needle_dir(rel_deg: float) -> Vector2:
	var a := deg_to_rad(rel_deg)
	return Vector2(sin(a), -cos(a))


## The crab angle: how far the ground track lies off the bow. Positive = making ground to
## starboard of where the bow points.
static func crab(cog_deg: float, heading_deg: float) -> float:
	return relative_bearing(cog_deg, heading_deg)


## Is there a course to draw? A hull with no way on publishes cog 0, which is due north.
static func has_track(sog_ms: float) -> bool:
	return sog_ms > TRACK_MIN_SOG


## Is there a wind to draw a bearing for? Same rule as has_track, one axis over: a wind speed of
## zero leaves its angle undefined and both 'awa' and 'twd' publish 0 there — dead ahead and due
## north, two perfectly good bearings. Used for the apparent needle and the true tick alike, so
## there is ONE rule rather than a threshold here and a bare comparison there.
static func has_wind(speed_ms: float) -> bool:
	return speed_ms > WIND_MIN_AWS


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	var s := UiTheme.scale_of(self)
	var center := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - DISC_INSET * s
	var font := get_theme_default_font()
	var small := int(UiTheme.px(self, 10.0))

	# The card: ticks every CARD_STEP of TRUE bearing, turned under the fixed bow index.
	for deg in range(0, 360, CARD_STEP):
		var dir := needle_dir(relative_bearing(float(deg), heading))
		var cardinal: String = CARDINALS.get(deg, "")
		var inner := r - (10.0 if cardinal.is_empty() else 6.0) * s
		draw_line(center + dir * inner, center + dir * r, CARD_COLOR,
				(1.5 if cardinal.is_empty() else 2.5) * s)
		if not cardinal.is_empty():
			_draw_centered(font, center + dir * (r - 17.0 * s) + Vector2(0.0, 4.0 * s),
					cardinal, small, CARD_TEXT)
	draw_arc(center, r, 0.0, TAU, 96, BEZEL_COLOR, 2.0 * s, true)

	# True wind: a short outer tick, so it cannot be mistaken for the apparent needle.
	if has_wind(tws):
		var td := needle_dir(relative_bearing(twd, heading))
		draw_line(center + td * (r * 0.72), center + td * (r - 2.0 * s), TRUE_COLOR, 3.0 * s)

	# Apparent wind: an arrow flying FROM its bearing INTO the middle, which is what the airflow
	# over the hull does. Not drawn in a calm — see the header.
	if has_wind(aws):
		var ad := needle_dir(awa)
		var tip := center + ad * (r * 0.26)
		draw_line(center + ad * (r * 0.92), tip, APPARENT_COLOR, 3.0 * s)
		var side := Vector2(-ad.y, ad.x)
		draw_colored_polygon(PackedVector2Array([
			tip, tip + ad * (9.0 * s) + side * (5.0 * s), tip + ad * (9.0 * s) - side * (5.0 * s),
		]), APPARENT_COLOR)

	# Ground track, only where there is one.
	if has_track(sog):
		var cd := needle_dir(crab(cog, heading))
		draw_line(center, center + cd * (r * 0.86), TRACK_COLOR, 2.5 * s)

	# The hull index: fixed at the top, so everything above is read against the bow.
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -r + 1.0 * s),
		center + Vector2(-5.0 * s, -r + 11.0 * s),
		center + Vector2(5.0 * s, -r + 11.0 * s),
	]), BOW_COLOR)

	if not caption.is_empty():
		_draw_centered(font, center + Vector2(0.0, -r * 0.62), caption, small, CARD_COLOR)
	# Gauge's own stack: the number, then its unit a line under it.
	_draw_centered(font, center + Vector2(0.0, r * 0.30), "%.1f" % aws,
			int(UiTheme.px(self, 17.0)), TEXT_COLOR)
	_draw_centered(font, center + Vector2(0.0, r * 0.30 + 15.0 * s), "AWS m/s", small, CARD_COLOR)
	var awa_text := ("%+d" % roundi(awa)) if has_wind(aws) else BLANK
	_draw_centered(font, center + Vector2(0.0, r * 0.72),
			"AWA %s   TWS %.1f" % [awa_text, tws], small, CARD_TEXT)
	_draw_centered(font, center + Vector2(0.0, r * 0.92),
			("CRAB %+d" % roundi(crab(cog, heading))) if has_track(sog) else "CRAB " + BLANK,
			small, TRACK_COLOR if has_track(sog) else CARD_COLOR)


func _draw_centered(font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(font, at - Vector2(w * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			font_size, color)

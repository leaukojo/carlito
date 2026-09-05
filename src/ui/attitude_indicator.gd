class_name AttitudeIndicator
extends Control
## Hand-built artificial horizon, the flight counterpart of Gauge and built the same way: one
## instance, shown only where the vehicle declares both 'pitch' and 'roll' (boat/plane/drone).
## Dashboard reads only the two warn thresholds off the contract and feeds pitch/roll per frame.
##
## Conventions are the contract's, verbatim: pitch + = nose/bow up, roll + = starboard/right
## side down. A nose-up craft pushes the horizon down the disc; a right bank lifts the horizon's
## right end. Either sign backwards makes an instrument worse than none — pinned in
## tests/test_dashboard.gd via `horizon_dir` / `horizon_center`.
##
## Plain text + color only, no emoji.

const DISC_INSET := 6.0  ## disc inset from the widget's short edge, for the bezel stroke
## Degrees of pitch that displace the horizon by the full disc radius. 45 keeps the ladder
## readable in the aircraft's usual +/-20 deg without pinning the drone's 32 deg tilt to the rim.
const PITCH_FULL_SCALE := 45.0
const LADDER_STEP := 10  ## pitch-ladder rungs, degrees either side of the horizon
const LADDER_MAX := 30
const BANK_MARKS: PackedInt32Array = [10, 20, 30, 45, 60]  ## bezel bank-scale marks, deg either side of vertical

const SKY_COLOR := Color(0.20, 0.44, 0.72)
const GROUND_COLOR := Color(0.42, 0.30, 0.18)
const HORIZON_COLOR := Color(0.95, 0.96, 1.0)
const LADDER_COLOR := Color(0.88, 0.90, 0.94)
const BEZEL_COLOR := Color(0.30, 0.32, 0.36)
const MARK_COLOR := Color(0.55, 0.58, 0.63)
const CRAFT_COLOR := Color(1.0, 0.78, 0.10)  ## the fixed airframe symbol, amber like a real one
const TEXT_COLOR := Color(0.95, 0.96, 1.0)
const WARN_COLOR := Color(0.90, 0.20, 0.16)

var pitch := 0.0: set = _set_pitch  ## deg, + = nose/bow up (contract 'pitch')
var roll := 0.0: set = _set_roll    ## deg, + = starboard/right side down (contract 'roll')
var pitch_warn := NAN               ## |pitch| at or past which the readout goes danger; NAN = none
var roll_warn := NAN                ## same for |roll|
var caption := ""                   ## static label drawn under the top bezel


func _set_pitch(v: float) -> void:
	pitch = v
	queue_redraw()


func _set_roll(v: float) -> void:
	roll = v
	queue_redraw()


## Redraw when the UI scale changes — every stroke/font size below is logical px, like Gauge.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


# --- pure geometry (unit-tested) ---------------------------------------------

## y-down canvas: a right bank lifts the horizon's right end, so the angle is the negated roll.
static func horizon_dir(roll_deg: float) -> Vector2:
	var a := deg_to_rad(-roll_deg)
	return Vector2(cos(a), sin(a))


## The direction pitch displaces the horizon along: `horizon_dir` rotated a quarter turn.
static func horizon_down(roll_deg: float) -> Vector2:
	var d := horizon_dir(roll_deg)
	return Vector2(-d.y, d.x)


## Nose up pushes the horizon down the disc (the craft is looking over the horizon).
static func horizon_center(center: Vector2, radius: float, pitch_deg: float,
		roll_deg: float) -> Vector2:
	var offset := clampf(pitch_deg, -90.0, 90.0) / PITCH_FULL_SCALE * radius
	return center + horizon_down(roll_deg) * offset


## Clips a convex polygon to the half-plane `(p - origin) dot normal >= 0` (Sutherland-Hodgman
## against one edge) — carves the ground out of the disc polygon without a stencil the
## Compatibility renderer would rather not have.
static func clip_half_plane(poly: PackedVector2Array, origin: Vector2,
		normal: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	if n == 0:
		return out
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var da := (a - origin).dot(normal)
		var db := (b - origin).dot(normal)
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			# The segment crosses the line: add the crossing point once, from whichever side.
			out.append(a.lerp(b, da / (da - db)))
	return out


## |value| at or past |warn|. A NAN warn (a signal with no threshold) is never past.
static func past_warn(value: float, warn: float) -> bool:
	return not is_nan(warn) and absf(value) >= absf(warn)


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	var s := UiTheme.scale_of(self)
	var center := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - DISC_INSET * s
	if r <= 0.0:
		return

	var dir := horizon_dir(roll)
	var down := horizon_down(roll)
	var h := horizon_center(center, r, pitch, roll)

	var disc := PackedVector2Array()
	for i in 64:
		var t := TAU * float(i) / 64.0
		disc.append(center + Vector2(cos(t), sin(t)) * r)
	draw_colored_polygon(disc, SKY_COLOR)
	var ground := clip_half_plane(disc, h, down)
	if ground.size() >= 3:
		draw_colored_polygon(ground, GROUND_COLOR)

	draw_line(h - dir * r, h + dir * r, HORIZON_COLOR, 2.0 * s)

	# Ladder rungs offset along `down` by the same scale the horizon itself moves on, so ladder
	# and horizon cannot disagree.
	var per_deg := r / PITCH_FULL_SCALE
	for deg in range(LADDER_STEP, LADDER_MAX + 1, LADDER_STEP):
		for way in [-1, 1]:
			var rung := h - down * (float(deg * way) * per_deg)
			if rung.distance_to(center) > r:
				continue
			var half := r * (0.30 if deg % 20 == 0 else 0.18)
			draw_line(rung - dir * half, rung + dir * half, LADDER_COLOR, 1.0 * s)

	# Bank scale marks are fixed to the instrument, not rotating with the horizon.
	draw_arc(center, r, 0.0, TAU, 96, BEZEL_COLOR, 3.0 * s, true)
	for mark in BANK_MARKS:
		for way in [-1, 1]:
			var a := deg_to_rad(-90.0 + float(mark * way))
			var p := Vector2(cos(a), sin(a))
			draw_line(center + p * (r - 7.0 * s), center + p * r, MARK_COLOR, 2.0 * s)
	# Roll pointer: the rim mark that does rotate, over the bank scale at the current angle.
	var pa := deg_to_rad(-90.0 - roll)
	var pp := Vector2(cos(pa), sin(pa))
	draw_line(center + pp * (r - 11.0 * s), center + pp * r, CRAFT_COLOR, 3.0 * s)

	# Fixed airframe symbol, screen-locked; the horizon moves behind it.
	var wing := r * 0.42
	var gap := r * 0.10
	draw_line(center + Vector2(-wing, 0.0), center + Vector2(-gap, 0.0), CRAFT_COLOR, 3.0 * s)
	draw_line(center + Vector2(gap, 0.0), center + Vector2(wing, 0.0), CRAFT_COLOR, 3.0 * s)
	draw_circle(center, 2.5 * s, CRAFT_COLOR)

	var font := get_theme_default_font()
	if not caption.is_empty():
		_draw_centered(font, center + Vector2(0.0, -r * 0.72), caption,
				int(UiTheme.px(self, 11.0)), MARK_COLOR)
	# Each number goes danger on its own contract warn, so a boat past capsize roll says so
	# without waiting for pitch.
	var big := int(UiTheme.px(self, 13.0))
	_draw_at(font, center + Vector2(-r * 0.62, r * 0.72), "P %d" % roundi(pitch), big,
			WARN_COLOR if past_warn(pitch, pitch_warn) else TEXT_COLOR)
	var roll_text := "R %d" % roundi(roll)
	var w := font.get_string_size(roll_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, big).x
	_draw_at(font, center + Vector2(r * 0.62 - w, r * 0.72), roll_text, big,
			WARN_COLOR if past_warn(roll, roll_warn) else TEXT_COLOR)


func _draw_centered(font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	_draw_at(font, at - Vector2(w * 0.5, 0.0), text, font_size, color)


func _draw_at(font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

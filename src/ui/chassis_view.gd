class_name ChassisView
extends Control
## The chassis view: a plan view of the bound body's wheels off `ChassisReading` each physics tick,
## front up. Each tyre is a patch whose AREA is its share of the normal load, filled by its grip in
## use, hatched past the curve's peak, a dashed outline off the ground; on it the road's push, beside
## it its slip bar; diff links between the wheels; the body's g arrow and load-centre dot at the COM.
## It draws each reading as given, with no lag or hold (`Instrument`'s rule): a flicker here is the
## sim flickering. A body with no wheels (boat, drone, train) draws nothing. A coupled body draws
## behind at its live articulation (`layout_box`, `held_swing`). Not in sloppyCAN: no bus has this.
##
## Full-rect, mouse-transparent; the panel sits at the right edge, docked on the higher of the
## dashboard's and the touch pads' top edges (`dock`), below the challenge HUD (`keep_clear`).

## The panel at full size, logical px.
const PANEL_SIZE := Vector2(190.0, 260.0)
## The panel while a body is coupled, logical px: the semi and the tanker swung SWING_HELD_DEG
## either way fill it (`layout_box`).
const RIG_PANEL_SIZE := Vector2(265.0, 270.0)
## deg, the towed swing a rig's plan holds still through; past it the plan zooms out with the body.
const SWING_HELD_DEG := 45.0
## Under this height (logical px) there is no room for a readable panel, so none is drawn.
const MIN_H := 90.0
const MARGIN := 10.0   ## from the window's right edge, logical px (DebugOverlay's inset)
const GAP := 8.0       ## between the panel and what it docks against, logical px
const PAD := 10.0      ## inside the panel, logical px
const LEGEND_H := 14.0  ## the grip legend's band at the panel's bottom, logical px
## The legend's type, logical px: under the theme's FS_SMALL, so its row fits the narrow panel.
const LEGEND_FS := 11.0
const LEGEND_SWATCH := 8.0  ## a legend colour's square, logical px
## A patch at an even share of the load (total / wheel count), logical px along the car; its width
## is PATCH_ASPECT of that. Area follows the share, so a side follows its square root.
const PATCH_LEN := 32.0
const PATCH_ASPECT := 0.55
## m, the tightest axle pitch drawn (the trailers' tri-axle bogies): a plan with fewer px per m
## than fits a full patch in it shrinks every mark (`mark_scale`).
const MIN_PITCH := 0.8
## Room kept around the layout for a patch above its even share: 1.0 + this fits a patch of three
## times the even area (a four-wheeler's outer front in a full-lock push carries over twice; a
## lifted wheel hands its share to the rest).
const PATCH_HEADROOM := 0.75
const HATCH_STEP := 5.0  ## between hatch lines, logical px
## A tyre force equal to the body's weight over its wheel count, logical px; every wheel's arrow on
## this one scale, capped at ARROW_CAP times it. Weight, not this tick's load: a crest or a landing
## moves the arrows, never the scale.
const ARROW_LEN := 20.0
const ARROW_CAP := 3.0
## The body's acceleration arrow: logical px per g, capped at BODY_ARROW_CAP g.
const BODY_ARROW_LEN := 30.0
const BODY_ARROW_CAP := 2.0
const G := 9.8  ## m/s² in one g (`BrakeSizing.G`)
## A slip bar's length at a slip ratio of 1 (locked, or spinning at twice the road speed), logical
## px. It follows the square root of the ratio, so the curve's peak (~0.1) reads a third of it.
const SPIN_LEN := 15.0
const SPIN_GAP := 3.0  ## between a patch and its slip bar, logical px
## A differential link's width per state (`ChassisReading.Diff`: NONE, OPEN, BIASING, LOCKED),
## logical px; LOCKED draws two lines DIFF_SPLIT apart.
const DIFF_WIDTHS: Array[float] = [0.0, 1.0, 2.5, 1.5]
const DIFF_SPLIT := 3.0

## Grip in use below which a patch reads cool, then warm; at or past WARM_BELOW it is at the limit.
const COOL_BELOW := 0.7
const WARM_BELOW := 0.95
const GRIP_COLORS: Array[Color] = [Color(0.30, 0.62, 0.95), UiTheme.WARN, UiTheme.DANGER]
const LEGEND_TITLE := "GRIP"  ## the legend's title, before GRIP_COLORS (`legend_labels`)

const PANEL_COLOR := Color(0.06, 0.07, 0.09, 0.82)  ## the dashboard's panel
const OUTLINE_COLOR := Color(0.02, 0.02, 0.03, 0.9)
const HATCH_COLOR := Color(0.02, 0.02, 0.03, 0.7)
const LIFTED_COLOR := Color(0.62, 0.67, 0.74)       ## UiTheme.TEXT_DIM, opaque
const FORCE_COLOR := Color(0.92, 0.94, 0.97)
## The body's arrow and its load-centre dot: the horizon's and the rose's index yellow.
const BODY_COLOR := Color(1.0, 0.78, 0.10)
const HELD_COLOR := Color(0.85, 0.45, 1.0)          ## a slip bar while ABS / TCS / ESC held it
const DIFF_COLORS: Array[Color] = [Color.TRANSPARENT, Color(0.62, 0.67, 0.74, 0.7),
		Color(0.92, 0.94, 0.97), Color(0.92, 0.94, 0.97)]

var _on := false        ## the toggle's (F6 / touch CHASSIS), saved by the shell
var _shown := false     ## the shell's HUD visibility
var _vehicle: BaseVehicle = null  ## the bound body, null with none or no wheels
var _hosts: Array[TowHost] = []   ## the bound body's couplings, read for a towed body each tick
var _dock: Dashboard = null
var _pads: TouchControls = null
var _keep_clear: ChallengeHud = null
var _reading: ChassisReading = null
var _tick := -1  ## the physics frame `_reading` was taken on


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_visible()


## Rebind to `level`'s vehicle (the shell's `Dashboard.bind` partner); null drops it.
func bind(level: Node) -> void:
	_vehicle = null
	_hosts.clear()
	_reading = null
	_tick = -1
	if level != null:
		var v := level.get("vehicle") as BaseVehicle
		if v != null and v.drive != null and not v.drive.wheels.is_empty():
			_vehicle = v
			for node in v.find_children("*", "TowHost", true, false):
				_hosts.append(node as TowHost)
	_apply_visible()


## The dashboard and the touch pads whose top edges the panel stands above; either may be null.
func dock(dashboard: Dashboard, pads: TouchControls) -> void:
	_dock = dashboard
	_pads = pads


## The y the panel stands above: the highest of the dashboard's and the driving pads' top edges.
func standing_edge() -> float:
	var y := _dock.top_edge() if _dock != null else size.y
	if _pads != null:
		y = minf(y, _pads.drive_top())
	return y


## The challenge HUD to stay below where the panel would cover it; null with none.
func keep_clear(hud: ChallengeHud) -> void:
	_keep_clear = hud


func is_on() -> bool:
	return _on


func set_on(on: bool) -> void:
	_on = on
	_apply_visible()


## Shell's HUD visibility, kept apart from the toggle so neither clobbers the other.
func set_shown(shown: bool) -> void:
	_shown = shown
	_apply_visible()


func _apply_visible() -> void:
	visible = _on and _shown and _vehicle != null
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESIZED:
		queue_redraw()


func _process(_dt: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_vehicle):
		_vehicle = null
		_apply_visible()
		return
	var tick := Engine.get_physics_frames()
	if tick == _tick:
		return
	_tick = tick
	_reading = ChassisReading.of(_vehicle, _hosts)
	queue_redraw()


# --- pure mapping (unit-tested) -----------------------------------------------

## 0 cool, 1 warm, 2 at the limit, for a grip-use ratio (`ChassisReading.WheelReading.grip_use`).
static func grip_step(use: float) -> int:
	if use < COOL_BELOW:
		return 0
	return 1 if use < WARM_BELOW else 2


## The legend's words for each `grip_step`, off its thresholds.
static func legend_labels() -> PackedStringArray:
	return PackedStringArray(["<%d%%" % roundi(COOL_BELOW * 100.0),
			"<%d%%" % roundi(WARM_BELOW * 100.0), "LIMIT"])


## A patch's side scale: the square root of its share of `total` load times the wheel `count`, so
## its AREA is the share and an even share reads 1. 0 with no load anywhere.
static func patch_scale(load_n: float, total: float, count: int) -> float:
	if total <= 0.0 or load_n <= 0.0:
		return 0.0
	return sqrt(load_n / total * count)


## The panel's rect in a `view`-sized full-rect parent: its bottom GAP over `floor_y`, its top no
## higher than `ceiling_y`, `full`'s shape (logical px), shrunk in proportion where the room is
## short; an empty Rect2 when under MIN_H. `s` is the UI scale. Its right edge is `span.y` (the
## touch pads' drive block, `TouchControls.drive_span`) or MARGIN in from the window's; with
## `span.x` too it spans both edges at `full`'s aspect, keeping that width where the room is short.
static func panel_rect(view: Vector2, floor_y: float, ceiling_y: float, s: float,
		full := PANEL_SIZE, span := Vector2(NAN, NAN)) -> Rect2:
	var bottom := floor_y - GAP * s
	var right := span.y if is_finite(span.y) else view.x - MARGIN * s
	var spanned := is_finite(span.x) and is_finite(span.y) and span.y > span.x
	var w0 := span.y - span.x if spanned else full.x * s
	var h0 := w0 * full.y / full.x
	var h := minf(h0, bottom - ceiling_y)
	if h < MIN_H * s:
		return Rect2()
	var w := w0 if spanned else w0 * h / h0
	return Rect2(right - w, bottom - h, w, h)


## A panel's size against `full`'s at UI scale `s`: what its contents scale by.
static func panel_scale(panel: Rect2, full: Vector2, s: float) -> float:
	return minf(panel.size.x / full.x, panel.size.y / full.y) / s


## Diagonal hatch lines filling `rect`, `step` px apart: pairs of end points for draw_multiline,
## every point on or inside the rect.
static func hatch_lines(rect: Rect2, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if step <= 0.0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return out
	var left := rect.position.x
	var right := rect.end.x
	var top := rect.position.y
	var bottom := rect.end.y
	# Lines x + y = c, from the top-left corner to the bottom-right one.
	var c := left + top + step
	while c < right + bottom:
		var x0 := maxf(left, c - bottom)
		var x1 := minf(right, c - top)
		out.append(Vector2(x0, c - x0))
		out.append(Vector2(x1, c - x1))
		c += step
	return out


## Each wheel's patch (px), in `wheels`' order, centred on `to_px * anchor` (`plan_transform`,
## times a towed body's `frame`). `patch` is the even-share size; a lifted wheel's rect is that
## size (its dashed outline), a loaded one's follows its share of `total` load over `count` wheels,
## the rig's (`patch_scale`).
static func patch_rects(wheels: Array[ChassisReading.WheelReading], to_px: Transform2D,
		total: float, count: int, patch: Vector2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for w in wheels:
		var at := to_px * w.anchor
		var size_px := patch if not w.in_contact \
				else patch * patch_scale(w.normal_load, total, count)
		out.append(Rect2(at - size_px * 0.5, size_px))
	return out


## The towing unit's xz (m) to px in `area`: `box` (`layout_box`) centred and fitted to it, alike
## on both axes, with room for a patch above its even share; front up, so the centre of mass and the
## load centre land on it too.
static func plan_transform(box: Rect2, area: Rect2, patch: Vector2) -> Transform2D:
	var room := area.size - Vector2.ONE * patch.y * (1.0 + PATCH_HEADROOM)
	var k := fit_scale(box, room)
	return Transform2D(0.0, Vector2(k, k), 0.0, area.get_center() - box.get_center() * k)


## Px per m that fit `box` (m) inside `room` (px), alike on both axes, whichever axis binds; an axis
## with no extent binds nothing. 1 for a single point.
static func fit_scale(box: Rect2, room: Vector2) -> float:
	var k := INF
	if box.size.x > 0.0:
		k = room.x / box.size.x
	if box.size.y > 0.0:
		k = minf(k, room.y / box.size.y)
	return maxf(k, 0.0) if is_finite(k) else 1.0


## The plot's room inside a `full` panel at full size (logical px): less the padding and the
## legend's band.
static func plot_size(full: Vector2) -> Vector2:
	return full - Vector2(2.0 * PAD, 2.0 * PAD + LEGEND_H)


## The towing unit's xz (m) the plan fits: its wheels' box, and where a towed body's wheels reach
## swinging about its coupling up to `held_swing` either way (`ChassisReading.swept_box`).
static func layout_box(reading: ChassisReading) -> Rect2:
	var box := ChassisReading.anchor_box(anchors_of(reading.wheels))
	var t := reading.towed
	if t != null and not t.wheels.is_empty():
		var yaw := held_swing(t.frame.get_rotation(), t.yaw_stop)
		box = box.merge(ChassisReading.swept_box(anchors_of(t.wheels), t.coupling, yaw))
	return box


## rad, the swing a plan holds either way for a towed body at articulation `phi` (rad), its
## coupling's stop `stop`: SWING_HELD_DEG, so the frame holds still through an ordinary turn, or
## `phi` past it, so it zooms out to keep the body in view; never past the stop.
static func held_swing(phi: float, stop: float) -> float:
	return minf(stop, maxf(deg_to_rad(SWING_HELD_DEG), absf(phi)))


## The wheels' anchors (body xz, m).
static func anchors_of(wheels: Array[ChassisReading.WheelReading]) -> PackedVector2Array:
	var out := PackedVector2Array()
	for w in wheels:
		out.append(w.anchor)
	return out


## What the marks (patches, arrows, bars) draw at, for a plan of `per_m` logical px per m: whole
## while a full patch fits the tightest axle pitch (MIN_PITCH), shrunk with the plan below that,
## so a patch keeps its size against its neighbours. A lone body's plan never shrinks them; a rig
## fitted to its trailer's swing does.
static func mark_scale(per_m: float) -> float:
	return clampf(per_m * MIN_PITCH / PATCH_LEN, 0.0, 1.0)


## The wheels' normal loads summed, N.
static func total_load(wheels: Array[ChassisReading.WheelReading]) -> float:
	var total := 0.0
	for w in wheels:
		total += w.normal_load
	return total


## A tyre force's arrow (px, body xz, so front up): `length` px for a force equal to `weight` (N)
## over `count` wheels, the same scale on every wheel, capped at ARROW_CAP times `length`. Zero
## with no weight.
static func force_arrow(force: Vector2, weight: float, count: int, length: float) -> Vector2:
	if weight <= 0.0 or count <= 0:
		return Vector2.ZERO
	return (force / (weight / count) * length).limit_length(ARROW_CAP * length)


## The body's acceleration arrow (px): `per_g` px per g, capped at BODY_ARROW_CAP g.
static func accel_arrow(accel: Vector2, per_g: float) -> Vector2:
	return (accel / G * per_g).limit_length(BODY_ARROW_CAP * per_g)


## A slip bar's signed length as a share of SPIN_LEN: the square root of the slip ratio's size,
## capped at 1, + spinning (drawn up), - locking (drawn down).
static func spin_bar(long_slip: float) -> float:
	return signf(long_slip) * sqrt(minf(absf(long_slip), 1.0))


## The line segments (pairs for draw_multiline) of a differential link from `a` to `b` (px) in
## `state`: none for NONE, one for OPEN or BIASING, two `split` px apart for LOCKED. Its width and
## colour are DIFF_WIDTHS and DIFF_COLORS at the state.
static func diff_lines(a: Vector2, b: Vector2, state: ChassisReading.Diff,
		split: float) -> PackedVector2Array:
	if state == ChassisReading.Diff.NONE or a.is_equal_approx(b):
		return PackedVector2Array()
	if state != ChassisReading.Diff.LOCKED:
		return PackedVector2Array([a, b])
	var off := (b - a).normalized().orthogonal() * split * 0.5
	return PackedVector2Array([a + off, b + off, a - off, b - off])


## A rounded rectangle's outline, `r` px corners in `seg` steps each, clockwise from the top edge.
static func rounded_rect(rect: Rect2, r: float, seg := 3) -> PackedVector2Array:
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	var centres := [
		Vector2(rect.end.x - r, rect.position.y + r), Vector2(rect.end.x - r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.end.y - r), Vector2(rect.position.x + r, rect.position.y + r),
	]
	for k in 4:
		var a0 := -PI * 0.5 + k * PI * 0.5
		for i in seg + 1:
			var a := a0 + PI * 0.5 * i / seg
			pts.append(centres[k] + Vector2(cos(a), sin(a)) * r)
	return pts


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	if _reading == null:
		return
	var s := UiTheme.scale_of(self)
	var towed := _reading.towed
	var full := RIG_PANEL_SIZE if towed != null else PANEL_SIZE
	var bottom := standing_edge()
	# Lined up with the touch pads' drive block below: a lone body's panel spans it, the wider rig
	# panel shares its right edge.
	var span := _pads.drive_span() if _pads != null else Vector2(NAN, NAN)
	if towed != null:
		span.x = NAN
	var panel := panel_rect(size, bottom, MARGIN * s, s, full, span)
	var hud := _keep_clear.panel_rect() if is_instance_valid(_keep_clear) else Rect2()
	if hud.has_area() and panel.intersects(hud):
		panel = panel_rect(size, bottom, hud.end.y + GAP * s, s, full, span)
	if not panel.has_area():
		return
	var k := panel_scale(panel, full, s)  # applied to everything in the panel
	draw_colored_polygon(rounded_rect(panel, UiTheme.RADIUS * s), PANEL_COLOR)

	var inner := panel.grow(-PAD * s * k)
	var area := Rect2(inner.position, inner.size - Vector2(0.0, LEGEND_H * s * k))
	_draw_legend(Rect2(inner.position.x, area.end.y, inner.size.x, LEGEND_H * s * k), s * k)

	var box := layout_box(_reading)
	# The marks' scale: the panel's shrink, times the plan's at full size (`mark_scale`).
	var m := k * mark_scale(fit_scale(box, plot_size(full)))
	var patch := Vector2(PATCH_LEN * PATCH_ASPECT, PATCH_LEN) * s * m
	var plan := plan_transform(box, area, patch)
	var count := _reading.wheels.size()
	var total := total_load(_reading.wheels)
	var weight := _reading.mass * G
	if towed != null:
		count += towed.wheels.size()
		total += total_load(towed.wheels)
		weight += towed.mass * G
	_draw_diff_links(plan, s, m)
	var rects := patch_rects(_reading.wheels, plan, total, count, patch)
	var towed_rects: Array[Rect2] = []
	if towed != null:
		var to_px := plan * towed.frame
		_draw_spine(to_px, towed, s, m)
		towed_rects = patch_rects(towed.wheels, to_px, total, count, patch)
		_draw_patches(towed, towed_rects, towed.frame.get_rotation(), s, m)
	_draw_patches(_reading, rects, 0.0, s, m)
	_draw_marks(_reading, rects, 0.0, weight, count, s, m)
	if towed != null:
		_draw_marks(towed, towed_rects, towed.frame.get_rotation(), weight, count, s, m)
		_draw_load_dot(plan * towed.frame, towed, s, m)
	_draw_arrow(plan * _reading.com, accel_arrow(_reading.accel, BODY_ARROW_LEN * s * m),
			BODY_COLOR, 2.5 * s, 6.0 * s * m)
	_draw_load_dot(plan, _reading, s, m)


## The grip legend in `band`: its title, then each GRIP_COLORS swatch with its words
## (`legend_labels`), spread across the band. `sk` the UI scale times the panel's shrink.
func _draw_legend(band: Rect2, sk: float) -> void:
	var font := get_theme_default_font()
	var fs := maxi(1, roundi(LEGEND_FS * sk))
	var labels := legend_labels()
	var swatch := LEGEND_SWATCH * sk
	var gap := 3.0 * sk
	var widths := PackedFloat32Array()
	var used := font.get_string_size(LEGEND_TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	for text in labels:
		var w := swatch + gap + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		widths.append(w)
		used += w
	var space := maxf(0.0, (band.size.x - used) / labels.size())
	var mid := band.get_center().y
	var baseline := mid + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	var x := band.position.x
	draw_string(font, Vector2(x, baseline), LEGEND_TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs,
			LIFTED_COLOR)
	x += font.get_string_size(LEGEND_TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	for i in labels.size():
		x += space
		draw_rect(Rect2(x, mid - swatch * 0.5, swatch, swatch), GRIP_COLORS[i])
		draw_string(font, Vector2(x + swatch + gap, baseline), labels[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, LIFTED_COLOR)
		x += widths[i]


## `reading`'s patches at `rects`, each turned `angle` rad about its centre (a towed body's
## articulation): the fill by grip in use, the hatch past the peak, a dashed outline lifted.
## `s` the UI scale, `m` the marks' (`_draw`).
func _draw_patches(reading: ChassisReading, rects: Array[Rect2], angle: float, s: float,
		m: float) -> void:
	for i in rects.size():
		var w := reading.wheels[i]
		draw_set_transform(rects[i].get_center(), angle)
		var rect := Rect2(-rects[i].size * 0.5, rects[i].size)
		if not w.in_contact:
			_draw_dashed_rect(rect, LIFTED_COLOR, s)
			continue
		if minf(rect.size.x, rect.size.y) < 2.0 * s:
			# In contact with next to no load: too small to fill, so a dot marks where it stands.
			draw_circle(Vector2.ZERO, 1.5 * s, OUTLINE_COLOR)
			continue
		var outline := rounded_rect(rect, 3.0 * s * m)
		draw_colored_polygon(outline, GRIP_COLORS[grip_step(w.grip_use)])
		var hatch := hatch_lines(rect.grow(-1.0 * s), HATCH_STEP * s * m) if w.past_peak \
				else PackedVector2Array()
		if not hatch.is_empty():  # a patch narrower than its border, or than one step, has none
			draw_multiline(hatch, HATCH_COLOR, 1.5 * s)
		outline.append(outline[0])
		draw_polyline(outline, OUTLINE_COLOR, 1.0 * s)
	draw_set_transform(Vector2.ZERO)


## `reading`'s slip bars and force arrows on its patches at `rects`, turned `angle` rad with them
## (`_draw_patches`): the arrows on the rig's scale, `weight` (N) over `count` wheels.
func _draw_marks(reading: ChassisReading, rects: Array[Rect2], angle: float, weight: float,
		count: int, s: float, m: float) -> void:
	for i in rects.size():
		var w := reading.wheels[i]
		draw_set_transform(rects[i].get_center(), angle)
		if w.driven or w.braked or w.abs_held or w.tcs_held or w.esc_braked:
			var right := w.anchor.x >= reading.com.x
			var x := rects[i].size.x * 0.5 + SPIN_GAP * s * m
			var held := w.abs_held or w.tcs_held or w.esc_braked
			var base := Vector2(x if right else -x, 0.0)
			draw_line(base - Vector2(2.0 * s * m, 0.0), base + Vector2(2.0 * s * m, 0.0),
					LIFTED_COLOR, 1.0 * s)
			draw_line(base, base - Vector2(0.0, spin_bar(w.long_slip) * SPIN_LEN * s * m),
					HELD_COLOR if held else LIFTED_COLOR, (2.5 if held else 1.5) * s)
		_draw_arrow(Vector2.ZERO, force_arrow(w.force, weight, count, ARROW_LEN * s * m),
				FORCE_COLOR, 1.5 * s, 4.0 * s * m)
	draw_set_transform(Vector2.ZERO)


## `reading`'s load-centre dot, its body xz to px by `to_px`; none with no load.
func _draw_load_dot(to_px: Transform2D, reading: ChassisReading, s: float, m: float) -> void:
	if is_nan(reading.load_centre.x):
		return
	var dot := to_px * reading.load_centre
	draw_circle(dot, 3.5 * s * m, OUTLINE_COLOR)
	draw_circle(dot, 2.5 * s * m, BODY_COLOR)


## A towed body's spine: from its coupling (its origin) to its wheels' middle, with a dot on the
## coupling, its body xz to px by `to_px`.
func _draw_spine(to_px: Transform2D, towed: ChassisReading, s: float, m: float) -> void:
	var pin := to_px.origin
	if not towed.wheels.is_empty():
		draw_line(pin, to_px * _mean(anchors_of(towed.wheels)), LIFTED_COLOR, 1.0 * s)
	draw_circle(pin, 2.0 * s * m, LIFTED_COLOR)


## Each differential's link: an axle's between its two wheels, the centre's between the axles'
## middles, styled by its state (`diff_lines`). `s` the UI scale, `k` the marks' scale.
func _draw_diff_links(plan: Transform2D, s: float, k: float) -> void:
	var front := PackedVector2Array()
	var rear := PackedVector2Array()
	for w in _reading.wheels:
		if w.rear:
			rear.append(plan * w.anchor)
		else:
			front.append(plan * w.anchor)
	if front.size() == 2:
		_draw_diff(front[0], front[1], _reading.front_diff, s, k)
	if rear.size() == 2:
		_draw_diff(rear[0], rear[1], _reading.rear_diff, s, k)
	if not front.is_empty() and not rear.is_empty():
		_draw_diff(_mean(front), _mean(rear), _reading.centre_diff, s, k)


func _draw_diff(a: Vector2, b: Vector2, state: ChassisReading.Diff, s: float, k: float) -> void:
	var lines := diff_lines(a, b, state, DIFF_SPLIT * s * k)
	if not lines.is_empty():
		draw_multiline(lines, DIFF_COLORS[state], DIFF_WIDTHS[state] * s)


static func _mean(points: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in points:
		sum += p
	return sum / points.size()


## An arrow from `from` along `vec` (px), its head `head` px long; a bare line when shorter.
func _draw_arrow(from: Vector2, vec: Vector2, color: Color, width: float, head: float) -> void:
	var length := vec.length()
	if length < head:
		if length > 0.0:
			draw_line(from, from + vec, color, width)
		return
	var dir := vec / length
	var tip := from + vec
	var neck := tip - dir * head
	draw_line(from, neck, color, width)
	var side := dir.orthogonal() * head * 0.5
	draw_colored_polygon(PackedVector2Array([tip, neck + side, neck - side]), color)


func _draw_dashed_rect(rect: Rect2, color: Color, s: float) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		draw_dashed_line(corners[i], corners[(i + 1) % 4], color, 1.5 * s, 3.0 * s)

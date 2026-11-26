extends GdUnitTestSuite
## ChassisView: the panel's pure mapping (grip steps, patch area, placement, hatch) and its
## visibility rules. The reading itself is tests/test_chassis_reading.gd's.

var _root_size: Vector2i


## Every case runs in the project's window: Linux headless is 64 px, too small for any panel.
func before_test() -> void:
	_root_size = get_tree().root.size
	get_tree().root.size = Vector2i(1152, 648)


func after_test() -> void:
	get_tree().root.size = _root_size


func test_grip_steps_are_cool_warm_and_at_the_limit() -> void:
	assert_int(ChassisView.grip_step(0.0)).is_equal(0)
	assert_int(ChassisView.grip_step(0.69)).is_equal(0)
	assert_int(ChassisView.grip_step(0.7)).is_equal(1)
	assert_int(ChassisView.grip_step(0.94)).is_equal(1)
	assert_int(ChassisView.grip_step(0.95)).is_equal(2)
	assert_int(ChassisView.grip_step(1.3)).is_equal(2)


## Area is the share of the load: an even share reads 1, half a four-wheeler's load doubles the
## area (a side of sqrt 2).
func test_patch_area_follows_the_share_of_the_load() -> void:
	assert_float(ChassisView.patch_scale(2500.0, 10000.0, 4)).is_equal_approx(1.0, 1e-6)
	assert_float(ChassisView.patch_scale(5000.0, 10000.0, 4)).is_equal_approx(sqrt(2.0), 1e-6)
	assert_float(ChassisView.patch_scale(625.0, 10000.0, 4)).is_equal_approx(0.5, 1e-6)
	assert_float(ChassisView.patch_scale(0.0, 10000.0, 4)).is_equal(0.0)
	assert_float(ChassisView.patch_scale(100.0, 0.0, 4)).is_equal(0.0)


func test_the_panel_stands_on_the_floor_at_the_right_edge() -> void:
	var view := Vector2(1280.0, 720.0)
	var r := ChassisView.panel_rect(view, 500.0, 10.0, 1.0)
	assert_float(r.end.x).is_equal_approx(view.x - ChassisView.MARGIN, 1e-4)
	assert_float(r.end.y).is_equal_approx(500.0 - ChassisView.GAP, 1e-4)
	assert_vector(r.size).is_equal_approx(ChassisView.PANEL_SIZE, Vector2(1e-4, 1e-4))
	# Twice the scale, twice the panel, given the room.
	var big := ChassisView.panel_rect(view, 700.0, 10.0, 2.0)
	assert_vector(big.size).is_equal_approx(ChassisView.PANEL_SIZE * 2.0, Vector2(1e-4, 1e-4))


## Short of room it shrinks in proportion and never rises above the ceiling; under MIN_H it is gone.
func test_a_short_room_shrinks_the_panel_and_a_tiny_one_drops_it() -> void:
	var view := Vector2(1280.0, 720.0)
	var r := ChassisView.panel_rect(view, 168.0, 10.0, 1.0)
	assert_float(r.position.y).is_greater_equal(10.0 - 1e-4)
	assert_float(r.size.y).is_less(ChassisView.PANEL_SIZE.y)
	assert_float(r.size.x / r.size.y).is_equal_approx(
			ChassisView.PANEL_SIZE.x / ChassisView.PANEL_SIZE.y, 1e-4)
	assert_bool(ChassisView.panel_rect(view, 60.0, 10.0, 1.0).has_area()).is_false()


## The plan fits a layout on whichever axis binds, alike on both, centred: a long two-axle body on
## its length, a wide bogie on its track; a single point sits at the centre.
func test_the_plan_fits_a_layout_on_its_binding_axis() -> void:
	var area := Rect2(10.0, 20.0, 170.0, 216.0)
	var patch := Vector2.ZERO  # no headroom: the layout alone fills the area
	# The semi tractor's anchors (`semi_spec.tres`): 1.44 m across, 3.6 m long; the length binds.
	var semi := Rect2(-0.72, -2.65, 1.44, 3.6)
	var plan := ChassisView.plan_transform(semi, area, patch)
	assert_float(plan.get_scale().x).is_equal_approx(216.0 / 3.6, 1e-3)
	assert_float(plan.get_scale().y).is_equal_approx(plan.get_scale().x, 1e-5)
	assert_float((plan * Vector2(0.0, -2.65)).y).is_equal_approx(area.position.y, 1e-3)
	assert_float((plan * Vector2(0.0, 0.95)).y).is_equal_approx(area.end.y, 1e-3)
	assert_vector(plan * semi.get_center()).is_equal_approx(area.get_center(), Vector2.ONE * 1e-3)
	# A tri-axle bogie, 1.8 m across and 1.6 m long, in a wide area: the track binds.
	var wide := Rect2(0.0, 0.0, 310.0, 226.0)
	var bogie := Rect2(-0.9, 4.4, 1.8, 1.6)
	assert_float(ChassisView.plan_transform(bogie, wide, patch).get_scale().x) \
			.is_equal_approx(226.0 / 1.6, 1e-3)
	assert_float(ChassisView.fit_scale(bogie, Vector2(170.0, 400.0))).is_equal_approx(170.0 / 1.8, 1e-3)
	# One point: scale 1, on the centre.
	var one := Rect2(Vector2(0.5, 2.0), Vector2.ZERO)
	assert_float(ChassisView.fit_scale(one, area.size)).is_equal(1.0)
	assert_vector(ChassisView.plan_transform(one, area, patch) * Vector2(0.5, 2.0)) \
			.is_equal_approx(area.get_center(), Vector2.ONE * 1e-4)


## The legend's words follow the grip steps' thresholds.
func test_the_legend_names_the_grip_steps() -> void:
	var labels := ChassisView.legend_labels()
	assert_int(labels.size()).is_equal(ChassisView.GRIP_COLORS.size())
	assert_str(labels[0]).is_equal("<70%")
	assert_str(labels[1]).is_equal("<95%")
	# Its row, as `_draw_legend` lays it with the theme's font, fits the narrow panel's plot.
	var font: Font = UiTheme.FONT
	var fs := roundi(ChassisView.LEGEND_FS)
	var row := font.get_string_size(ChassisView.LEGEND_TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	for text in labels:
		row += ChassisView.LEGEND_SWATCH + 3.0 \
				+ font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	prints("chassis legend row", row, "px of", ChassisView.plot_size(ChassisView.PANEL_SIZE).x)
	assert_float(row).is_less(ChassisView.plot_size(ChassisView.PANEL_SIZE).x * 0.85)


## Given a span, the panel spans it at its own aspect and keeps that width where the room is short;
## given only a right edge (the rig's), it stands on it at its own size.
func test_a_spanned_panel_lines_up_with_it() -> void:
	var view := Vector2(1280.0, 720.0)
	var full := ChassisView.PANEL_SIZE
	var span := Vector2(1000.0, 1228.0)
	var r := ChassisView.panel_rect(view, 600.0, 10.0, 1.0, full, span)
	assert_float(r.position.x).is_equal_approx(span.x, 1e-4)
	assert_float(r.end.x).is_equal_approx(span.y, 1e-4)
	assert_float(r.size.y).is_equal_approx(228.0 * full.y / full.x, 1e-3)
	assert_float(ChassisView.panel_scale(r, full, 1.0)).is_equal_approx(228.0 / full.x, 1e-4)
	var short := ChassisView.panel_rect(view, 250.0, 10.0, 1.0, full, span)
	assert_float(short.size.x).is_equal_approx(228.0, 1e-4)
	assert_float(short.position.y).is_greater_equal(10.0 - 1e-4)
	assert_float(ChassisView.panel_scale(short, full, 1.0)).is_equal_approx(short.size.y / full.y, 1e-4)
	var rig := ChassisView.RIG_PANEL_SIZE
	var right := ChassisView.panel_rect(view, 600.0, 10.0, 1.0, rig, Vector2(NAN, span.y))
	assert_float(right.end.x).is_equal_approx(span.y, 1e-4)
	assert_vector(right.size).is_equal_approx(rig, Vector2(1e-4, 1e-4))


## A coupled rig's panel is RIG_PANEL_SIZE where there is room, and shrinks like the other.
func test_a_rig_panel_is_bigger_and_still_shrinks() -> void:
	var view := Vector2(1280.0, 720.0)
	var full := ChassisView.RIG_PANEL_SIZE
	var r := ChassisView.panel_rect(view, 500.0, 10.0, 1.0, full)
	assert_vector(r.size).is_equal_approx(full, Vector2(1e-4, 1e-4))
	assert_float(r.end.x).is_equal_approx(view.x - ChassisView.MARGIN, 1e-4)
	var short := ChassisView.panel_rect(view, 200.0, 10.0, 1.0, full)
	assert_float(short.position.y).is_greater_equal(10.0 - 1e-4)
	assert_float(short.size.x / short.size.y).is_equal_approx(full.x / full.y, 1e-4)


## The semi tractor's wheels (`semi_spec.tres`) and the tanker's bogie (`tanker_spec.tres`) on the
## fifth wheel's datum and stops (`semi.tscn` Kingpin, `FifthWheel.YAW_LIMIT_DEG`).
func _semi_with_tanker() -> ChassisReading:
	var r := ChassisReading.new()
	for p: Vector2 in [Vector2(-0.72, -2.65), Vector2(0.72, -2.65), Vector2(-0.62, 0.95),
			Vector2(0.62, 0.95)]:
		var w := ChassisReading.WheelReading.new()
		w.anchor = p
		r.wheels.append(w)
	var t := ChassisReading.new()
	for z: float in [4.4, 5.2, 6.0]:
		for x: float in [-0.72, 0.72]:
			var w := ChassisReading.WheelReading.new()
			w.anchor = Vector2(x, z)
			t.wheels.append(w)
	t.frame = Transform2D(0.0, Vector2(0.0, 0.45))
	t.coupling = Vector2(0.0, 0.45)
	t.yaw_stop = deg_to_rad(Articulation.JACKKNIFE_MAX_DEG)
	r.towed = t
	return r


## The plan holds the trailer swung SWING_HELD_DEG either way and the rig's marks shrink with it:
## about 0.65 for the semi and the tanker, the rig panel filled on both axes; whole for the semi
## alone.
func test_a_rig_fits_its_swing_and_shrinks_its_marks() -> void:
	var r := _semi_with_tanker()
	var unit := ChassisReading.anchor_box(ChassisView.anchors_of(r.wheels))
	var box := ChassisView.layout_box(r)
	var held := ChassisReading.swept_box(ChassisView.anchors_of(r.towed.wheels), r.towed.coupling,
			deg_to_rad(ChassisView.SWING_HELD_DEG))
	assert_bool(box.encloses(unit)).is_true()
	assert_bool(box.encloses(held)).is_true()
	var room := ChassisView.plot_size(ChassisView.RIG_PANEL_SIZE)
	var per_m := ChassisView.fit_scale(box, room)
	assert_float(ChassisView.mark_scale(per_m)).is_equal_approx(0.65, 0.01)
	# Fitted on both axes: the panel is no wider than the held swing needs.
	assert_float(box.size.x * per_m).is_equal_approx(room.x, room.x * 0.03)
	assert_float(box.size.y * per_m).is_equal_approx(room.y, room.y * 0.03)
	r.towed = null
	per_m = ChassisView.fit_scale(ChassisView.layout_box(r),
			ChassisView.plot_size(ChassisView.PANEL_SIZE))
	assert_float(ChassisView.mark_scale(per_m)).is_equal(1.0)


## Every wheeled body alone keeps whole marks: its layout fits the lone panel at MIN_PITCH's scale
## or better (the longest, the conventional truck's 4.4 m, reads 49 px per m against 40).
func test_no_lone_body_shrinks_its_marks() -> void:
	var room := ChassisView.plot_size(ChassisView.PANEL_SIZE)
	var checked := 0
	for id: String in VehicleCatalog.VARIANTS:
		var spec := VehicleCatalog.spec_of(id)
		if spec == null or spec.ground_drive == null or spec.ground_drive.wheel_positions.is_empty():
			continue
		var anchors := PackedVector2Array()
		for p in spec.ground_drive.wheel_positions:
			anchors.append(Vector2(p.x, p.z))
		var per_m := ChassisView.fit_scale(ChassisReading.anchor_box(anchors), room)
		assert_float(ChassisView.mark_scale(per_m)) \
				.override_failure_message("%s: %.1f px per m" % [id, per_m]).is_equal(1.0)
		checked += 1
	assert_int(checked).is_greater(10)


## The plan holds still up to SWING_HELD_DEG, zooms out past it, and never past the stop.
func test_the_plan_holds_still_then_zooms_out_past_the_held_swing() -> void:
	var held := deg_to_rad(ChassisView.SWING_HELD_DEG)
	var stop := deg_to_rad(Articulation.JACKKNIFE_MAX_DEG)
	assert_float(ChassisView.held_swing(0.0, stop)).is_equal_approx(held, 1e-6)
	assert_float(ChassisView.held_swing(-0.5, stop)).is_equal_approx(held, 1e-6)
	assert_float(ChassisView.held_swing(-1.0, stop)).is_equal_approx(1.0, 1e-6)
	assert_float(ChassisView.held_swing(2.0, stop)).is_equal_approx(stop, 1e-6)
	assert_float(ChassisView.held_swing(0.0, 0.3)).is_equal_approx(0.3, 1e-6)
	var r := _semi_with_tanker()
	var straight := ChassisView.layout_box(r)
	r.towed.frame = Transform2D(-held * 0.9, Vector2(0.0, 0.45))
	assert_vector(ChassisView.layout_box(r).size).is_equal_approx(straight.size, Vector2.ONE * 1e-4)
	r.towed.frame = Transform2D(stop, Vector2(0.0, 0.45))
	assert_float(ChassisView.layout_box(r).size.x).is_greater(straight.size.x + 1.0)


## A towed patch is centred where its frame puts its anchor, sized off the rig's load, and stays in
## the area turned with the body anywhere up to the coupling's stops, the plan zoomed to hold it.
func test_a_towed_patch_sits_on_its_framed_anchor() -> void:
	var r := _semi_with_tanker()
	for w in r.towed.wheels:
		w.in_contact = true
		w.normal_load = 20000.0
	var area := Rect2(0.0, 0.0, 210.0, 200.0)
	var patch := Vector2(6.0, 11.0)
	var stop := deg_to_rad(Articulation.JACKKNIFE_MAX_DEG)
	for swing: float in [-stop, -1.0, -0.6, 0.0, 0.6, 1.0, stop]:
		r.towed.frame = Transform2D(swing, Vector2(0.0, 0.45))
		var plan := ChassisView.plan_transform(ChassisView.layout_box(r), area, patch)
		var to_px := plan * r.towed.frame
		var rects := ChassisView.patch_rects(r.towed.wheels, to_px, 120000.0, 10, patch)
		for i in rects.size():
			var at := rects[i].get_center()
			assert_vector(at).is_equal_approx(to_px * r.towed.wheels[i].anchor, Vector2.ONE * 1e-3)
			# The patch as drawn: its rect turned with the body about its centre.
			var half := rects[i].size * 0.5
			for corner: Vector2 in [half, -half, Vector2(half.x, -half.y), Vector2(-half.x, half.y)]:
				assert_bool(area.has_point(at + corner.rotated(swing))) \
						.override_failure_message("wheel %d at %.2f rad leaves %s" % [i, swing, area]) \
						.is_true()
		# Each carries 20000 of the rig's 120000 N over 10 wheels: 5/3 of the even area.
		assert_float(rects[0].get_area() / (patch.x * patch.y)).is_equal_approx(5.0 / 3.0, 1e-3)


func test_hatch_lines_stay_inside_their_rect() -> void:
	var rect := Rect2(10.0, 20.0, 14.0, 26.0)
	var lines := ChassisView.hatch_lines(rect, 5.0)
	assert_int(lines.size()).is_greater(4)
	assert_int(lines.size() % 2).is_equal(0)
	var grown := rect.grow(1e-3)
	for p in lines:
		assert_bool(grown.has_point(p)).override_failure_message("%s outside %s" % [p, rect]).is_true()
	assert_int(ChassisView.hatch_lines(rect, 0.0).size()).is_equal(0)
	assert_int(ChassisView.hatch_lines(Rect2(), 5.0).size()).is_equal(0)


func test_a_rounded_rect_stays_inside_its_rect() -> void:
	var rect := Rect2(5.0, 5.0, 12.0, 20.0)
	var pts := ChassisView.rounded_rect(rect, 3.0)
	assert_int(pts.size()).is_equal(16)
	var grown := rect.grow(1e-3)
	for p in pts:
		assert_bool(grown.has_point(p)).is_true()


## One scale for every wheel: a force equal to the weight over the wheels is `length` px, twice
## that is twice as long, and the cap holds the direction.
func test_force_arrows_share_one_scale() -> void:
	var px := ChassisView.ARROW_LEN
	# 10000 N of weight on four wheels: 2500 N each.
	assert_vector(ChassisView.force_arrow(Vector2(0.0, -2500.0), 10000.0, 4, px)) \
			.is_equal_approx(Vector2(0.0, -px), Vector2.ONE * 1e-4)
	assert_vector(ChassisView.force_arrow(Vector2(-5000.0, 0.0), 10000.0, 4, px)) \
			.is_equal_approx(Vector2(-2.0 * px, 0.0), Vector2.ONE * 1e-4)
	var capped := ChassisView.force_arrow(Vector2(30000.0, 40000.0), 10000.0, 4, px)
	assert_float(capped.length()).is_equal_approx(ChassisView.ARROW_CAP * px, 1e-3)
	assert_vector(capped.normalized()).is_equal_approx(Vector2(0.6, 0.8), Vector2.ONE * 1e-5)
	assert_vector(ChassisView.force_arrow(Vector2(100.0, 0.0), 0.0, 4, px)).is_equal(Vector2.ZERO)


func test_the_body_arrow_reads_g_and_caps() -> void:
	var per_g := ChassisView.BODY_ARROW_LEN
	assert_vector(ChassisView.accel_arrow(Vector2(ChassisView.G * 0.5, 0.0), per_g)) \
			.is_equal_approx(Vector2(per_g * 0.5, 0.0), Vector2.ONE * 1e-4)
	assert_float(ChassisView.accel_arrow(Vector2(0.0, -ChassisView.G * 5.0), per_g).length()) \
			.is_equal_approx(ChassisView.BODY_ARROW_CAP * per_g, 1e-3)


## Up spinning, down locking, the square root of the ratio, a locked wheel the full bar.
func test_a_slip_bar_rises_spinning_and_falls_locking() -> void:
	assert_float(ChassisView.spin_bar(0.0)).is_equal(0.0)
	assert_float(ChassisView.spin_bar(0.09)).is_equal_approx(0.3, 1e-6)
	assert_float(ChassisView.spin_bar(-1.0)).is_equal_approx(-1.0, 1e-6)
	assert_float(ChassisView.spin_bar(4.0)).is_equal_approx(1.0, 1e-6)


## None draws nothing, open and biasing one line (open the thinner), locked two parallel lines.
func test_a_diff_link_follows_its_state() -> void:
	var a := Vector2(10.0, 50.0)
	var b := Vector2(60.0, 50.0)
	assert_int(ChassisView.diff_lines(a, b, ChassisReading.Diff.NONE, 3.0).size()).is_equal(0)
	assert_array(Array(ChassisView.diff_lines(a, b, ChassisReading.Diff.OPEN, 3.0))).is_equal([a, b])
	assert_array(Array(ChassisView.diff_lines(a, b, ChassisReading.Diff.BIASING, 3.0))).is_equal([a, b])
	assert_float(ChassisView.DIFF_WIDTHS[ChassisReading.Diff.OPEN]) \
			.is_less(ChassisView.DIFF_WIDTHS[ChassisReading.Diff.BIASING])
	var locked := ChassisView.diff_lines(a, b, ChassisReading.Diff.LOCKED, 3.0)
	assert_int(locked.size()).is_equal(4)
	assert_float(absf(locked[0].y - locked[2].y)).is_equal_approx(3.0, 1e-5)
	assert_float(locked[0].x).is_equal_approx(a.x, 1e-5)
	assert_float(locked[1].x).is_equal_approx(b.x, 1e-5)


## The plan view puts each patch on its anchor, and the load centre between them by the load.
func test_the_plan_maps_anchors_onto_patches_and_the_load_centre_between() -> void:
	var area := Rect2(0.0, 0.0, 130.0, 170.0)
	var patch := Vector2(14.3, 26.0)
	var wheels := _car_wheels()
	var plan := _plan(wheels, area, patch)
	var rects := _rects(wheels, area, patch)
	for i in wheels.size():
		assert_vector(plan * wheels[i].anchor).is_equal_approx(rects[i].get_center(),
				Vector2.ONE * 1e-3)
	# The right side carries 10000 of 11300 N: the load centre lands right of the middle.
	var points := PackedVector2Array()
	var loads := PackedFloat64Array()
	for w in wheels:
		points.append(w.anchor)
		loads.append(w.normal_load)
	assert_float((plan * ChassisReading.centre_of_loads(points, loads)).x) \
			.is_greater(area.get_center().x)


## Shown only when toggled on, the HUD is up and a wheeled body is bound.
func test_it_shows_only_toggled_on_with_the_hud_up_and_wheels_bound() -> void:
	var view: ChassisView = auto_free(ChassisView.new())
	add_child(view)
	view.set_on(true)
	view.set_shown(true)
	view.bind(null)
	assert_bool(view.visible).is_false()
	assert_bool(view.is_on()).is_true()
	view.set_on(false)
	assert_bool(view.is_on()).is_false()


## A lone body's plan: its wheels' layout fitted to `area`.
func _plan(wheels: Array[ChassisReading.WheelReading], area: Rect2, patch: Vector2) -> Transform2D:
	return ChassisView.plan_transform(ChassisReading.anchor_box(ChassisView.anchors_of(wheels)),
			area, patch)


## A lone body's patches in `area`, on its own load and wheel count.
func _rects(wheels: Array[ChassisReading.WheelReading], area: Rect2,
		patch: Vector2) -> Array[Rect2]:
	return ChassisView.patch_rects(wheels, _plan(wheels, area, patch),
			ChassisView.total_load(wheels), wheels.size(), patch)


## Four wheels: front left / right (1300 / 6000 N), rear left lifted, rear right 4000 N; the
## anchors a car's (front at -z).
func _car_wheels() -> Array[ChassisReading.WheelReading]:
	var out: Array[ChassisReading.WheelReading] = []
	for spec: Array in [[Vector2(-0.8, -1.3), 1300.0, true], [Vector2(0.8, -1.3), 6000.0, true],
			[Vector2(-0.8, 1.4), 0.0, false], [Vector2(0.8, 1.4), 4000.0, true]]:
		var w := ChassisReading.WheelReading.new()
		w.anchor = spec[0]
		w.normal_load = spec[1]
		w.in_contact = spec[2]
		out.append(w)
	return out


## Patches sit where their wheels are (front up, left left), sized by their share; a lifted one
## keeps the even-share size for its outline; all inside the area.
func test_patches_follow_the_layout_and_the_load() -> void:
	var area := Rect2(0.0, 0.0, 130.0, 170.0)
	var patch := Vector2(14.3, 26.0)
	var rects := _rects(_car_wheels(), area, patch)
	assert_int(rects.size()).is_equal(4)
	var fl := rects[0].get_center()
	var fr := rects[1].get_center()
	var rr := rects[3].get_center()
	assert_float(fl.x).is_less(fr.x)
	assert_float(fl.y).is_less(rr.y)
	assert_float(fl.y).is_equal_approx(fr.y, 1e-3)
	# The 6000 N corner carries over twice the 1300 N one's area share of 11300 N.
	assert_float(rects[1].get_area() / rects[0].get_area()).is_equal_approx(6000.0 / 1300.0, 1e-3)
	assert_vector(rects[2].size).is_equal_approx(patch, Vector2(1e-4, 1e-4))
	for r in rects:
		assert_bool(area.encloses(r)).override_failure_message("%s outside %s" % [r, area]).is_true()


## A wheel in contact with no load has a zero-size patch, which the draw marks with a dot rather
## than a polygon it cannot triangulate; the draw runs headless, so an error would print here.
func test_a_reading_with_an_unloaded_contact_draws() -> void:
	var view: ChassisView = auto_free(ChassisView.new())
	add_child(view)
	view.set_process(false)  # no bound body: keep `_process` from dropping the hand-made reading
	var r := ChassisReading.new()
	r.wheels = _car_wheels()
	r.wheels[0].normal_load = 0.0
	r.wheels[1].past_peak = true
	r.wheels[1].grip_use = 0.9
	# Arrows, a held and a plain slip bar, every drawn diff state.
	r.wheels[1].force = Vector2(-4000.0, 1000.0)
	r.wheels[1].driven = true
	r.wheels[1].long_slip = 0.3
	r.wheels[1].tcs_held = true
	r.wheels[3].braked = true
	r.wheels[3].long_slip = -1.0
	r.wheels[2].rear = true
	r.wheels[3].rear = true
	r.front_diff = ChassisReading.Diff.OPEN
	r.rear_diff = ChassisReading.Diff.LOCKED
	r.centre_diff = ChassisReading.Diff.BIASING
	r.accel = Vector2(-6.0, 2.0)
	r.load_centre = Vector2(0.4, 0.0)
	r.mass = 1200.0
	view._reading = r
	view.visible = true
	view.queue_redraw()
	await get_tree().process_frame
	var area := Rect2(0.0, 0.0, 130.0, 170.0)
	assert_float(_rects(r.wheels, area, Vector2(14.3, 26.0))[0].get_area()) \
			.is_equal(0.0)


## A rig draws: the towed body swung, one bogie wheel lifted, one braked and held by its ABS; the
## draw runs headless, so an error would print here.
func test_a_reading_with_a_towed_body_draws() -> void:
	var view: ChassisView = auto_free(ChassisView.new())
	add_child(view)
	view.set_process(false)  # no bound body: keep `_process` from dropping the hand-made reading
	var r := _semi_with_tanker()
	r.mass = 8000.0
	for w in r.wheels:
		w.in_contact = true
		w.normal_load = 30000.0
	var t := r.towed
	t.mass = 30000.0
	t.frame = Transform2D(-0.7, Vector2(0.0, 0.45))
	for w in t.wheels:
		w.in_contact = true
		w.normal_load = 40000.0
		w.force = Vector2(-1000.0, 8000.0)
	t.wheels[0].in_contact = false
	t.wheels[0].normal_load = 0.0
	t.wheels[3].braked = true
	t.wheels[3].abs_held = true
	t.wheels[3].long_slip = -0.2
	t.wheels[5].past_peak = true
	t.load_centre = Vector2(0.4, 5.2)
	view._reading = r
	view.visible = true
	view.queue_redraw()
	await get_tree().process_frame
	assert_object(view._reading.towed).is_not_null()
	# Sliding patches shrunk down through the size where their border leaves no room to hatch: the
	# engine would print `canvas_item_add_multiline` errors here on an empty hatch.
	for w in t.wheels:
		w.past_peak = true
	for load_n: float in [3000.0, 1500.0, 800.0, 400.0, 200.0, 100.0]:
		for i in range(1, t.wheels.size()):
			t.wheels[i].normal_load = load_n * i
		view.queue_redraw()
		await get_tree().process_frame


## With the dashboard and the touch pads up, the panel stands above both and still fits the window.
func test_the_panel_clears_the_dashboard_and_the_touch_pads() -> void:
	var saved := GameState.current_vehicle
	GameState.current_vehicle = "car"
	var dash: Dashboard = auto_free(Dashboard.new())
	add_child(dash)
	dash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dash.bind(null)
	dash.set_shown(true)
	var pads: TouchControls = auto_free(TouchControls.new())
	add_child(pads)
	pads.set_active(true)
	var view: ChassisView = auto_free(ChassisView.new())
	add_child(view)
	view.dock(dash, pads)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(pads.drive_top()).is_less(view.size.y)
	assert_float(view.standing_edge()).is_equal(minf(dash.top_edge(), pads.drive_top()))
	var s := UiTheme.scale_of(view)
	var panel := ChassisView.panel_rect(view.size, view.standing_edge(), ChassisView.MARGIN * s, s)
	prints("chassis panel", panel, "in", view.size, "dash top", dash.top_edge(), "pads top", pads.drive_top())
	assert_bool(panel.has_area()).is_true()
	# Lined up with the car's pedals below: BRAKE/REV's left edge, GAS's right.
	var span := pads.drive_span()
	var row := pads._drive_block.get_child(pads._drive_block.get_child_count() - 1) as Control
	var shown: Array[Control] = []
	for c in row.get_children():
		if (c as Control).visible:
			shown.append(c as Control)
	var cluster_x := pads._pedal_cluster.position.x + pads._drive_block.position.x + row.position.x
	assert_float(span.x).is_equal_approx(cluster_x + shown[0].position.x, 0.5)
	assert_float(span.y).is_equal_approx(cluster_x + shown[-1].position.x + shown[-1].size.x, 0.5)
	var lined := ChassisView.panel_rect(view.size, view.standing_edge(), ChassisView.MARGIN * s, s,
			ChassisView.PANEL_SIZE, span)
	prints("chassis panel on the pedals", lined, "span", span)
	assert_float(lined.position.x).is_equal_approx(span.x, 1e-3)
	assert_float(lined.end.x).is_equal_approx(span.y, 1e-3)
	pads.set_active(false)
	assert_float(pads.drive_top()).is_equal(INF)
	assert_bool(is_nan(pads.drive_span().x)).is_true()
	GameState.current_vehicle = saved


## Bound to the verification pad's spawned car, it shows and reads every wheel each tick.
func test_it_reads_a_spawned_cars_wheels() -> void:
	var level: Level = auto_free((load("res://src/levels/dev/chassis_pad/chassis_pad.tscn")
			as PackedScene).instantiate())
	add_child(level)
	await get_tree().physics_frame
	var view: ChassisView = auto_free(ChassisView.new())
	add_child(view)
	view.set_on(true)
	view.set_shown(true)
	view.bind(level)
	assert_bool(view.visible).is_true()
	for i in 10:
		await get_tree().physics_frame
	await get_tree().process_frame
	assert_object(view._reading).is_not_null()
	assert_int(view._reading.wheels.size()).is_equal(level.vehicle.drive.wheels.size())
	assert_float(view._reading.mass).is_equal(level.vehicle.mass)
	view.bind(null)
	assert_bool(view.visible).is_false()
	remove_child(level)
	level.free()


## On the verification pad the semi with the tanker coupled reads its trailer live: the bogie
## settles onto its six wheels, carrying the trailer's weight less the kingpin's share.
func test_it_reads_a_spawned_semis_trailer() -> void:
	var saved := GameState.current_vehicle
	var saved_variant := GameState.current_variant
	var level: Level = auto_free((load("res://src/levels/dev/chassis_pad/chassis_pad.tscn")
			as PackedScene).instantiate())
	level.initial_variant = "semi"
	add_child(level)
	assert_object(level.vehicle as SemiTractor).is_not_null()
	await get_tree().physics_frame
	var host := level.vehicle.get_node("FifthWheel") as TowHost
	if not host.is_coupled():
		assert_bool(host.couple(
				load("res://src/vehicles/truck/trailers/tanker.tscn") as PackedScene)).is_true()
	var view: ChassisView = auto_free(ChassisView.new())
	add_child(view)
	view.set_on(true)
	view.set_shown(true)
	view.bind(level)
	for i in 90:
		await get_tree().physics_frame
	await get_tree().process_frame
	var t := view._reading.towed
	assert_object(t).is_not_null()
	assert_int(t.wheels.size()).is_equal(6)
	var bogie := ChassisView.total_load(t.wheels)
	var expect := host.trailer.mass * (1.0 - host.trailer.kingpin_share()) * ChassisView.G
	prints("chassis pad semi + tanker: bogie", bogie, "N, expected", expect, "N, frame",
			t.frame)
	for w in t.wheels:
		assert_bool(w.in_contact).is_true()
	assert_float(bogie).is_equal_approx(expect, expect * 0.15)
	assert_float(absf(t.frame.get_rotation())).is_less(0.02)
	view.bind(null)
	host.uncouple()
	remove_child(level)
	level.free()
	GameState.current_vehicle = saved
	GameState.current_variant = saved_variant


## The dashboard's top edge is its panel's while shown, its own bottom while hidden.
func test_the_dashboard_reports_its_top_edge() -> void:
	var saved := GameState.current_vehicle
	GameState.current_vehicle = "car"
	var dash: Dashboard = auto_free(Dashboard.new())
	add_child(dash)
	dash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dash.set_pins({"car": "compact"})
	dash.bind(null)
	dash.set_shown(true)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(dash.top_edge()).is_less(dash.size.y)
	assert_float(dash.top_edge()).is_greater(0.0)
	dash.set_shown(false)
	assert_float(dash.top_edge()).is_equal(dash.size.y)
	GameState.current_vehicle = saved

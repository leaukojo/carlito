extends GdUnitTestSuite
## RoadBuilder / RoadProfile pure fns + the baker's road integration:
## curvature-adaptive sampling, ribbon extrusion (winding must stay up-facing
## for BOTH curve directions — a flipped ribbon is drive-through), banking from tilt,
## the conform flatten mask (floor-quantized so the 8-bit PNG never sits above the
## road), and split_arrays_by_chunk. Hand-checkable numbers throughout, same discipline
## as Drivetrain. Curve3D and Image are headless-constructible, so everything runs in CI.

const Builder := preload("res://kit/helpers/road_builder.gd")
const Profile := preload("res://kit/helpers/road_profile.gd")
const Baker := preload("res://kit/bake/level_baker.gd")
const RoadPathScript := preload("res://kit/helpers/road_path.gd")


func _straight(a: Vector3, b: Vector3) -> Curve3D:
	var c := Curve3D.new()
	c.add_point(a)
	c.add_point(b)
	return c


## Quarter arc of radius 20 in the XZ plane (bezier circle approximation, handle
## length r * 0.5523).
func _quarter_arc() -> Curve3D:
	var c := Curve3D.new()
	var h := 20.0 * 0.5523
	c.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, h))
	c.add_point(Vector3(20, 0, 20), Vector3(-h, 0, 0), Vector3.ZERO)
	return c


# -------------------------------------------------------------- min turn radius


func test_min_turn_radius_straight_is_infinite() -> void:
	assert_bool(Builder.min_turn_radius(
			_straight(Vector3.ZERO, Vector3(0, 0, 100)), 6.0, 6.0) == INF).is_true()


func test_min_turn_radius_arc_matches_radius() -> void:
	# quarter arc of radius 20: every local radius is ~20
	assert_float(Builder.min_turn_radius(_quarter_arc(), 6.0, 6.0)) \
			.is_equal_approx(20.0, 1.5)


func test_min_turn_radius_pure_crest_is_infinite() -> void:
	# vertical kink only (no lateral turn): the fold clamp ignores it, so does the guard
	var c := Curve3D.new()
	c.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 5))
	c.add_point(Vector3(0, 6, 12), Vector3(0, 0, -4), Vector3(0, 0, 4))
	c.add_point(Vector3(0, 0, 24), Vector3(0, 0, -5), Vector3.ZERO)
	assert_bool(Builder.min_turn_radius(c, 6.0, 6.0) == INF).is_true()


func test_min_turn_radius_flags_hairpin_below_half_width() -> void:
	# the level_1 pathology: two near-coincident clicks across a 4 m drop; the
	# smoothed middle point hairpins the curve far under the ~6 m ribbon half-width
	var c := Curve3D.new()
	c.add_point(Vector3(9.947, 23.362, 58.729))
	c.add_point(Vector3(10.652, 19.256, 57.171),
			Vector3(-1.389, 0.222, 0.468), Vector3(4.325, -0.690, -1.456))
	c.add_point(Vector3(24, 21.12, 54), Vector3(-4, 0, 0), Vector3.ZERO)
	assert_bool(Builder.min_turn_radius(c, 6.0, 6.0) < 3.0).is_true()


# --------------------------------------------------------------- adaptive sampling


func test_adaptive_straight_is_uniform_coarse() -> void:
	var offsets := Builder.adaptive_offsets(_straight(Vector3.ZERO, Vector3(0, 0, 100)), 6.0, 6.0)
	# ceil(100/6) = 17 segments -> 18 offsets, no curvature subdivision
	assert_int(offsets.size()).is_equal(18)
	assert_float(offsets[0]).is_equal(0.0)
	assert_float(offsets[17]).is_equal_approx(100.0, 0.01)
	var step := offsets[1] - offsets[0]
	for i in range(1, offsets.size()):
		assert_bool(offsets[i] > offsets[i - 1]).is_true()
		assert_float(offsets[i] - offsets[i - 1]).is_equal_approx(step, 0.001)


func test_adaptive_arc_subdivides_and_bounds_angle() -> void:
	var arc := _quarter_arc()
	var arc_offsets := Builder.adaptive_offsets(arc, 6.0, 6.0)
	var length := arc.get_baked_length()
	var straight_offsets := Builder.adaptive_offsets(
			_straight(Vector3.ZERO, Vector3(0, 0, length)), 6.0, 6.0)
	assert_bool(arc_offsets.size() > straight_offsets.size()).is_true()
	# every final segment's end tangents agree within the budget (or hit the MIN_SEG floor)
	for i in range(1, arc_offsets.size()):
		var a := arc_offsets[i - 1]
		var b := arc_offsets[i]
		var angle := Builder.tangent_at(arc, a, length).angle_to(
				Builder.tangent_at(arc, b, length))
		assert_bool(angle <= deg_to_rad(6.0) + 0.02 or b - a <= Builder.MIN_SEG + 0.001).is_true()


func test_adaptive_is_deterministic() -> void:
	var arc := _quarter_arc()
	assert_that(Builder.adaptive_offsets(arc, 6.0, 6.0)) \
			.is_equal(Builder.adaptive_offsets(arc, 6.0, 6.0))


## Zero-handle corner: an offset must land exactly on the interior control point (the
## miter ring — its central-difference tangent is the corner's angle bisector), and
## the list stays strictly increasing.
func test_adaptive_offsets_anchor_interior_control_points() -> void:
	var c := Curve3D.new()
	c.add_point(Vector3.ZERO)
	c.add_point(Vector3(20, 0, 0))
	c.add_point(Vector3(20, 0, 20))
	var length := c.get_baked_length()
	var corner := c.get_closest_offset(Vector3(20, 0, 0))
	var offsets := Builder.adaptive_offsets(c, 6.0, 6.0)
	var best := INF
	for i in range(1, offsets.size()):
		assert_bool(offsets[i] > offsets[i - 1]).is_true()
		best = minf(best, absf(offsets[i] - corner))
	assert_float(best).is_equal_approx(0.0, 0.01)
	# the ring AT the corner frames along the bisector of the two segment directions
	var t := Builder.tangent_at(c, corner, length)
	assert_float(t.dot(Vector3(1, 0, 1).normalized())).is_equal_approx(1.0, 0.01)


func test_smooth_handles_catmull_rom() -> void:
	var h: Dictionary = Builder.smooth_handles(
			Vector3.ZERO, Vector3(10, 0, 0), Vector3(10, 0, 10))
	var dir := Vector3(10, 0, 10).normalized()
	assert_vector(h["in"]).is_equal_approx(-dir * (10.0 / 3.0), Vector3.ONE * 0.001)
	assert_vector(h["out"]).is_equal_approx(dir * (10.0 / 3.0), Vector3.ONE * 0.001)
	# coincident neighbours degenerate to zero handles
	var d: Dictionary = Builder.smooth_handles(Vector3.ONE, Vector3(5, 0, 0), Vector3.ONE)
	assert_vector(d["in"]).is_equal(Vector3.ZERO)
	assert_vector(d["out"]).is_equal(Vector3.ZERO)


func test_adaptive_degenerate_curves_are_empty() -> void:
	assert_int(Builder.adaptive_offsets(null, 6.0, 6.0).size()).is_equal(0)
	assert_int(Builder.adaptive_offsets(Curve3D.new(), 6.0, 6.0).size()).is_equal(0)
	var one := Curve3D.new()
	one.add_point(Vector3(3, 0, 0))
	assert_int(Builder.adaptive_offsets(one, 6.0, 6.0).size()).is_equal(0)
	assert_int(Builder.adaptive_offsets(
			_straight(Vector3(3, 0, 0), Vector3(3, 0, 0)), 6.0, 6.0).size()).is_equal(0)


# ------------------------------------------------------------- draw-mode primitives


## Curve3D from an arc_points result (what the draw tool commits).
func _arc_curve(start: Vector3, res: Dictionary) -> Curve3D:
	var c := Curve3D.new()
	c.add_point(start, Vector3.ZERO, res.start_out)
	for p: Dictionary in res.points:
		c.add_point(p["pos"], p["in"], p["out"])
	return c


func test_arc_points_quarter_arc_matches_bezier_circle() -> void:
	# start at origin heading +Z, end (20, 0, 20): the r=20 quarter arc — one cubic
	# whose handle length is r * 0.5523 (the _quarter_arc fixture's constant)
	var res: Dictionary = Builder.arc_points(
			Vector3.ZERO, Vector3(0, 0, 1), Vector3(20, 0, 20))
	assert_float(res.radius).is_equal_approx(20.0, 0.01)
	var pts: Array = res.points
	assert_int(pts.size()).is_equal(1)
	assert_vector(pts[0]["pos"]).is_equal_approx(Vector3(20, 0, 20), Vector3.ONE * 0.001)
	var h := 20.0 * 0.5523
	assert_vector(res.start_out).is_equal_approx(Vector3(0, 0, h), Vector3.ONE * 0.01)
	assert_vector(pts[0]["in"]).is_equal_approx(Vector3(-h, 0, 0), Vector3.ONE * 0.01)
	assert_vector(pts[0]["out"]).is_equal_approx(Vector3(h, 0, 0), Vector3.ONE * 0.01)
	# max radial error of the 90-degree cubic approximation is ~2.7e-4 * r
	var center := Vector3(20, 0, 0)
	for p in _arc_curve(Vector3.ZERO, res).get_baked_points():
		assert_float(absf(p.distance_to(center) - 20.0)).is_less(0.02)


func test_arc_points_reflex_splits_and_stays_on_circle() -> void:
	# r=10 turning left (center (-10, 0, 0)), 200-degree sweep -> 3 cubics
	var a := deg_to_rad(200.0)
	var end := Vector3(-10.0 + 10.0 * cos(a), 0, 10.0 * sin(a))
	var res: Dictionary = Builder.arc_points(Vector3.ZERO, Vector3(0, 0, 1), end)
	assert_float(res.radius).is_equal_approx(10.0, 0.01)
	var pts: Array = res.points
	assert_int(pts.size()).is_equal(3)
	assert_vector(pts[2]["pos"]).is_equal_approx(end, Vector3.ONE * 0.001)
	var center := Vector3(-10, 0, 0)
	for p in _arc_curve(Vector3.ZERO, res).get_baked_points():
		assert_float(absf(p.distance_to(center) - 10.0)).is_less(0.02)


func test_arc_points_sloped_keeps_tangent_continuity() -> void:
	# the reflex arc climbing 6 m: every join is C1 by construction (in == -out incl.
	# the slope term) and the sampled tangent at each emitted point matches its handle
	var a := deg_to_rad(200.0)
	var end := Vector3(-10.0 + 10.0 * cos(a), 6.0, 10.0 * sin(a))
	var res: Dictionary = Builder.arc_points(Vector3.ZERO, Vector3(0, 0, 1), end)
	var pts: Array = res.points
	for p: Dictionary in pts:
		assert_vector(p["in"]).is_equal_approx(-(p["out"] as Vector3), Vector3.ONE * 1e-5)
	var curve := _arc_curve(Vector3.ZERO, res)
	var length := curve.get_baked_length()
	for p: Dictionary in pts:
		var o := curve.get_closest_offset(p["pos"])
		var t := Builder.tangent_at(curve, o, length)
		var expect: Vector3 = (p["out"] as Vector3).normalized()
		assert_float(rad_to_deg(t.angle_to(expect))).is_less(2.0)


func test_arc_points_collinear_falls_back_to_straight() -> void:
	var res: Dictionary = Builder.arc_points(
			Vector3.ZERO, Vector3(0, 0, 1), Vector3(0, 0, 30))
	assert_bool(res.radius == INF).is_true()
	var pts: Array = res.points
	assert_int(pts.size()).is_equal(1)
	assert_vector(pts[0]["pos"]).is_equal(Vector3(0, 0, 30))
	assert_vector(pts[0]["in"]).is_equal(Vector3.ZERO)
	assert_vector(res.start_out).is_equal(Vector3.ZERO)


func test_snap_direction_snaps_heading_preserving_length_and_y() -> void:
	# a 50-degree heading with 45-degree steps lands on 45; XZ length and Y survive
	var dir := Vector3(cos(deg_to_rad(50.0)), 2.0, sin(deg_to_rad(50.0)))
	var snapped_dir: Vector3 = Builder.snap_direction(dir, 45.0)
	assert_vector(snapped_dir).is_equal_approx(
			Vector3(cos(deg_to_rad(45.0)), 2.0, sin(deg_to_rad(45.0))),
			Vector3.ONE * 0.0001)
	# step 0 = off; a vertical dir passes through untouched
	assert_vector(Builder.snap_direction(Vector3(1, 0, 2), 0.0)).is_equal(Vector3(1, 0, 2))
	assert_vector(Builder.snap_direction(Vector3(0, 3, 0), 45.0)).is_equal(Vector3(0, 3, 0))


func test_end_tangent_out_reads_handles() -> void:
	var c := Curve3D.new()
	c.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 4))        # start out = +Z
	c.add_point(Vector3(0, 0, 12), Vector3(0, 0, -4), Vector3.ZERO)  # last in = -Z
	# first end points AWAY from the road (backward, -Z); last end forward (+Z)
	assert_vector(Builder.end_tangent_out(c, false)).is_equal_approx(
			Vector3(0, 0, -1), Vector3.ONE * 0.0001)
	assert_vector(Builder.end_tangent_out(c, true)).is_equal_approx(
			Vector3(0, 0, 1), Vector3.ONE * 0.0001)


func test_end_tangent_out_chord_fallback_when_no_handles() -> void:
	var c := Curve3D.new()
	c.add_point(Vector3.ZERO)          # zero handles (polyline / Straight ends)
	c.add_point(Vector3(0, 0, 12))
	# first: (start - second) = -Z away; last: (last - prev) = +Z forward
	assert_vector(Builder.end_tangent_out(c, false)).is_equal_approx(
			Vector3(0, 0, -1), Vector3.ONE * 0.0001)
	assert_vector(Builder.end_tangent_out(c, true)).is_equal_approx(
			Vector3(0, 0, 1), Vector3.ONE * 0.0001)


func test_end_tangent_out_degenerate_is_zero() -> void:
	var c := Curve3D.new()
	c.add_point(Vector3.ZERO)
	assert_bool(Builder.end_tangent_out(c, true) == Vector3.ZERO).is_true()
	assert_bool(Builder.end_tangent_out(null, false) == Vector3.ZERO).is_true()


func test_first_coincident_index_flags_zero_length_segments() -> void:
	var clean := Curve3D.new()
	clean.add_point(Vector3.ZERO)
	clean.add_point(Vector3(0, 0, 12))
	clean.add_point(Vector3(0, 0, 24))
	assert_int(Builder.first_coincident_index(clean)).is_equal(-1)
	# points 1 and 2 coincide (the snapped-end stacking that spawned the Curve3D errors)
	var dup := Curve3D.new()
	dup.add_point(Vector3.ZERO)
	dup.add_point(Vector3(0, 0, 12))
	dup.add_point(Vector3(0, 0, 12))
	dup.add_point(Vector3(0, 0, 24))
	assert_int(Builder.first_coincident_index(dup)).is_equal(2)
	assert_int(Builder.first_coincident_index(null)).is_equal(-1)


# ------------------------------------------------------------------ cross-section


func test_asphalt_cross_section() -> void:
	var p: Resource = Profile.new()   # defaults: 3.5 / 0.6 / 0.15 / 0.3 / 0.5
	var cs: Dictionary = p.call("cross_section")
	var points: PackedVector2Array = cs.points
	var mats: PackedInt32Array = cs.mats
	assert_int(points.size()).is_equal(8)
	assert_that(mats).is_equal(PackedInt32Array([2, 2, 1, 0, 1, 2, 2]))
	# mirror-symmetric laterals from the width exports
	var expect := PackedFloat32Array([-4.75, -4.25, -3.65, -3.5, 3.5, 3.65, 4.25, 4.75])
	for i in points.size():
		assert_float(points[i].x).is_equal_approx(expect[i], 0.0001)
	assert_float(points[0].y).is_equal_approx(-0.3, 0.0001)   # drop skirt ends
	assert_float(points[7].y).is_equal_approx(-0.3, 0.0001)
	assert_float(points[3].y).is_equal(0.0)
	assert_float(float(p.call("paved_half_width"))).is_equal_approx(4.25, 0.0001)
	assert_float(float(p.call("full_half_width"))).is_equal_approx(4.75, 0.0001)


func test_gravel_cross_section_drops_zero_width_strips() -> void:
	var p: Resource = Profile.new()
	p.set("edge_line_width", 0.0)
	var cs: Dictionary = p.call("cross_section")
	assert_int((cs.points as PackedVector2Array).size()).is_equal(6)
	assert_that(cs.mats).is_equal(PackedInt32Array([2, 2, 0, 2, 2]))


func test_base_depth_zero_is_a_plain_road() -> void:
	# The bridge base is opt-in: base_depth 0 (the default) leaves every non-bridge
	# profile byte-identical, so no existing bake changes.
	var p: Resource = Profile.new()
	p.set("base_depth", 0.0)
	var cs: Dictionary = p.call("cross_section")
	assert_int((cs.points as PackedVector2Array).size()).is_equal(8)
	assert_that(cs.mats).is_equal(PackedInt32Array([2, 2, 1, 0, 1, 2, 2]))
	assert_int((p.call("materials") as Array).size()).is_equal(4)   # base slot present


func test_base_depth_appends_box_below_outer_edges() -> void:
	var p: Resource = Profile.new()   # defaults: outer half-width 4.75, skirt y -0.3
	p.set("base_depth", 2.0)
	var cs: Dictionary = p.call("cross_section")
	var points: PackedVector2Array = cs.points
	assert_int(points.size()).is_equal(11)
	assert_that(cs.mats).is_equal(PackedInt32Array([2, 2, 1, 0, 1, 2, 2, 3, 3, 3]))
	# box continues the open polyline: right wall down, bottom right->left, left wall up
	assert_float(points[8].x).is_equal_approx(4.75, 0.0001)
	assert_float(points[8].y).is_equal_approx(-2.3, 0.0001)    # right wall bottom
	assert_float(points[9].x).is_equal_approx(-4.75, 0.0001)
	assert_float(points[9].y).is_equal_approx(-2.3, 0.0001)    # bottom-left
	assert_float(points[10].x).is_equal_approx(-4.75, 0.0001)
	assert_float(points[10].y).is_equal_approx(-0.3, 0.0001)   # left wall top
	# the box hangs straight down — no extra lateral reach for conform / the fold limit
	assert_float(float(p.call("full_half_width"))).is_equal_approx(4.75, 0.0001)


# ---------------------------------------------------------------------- extrusion


func _extrude_straight(banked := false, a := Vector3.ZERO, b := Vector3(0, 0, 12),
		tilt := 0.0) -> Dictionary:
	var curve := _straight(a, b)
	if tilt != 0.0:
		curve.set_point_tilt(0, tilt)
		curve.set_point_tilt(1, tilt)
	var p: Resource = Profile.new()
	var cs: Dictionary = p.call("cross_section")
	var offsets := Builder.adaptive_offsets(curve, 6.0, 6.0)   # [0, 6, 12]
	return Builder.extrude(curve, cs.points, cs.mats, offsets, banked)


func test_extrude_vertex_counts_per_slot() -> void:
	var surfaces := _extrude_straight()
	# 3 rings x 2 verts x strips-per-slot: surface 1 strip, line 2, shoulder 4
	assert_int((surfaces[0][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(6)
	assert_int((surfaces[1][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(12)
	assert_int((surfaces[2][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(24)
	# 2 quads per strip -> 4 triangles -> 12 indices per strip
	assert_int((surfaces[0][Mesh.ARRAY_INDEX] as PackedInt32Array).size()).is_equal(12)
	assert_int((surfaces[2][Mesh.ARRAY_INDEX] as PackedInt32Array).size()).is_equal(48)


func test_extrude_positions_honor_profile_widths() -> void:
	var surfaces := _extrude_straight()
	for v: Vector3 in (surfaces[0][Mesh.ARRAY_VERTEX] as PackedVector3Array):
		assert_float(absf(v.x)).is_equal_approx(3.5, 0.0001)   # lane edges
		assert_float(v.y).is_equal(0.0)
		assert_bool([0.0, 6.0, 12.0].any(func(z: float) -> bool:
				return absf(v.z - z) < 0.01)).is_true()


func test_extrude_flat_normals_up_and_drop_tilts_outward() -> void:
	var surfaces := _extrude_straight()
	for n: Vector3 in (surfaces[0][Mesh.ARRAY_NORMAL] as PackedVector3Array):
		assert_bool(n.is_equal_approx(Vector3.UP)).is_true()
	# shoulder slot holds the drop skirts: some normals lean sideways, all stay upward
	var leaned := false
	for n: Vector3 in (surfaces[2][Mesh.ARRAY_NORMAL] as PackedVector3Array):
		assert_bool(n.y > 0.0).is_true()
		if absf(n.x) > 0.1:
			leaned = true
	assert_bool(leaned).is_true()


func test_extrude_uvs_are_lateral_and_arc_length() -> void:
	var surfaces := _extrude_straight()
	var uvs: PackedVector2Array = surfaces[0][Mesh.ARRAY_TEX_UV]
	var pos: PackedVector3Array = surfaces[0][Mesh.ARRAY_VERTEX]
	for i in uvs.size():
		assert_float(absf(uvs[i].x)).is_equal_approx(3.5, 0.0001)   # u = lateral meters
		assert_float(uvs[i].y).is_equal_approx(pos[i].z, 0.01)      # v = arc meters


func _assert_up_facing(surfaces: Dictionary) -> void:
	for slot in surfaces:
		var pos: PackedVector3Array = surfaces[slot][Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = surfaces[slot][Mesh.ARRAY_INDEX]
		for i in range(0, idx.size(), 3):
			var cross := (pos[idx[i + 1]] - pos[idx[i]]).cross(pos[idx[i + 2]] - pos[idx[i]])
			# CW seen from above = Godot front face up = geometric cross points DOWN
			assert_bool(cross.y < -1e-6).is_true()


func test_extrude_winding_up_facing_both_directions() -> void:
	_assert_up_facing(_extrude_straight(false, Vector3.ZERO, Vector3(0, 0, 12)))
	_assert_up_facing(_extrude_straight(false, Vector3(0, 0, 12), Vector3.ZERO))


## Every triangle's Godot front face (= -geometric cross) must align with its authored
## outward vertex normal (cross . normal < 0). Generalizes _assert_up_facing to the bridge
## base, whose walls face sideways and bottom faces down — so a single-sided material can
## never render the box inside-out.
func _assert_faces_outward(surfaces: Dictionary) -> void:
	for slot in surfaces:
		var pos: PackedVector3Array = surfaces[slot][Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = surfaces[slot][Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = surfaces[slot][Mesh.ARRAY_INDEX]
		for i in range(0, idx.size(), 3):
			var cross := (pos[idx[i + 1]] - pos[idx[i]]).cross(pos[idx[i + 2]] - pos[idx[i]])
			assert_bool(cross.dot(nrm[idx[i]]) < -1e-6).is_true()


func test_extrude_bridge_base_all_faces_outward() -> void:
	var p: Resource = Profile.new()
	p.set("base_depth", 2.0)
	var cs: Dictionary = p.call("cross_section")
	var curve := _straight(Vector3.ZERO, Vector3(0, 0, 12))
	var offsets := Builder.adaptive_offsets(curve, 6.0, 6.0)
	var surfaces := Builder.extrude(curve, cs.points, cs.mats, offsets, false)
	_assert_faces_outward(surfaces)
	# the base slot exists and includes a downward-facing bottom strip
	assert_bool(surfaces.has(Profile.SLOT_BASE)).is_true()
	var found_down := false
	for n: Vector3 in (surfaces[Profile.SLOT_BASE][Mesh.ARRAY_NORMAL] as PackedVector3Array):
		if n.y < -0.9:
			found_down = true
	assert_bool(found_down).is_true()


## A closed cross-section (RoadProfile's base_depth box) encloses a solid volume, so both
## ends must be capped. Sweeping it alone produced an open tube: you looked straight down
## a bridge's open end into its hollow interior, and since the box's walls and floor are
## welded into the drivable body, a vehicle entering through an open end sat inside it and
## dropped out through the back faces of the floor.
func test_extrude_bridge_base_is_capped_at_both_ends() -> void:
	var p: Resource = Profile.new()
	p.set("base_depth", 2.0)
	var cs: Dictionary = p.call("cross_section")
	var curve := _straight(Vector3.ZERO, Vector3(0, 0, 12))
	var offsets := Builder.adaptive_offsets(curve, 6.0, 6.0)
	var surfaces := Builder.extrude(curve, cs.points, cs.mats, offsets, false)
	# the road runs along +Z, so the caps are the only faces pointing along Z
	var nrm: PackedVector3Array = surfaces[Profile.SLOT_BASE][Mesh.ARRAY_NORMAL]
	var back := 0
	var front := 0
	for n: Vector3 in nrm:
		if n.z < -0.99:
			back += 1
		elif n.z > 0.99:
			front += 1
	assert_int(back).is_greater(0)    # cap at the start ring, facing -T
	assert_int(front).is_greater(0)   # cap at the end ring, facing +T
	# caps included, every triangle still fronts along its own normal
	_assert_faces_outward(surfaces)


## Caps are opt-in with the box: an open profile (every non-bridge road) gains nothing, so
## no existing bake changes shape.
func test_extrude_plain_profile_has_no_end_caps() -> void:
	var surfaces := _extrude_straight()
	for slot in surfaces:
		for n: Vector3 in (surfaces[slot][Mesh.ARRAY_NORMAL] as PackedVector3Array):
			assert_float(absf(n.z)).is_less(0.01)   # nothing faces along the road


func test_extrude_banking_rotates_about_tangent() -> void:
	var banked := _extrude_straight(true, Vector3.ZERO, Vector3(0, 0, 12), 0.3)
	# T = +Z, so tilt 0.3 rotates UP about +Z: (-sin 0.3, cos 0.3, 0)
	var expect := Vector3(-sin(0.3), cos(0.3), 0)
	for n: Vector3 in (banked[0][Mesh.ARRAY_NORMAL] as PackedVector3Array):
		assert_bool(n.is_equal_approx(expect)).is_true()
	# banked=false ignores the authored tilt entirely
	var flat := _extrude_straight(false, Vector3.ZERO, Vector3(0, 0, 12), 0.3)
	for n: Vector3 in (flat[0][Mesh.ARRAY_NORMAL] as PackedVector3Array):
		assert_bool(n.is_equal_approx(Vector3.UP)).is_true()


func test_faces_from_surfaces_flattens_all_triangles() -> void:
	var surfaces := _extrude_straight()
	var faces := Builder.faces_from_surfaces(surfaces)
	assert_int(faces.size()).is_equal(12 + 24 + 48)   # every index becomes a soup vert
	# soup verts come from the surface verts (spot-check containment)
	var pos: PackedVector3Array = surfaces[0][Mesh.ARRAY_VERTEX]
	assert_bool(Array(faces).has(pos[0])).is_true()


# ------------------------------------------------------- extrusion: fold clamp / seam


## Quarter arc of radius 3 in the XZ plane — tighter than the 4.75 m asphalt
## half-width, so the inside-edge fold clamp must engage.
func _tight_arc() -> Curve3D:
	var c := Curve3D.new()
	var h := 3.0 * 0.5523
	c.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, h))
	c.add_point(Vector3(3, 0, 3), Vector3(-h, 0, 0), Vector3.ZERO)
	return c


## Single full-width strip: surfaces[0] verts come in rings of (left, right) pairs, so
## edge progression is directly checkable.
func _edge_cross_section() -> Dictionary:
	return {"points": PackedVector2Array([Vector2(-4.75, 0), Vector2(4.75, 0)]),
			"mats": PackedInt32Array([0])}


## The fold clamp: on a turn tighter than the half-width, neither ribbon edge may
## sweep backwards between adjacent rings (unclamped, the inside edge folds).
func test_extrude_tight_arc_inside_edge_never_reverses() -> void:
	var arc := _tight_arc()
	var length := arc.get_baked_length()
	var cs := _edge_cross_section()
	var offsets := Builder.adaptive_offsets(arc, 6.0, 6.0)
	var surfaces := Builder.extrude(arc, cs.points, cs.mats, offsets, false)
	var pos: PackedVector3Array = surfaces[0][Mesh.ARRAY_VERTEX]
	assert_int(pos.size()).is_equal(offsets.size() * 2)
	for i in offsets.size() - 1:
		var t_avg := (Builder.tangent_at(arc, offsets[i], length)
				+ Builder.tangent_at(arc, offsets[i + 1], length)).normalized()
		for side in 2:
			var d := pos[(i + 1) * 2 + side] - pos[i * 2 + side]
			assert_bool(d.dot(t_avg) >= -1e-6).is_true()
	# the clamp actually engaged: some rings are narrower than the full 9.5 m
	var narrowed := false
	for i in offsets.size():
		if pos[i * 2].distance_to(pos[i * 2 + 1]) < 9.5 - 0.01:
			narrowed = true
	assert_bool(narrowed).is_true()
	# UVs keep the profile lateral, not the clamped one
	for v: Vector2 in (surfaces[0][Mesh.ARRAY_TEX_UV] as PackedVector2Array):
		assert_float(absf(v.x)).is_equal_approx(4.75, 0.0001)


## A wide arc (radius 20 >> half-width) is untouched by the clamp: every ring keeps
## the full profile width. (Straights are covered by the exact-width tests above.)
func test_extrude_wide_arc_is_not_clamped() -> void:
	var arc := _quarter_arc()
	var cs := _edge_cross_section()
	var offsets := Builder.adaptive_offsets(arc, 6.0, 6.0)
	var surfaces := Builder.extrude(arc, cs.points, cs.mats, offsets, false)
	var pos: PackedVector3Array = surfaces[0][Mesh.ARRAY_VERTEX]
	for i in offsets.size():
		assert_float(pos[i * 2].distance_to(pos[i * 2 + 1])).is_equal_approx(9.5, 0.0001)


func test_extrude_tight_arc_is_deterministic() -> void:
	var cs := _edge_cross_section()
	var a_arc := _tight_arc()
	var b_arc := _tight_arc()
	var a := Builder.extrude(a_arc, cs.points, cs.mats,
			Builder.adaptive_offsets(a_arc, 6.0, 6.0), false)
	var b := Builder.extrude(b_arc, cs.points, cs.mats,
			Builder.adaptive_offsets(b_arc, 6.0, 6.0), false)
	assert_that(a[0][Mesh.ARRAY_VERTEX]).is_equal(b[0][Mesh.ARRAY_VERTEX])
	assert_that(a[0][Mesh.ARRAY_INDEX]).is_equal(b[0][Mesh.ARRAY_INDEX])


## Closed loop (first == last control position): both end rings get the bisector of
## the two end tangents, so they share one frame — identical verts, identical right
## vectors — instead of a crease/wedge at the seam.
func test_extrude_closed_square_loop_seam_rings_coincide() -> void:
	var c := Curve3D.new()
	c.add_point(Vector3.ZERO)
	c.add_point(Vector3(20, 0, 0))
	c.add_point(Vector3(20, 0, 20))
	c.add_point(Vector3(0, 0, 20))
	c.add_point(Vector3.ZERO)
	# half-width 1 m: well inside the corner fold limits, so the seam comparison is
	# pure frame math
	var points := PackedVector2Array([Vector2(-1.0, 0), Vector2(1.0, 0)])
	var offsets := Builder.adaptive_offsets(c, 6.0, 6.0)
	var surfaces := Builder.extrude(c, points, PackedInt32Array([0]), offsets, false)
	var pos: PackedVector3Array = surfaces[0][Mesh.ARRAY_VERTEX]
	var last := (offsets.size() - 1) * 2
	assert_vector(pos[0]).is_equal_approx(pos[last], Vector3.ONE * 0.001)
	assert_vector(pos[1]).is_equal_approx(pos[last + 1], Vector3.ONE * 0.001)
	var r_first := (pos[1] - pos[0]).normalized()
	var r_last := (pos[last + 1] - pos[last]).normalized()
	assert_vector(r_first).is_equal_approx(r_last, Vector3.ONE * 0.001)
	# the shared frame is the seam bisector: right = perpendicular of (t_in + t_out)/2
	# = perpendicular of (1,0,-1)/sqrt(2) in the XZ plane... derive: r = t x UP
	var t_seam := (Vector3(1, 0, 0) + Vector3(0, 0, -1)).normalized()
	assert_vector(r_first).is_equal_approx(t_seam.cross(Vector3.UP), Vector3.ONE * 0.01)


## Open ends: the end ring's tangent is the endpoint's handle direction EXACTLY, not
## the finite difference — a port-snapped end that bends right after the port must stay
## perpendicular to its locked handle or the seam gaps on one side (the "slit").
func test_extrude_open_end_rings_perpendicular_to_handles() -> void:
	# the socket-road shape: out-handle +X off the port, immediate hard bend
	var c := Curve3D.new()
	c.add_point(Vector3(36, 0.12, -18), Vector3.ZERO, Vector3(4, 0, 0))
	c.add_point(Vector3(46, 0.05, -24), Vector3(-3, 0, 1.8), Vector3(3, 0, -1.8))
	c.add_point(Vector3(52, 0.05, -34), Vector3(0, 0, 4), Vector3.ZERO)
	var points := PackedVector2Array([Vector2(-1.0, 0), Vector2(1.0, 0)])
	var offsets := Builder.adaptive_offsets(c, 6.0, 6.0)
	var surfaces := Builder.extrude(c, points, PackedInt32Array([0]), offsets, false)
	var pos: PackedVector3Array = surfaces[0][Mesh.ARRAY_VERTEX]
	var r_first := (pos[1] - pos[0]).normalized()
	assert_float(r_first.dot(Vector3(1, 0, 0))).is_equal_approx(0.0, 0.0001)
	var last := (offsets.size() - 1) * 2
	var r_last := (pos[last + 1] - pos[last]).normalized()
	assert_float(r_last.dot(Vector3(0, 0, 1).normalized())).is_equal_approx(0.0, 0.0001)


## The endpoint handle frames the end ring (v6, so port-snapped ends stay square to the
## tile face) — but only while it still describes the road's direction. A 2 cm handle
## dragged sideways is authored noise: it yawed the end ring ~90 degrees, the fold clamp
## saw an enormous swing over the first segment, and the road opened as a pinched bowtie.
## Past END_TANGENT_MAX_DEV_DEG the finite difference takes over again.
func test_extrude_wild_end_handle_falls_back_to_finite_difference() -> void:
	var c := Curve3D.new()
	# handle 2 cm along +X against a 30 m run down +Z: the curve is heading +Z well
	# within the 0.1 m finite-difference step
	c.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0.02, 0, 0))
	c.add_point(Vector3(0, 0, 30), Vector3(0, 0, -10), Vector3.ZERO)
	var cs := _edge_cross_section()
	var offsets := Builder.adaptive_offsets(c, 6.0, 6.0)
	var surfaces := Builder.extrude(c, cs.points, cs.mats, offsets, false)
	var pos: PackedVector3Array = surfaces[0][Mesh.ARRAY_VERTEX]
	# ring 0 keeps the full 9.5 m width — with the ring yawed to the handle the clamp
	# pinched it to roughly a third of that
	assert_float(pos[0].distance_to(pos[1])).is_equal_approx(9.5, 0.001)
	# and it is framed on the curve's own end tangent, not on the handle
	var right := (pos[1] - pos[0]).normalized()
	var expect := Builder.frame_at(c, 0.0, c.get_baked_length(), 0.0, Vector3.RIGHT)
	assert_vector(right).is_equal_approx(expect.basis.x, Vector3.ONE * 0.001)
	var handle_right: Vector3 = Builder.frame_from_tangent(
			Vector3(1, 0, 0), Vector3.ZERO, 0.0, Vector3.RIGHT).basis.x
	assert_bool(right.distance_to(handle_right) > 0.1).is_true()


## A handle that agrees with the curve still wins (the v6 behaviour this bounds, not undoes).
func test_extrude_sane_end_handle_still_frames_the_ring() -> void:
	var c := Curve3D.new()
	c.add_point(Vector3(36, 0.12, -18), Vector3.ZERO, Vector3(4, 0, 0))
	c.add_point(Vector3(46, 0.05, -24), Vector3(-3, 0, 1.8), Vector3(3, 0, -1.8))
	var cs := _edge_cross_section()
	var offsets := Builder.adaptive_offsets(c, 6.0, 6.0)
	var surfaces := Builder.extrude(c, cs.points, cs.mats, offsets, false)
	var pos: PackedVector3Array = surfaces[0][Mesh.ARRAY_VERTEX]
	assert_float((pos[1] - pos[0]).normalized().dot(Vector3(1, 0, 0))) \
			.is_equal_approx(0.0, 0.0001)


func test_extrude_climbing_straight_has_no_roll() -> void:
	# a road up a slope: the right vector stays horizontal, so each cross-section
	# vertex pair of the flat surface strip shares one world Y
	var surfaces := _extrude_straight(false, Vector3.ZERO, Vector3(0, 5, 50))
	var pos: PackedVector3Array = surfaces[0][Mesh.ARRAY_VERTEX]
	for i in range(0, pos.size(), 2):
		assert_float(pos[i].y).is_equal_approx(pos[i + 1].y, 0.0001)


# ------------------------------------------------------ closed loops / mirrored paths


func test_endpoint_gap_and_is_closed_loop() -> void:
	var closed := Curve3D.new()
	closed.add_point(Vector3.ZERO)
	closed.add_point(Vector3(20, 0, 0))
	closed.add_point(Vector3(20, 0, 20))
	closed.add_point(Vector3.ZERO)
	assert_bool(Builder.is_closed_loop(closed)).is_true()
	assert_float(Builder.endpoint_gap(closed)).is_equal_approx(0.0, 1e-5)
	# closed by eye, not by snapping
	closed.set_point_position(3, Vector3(0.4, 0, 0))
	assert_bool(Builder.is_closed_loop(closed)).is_false()
	assert_float(Builder.endpoint_gap(closed)).is_equal_approx(0.4, 1e-5)
	# too few points to be a loop at all
	assert_bool(Builder.is_closed_loop(_straight(Vector3.ZERO, Vector3(0, 0, 10)))).is_false()
	assert_bool(Builder.endpoint_gap(null) == INF).is_true()


## A loop closed by eye gets neither the shared seam frame nor a weld: the end rings sit
## that same distance apart, and past the bake's 1 mm snap that is a real hole in the
## drivable body. RoadPath must say so — the gap is invisible at gizmo zoom.
func test_road_path_warns_on_near_closed_loop() -> void:
	var road: Node3D = auto_free(Node3D.new())
	road.set_script(RoadPathScript)
	road.set("profile", load("res://kit/roads/asphalt_profile.tres"))
	var path := Path3D.new()
	path.name = "Path"
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(30, 0, 0))
	curve.add_point(Vector3(30, 0, 30))
	curve.add_point(Vector3(0.4, 0, 0))   # 40 cm short of closing
	path.curve = curve
	road.add_child(path)
	assert_bool("\n".join(road._get_configuration_warnings()).contains("endpoints")) \
			.is_true()
	# properly closed: no complaint
	curve.set_point_position(3, Vector3.ZERO)
	assert_bool("\n".join(road._get_configuration_warnings()).contains("endpoints")) \
			.is_false()


## A negatively scaled Path3D child would otherwise hand the baker a ribbon wound
## inside-out — invisible under cull_back, and one-way in the welded drivable body.
func test_transform_surface_arrays_preserves_winding_when_mirrored() -> void:
	var surfaces := _extrude_straight()
	var mirror := Transform3D(Basis.IDENTITY.scaled(Vector3(-1, 1, 1)), Vector3.ZERO)
	var out: Array = Builder.transform_surface_arrays(surfaces[0], mirror)
	var pos: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = out[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = out[Mesh.ARRAY_INDEX]
	for i in range(0, idx.size(), 3):
		var cross := (pos[idx[i + 1]] - pos[idx[i]]).cross(pos[idx[i + 2]] - pos[idx[i]])
		assert_bool(cross.dot(nrm[idx[i]]) < -1e-6).is_true()


# ------------------------------------------------------------------- conform math


func test_flatten_weight_shape() -> void:
	assert_float(Builder.flatten_weight(0.0, 2.0, 3.0)).is_equal(1.0)
	assert_float(Builder.flatten_weight(2.0, 2.0, 3.0)).is_equal(1.0)
	assert_float(Builder.flatten_weight(3.5, 2.0, 3.0)).is_equal_approx(0.5, 0.001)
	assert_float(Builder.flatten_weight(5.0, 2.0, 3.0)).is_equal(0.0)
	assert_float(Builder.flatten_weight(99.0, 2.0, 3.0)).is_equal(0.0)
	# monotone non-increasing across the falloff band
	assert_bool(Builder.flatten_weight(2.5, 2.0, 3.0) >= Builder.flatten_weight(3.0, 2.0, 3.0)).is_true()
	assert_bool(Builder.flatten_weight(3.0, 2.0, 3.0) >= Builder.flatten_weight(4.0, 2.0, 3.0)).is_true()


## Centerline row of samples across a 16x16 image (span 15 m -> 1 px = 1 m). The line
## sits on pixel row 7 (lz = -0.5); samples every 0.5 m cover every column.
func _conform_test_image() -> Dictionary:
	var img := Image.create(16, 16, false, Image.FORMAT_L8)
	img.fill(Color(0.5, 0.5, 0.5))
	var samples := PackedVector3Array()
	var lx := -7.5
	while lx <= 7.51:
		samples.append(Vector3(lx, -0.5, 0.25))
		lx += 0.5
	return {"img": img, "samples": samples}


func test_conform_heights_flattens_inner_and_blends_falloff() -> void:
	var setup := _conform_test_image()
	var img: Image = setup.img
	var orig := img.get_pixel(0, 0).r
	var dirty := Builder.conform_heights(img, setup.samples, 2.5, 3.0, 15.0, 15.0)
	# inner band (rows 5..9, dist <= 2.5): the floor-quantized target, never above it
	for row in [5, 6, 7, 8, 9]:
		var r := img.get_pixel(8, row).r
		assert_float(r * 255.0).is_equal_approx(63.0, 1.0)   # floor(0.25*255) = 63
		assert_bool(r <= 0.25 + 1e-6).is_true()
	# mid-falloff (row 4, dist 3): strictly between target and original
	var mid := img.get_pixel(8, 4).r
	assert_bool(mid > img.get_pixel(8, 7).r and mid < orig).is_true()
	# beyond half_width + falloff (dist >= 5.5): untouched
	assert_float(img.get_pixel(8, 13).r).is_equal(orig)
	assert_float(img.get_pixel(0, 0).r).is_equal(orig)
	# tight dirty rect: rows 2..12 change (dist 5 still blends), all 16 columns
	assert_that(dirty).is_equal(Rect2i(0, 2, 16, 11))


func test_conform_heights_is_deterministic() -> void:
	var a := _conform_test_image()
	var b := _conform_test_image()
	Builder.conform_heights(a.img, a.samples, 2.5, 3.0, 15.0, 15.0)
	Builder.conform_heights(b.img, b.samples, 2.5, 3.0, 15.0, 15.0)
	assert_that((a.img as Image).get_data()).is_equal((b.img as Image).get_data())


func test_conform_heights_empty_inputs() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_L8)
	assert_that(Builder.conform_heights(img, PackedVector3Array(), 2.0, 2.0, 7.0, 7.0)) \
			.is_equal(Rect2i())


## The target is lerped at the pixel's projection onto the centerline SEGMENT, never
## snapped to the nearest point sample: two samples 15 m apart still flatten the span
## between them, and a mid-span pixel gets the interpolated height.
func test_conform_heights_lerps_target_along_segment() -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_L8)
	img.fill(Color(0.5, 0.5, 0.5))
	var samples := PackedVector3Array([
		Vector3(-7.5, -0.5, 0.1), Vector3(7.5, -0.5, 0.3)])
	Builder.conform_heights(img, samples, 2.5, 3.0, 15.0, 15.0)
	# pixel (8, 7): on the line at lx = 0.5 -> t = 8/15, target = 0.1 + 0.2 * 8/15,
	# stored = floor(target * 255) = 52
	assert_float(img.get_pixel(8, 7).r * 255.0).is_equal_approx(52.0, 0.5)
	# endpoints keep their own targets: floor(0.1*255) = 25, floor(0.3*255) = 76
	assert_float(img.get_pixel(0, 7).r * 255.0).is_equal_approx(25.0, 0.5)
	assert_float(img.get_pixel(15, 7).r * 255.0).is_equal_approx(76.0, 0.5)


## The seam invariant: on a steep road, every plateau pixel stays
## within (target - one 8-bit step, target] of the analytic road height at its own
## projection. The nearest-point-sample flatten violated this on any grade over ~20%
## (a point target is off by up to half the sample spacing x the grade).
func test_conform_heights_sloped_road_stays_below_ribbon() -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_L8)
	img.fill(Color(0.5, 0.5, 0.5))
	# straight line along x at lz = -0.5, target climbing 0.05 -> 0.95; samples every
	# 0.8 m (deliberately NOT aligned with the 1 m pixel grid) + the exact endpoint,
	# the _conform_terrain convention
	var samples := PackedVector3Array()
	var x := -7.5
	while x < 7.5:
		samples.append(Vector3(x, -0.5, 0.05 + (x + 7.5) / 15.0 * 0.9))
		x += 0.8
	samples.append(Vector3(7.5, -0.5, 0.95))
	Builder.conform_heights(img, samples, 2.5, 3.0, 15.0, 15.0)
	var step := 1.0 / 255.0
	for pz in [5, 6, 7, 8, 9]:           # rows within the 2.5 m plateau of the line
		for px in 16:
			var lx := float(px) - 7.5
			var t_proj := 0.05 + (lx + 7.5) / 15.0 * 0.9
			var stored := img.get_pixel(px, pz).r
			assert_bool(stored <= t_proj + 1e-4).is_true()
			assert_bool(stored >= t_proj - step - 1e-4).is_true()


## Over a crest (a road tipping over into a descent) the analytic curve rides ABOVE
## the ribbon's chords, so conform samples must be taken AT the extrusion's
## adaptive_offsets rings (the RoadPath._conform_terrain convention) — a fixed fine
## step targets the analytic curve and the flattened terrain pokes through the ribbon.
## Both samplings share conform_heights; only the sampling differs, like the caller.
func test_conform_at_ring_offsets_stays_below_crest_chords() -> void:
	# A 17-degree vertical circular arc (r = 50 m) cresting at z = -12 then
	# descending: uniform curvature, so the coarse ~5 m splits sit just under the
	# 6-degree bisection threshold and keep the maximal chord rise (~L * theta / 8
	# ~ 6 cm of curve-above-chord).
	var r := 50.0
	var sweep := deg_to_rad(17.0)
	var k := 4.0 / 3.0 * tan(sweep * 0.25) * r
	var t1 := Vector3(0, -sin(sweep), cos(sweep))
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 3.5, -12), Vector3.ZERO, Vector3(0, 0, k))
	curve.add_point(Vector3(0, 3.5 - r * (1.0 - cos(sweep)), -12 + r * sin(sweep)),
			-t1 * k, Vector3.ZERO)
	var length := curve.get_baked_length()
	var eps := 0.02
	var amp := 5.0
	var offsets := Builder.adaptive_offsets(curve, 6.0, 6.0)
	var rings := PackedVector3Array()
	for o in offsets:
		rings.append(curve.sample_baked(o))

	# fixture precondition: somewhere the analytic curve sits above the chord by more
	# than eps, else neither sampling could differ and the test proves nothing
	var max_rise := 0.0
	for i in rings.size() - 1:
		var mid := curve.sample_baked((offsets[i] + offsets[i + 1]) * 0.5)
		max_rise = maxf(max_rise, mid.y - (rings[i].y + rings[i + 1].y) * 0.5)
	assert_bool(max_rise > eps + 1e-3).is_true()

	var fine := PackedVector3Array()   # the old fixed-0.5 m sampling
	var count := maxi(2, int(ceil(length / 0.5)) + 1)
	for i in count:
		var w := curve.sample_baked(length * float(i) / float(count - 1))
		fine.append(Vector3(w.x, w.z, (w.y - eps) / amp))
	var at_rings := PackedVector3Array()
	for w in rings:
		at_rings.append(Vector3(w.x, w.z, (w.y - eps) / amp))

	var img_old := Image.create(40, 40, false, Image.FORMAT_L8)
	img_old.fill(Color(0.9, 0.9, 0.9))
	var img_new := img_old.duplicate() as Image
	Builder.conform_heights(img_old, fine, 2.5, 3.0, 39.0, 39.0)
	Builder.conform_heights(img_new, at_rings, 2.5, 3.0, 39.0, 39.0)

	# plateau pixels along the centerline column: stored height vs the chordal ribbon
	var above_old := 0
	var above_new := 0
	for pz in range(9, 22):
		var lz := float(pz) - 19.5
		for px in range(17, 23):
			if absf(float(px) - 19.5) > 2.5:
				continue
			var chord := _chord_height_along_z(rings, lz)
			if is_nan(chord):
				continue
			assert_bool(img_new.get_pixel(px, pz).r * amp <= chord - eps + 1e-4).is_true()
			if img_old.get_pixel(px, pz).r * amp > chord + 1e-4:
				above_old += 1
			if img_new.get_pixel(px, pz).r * amp > chord + 1e-4:
				above_new += 1
	assert_int(above_old).is_greater(0)   # the old sampling really did overshoot
	assert_int(above_new).is_equal(0)


## On a segment that is both STEEP and YAWING the ruled deck surface between rings
## shifts along-slope by up to half_width * sin(swing/2) * grade, so the centerline
## XZ-projection mis-heights the deck edges by tens of centimetres — conform must
## rasterize the actual deck triangles (the `deck` argument, extruded on the ribbon's
## own frames). Ground truth here is the REAL ribbon's surface-slot triangles.
func test_conform_deck_raster_stays_below_ruled_surface_on_steep_bend() -> void:
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 18, -15), Vector3.ZERO, Vector3(0, -4, 6))
	curve.add_point(Vector3(6, 6, 0), Vector3(-4, 4, -4), Vector3(4, -4, 4))
	curve.add_point(Vector3(16, 2, 4), Vector3(-4, 1, -1), Vector3.ZERO)
	var eps := 0.05
	var amp := 20.0
	var profile := Profile.new()   # defaults: paved 4.25, full 4.75
	var offsets := Builder.adaptive_offsets(curve, 6.0, 6.0)
	var rings := PackedVector3Array()
	var samples := PackedVector3Array()
	for o in offsets:
		var w := curve.sample_baked(o)
		rings.append(w)
		samples.append(Vector3(w.x, w.z, (w.y - eps) / amp))
	var fw: float = profile.full_half_width()
	var deck_faces := Builder.faces_from_surfaces(Builder.extrude(curve,
			PackedVector2Array([Vector2(-fw, 0), Vector2(fw, 0)]),
			PackedInt32Array([0]), offsets, false))
	var deck := PackedVector3Array()
	for v in deck_faces:
		deck.append(Vector3(v.x, v.z, (v.y - eps) / amp))

	var img_old := Image.create(48, 48, false, Image.FORMAT_L8)
	img_old.fill(Color(0.9, 0.9, 0.9))
	var img_new := img_old.duplicate() as Image
	Builder.conform_heights(img_old, samples, fw, 3.0, 47.0, 47.0)
	Builder.conform_heights(img_new, samples, fw, 3.0, 47.0, 47.0, deck)

	# ground truth: the real ribbon's SURFACE strips (slot 0), rasterized test-side
	var cs: Dictionary = profile.cross_section()
	var surf: Array = Builder.extrude(curve, cs["points"], cs["mats"], offsets,
			false)[Profile.SLOT_SURFACE]
	var pos: PackedVector3Array = surf[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = surf[Mesh.ARRAY_INDEX]
	var above_old := 0
	var above_new := 0
	var covered := 0
	for pz in 48:
		for px in 48:
			var expected := _surface_height_at(pos, idx,
					float(px) - 23.5, float(pz) - 23.5)
			if is_nan(expected):
				continue
			covered += 1
			assert_bool(img_new.get_pixel(px, pz).r * amp <= expected - eps + 1e-3).is_true()
			if img_old.get_pixel(px, pz).r * amp > expected + 1e-3:
				above_old += 1
			if img_new.get_pixel(px, pz).r * amp > expected + 1e-3:
				above_new += 1
	assert_int(covered).is_greater(50)    # the fixture actually exercises the deck
	assert_int(above_old).is_greater(0)   # projection-only sampling really overshot
	assert_int(above_new).is_equal(0)


## Height of the ribbon surface triangles at local (x, z), NAN when outside them all.
func _surface_height_at(pos: PackedVector3Array, idx: PackedInt32Array,
		x: float, z: float) -> float:
	for t in range(0, idx.size(), 3):
		var a := pos[idx[t]]
		var b := pos[idx[t + 1]]
		var c := pos[idx[t + 2]]
		var den := (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)
		if absf(den) < 1e-9:
			continue
		var w1 := ((x - a.x) * (c.z - a.z) - (z - a.z) * (c.x - a.x)) / den
		var w2 := ((b.x - a.x) * (z - a.z) - (b.z - a.z) * (x - a.x)) / den
		if w1 < -1e-6 or w2 < -1e-6 or w1 + w2 > 1.0 + 1e-6:
			continue
		return a.y + w1 * (b.y - a.y) + w2 * (c.y - a.y)
	return NAN


## Ribbon chord height at local z for a straight-in-plan road along +z (NAN outside).
func _chord_height_along_z(rings: PackedVector3Array, lz: float) -> float:
	for i in rings.size() - 1:
		if lz >= rings[i].z and lz <= rings[i + 1].z:
			var span := rings[i + 1].z - rings[i].z
			var t := 0.0 if span <= 0.0 else (lz - rings[i].z) / span
			return lerpf(rings[i].y, rings[i + 1].y, t)
	return NAN


# --------------------------------------------------------- baker: chunk bucketing


func _two_quad_arrays() -> Array:
	# two up-facing quads either side of x = 48 (chunk border at chunk_size 48)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(40, 0, 0), Vector3(46, 0, 0), Vector3(40, 0, 2), Vector3(46, 0, 2),
		Vector3(50, 0, 0), Vector3(56, 0, 0), Vector3(50, 0, 2), Vector3(56, 0, 2)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP,
		Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1),
		Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 1, 2, 3, 4, 6, 5, 5, 6, 7])
	return arrays


func test_split_arrays_by_chunk_buckets_by_world_centroid() -> void:
	var out: Dictionary = Baker.split_arrays_by_chunk(_two_quad_arrays(),
			Transform3D.IDENTITY, 48.0)
	assert_int(out.size()).is_equal(2)
	assert_bool(out.has(Vector2i(0, 0)) and out.has(Vector2i(1, 0))).is_true()
	var tri_total := 0
	for key: Vector2i in out:
		var arrays: Array = out[key]
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		assert_int(pos.size()).is_equal(4)   # per-chunk dedup
		@warning_ignore("integer_division")
		tri_total += idx.size() / 3
		for i in idx:
			assert_bool(i >= 0 and i < pos.size()).is_true()
	assert_int(tri_total).is_equal(4)   # triangle count conserved
	# vertex positions preserved (source-space, not shifted by the keying transform)
	assert_bool(Array((out[Vector2i(0, 0)] as Array)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			.has(Vector3(40, 0, 0))).is_true()


func test_split_arrays_by_chunk_transform_keys_only() -> void:
	var shifted: Dictionary = Baker.split_arrays_by_chunk(_two_quad_arrays(),
			Transform3D(Basis.IDENTITY, Vector3(48, 0, 0)), 48.0)
	assert_bool(shifted.has(Vector2i(1, 0)) and shifted.has(Vector2i(2, 0))).is_true()
	# output verts stay in source space
	assert_bool(Array((shifted[Vector2i(1, 0)] as Array)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			.has(Vector3(40, 0, 0))).is_true()


## conform_rects: the rect interior is a hard plateau at the ROUND-quantized target,
## the falloff ring blends toward it, and pixels beyond the reach are untouched.
func test_conform_rects_plateau_falloff_and_round_quantize() -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_L8)
	img.fill(Color(0.6, 0.6, 0.6))   # 0.6 * 255 = 153 exact (0.5 would truncate)
	var rects: Array[Rect2] = [Rect2(-3, -3, 6, 6)]
	# 0.2004 * 255 = 51.1 -> ROUND lands on 51 (floor would too — the round-vs-floor
	# distinction is asserted in the two-rect test below with a .6 fraction)
	Builder.conform_rects(img, rects, PackedFloat32Array([0.2004]), 2.0, 15.0, 15.0)
	for pz in range(5, 11):
		for px in range(5, 11):   # lx/lz in [-2.5, 2.5] — inside the rect
			assert_int(roundi(img.get_pixel(px, pz).r * 255.0)).is_equal(51)
	# falloff ring: pulled toward the target but not on it
	var ring := img.get_pixel(3, 8).r   # lx = -4.5, 1.5 m outside the rect
	assert_bool(ring > 51.0 / 255.0 and ring < 0.6).is_true()
	# beyond reach: untouched
	assert_int(roundi(img.get_pixel(0, 8).r * 255.0)).is_equal(153)


## Two rects with different targets: the strictly-nearest rect's target wins per
## pixel, and a target between 8-bit steps ROUND-quantizes to the nearest step
## (0.6 fraction rounds UP — floor would land one step below).
func test_conform_rects_nearest_rect_wins_and_rounds_up() -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_L8)
	img.fill(Color(0.5, 0.5, 0.5))
	var rects: Array[Rect2] = [Rect2(-6, -2, 4, 4), Rect2(2, -2, 4, 4)]
	# 0.8 * 255 = 204.0 exact; 0.2024 * 255 = 51.6 -> round 52 (floor: 51)
	Builder.conform_rects(img, rects,
			PackedFloat32Array([0.8, 0.2024]), 2.0, 15.0, 15.0)
	assert_int(roundi(img.get_pixel(4, 8).r * 255.0)).is_equal(204)   # inside A
	assert_int(roundi(img.get_pixel(11, 8).r * 255.0)).is_equal(52)   # inside B
	# gap pixels: each side pulled toward ITS nearest rect's target
	assert_bool(img.get_pixel(7, 8).r > 0.5).is_true()    # lx = -0.5, nearer A (0.8)
	assert_bool(img.get_pixel(8, 8).r < 0.5).is_true()    # lx = +0.5, nearer B (0.2)


# --------------------------------------------------- tile conform footprints


const TileConform := preload("res://addons/carlito_kit/tile_conform.gd")


## footprint_rects against the real roads meshlib: a 1x1 tile covers its 12 m cell
## (any orientation/layer), the XZ-centered 2x2 road-curve covers 24 m around its
## anchor — the overhang cells a plain occupancy walk would miss.
func test_tile_footprint_rects_cover_cells_and_overhangs() -> void:
	var grid: GridMap = auto_free(GridMap.new())
	grid.mesh_library = load("res://kit/palettes/roads.meshlib")
	grid.cell_size = Vector3(12, 3, 12)
	grid.cell_center_y = false
	var straight := -1
	var curve_id := -1
	for i in grid.mesh_library.get_item_list():
		match grid.mesh_library.get_item_name(i):
			"road-straight": straight = i
			"road-curve": curve_id = i
	assert_int(straight).is_greater(-1)
	assert_int(curve_id).is_greater(-1)
	grid.set_cell_item(Vector3i(0, 0, 0), straight, 0)
	grid.set_cell_item(Vector3i(4, 1, 0), straight, 16)   # yawed, one layer up
	grid.set_cell_item(Vector3i(0, 0, 4), curve_id, 0)

	var fps: Dictionary = TileConform.footprint_rects(grid)
	var rects: Array = fps["rects"]
	var base_ys: PackedFloat32Array = fps["base_ys"]
	assert_int(rects.size()).is_equal(3)   # sorted cells: (0,0,0), (0,0,4), (4,1,0)

	var r0: Rect2 = rects[0]   # straight at (0,0,0): 12x12 centered on (6, 6)
	assert_bool(absf(r0.size.x - 12.0) < 0.6 and absf(r0.size.y - 12.0) < 0.6).is_true()
	assert_bool(r0.get_center().distance_to(Vector2(6, 6)) < 0.6).is_true()
	assert_float(base_ys[0]).is_equal_approx(0.0, 1e-4)

	var r1: Rect2 = rects[1]   # 2x2 curve at (0,0,4): ~24 m square, re-centered onto the
	# clicked cell by the recipe's half-cell (+6 X / +6 Z) offset, so (6,54) -> (12,60)
	assert_bool(absf(r1.size.x - 24.0) < 1.5 and absf(r1.size.y - 24.0) < 1.5).is_true()
	assert_bool(r1.get_center().distance_to(Vector2(12, 60)) < 1.5).is_true()

	var r2: Rect2 = rects[2]   # yawed straight at (4,1,0): still its 12 m cell, base +3
	assert_bool(absf(r2.size.x - 12.0) < 0.6 and absf(r2.size.y - 12.0) < 0.6).is_true()
	assert_bool(r2.get_center().distance_to(Vector2(54, 6)) < 0.6).is_true()
	assert_float(base_ys[2]).is_equal_approx(3.0, 1e-4)


# ----------------------------------------------------------------- reverse curve


## _apply_reverse (the Reverse direction button's do/undo payload, its own inverse):
## same shape traversed the other way — per point the in/out handles SWAP (a reversed
## Bezier segment (A, A+out_a, B+in_b, B) reads (B, B+in_b, A+out_a, A)) and tilts
## ride their point. Off-tree node, no _ready side effects (the baker fixture pattern).
func test_road_path_reverse_swaps_handles_and_preserves_shape() -> void:
	var road: Node3D = auto_free(Node3D.new())
	road.set_script(RoadPathScript)
	var path := Path3D.new()
	path.name = "Path"
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 1, 0), Vector3.ZERO, Vector3(2, 0, 6))
	curve.add_point(Vector3(4, 2, 20), Vector3(-1, 0, -5), Vector3(1, 0, 5))
	curve.add_point(Vector3(0, 0.5, 40), Vector3(0, 0, -6), Vector3.ZERO)
	curve.set_point_tilt(1, 0.3)
	path.curve = curve
	road.add_child(path)
	var length := curve.get_baked_length()
	var orig := PackedVector3Array()
	for i in 9:
		orig.append(curve.sample_baked(length * float(i) / 8.0))

	road._apply_reverse()
	assert_float(curve.get_baked_length()).is_equal_approx(length, 0.01)
	for i in 9:
		var p := curve.sample_baked(curve.get_baked_length() * float(i) / 8.0)
		assert_bool(p.distance_to(orig[8 - i]) < 0.01).is_true()
	assert_bool(curve.get_point_out(0).is_equal_approx(Vector3(0, 0, -6))).is_true()
	assert_bool(curve.get_point_in(2).is_equal_approx(Vector3(2, 0, 6))).is_true()
	assert_bool(curve.get_point_in(1).is_equal_approx(Vector3(1, 0, 5))).is_true()
	assert_bool(curve.get_point_out(1).is_equal_approx(Vector3(-1, 0, -5))).is_true()
	assert_float(curve.get_point_tilt(1)).is_equal_approx(0.3, 1e-6)

	road._apply_reverse()   # involution: back to the original
	assert_bool(curve.get_point_position(0).is_equal_approx(Vector3(0, 1, 0))).is_true()
	assert_bool(curve.get_point_out(0).is_equal_approx(Vector3(2, 0, 6))).is_true()
	assert_bool(curve.get_point_in(1).is_equal_approx(Vector3(-1, 0, -5))).is_true()


# ------------------------------------------------------------ baker: road collect


## Minimal bakeable level with one RoadPath (never enters the tree, so no _ready side
## effects — the baker's own operating mode).
func _road_level(with_profile: bool) -> Dictionary:
	var root := Node3D.new()
	root.name = "L"
	var spawn := Marker3D.new()
	spawn.name = "Spawn"
	spawn.set_script(load("res://src/levels/base/vehicle_spawn.gd"))
	root.add_child(spawn)
	var authoring := Node3D.new()
	authoring.name = "Authoring"
	authoring.set_script(preload("res://kit/helpers/authoring_root.gd"))
	root.add_child(authoring)
	var road := Node3D.new()
	road.name = "Road"
	road.set_script(RoadPathScript)
	if with_profile:
		road.set("profile", load("res://kit/roads/asphalt_profile.tres"))
	authoring.add_child(road)
	var path := Path3D.new()
	path.name = "Path"
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0.05, 60))
	path.curve = curve
	road.add_child(path)
	return {"root": root, "road": road}


func test_bake_collects_road_into_weld_and_chunks() -> void:
	var level := _road_level(true)
	var result: Dictionary = Baker.bake(level.root)
	assert_bool(result.ok).is_true()
	var stats: Dictionary = result.stats
	assert_int(int(stats.roads)).is_equal(1)
	assert_bool(int(stats.drivable_triangles) > 0).is_true()
	# a 60 m ribbon along z straddling x = 0 buckets into 4 chunks at chunk_size 48:
	# x chunks -1/0 (triangle centroids either side of the centerline), z chunks 0/1
	assert_int(int(stats.chunks)).is_equal(4)
	var baked: Node3D = result.root
	assert_object(baked.get_node_or_null("Drivable")).is_not_null()
	baked.free()
	level.root.free()


func test_bake_road_without_profile_is_an_error() -> void:
	var level := _road_level(false)
	var result: Dictionary = Baker.bake(level.root)
	assert_bool(result.ok).is_false()
	assert_bool("\n".join(result.errors as PackedStringArray).contains("profile")).is_true()
	level.root.free()


func test_bake_road_with_degenerate_curve_is_an_error() -> void:
	var level := _road_level(true)
	((level.road as Node).get_node("Path") as Path3D).curve = Curve3D.new()
	var result: Dictionary = Baker.bake(level.root)
	assert_bool(result.ok).is_false()
	assert_bool("\n".join(result.errors as PackedStringArray).contains("curve")).is_true()
	level.root.free()

extends GdUnitTestSuite
## RailProfile's cross-section, the duck-typed rail node API shared by RoadPath and
## RailTrack, and the baker's RailTrack emission. Same discipline as test_road.gd:
## hand-checkable numbers, everything headless-constructible, no scene tree needed.
##
## The load-bearing case is the last one: a baked level FREES its AuthoringRoot at load
## and export strips it, so if the baker stops emitting the RailTrack the curve is gone
## from shipped builds and the train has nothing to ride — with no other symptom.

const RailProfileScript := preload("res://kit/helpers/rail_profile.gd")
const Builder := preload("res://kit/helpers/road_builder.gd")
const Baker := preload("res://kit/bake/level_baker.gd")
const RoadPathScript := preload("res://kit/helpers/road_path.gd")
const RAIL_PRESET := "res://kit/roads/rail_profile.tres"
const CITY_PRESET := "res://kit/roads/city_profile.tres"


## Hand-set numbers rather than the preset's, so the assertions below stay readable and
## a preset tweak never fails a geometry test.
func _profile() -> RailProfile:
	var p := RailProfileScript.new() as RailProfile
	p.gauge = 1.44
	p.rail_width = 0.24
	p.rail_height = 0.12
	p.ballast_half_width = 1.8
	p.edge_drop = 0.4
	p.drop_run = 0.6
	return p


# ------------------------------------------------------------ cross-section


func test_cross_section_puts_ribs_on_the_gauge() -> void:
	var cs := _profile().cross_section()
	var points: PackedVector2Array = cs.points
	var mats: PackedInt32Array = cs.mats
	assert_int(mats.size()).is_equal(points.size() - 1)
	# skirt + bed + 3 rib strips + between + 3 rib strips + bed + skirt
	assert_int(points.size()).is_equal(12)
	# rib tops at +/- (gauge/2 +/- rail_width/2), at exactly rail_height
	var tops := PackedFloat32Array()
	for p in points:
		if is_equal_approx(p.y, 0.12):
			tops.append(p.x)
	tops.sort()
	# float32 storage vs float64 literals: only binary-exact values compare with is_equal
	assert_int(tops.size()).is_equal(4)
	var expected := [-0.84, -0.6, 0.6, 0.84]
	for i in 4:
		assert_float(tops[i]).is_equal_approx(expected[i], 1e-5)


func test_cross_section_is_mirror_symmetric() -> void:
	var points: PackedVector2Array = _profile().cross_section().points
	var n := points.size()
	for i in n:
		var mirrored := points[n - 1 - i]
		assert_float(mirrored.x).is_equal_approx(-points[i].x, 1e-5)
		assert_float(mirrored.y).is_equal_approx(points[i].y, 1e-5)


## Zero-area quads are what the extruder must never see. The rib walls are the trap: they
## have zero LATERAL extent, so RoadProfile's lateral-only filter would delete them.
func test_no_strip_is_degenerate_and_the_rib_walls_survive() -> void:
	var points: PackedVector2Array = _profile().cross_section().points
	var walls := 0
	for i in points.size() - 1:
		var d := points[i + 1] - points[i]
		assert_bool(absf(d.x) > 1e-4 or absf(d.y) > 1e-4) \
				.override_failure_message("strip %d is degenerate" % i).is_true()
		if absf(d.x) <= 1e-4:
			walls += 1
	assert_int(walls).is_equal(4)   # two ribs, two walls each


func test_zero_drop_run_removes_the_skirt() -> void:
	var p := _profile()
	p.drop_run = 0.0
	var points: PackedVector2Array = p.cross_section().points
	assert_int(points.size()).is_equal(10)
	for v in points:
		assert_float(v.y).is_greater_equal(0.0)   # nothing dips below the bed


## A ballast narrower than the rails is authoring nonsense, but it must degrade to a
## rails-only ribbon rather than to inverted bed strips.
func test_narrow_ballast_drops_the_bed_strips() -> void:
	var p := _profile()
	p.ballast_half_width = 0.1
	p.drop_run = 0.0
	var points: PackedVector2Array = p.cross_section().points
	assert_float(points[0].x).is_equal_approx(-0.84, 1e-5)
	for i in points.size() - 1:
		var d := points[i + 1] - points[i]
		assert_bool(absf(d.x) > 1e-4 or absf(d.y) > 1e-4).is_true()


func test_widths_come_from_the_ballast_not_the_lane() -> void:
	var p := _profile()
	p.lane_width = 99.0   # inherited and deliberately meaningless for rails
	assert_float(p.paved_half_width()).is_equal_approx(1.8, 1e-5)
	assert_float(p.full_half_width()).is_equal_approx(2.4, 1e-5)


func test_materials_are_index_matched_to_the_slots() -> void:
	var p := _profile()
	p.ballast_material = StandardMaterial3D.new()
	p.rail_material = StandardMaterial3D.new()
	var mats: Array = p.materials()
	var cs := p.cross_section()
	for slot: int in (cs.mats as PackedInt32Array):
		assert_object(mats[slot]).is_not_null()


## Extruded straight along +Z, every face must point out of the solid. Godot's front face
## is the opposite of the geometric cross, so an up-facing triangle's cross points DOWN
## (test_road.gd's convention).
func test_extruded_rail_faces_point_outward() -> void:
	var p := _profile()
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0, 40))
	var cs := p.cross_section()
	var offsets := Builder.adaptive_offsets(curve, 6.0, 6.0)
	var surfaces := Builder.extrude(curve, cs.points, cs.mats, offsets, false)
	var bed_up := 0
	var walls_out := 0
	for slot: int in surfaces:
		var arrays: Array = surfaces[slot]
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size() - 2, 3):
			var a := pos[idx[t]]
			var cross := (pos[idx[t + 1]] - a).cross(pos[idx[t + 2]] - a).normalized()
			if absf(cross.y) > 0.9:
				assert_float(cross.y).is_less(0.0)   # horizontal faces all face UP
				bed_up += 1
			elif absf(cross.x) > 0.9:
				# a rib wall: its normal (-cross) must point AWAY from the centreline
				var lateral := (a.x + pos[idx[t + 1]].x + pos[idx[t + 2]].x) / 3.0
				var outer := absf(lateral) > 0.72   # gauge/2, i.e. the outer wall
				assert_bool(signf(-cross.x) == signf(lateral if outer else -lateral)) \
						.override_failure_message("rib wall at x=%.2f faces inward" % lateral) \
						.is_true()
				walls_out += 1
	assert_int(bed_up).is_greater(0)
	assert_int(walls_out).is_greater(0)


func test_preset_is_a_rail_profile() -> void:
	var preset: Resource = load(RAIL_PRESET)
	assert_object(preset).is_not_null()
	assert_bool(preset.has_method("is_carlito_rail_profile")).is_true()
	assert_float(preset.get("gauge")).is_equal_approx(1.44, 1e-5)


# ------------------------------------------------------------ the rail node API


func _road(preset: String, curve: Curve3D) -> Node3D:
	var road := Node3D.new()
	road.name = "Rail"
	road.set_script(RoadPathScript)
	road.set("profile", load(preset))
	var path := Path3D.new()
	path.name = "Path"
	path.curve = curve
	road.add_child(path)
	return road


func _loop() -> Curve3D:
	var curve := Curve3D.new()
	for i in 8:
		var ang := TAU * float(i) / 8.0
		curve.add_point(Vector3(60.0 * cos(ang), 0, 60.0 * sin(ang)))
	curve.add_point(curve.get_point_position(0))
	return curve


func test_a_city_road_is_not_a_rail() -> void:
	var road := _road(CITY_PRESET, _loop())
	assert_object(road.call("get_rail_curve")).is_null()
	assert_float(road.call("rail_gauge")).is_equal(0.0)
	road.free()


func test_a_rail_road_exposes_its_curve_and_gauge() -> void:
	var curve := _loop()
	var road := _road(RAIL_PRESET, curve)
	assert_object(road.call("get_rail_curve")).is_same(curve)
	assert_float(road.call("rail_gauge")).is_equal_approx(1.44, 1e-5)
	road.free()


## Curve space -> node-local must be the Path child's transform, not the identity: the
## baker composes exactly this to place the RailTrack, and it runs on an UNTREED
## instance where global_transform is unavailable.
func test_rail_local_xform_is_the_path_childs_transform() -> void:
	var road := _road(RAIL_PRESET, _loop())
	var path := road.get_node("Path") as Path3D
	path.position = Vector3(3, 4, 5)
	assert_vector((road.call("rail_local_xform") as Transform3D).origin) \
			.is_equal(Vector3(3, 4, 5))
	road.free()


## One closed-loop predicate, not two: RoadBuilder.is_closed_loop already owns the
## question (extrude's shared bisector seam frame, RoadPath's "closed by eye" warning).
func test_closed_predicate_agrees_with_road_builder() -> void:
	var closed := _loop()
	var open := Curve3D.new()
	open.add_point(Vector3.ZERO)
	open.add_point(Vector3(0, 0, 30))
	open.add_point(Vector3(30, 0, 30))
	var nearly := _loop()
	nearly.set_point_position(nearly.point_count - 1,
			nearly.get_point_position(0) + Vector3(0.5, 0, 0))
	for curve in [closed, open, nearly]:
		var road := _road(RAIL_PRESET, curve)
		assert_bool(road.call("is_rail_closed")).is_equal(Builder.is_closed_loop(curve))
		road.free()
	assert_bool(Builder.is_closed_loop(closed)).is_true()
	assert_bool(Builder.is_closed_loop(nearly)).is_false()


# ------------------------------------------------------------ baker emission


## Minimal bakeable level with one road (never entered into the tree — the baker's own
## operating mode). Mirrors test_road.gd's _road_level.
func _level(preset: String) -> Dictionary:
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
	var road := _road(preset, _loop())
	authoring.add_child(road)
	return {"root": root, "road": road}


func test_bake_emits_a_rail_track_carrying_the_curve() -> void:
	var level := _level(RAIL_PRESET)
	var road: Node3D = level.road
	(road.get_node("Path") as Path3D).position = Vector3(0, 2, 0)
	road.position = Vector3(10, 0, 0)
	var result: Dictionary = Baker.bake(level.root)
	assert_bool(result.ok).override_failure_message(
			"\n".join(result.errors as PackedStringArray)).is_true()
	assert_int(int(result.stats.rail_tracks)).is_equal(1)
	var baked: Node3D = result.root
	var track := baked.get_node_or_null("Rails/rail_0")
	assert_object(track).is_not_null()
	assert_bool(track.has_method("is_carlito_rail_track")).is_true()
	assert_float(track.call("rail_gauge")).is_equal_approx(1.44, 1e-5)
	assert_bool(track.call("is_rail_closed")).is_true()
	# road transform * Path child transform, so a consumer can sample straight through it
	assert_vector((track as Node3D).transform.origin).is_equal(Vector3(10, 2, 0))
	var baked_curve: Curve3D = track.call("get_rail_curve")
	assert_int(baked_curve.point_count).is_equal(9)
	# a COPY: editing the authored curve afterwards must not reach a shipped level
	assert_object(baked_curve).is_not_same((road.get_node("Path") as Path3D).curve)
	baked.free()
	level.root.free()


func test_bake_of_a_plain_road_emits_no_rails_node() -> void:
	var level := _level(CITY_PRESET)
	var result: Dictionary = Baker.bake(level.root)
	assert_bool(result.ok).is_true()
	assert_int(int(result.stats.rail_tracks)).is_equal(0)
	var baked: Node3D = result.root
	assert_object(baked.get_node_or_null("Rails")).is_null()
	baked.free()
	level.root.free()

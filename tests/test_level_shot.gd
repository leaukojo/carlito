extends GdUnitTestSuite
## LevelShot: the side-car paths the kit tools and the capture tool must agree on, and the
## overview framing used when a level has no saved view. Pure statics, so this runs headless.


func test_side_car_and_thumb_paths() -> void:
	assert_str(LevelShot.path_for("res://src/levels/island/level_1/level_1.tscn")) \
			.is_equal("res://src/levels/island/level_1/level_1_shot.tres")
	assert_str(LevelShot.thumb_path("level_1")) \
			.is_equal("res://src/ui/level_thumbs/level_1.png")


func test_load_for_missing_side_car_is_null() -> void:
	assert_object(LevelShot.load_for("res://src/levels/nope/nope.tscn")).is_null()


func test_overview_sits_outside_the_bounds_and_looks_at_their_centre() -> void:
	var bounds := AABB(Vector3(-100.0, 0.0, -100.0), Vector3(200.0, 50.0, 200.0))
	var xform := LevelShot.overview(bounds, 60.0)
	var center := bounds.get_center()

	# Far enough that the bounding sphere fits the frustum...
	var radius := bounds.size.length() * 0.5
	var expected := radius / sin(deg_to_rad(30.0)) * LevelShot.OVERVIEW_MARGIN
	assert_float(xform.origin.distance_to(center)).is_equal_approx(expected, 0.01)
	assert_bool(bounds.has_point(xform.origin)).is_false()
	# ...above it, and aimed at the centre (a camera looks down its own -Z).
	assert_bool(xform.origin.y > bounds.end.y).is_true()
	var forward := -xform.basis.z
	assert_float(forward.dot(center - xform.origin) / (center - xform.origin).length()) \
			.is_equal_approx(1.0, 1e-4)


func test_overview_distance_scales_with_the_bounds() -> void:
	var small := AABB(Vector3(-50.0, 0.0, -50.0), Vector3(100.0, 20.0, 100.0))
	var big := AABB(small.position * 2.0, small.size * 2.0)
	var d_small := LevelShot.overview(small, 60.0).origin.distance_to(small.get_center())
	var d_big := LevelShot.overview(big, 60.0).origin.distance_to(big.get_center())
	assert_float(d_big).is_equal_approx(d_small * 2.0, 0.01)


func test_narrower_fov_pulls_the_camera_back() -> void:
	var bounds := AABB(Vector3(-100.0, 0.0, -100.0), Vector3(200.0, 50.0, 200.0))
	var wide := LevelShot.overview(bounds, 70.0).origin.distance_to(bounds.get_center())
	var narrow := LevelShot.overview(bounds, 35.0).origin.distance_to(bounds.get_center())
	assert_float(narrow).is_greater(wide)

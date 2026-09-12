extends GdUnitTestSuite
## Course zone geometry: ZoneShape's inclusive boundaries, and ChallengeZone.zones_of resolving a
## course's zones by name without the course ever entering a tree.

const TOL := Vector3(1e-4, 1e-4, 1e-4)


func test_box_edges_are_inclusive() -> void:
	var z := ZoneShape.box(Transform3D.IDENTITY, Vector3(4, 2, 6))
	assert_bool(z.contains(Vector3(2, 0, 3))).is_true()
	assert_bool(z.contains(Vector3(-2, -1, -3))).is_true()
	assert_bool(z.contains(Vector3(2.001, 0, 0))).is_false()
	assert_bool(z.contains(Vector3(0, 0, -3.001))).is_false()
	assert_bool(z.contains(Vector3(0, 1.001, 0))).is_false()


## Rotated 90 degrees about Y, the box's long local Z lies along world X. The node scale folded
## into the transform is ignored: `size` is the size.
func test_box_follows_its_rotation_and_ignores_scale() -> void:
	var t := Transform3D(Basis(Vector3.UP, PI / 2.0).scaled(Vector3(3, 3, 3)), Vector3(10, 0, 0))
	var z := ZoneShape.box(t, Vector3(2, 2, 8))
	assert_bool(z.contains(Vector3(13.9, 0, 0))).is_true()
	assert_bool(z.contains(Vector3(10, 0, 0.99))).is_true()
	assert_bool(z.contains(Vector3(10, 0, 3.9))).is_false()
	assert_bool(z.contains(Vector3(14.1, 0, 0))).is_false()


func test_ring_radii_are_inclusive_and_height_bounds_it() -> void:
	var z := ZoneShape.ring(Transform3D(Basis.IDENTITY, Vector3(5, 0, 5)), 10.0, 20.0, 4.0)
	assert_bool(z.contains(Vector3(15, 0, 5))).is_true()
	assert_bool(z.contains(Vector3(5, 0, 25))).is_true()
	assert_bool(z.contains(Vector3(14.99, 0, 5))).is_false()
	assert_bool(z.contains(Vector3(25.01, 0, 5))).is_false()
	assert_bool(z.contains(Vector3(5, 0, 5))).is_false()
	assert_bool(z.contains(Vector3(15, 2, 5))).is_true()
	assert_bool(z.contains(Vector3(15, 2.01, 5))).is_false()


## A waypoint: no inner radius is a solid cylinder, and no height reaches any altitude.
func test_ring_with_no_inner_radius_is_an_unbounded_cylinder() -> void:
	var z := ZoneShape.ring(Transform3D.IDENTITY, 0.0, 3.0)
	assert_bool(z.contains(Vector3.ZERO)).is_true()
	assert_bool(z.contains(Vector3(0, 500, 0))).is_true()
	assert_bool(z.contains(Vector3(3, -500, 0))).is_true()
	assert_bool(z.contains(Vector3(3.01, 0, 0))).is_false()


func test_zones_of_composes_transforms_outside_the_tree() -> void:
	var course: Node3D = auto_free(Node3D.new())
	course.position = Vector3(100, 0, 0)
	var group := Node3D.new()
	group.position = Vector3(0, 0, 50)
	course.add_child(group)
	group.add_child(_zone("Box", Vector3(1, 0, 0)))
	var ring := _zone("Ring", Vector3(0, 0, -40))
	ring.kind = ZoneShape.Kind.RING
	ring.inner_r = 10.0
	ring.outer_r = 15.0
	course.add_child(ring)

	var zones := ChallengeZone.zones_of(course)
	assert_int(zones.size()).is_equal(2)
	assert_vector(zones[&"Box"].xform.origin).is_equal_approx(Vector3(101, 0, 50), TOL)
	assert_bool(zones[&"Box"].contains(Vector3(102, 0, 50))).is_true()
	assert_int(zones[&"Ring"].kind).is_equal(ZoneShape.Kind.RING)
	assert_bool(zones[&"Ring"].contains(Vector3(112, 0, -40))).is_true()


func test_duplicate_zone_names_are_reported_and_the_first_is_kept() -> void:
	var course: Node3D = auto_free(Node3D.new())
	var a := Node3D.new()
	var b := Node3D.new()
	course.add_child(a)
	course.add_child(b)
	a.add_child(_zone("Gate", Vector3(1, 0, 0)))
	b.add_child(_zone("Gate", Vector3(2, 0, 0)))
	course.add_child(_zone("Finish", Vector3.ZERO))
	assert_array(ChallengeZone.duplicate_names(course)).contains_exactly(["Gate"])
	assert_vector(ChallengeZone.zones_of(course)[&"Gate"].xform.origin) \
			.is_equal_approx(Vector3(1, 0, 0), TOL)


func _zone(zone_name: String, pos: Vector3) -> ChallengeZone:
	var z := ChallengeZone.new()
	z.name = zone_name
	z.position = pos
	z.size = Vector3(2, 2, 2)
	return z

extends GdUnitTestSuite
## WorldBounds: level containment box. Must be CLOSED to flying vehicles (slabs overlap).

const WB := preload("res://src/levels/base/world_bounds.gd")

const EXTENT := Vector2(2000.0, 2000.0)
const CEILING := 1500.0
const FLOOR := 100.0


func _bounds() -> Node3D:
	var b: Node3D = WB.new()
	b.extent = EXTENT
	b.ceiling_height = CEILING
	b.floor_depth = FLOOR
	add_child(b)
	return auto_free(b)


## Every box slab as world-space AABBs, in build order (4 walls then the ceiling).
func _boxes(b: Node3D) -> Array[AABB]:
	var out: Array[AABB] = []
	for c in b.get_children(true):
		if c is CollisionShape3D and c.shape is BoxShape3D:
			var size: Vector3 = (c.shape as BoxShape3D).size
			out.append(AABB(c.position - size * 0.5, size))
	return out


func test_it_builds_four_walls_and_a_ceiling() -> void:
	assert_int(_boxes(_bounds()).size()).is_equal(5)


func test_the_walls_sit_on_the_extent_rect() -> void:
	var boxes := _boxes(_bounds())
	# Walls are the first four; each one's inner face is at the half-extent.
	var half := EXTENT * 0.5
	assert_float(boxes[0].position.z + boxes[0].size.z).is_equal_approx(
		half.y + WB.THICKNESS, 0.001
	)
	assert_float(boxes[2].position.x).is_equal_approx(half.x, 0.001)


func test_the_walls_span_from_below_the_floor_to_the_ceiling() -> void:
	# A drone climbing the inside of a wall must never top it out below the ceiling —
	# this is exactly what the old 20 m water walls got wrong.
	for i in 4:
		var box := _boxes(_bounds())[i]
		assert_float(box.position.y).is_less_equal(-FLOOR + 0.001)
		assert_float(box.end.y).is_greater_equal(CEILING - 0.001)


func test_the_ceiling_covers_the_whole_rect_including_the_walls() -> void:
	var ceiling := _boxes(_bounds())[4]
	assert_float(ceiling.position.x).is_less_equal(-EXTENT.x * 0.5 - WB.THICKNESS + 0.001)
	assert_float(ceiling.end.x).is_greater_equal(EXTENT.x * 0.5 + WB.THICKNESS - 0.001)
	assert_float(ceiling.position.z).is_less_equal(-EXTENT.y * 0.5 - WB.THICKNESS + 0.001)
	assert_float(ceiling.end.z).is_greater_equal(EXTENT.y * 0.5 + WB.THICKNESS - 0.001)


func test_the_ceiling_meets_the_walls_with_no_gap() -> void:
	var boxes := _boxes(_bounds())
	# The ceiling's underside is at or below every wall's top: no slot to fly through.
	for i in 4:
		assert_float(boxes[4].position.y).is_less_equal(boxes[i].end.y + 0.001)


func test_the_side_walls_overlap_the_end_walls_at_the_corners() -> void:
	# Long walls run past the rect by THICKNESS so the corners are sealed.
	var boxes := _boxes(_bounds())
	assert_float(boxes[0].end.x).is_greater_equal(boxes[2].end.x - 0.001)
	assert_float(boxes[0].position.x).is_less_equal(boxes[3].position.x + 0.001)


func test_resizing_the_extent_rebuilds_rather_than_accumulates() -> void:
	# The setter rebuilds on every change; a level re-sized in the editor must not end up
	# with two overlapping sets of slabs.
	var b := _bounds()
	b.extent = Vector2(400.0, 400.0)
	assert_int(_boxes(b).size()).is_equal(5)
	assert_float(_boxes(b)[2].position.x).is_equal_approx(200.0, 0.001)


func test_a_rebuild_keeps_children_the_author_put_there() -> void:
	# This is a @tool script and _rebuild() runs on _ready AND on all three setters, so a
	# blanket child sweep would delete an author's own node the moment the scene loaded or
	# an inspector value moved — silently, and permanently at the next save. Only the
	# INTERNAL slabs belong to this node.
	var b := _bounds()
	var mine := Marker3D.new()
	mine.name = "AuthorNote"
	b.add_child(mine)
	b.extent = Vector2(300.0, 300.0)
	b.ceiling_height = 900.0
	b.floor_depth = 50.0
	assert_object(b.get_node_or_null(^"AuthorNote")).is_not_null()
	assert_bool(is_instance_valid(mine)).is_true()
	# ...and the authored child is not counted as a slab, so the box is still five boxes.
	assert_int(_boxes(b).size()).is_equal(5)

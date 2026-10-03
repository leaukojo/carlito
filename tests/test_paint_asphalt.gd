# GdUnit generated TestSuite
extends GdUnitTestSuite
## tools/paint_road_asphalt.gd: which levels take the paint, and the changed-pixel count
## the stale-paint gate in tools/check_bakes.gd reads.

const Paint := preload("res://tools/paint_road_asphalt.gd")


## The level's generator chain is the opt-in; car_arena paints its own roads and Ice.
func test_only_a_level_whose_chain_lists_the_tool_is_painted() -> void:
	assert_bool(Paint.is_painted_level("res://src/levels/island/level_1/level_1.tscn")).is_true()
	assert_bool(Paint.is_painted_level("res://src/levels/island/car_arena/car_arena.tscn")).is_false()
	assert_bool(Paint.is_painted_level("res://src/levels/flatland/flatland.tscn")).is_false()


## A stamp counts only pixels it changed, so a second identical stamp reads 0 (current).
func test_stamp_counts_changed_pixels_and_is_idempotent() -> void:
	var splat := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	splat.fill(Color(1, 0, 0, 0))
	var splat2 := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	splat2.fill(Color(0, 0, 0, 0))
	var a := Vector2(-4, 0)
	var b := Vector2(4, 0)
	var first := Paint._stamp_segment(splat, splat2, a, b, 1.0, 3, 16, 16, 16.0, 16.0, 0.0, 0.0)
	assert_int(first).is_greater(0)
	assert_int(Paint._stamp_segment(splat, splat2, a, b, 1.0, 3, 16, 16, 16.0, 16.0, 0.0, 0.0)) \
			.is_equal(0)
	# a wider profile reaches past the old paint: only the new rim counts
	var wider := Paint._stamp_segment(splat, splat2, a, b, 2.0, 4, 16, 16, 16.0, 16.0, 0.0, 0.0)
	assert_int(wider).is_greater(0)

extends GdUnitTestSuite
## BrushOps: weight curve, sculpt ops, height/splat stamps. Float image formats (RF/RGBAF)
## keep values exact; RGB8 would quantize.

const BrushOps := preload("res://kit/helpers/brush_ops.gd")


# --- weight curve ---


func test_weight_endpoints() -> void:
	assert_float(BrushOps.weight(0.0, 0.5)).is_equal(1.0)
	assert_float(BrushOps.weight(1.0, 0.5)).is_equal(0.0)
	assert_float(BrushOps.weight(1.5, 0.5)).is_equal(0.0)


func test_weight_hard_edge_is_solid_disk() -> void:
	assert_float(BrushOps.weight(0.5, 0.0)).is_equal(1.0)
	assert_float(BrushOps.weight(0.99, 0.0)).is_equal(1.0)


func test_weight_full_falloff_is_dome() -> void:
	assert_float(BrushOps.weight(0.5, 1.0)).is_equal_approx(0.5, 0.001)


# --- sculpt ops ---


func test_sculpt_raise_and_lower() -> void:
	assert_float(BrushOps.sculpt_value(BrushOps.RAISE, 0.5, 0.0, 0.0, 1.0)) \
			.is_equal_approx(0.5 + BrushOps.RATE, 0.0001)
	assert_float(BrushOps.sculpt_value(BrushOps.LOWER, 0.5, 0.0, 0.0, 1.0)) \
			.is_equal_approx(0.5 - BrushOps.RATE, 0.0001)


func test_sculpt_clamps_to_unit_range() -> void:
	assert_float(BrushOps.sculpt_value(BrushOps.RAISE, 0.99, 0.0, 0.0, 1.0)).is_equal(1.0)
	assert_float(BrushOps.sculpt_value(BrushOps.LOWER, 0.01, 0.0, 0.0, 1.0)).is_equal(0.0)


func test_sculpt_smooth_moves_toward_average() -> void:
	assert_float(BrushOps.sculpt_value(BrushOps.SMOOTH, 0.2, 0.6, 0.0, 0.5)) \
			.is_equal_approx(0.4, 0.0001)


func test_sculpt_flatten_moves_toward_target() -> void:
	assert_float(BrushOps.sculpt_value(BrushOps.FLATTEN, 0.2, 0.0, 0.8, 0.5)) \
			.is_equal_approx(0.5, 0.0001)


# --- grid snap ---


func test_snap_to_grid_pulls_to_nearest_cell_centre() -> void:
	# 12 m cells at origin; centres at multiples of 12.
	assert_vector(BrushOps.snap_to_grid(5.0, 7.0, 12.0, 12.0, 0.0, 0.0)) \
			.is_equal(Vector2(0.0, 12.0))
	assert_vector(BrushOps.snap_to_grid(-5.0, -7.0, 12.0, 12.0, 0.0, 0.0)) \
			.is_equal(Vector2(0.0, -12.0))


func test_snap_to_grid_cell_centre_is_a_fixed_point() -> void:
	assert_vector(BrushOps.snap_to_grid(24.0, -12.0, 12.0, 12.0, 0.0, 0.0)) \
			.is_equal(Vector2(24.0, -12.0))


func test_snap_to_grid_offset_origin_shifts_the_lattice() -> void:
	# Origin at (6, 6); centres land at 6 + 12k.
	assert_vector(BrushOps.snap_to_grid(11.0, 1.0, 12.0, 12.0, 6.0, 6.0)) \
			.is_equal(Vector2(6.0, 6.0))
	assert_vector(BrushOps.snap_to_grid(13.0, 19.0, 12.0, 12.0, 6.0, 6.0)) \
			.is_equal(Vector2(18.0, 18.0))


# --- height stamp ---


func _flat_rf(n: int, value: float) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RF)
	img.fill(Color(value, 0, 0))
	return img


func test_stamp_height_raises_center_only_inside_radius() -> void:
	var img := _flat_rf(9, 0.5)
	var dirty := BrushOps.stamp_height(img, 4, 4, 2.0, 2.0, BrushOps.RAISE, 1.0, 0.0, 0.0)
	assert_float(img.get_pixel(4, 4).r).is_equal_approx(0.55, 0.0001)
	assert_float(img.get_pixel(0, 0).r).is_equal(0.5)
	assert_bool(dirty.size == Vector2i.ZERO).is_false()
	assert_bool(Rect2i(0, 0, 9, 9).encloses(dirty)).is_true()


func test_stamp_height_flatten_pulls_toward_target() -> void:
	var img := _flat_rf(7, 0.2)
	BrushOps.stamp_height(img, 3, 3, 2.0, 2.0, BrushOps.FLATTEN, 1.0, 0.0, 0.8)
	assert_float(img.get_pixel(3, 3).r).is_equal_approx(0.8, 0.0001)


func test_stamp_height_empty_when_out_of_bounds() -> void:
	var img := _flat_rf(5, 0.5)
	var dirty := BrushOps.stamp_height(img, 50, 50, 1.0, 1.0, BrushOps.RAISE, 1.0, 0.0, 0.0)
	assert_bool(dirty.size == Vector2i.ZERO).is_true()
	assert_float(img.get_pixel(4, 4).r).is_equal(0.5)


# --- splat stamp ---


func test_stamp_splat_paints_channel_toward_pure() -> void:
	var img := Image.create(9, 9, false, Image.FORMAT_RGBAF)
	img.fill(Color(0.25, 0.25, 0.25, 0.25))
	BrushOps.stamp_splat(img, 4, 4, 2.0, 2.0, BrushOps.unit_slice(0, 0), 1.0, 0.0)
	var c := img.get_pixel(4, 4)
	assert_float(c.r).is_equal_approx(1.0, 0.0001)
	assert_float(c.g).is_equal_approx(0.0, 0.0001)
	assert_float(c.b).is_equal_approx(0.0, 0.0001)
	assert_float(img.get_pixel(0, 0).r).is_equal_approx(0.25, 0.0001)


# --- 8 channels across two splat images ---


## Weights of channel 0..7 at a pixel.
func _weights(img: Image, img2: Image, x: int, y: int) -> PackedFloat32Array:
	var a := img.get_pixel(x, y)
	var b := img2.get_pixel(x, y)
	return PackedFloat32Array([a.r, a.g, a.b, a.a, b.r, b.g, b.b, b.a])


func _total(w: PackedFloat32Array) -> float:
	var sum := 0.0
	for v in w:
		sum += v
	return sum


func test_unit_slice_places_channel_in_its_own_image() -> void:
	assert_float(BrushOps.unit_slice(1, 0).g).is_equal(1.0)
	assert_bool(BrushOps.unit_slice(1, 1) == Color(0, 0, 0, 0)).is_true()
	assert_float(BrushOps.unit_slice(5, 1).g).is_equal(1.0)
	assert_float(BrushOps.unit_slice(5, 0).a).is_equal(0.0)


## Paint one sample: same kernel stamped into both weight images.
func _paint(img: Image, img2: Image, channel: int, strength: float) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	rects.append(BrushOps.stamp_splat(img, 4, 4, 2.0, 2.0, BrushOps.unit_slice(channel, 0),
			strength, 0.0))
	rects.append(BrushOps.stamp_splat(img2, 4, 4, 2.0, 2.0, BrushOps.unit_slice(channel, 1),
			strength, 0.0))
	return rects


func _rgbaf(n: int, fill: Color) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGBAF)
	img.fill(fill)
	return img


func test_paint_high_channel_becomes_dominant_and_total_stays_normalized() -> void:
	var img := _rgbaf(9, Color(0.25, 0.25, 0.25, 0.25))
	var img2 := _rgbaf(9, Color(0, 0, 0, 0))
	_paint(img, img2, 5, 1.0)
	var w := _weights(img, img2, 4, 4)
	assert_float(w[5]).is_equal_approx(1.0, 0.0001)
	assert_float(_total(w)).is_equal_approx(1.0, 0.0001)
	var far := _weights(img, img2, 0, 0)
	assert_float(far[0]).is_equal_approx(0.25, 0.0001)
	assert_float(far[5]).is_equal(0.0)


func test_paint_base_channel_fades_a_high_channel() -> void:
	var img := _rgbaf(9, Color(0, 0, 0, 0))
	var img2 := _rgbaf(9, Color(0, 1.0, 0, 0))
	_paint(img, img2, 0, 0.5)
	var w := _weights(img, img2, 4, 4)
	assert_float(w[0]).is_equal_approx(0.5, 0.0001)
	assert_float(w[5]).is_equal_approx(0.5, 0.0001)
	assert_float(_total(w)).is_equal_approx(1.0, 0.0001)


func test_paint_with_zero_splat2_matches_four_channel_behavior() -> void:
	var img := _rgbaf(9, Color(0.25, 0.25, 0.25, 0.25))
	var img2 := _rgbaf(9, Color(0, 0, 0, 0))
	_paint(img, img2, 2, 1.0)
	var c := img.get_pixel(4, 4)
	assert_float(c.b).is_equal_approx(1.0, 0.0001)
	assert_float(c.r).is_equal_approx(0.0, 0.0001)
	var c2 := img2.get_pixel(4, 4)
	assert_float(c2.g).is_equal(0.0)
	assert_float(c2.a).is_equal(0.0)


func test_both_splat_stamps_report_the_same_dirty_rect() -> void:
	var img := _rgbaf(9, Color(0.25, 0.25, 0.25, 0.25))
	var img2 := _rgbaf(9, Color(0, 0, 0, 0))
	var rects := _paint(img, img2, 6, 0.75)
	assert_bool(rects[0] == rects[1]).is_true()
	assert_bool(rects[0].size == Vector2i.ZERO).is_false()


# --- fill bucket ---


func test_fill_splat_makes_every_pixel_the_unit_colour() -> void:
	var img := _rgbaf(4, Color(0.25, 0.25, 0.25, 0.25))
	var dirty := BrushOps.fill_splat(img, BrushOps.unit_slice(2, 0))
	assert_bool(dirty == Rect2i(0, 0, 4, 4)).is_true()
	for y in 4:
		for x in 4:
			assert_bool(img.get_pixel(x, y) == Color(0, 0, 1, 0)).is_true()


func test_fill_splat_of_a_high_channel_zeroes_the_base_image() -> void:
	var img := _rgbaf(3, Color(0.25, 0.25, 0.25, 0.25))
	var img2 := _rgbaf(3, Color(0, 0, 0, 0))
	BrushOps.fill_splat(img, BrushOps.unit_slice(5, 0))
	BrushOps.fill_splat(img2, BrushOps.unit_slice(5, 1))
	var w := _weights(img, img2, 1, 1)
	assert_float(w[5]).is_equal(1.0)
	assert_float(_total(w)).is_equal(1.0)


# --- square brush ---


func test_brush_dist_metrics() -> void:
	assert_float(BrushOps.brush_dist(1.0, 1.0, false)).is_equal_approx(sqrt(2.0), 0.0001)
	assert_float(BrushOps.brush_dist(1.0, 1.0, true)).is_equal(1.0)
	assert_float(BrushOps.brush_dist(-0.4, 0.9, true)).is_equal_approx(0.9, 0.0001)


## Radii 2.5 px: corner at Chebyshev 0.8 (inside square), Euclidean 1.13 (outside round).
const SQ_R := 2.5


func test_square_stamp_reaches_corners_a_circle_misses() -> void:
	var round_img := _flat_rf(9, 0.5)
	var square_img := _flat_rf(9, 0.5)
	BrushOps.stamp_height(round_img, 4, 4, SQ_R, SQ_R, BrushOps.RAISE, 1.0, 0.0, 0.0, false)
	BrushOps.stamp_height(square_img, 4, 4, SQ_R, SQ_R, BrushOps.RAISE, 1.0, 0.0, 0.0, true)
	assert_float(round_img.get_pixel(6, 6).r).is_equal(0.5)
	assert_float(square_img.get_pixel(6, 6).r).is_equal_approx(0.55, 0.0001)


func test_square_hard_rim_is_inclusive_so_abutting_pads_tile() -> void:
	# Radius 2: rim at 1.0; hard square includes rim (shared boundary column stamped).
	var sq := _flat_rf(9, 0.5)
	BrushOps.stamp_height(sq, 4, 4, 2.0, 2.0, BrushOps.RAISE, 1.0, 0.0, 0.0, true)
	assert_float(sq.get_pixel(6, 4).r).is_equal_approx(0.55, 0.0001)
	assert_float(sq.get_pixel(2, 4).r).is_equal_approx(0.55, 0.0001)
	var rnd := _flat_rf(9, 0.5)
	BrushOps.stamp_height(rnd, 4, 4, 2.0, 2.0, BrushOps.RAISE, 1.0, 0.0, 0.0, false)
	assert_float(rnd.get_pixel(6, 4).r).is_equal(0.5)


func test_square_stamp_hard_falloff_is_a_uniform_plateau() -> void:
	var img := _flat_rf(9, 0.25)
	var dirty := BrushOps.stamp_height(img, 4, 4, SQ_R, SQ_R, BrushOps.FLATTEN, 1.0, 0.0, 0.8,
			true)
	for y in range(2, 7):
		for x in range(2, 7):
			assert_float(img.get_pixel(x, y).r).is_equal_approx(0.8, 0.0001)
	assert_float(img.get_pixel(1, 4).r).is_equal(0.25)
	assert_bool(dirty == Rect2i(2, 2, 5, 5)).is_true()


func test_square_splat_stamp_covers_the_full_square() -> void:
	var img := _rgbaf(9, Color(0, 0, 0, 0))
	BrushOps.stamp_splat(img, 4, 4, SQ_R, SQ_R, BrushOps.unit_slice(0, 0), 1.0, 0.0, true)
	assert_float(img.get_pixel(6, 2).r).is_equal_approx(1.0, 0.0001)
	assert_float(img.get_pixel(7, 4).r).is_equal(0.0)


# --- ramp ---
#
# Ramps below run along row 5 from x=2 to x=8 with 2 px half-widths, over an image filled
# with 0.0 — so "moved" is unambiguous (a fill value that collided with an interpolated
# height would make `is_not_equal` assertions meaningless).


func test_ramp_centerline_follows_the_lerp() -> void:
	var img := _flat_rf(9, 0.0)
	BrushOps.stamp_ramp(img, Vector2i(0, 4), 0.0, Vector2i(8, 4), 1.0, 2.0, 2.0, 1.0, 0.0)
	for x in 9:
		assert_float(img.get_pixel(x, 4).r).is_equal_approx(float(x) / 8.0, 1.0 / 255.0)


func test_ramp_endpoints_hit_their_heights_and_ends_are_capped() -> void:
	var img := _flat_rf(11, 0.5)
	BrushOps.stamp_ramp(img, Vector2i(2, 5), 0.2, Vector2i(8, 5), 0.9, 2.0, 2.0, 1.0, 0.0)
	assert_float(img.get_pixel(2, 5).r).is_equal_approx(0.2, 1.0 / 255.0)
	assert_float(img.get_pixel(8, 5).r).is_equal_approx(0.9, 1.0 / 255.0)
	assert_float(img.get_pixel(9, 5).r).is_equal_approx(0.9, 1.0 / 255.0)
	assert_float(img.get_pixel(10, 5).r).is_equal(0.5)


func test_ramp_leaves_pixels_beyond_half_width_untouched() -> void:
	var img := _flat_rf(11, 0.0)
	var dirty := BrushOps.stamp_ramp(img, Vector2i(2, 5), 0.2, Vector2i(8, 5), 1.0,
			2.0, 2.0, 1.0, 0.0)
	assert_float(img.get_pixel(5, 4).r).is_not_equal(0.0)
	assert_float(img.get_pixel(5, 3).r).is_equal(0.0)
	assert_float(img.get_pixel(5, 2).r).is_equal(0.0)
	assert_float(img.get_pixel(5, 8).r).is_equal(0.0)
	assert_bool(Rect2i(0, 0, 11, 11).encloses(dirty)).is_true()
	assert_bool(dirty == Rect2i(1, 4, 9, 3)).is_true()


func test_ramp_degenerate_a_equals_b_is_a_flatten_disk() -> void:
	var img := _flat_rf(9, 0.0)
	var dirty := BrushOps.stamp_ramp(img, Vector2i(4, 4), 1.0, Vector2i(4, 4), 1.0,
			2.0, 2.0, 0.5, 0.0)
	assert_float(img.get_pixel(4, 4).r).is_equal_approx(0.5, 1.0 / 255.0)
	assert_bool(dirty == Rect2i(3, 3, 3, 3)).is_true()
	assert_float(img.get_pixel(0, 0).r).is_equal(0.0)


func test_ramp_diagonal_measures_across_the_segment() -> void:
	var img := _flat_rf(11, 0.0)
	BrushOps.stamp_ramp(img, Vector2i(2, 2), 0.2, Vector2i(8, 8), 1.0, 2.0, 2.0, 1.0, 0.0)
	assert_float(img.get_pixel(5, 5).r).is_equal_approx(0.6, 1.0 / 255.0)
	assert_float(img.get_pixel(7, 4).r).is_equal(0.0)

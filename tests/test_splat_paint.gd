extends GdUnitTestSuite
## SplatPaint pure fns: the strip and rect rasterizers behind the "Paint splat under
## road / tiles" buttons. 17x17 RGBA8 images over a 16 m span, so pixel centers sit at
## whole meters (-8..8) and painted weights are binary-exact (0 or 1) — assert_float
## is_equal is safe (see the CLAUDE.md float-assert gotcha).

const SplatPaint := preload("res://kit/helpers/splat_paint.gd")
const BrushOps := preload("res://kit/helpers/brush_ops.gd")

const SPAN := 16.0
const ASPHALT := 6   # channel index: splatmap2.b

var _img: Image    # channels 0..3, seeded all-grass (r = 1)
var _img2: Image   # channels 4..7, seeded empty


func before_test() -> void:
	_img = Image.create(17, 17, false, Image.FORMAT_RGBA8)
	_img.fill(Color(1, 0, 0, 0))
	_img2 = Image.create(17, 17, false, Image.FORMAT_RGBA8)
	_img2.fill(Color(0, 0, 0, 0))


## Pixel index of a terrain-local meter coordinate (span 16 -> px = m + 8).
func _px(m: float) -> int:
	return int(m + 8.0)


func _units() -> Array[Color]:
	return [BrushOps.unit_slice(ASPHALT, 0), BrushOps.unit_slice(ASPHALT, 1)]


func _images() -> Array[Image]:
	return [_img, _img2]


func _assert_painted(mx: float, mz: float) -> void:
	assert_float(_img.get_pixel(_px(mx), _px(mz)).r).is_equal(0.0)
	assert_float(_img2.get_pixel(_px(mx), _px(mz)).b).is_equal(1.0)


func _assert_untouched(mx: float, mz: float) -> void:
	assert_float(_img.get_pixel(_px(mx), _px(mz)).r).is_equal(1.0)
	assert_float(_img2.get_pixel(_px(mx), _px(mz)).b).is_equal(0.0)


# --- paint_tris ---


func test_tris_paints_eroded_interior_only() -> void:
	# Big triangle (-4,-4)/(4,-4)/(0,4): the center survives the 1 px erosion,
	# the apex and the bottom-edge pixels do not (their neighbors are uncovered).
	var tris := PackedVector2Array([Vector2(-4, -4), Vector2(4, -4), Vector2(0, 4)])
	var dirty := SplatPaint.paint_tris(_images(), _units(), tris, SPAN, SPAN)
	assert_bool(dirty.has_area()).is_true()
	_assert_painted(0.0, 0.0)
	_assert_untouched(0.0, 4.0)    # apex eroded
	_assert_untouched(-4.0, -4.0)  # corner eroded
	_assert_untouched(-5.0, 0.0)   # outside the triangle


func test_tris_shared_interior_edge_has_no_pinhole() -> void:
	# A quad split into two triangles along z = x: pixels on the shared diagonal are
	# covered by the raster and interior ones survive erosion.
	var tris := PackedVector2Array([
		Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4),
		Vector2(-4, -4), Vector2(4, 4), Vector2(-4, 4)])
	SplatPaint.paint_tris(_images(), _units(), tris, SPAN, SPAN)
	_assert_painted(0.0, 0.0)    # on the shared diagonal
	_assert_painted(1.0, 1.0)
	_assert_untouched(4.0, 4.0)  # rim eroded


func test_tris_off_image_paints_nothing() -> void:
	var tris := PackedVector2Array([Vector2(20, 20), Vector2(24, 20), Vector2(22, 24)])
	var dirty := SplatPaint.paint_tris(_images(), _units(), tris, SPAN, SPAN)
	assert_bool(dirty.has_area()).is_false()
	_assert_untouched(8.0, 8.0)   # clamped boxes must NOT catch the border pixels


func test_tris_mismatched_image_sizes_refused() -> void:
	var small := Image.create(9, 9, false, Image.FORMAT_RGBA8)
	var tris := PackedVector2Array([Vector2(-4, -4), Vector2(4, -4), Vector2(0, 4)])
	var dirty := SplatPaint.paint_tris([_img, small] as Array[Image], _units(),
			tris, SPAN, SPAN)
	assert_bool(dirty.has_area()).is_false()
	_assert_untouched(0.0, 0.0)


# --- paint_strip ---


func test_strip_covers_half_width_around_segment() -> void:
	var samples := PackedVector2Array([Vector2(-4, 0), Vector2(4, 0)])
	var dirty := SplatPaint.paint_strip(_images(), _units(), samples, 1.0, SPAN, SPAN)
	assert_bool(dirty.has_area()).is_true()
	_assert_painted(0.0, 0.0)
	_assert_painted(0.0, 1.0)    # exactly half_width away: inclusive
	_assert_painted(-4.0, 0.0)   # segment end
	_assert_untouched(0.0, 2.0)
	_assert_untouched(-6.0, 0.0)


func test_strip_single_sample_paints_a_dot() -> void:
	var samples := PackedVector2Array([Vector2(0, 0)])
	var dirty := SplatPaint.paint_strip(_images(), _units(), samples, 1.0, SPAN, SPAN)
	assert_bool(dirty.has_area()).is_true()
	_assert_painted(0.0, 0.0)
	_assert_untouched(2.0, 0.0)


func test_strip_deck_triangle_covers_what_centerline_misses() -> void:
	# centerline far off-image: only the deck triangle can paint
	var samples := PackedVector2Array([Vector2(100, 100)])
	var deck := PackedVector2Array([Vector2(-2, -2), Vector2(2, -2), Vector2(0, 2)])
	var dirty := SplatPaint.paint_strip(_images(), _units(), samples, 1.0, SPAN, SPAN, deck)
	assert_bool(dirty.has_area()).is_true()
	_assert_painted(0.0, 0.0)
	_assert_painted(0.0, 2.0)    # triangle apex
	_assert_untouched(-3.0, 0.0)
	_assert_untouched(2.0, 2.0)


func test_strip_determinism_same_inputs_same_bytes() -> void:
	var samples := PackedVector2Array([Vector2(-4, -3), Vector2(4, 3)])
	SplatPaint.paint_strip(_images(), _units(), samples, 1.5, SPAN, SPAN)
	var first := _img.get_data().duplicate()
	var first2 := _img2.get_data().duplicate()
	before_test()
	SplatPaint.paint_strip(_images(), _units(), samples, 1.5, SPAN, SPAN)
	assert_bool(_img.get_data() == first).is_true()
	assert_bool(_img2.get_data() == first2).is_true()

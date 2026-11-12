extends GdUnitTestSuite
## RoadTerrain: a road's footprint in a terrain's frame, and the Conform and Paint writes under
## it. 33x33 images over a 32 m terrain: 1 px = 1 m, pixel (16, 16) at the terrain's centre.

const RoadTerrain := preload("res://kit/helpers/road_terrain.gd")

const SPAN := Vector2(32.0, 32.0)
const HEIGHT := 20.0
const EPSILON := 0.05
const HALF_WIDTH := 2.5
const FALLOFF := 3.0
## The road's height: 0.25 of the terrain's once `EPSILON` is off, stored floored as 63.
const ROAD_Y := 5.05
const ASPHALT := 6   # channel index: splatmap2.b


## A straight, level road along x through the curve's origin, 24 m long.
func _road() -> Curve3D:
	var c := Curve3D.new()
	c.add_point(Vector3(-12.0, ROAD_Y, 0.0))
	c.add_point(Vector3(12.0, ROAD_Y, 0.0))
	return c


func _footprint(half_width: float, xform := Transform3D.IDENTITY) -> Dictionary:
	return RoadTerrain.footprint(_road(), half_width, false, 6.0, 6.0, xform)


func _heights() -> Image:
	var img := Image.create(33, 33, false, Image.FORMAT_L8)
	img.fill(Color(0.5, 0.5, 0.5))
	return img


## Pixel value (0..255) at terrain-local metres (`mx`, `mz`).
func _level(img: Image, mx: int, mz: int) -> float:
	return img.get_pixel(mx + 16, mz + 16).r * 255.0


func test_footprint_samples_the_rings_and_decks_the_half_width() -> void:
	var curve := _road()
	var fp := _footprint(HALF_WIDTH)
	var samples: PackedVector3Array = fp["samples"]
	assert_int(samples.size()).is_equal(RoadBuilder.adaptive_offsets(curve, 6.0, 6.0).size())
	assert_vector(samples[0]).is_equal_approx(Vector3(-12.0, ROAD_Y, 0.0), Vector3.ONE * 1e-4)
	assert_vector(samples[samples.size() - 1]) \
			.is_equal_approx(Vector3(12.0, ROAD_Y, 0.0), Vector3.ONE * 1e-4)
	var deck: PackedVector3Array = fp["deck"]
	assert_int(deck.size()).is_greater(0)
	assert_int(deck.size() % 3).is_equal(0)
	for v in deck:
		assert_float(absf(v.z)).is_equal_approx(HALF_WIDTH, 1e-4)
		assert_float(v.y).is_equal_approx(ROAD_Y, 1e-4)


func test_conform_flattens_under_the_road_to_epsilon_below_it() -> void:
	var img := _heights()
	var dirty := RoadTerrain.conform(img, _footprint(HALF_WIDTH), HALF_WIDTH, FALLOFF,
			Vector3.ZERO, SPAN, HEIGHT, EPSILON)
	assert_bool(dirty.has_area()).is_true()
	for mz in [-2, 0, 2]:
		assert_float(_level(img, 0, mz)).is_equal_approx(63.0, 0.5)
	# The blend, then the untouched terrain past `HALF_WIDTH + FALLOFF`.
	assert_float(_level(img, 0, 4)).is_between(64.0, 126.0)
	assert_float(_level(img, 0, 7)).is_equal_approx(127.0, 0.5)


## The same road and terrain moved and turned together write the same heights: the footprint
## rides `xform`, and the terrain's `origin` (its height included) comes back off it.
func test_conform_reads_the_road_in_the_terrains_frame() -> void:
	var origin := Vector3(64.0, 8.0, -32.0)
	var turned := Transform3D(Basis(Vector3.UP, PI / 2.0), origin)
	var img := _heights()
	RoadTerrain.conform(img, _footprint(HALF_WIDTH, turned), HALF_WIDTH, FALLOFF, origin, SPAN,
			HEIGHT, EPSILON)
	# Turned a quarter about y, the road runs along z.
	for mz in [-10, 0, 10]:
		assert_float(_level(img, 0, mz)).is_equal_approx(63.0, 0.5)
	assert_float(_level(img, 10, 0)).is_equal_approx(127.0, 0.5)
	assert_float(_level(img, -10, 0)).is_equal_approx(127.0, 0.5)


func test_leaves_height_range_reads_the_terrains_base_and_top() -> void:
	var fp := _footprint(HALF_WIDTH)
	assert_bool(RoadTerrain.leaves_height_range(fp, 0.0, HEIGHT, EPSILON)).is_false()
	# The terrain's base above the road, then its top under it.
	assert_bool(RoadTerrain.leaves_height_range(fp, 6.0, HEIGHT, EPSILON)).is_true()
	assert_bool(RoadTerrain.leaves_height_range(fp, 0.0, 4.0, EPSILON)).is_true()
	assert_float(RoadTerrain.height_norm(ROAD_Y, 0.0, HEIGHT, EPSILON)).is_equal_approx(0.25, 1e-6)


func test_paint_writes_the_channel_under_the_road_in_the_terrains_frame() -> void:
	var origin := Vector3(64.0, 8.0, -32.0)
	var splat := Image.create(33, 33, false, Image.FORMAT_RGBA8)
	splat.fill(Color(1, 0, 0, 0))
	var splat2 := Image.create(33, 33, false, Image.FORMAT_RGBA8)
	splat2.fill(Color(0, 0, 0, 0))
	var images: Array[Image] = [splat, splat2]
	var dirty := RoadTerrain.paint(images, ASPHALT,
			_footprint(1.5, Transform3D(Basis.IDENTITY, origin)), 1.5, origin, SPAN)
	assert_bool(dirty.has_area()).is_true()
	# Under the road: asphalt alone, the grass zeroed. Past the half-width: untouched.
	assert_float(splat2.get_pixel(16, 16).b).is_equal(1.0)
	assert_float(splat.get_pixel(16, 16).r).is_equal(0.0)
	assert_float(splat2.get_pixel(16, 20).b).is_equal(0.0)
	assert_float(splat.get_pixel(16, 20).r).is_equal(1.0)


## A terrain with no splatmap2 hands over one image: a channel under 4 paints it alone.
func test_paint_takes_a_terrain_with_one_splat_image() -> void:
	var splat := Image.create(33, 33, false, Image.FORMAT_RGBA8)
	splat.fill(Color(1, 0, 0, 0))
	var images: Array[Image] = [splat]
	RoadTerrain.paint(images, 1, _footprint(1.5), 1.5, Vector3.ZERO, SPAN)
	assert_float(splat.get_pixel(16, 16).g).is_equal(1.0)
	assert_float(splat.get_pixel(16, 16).r).is_equal(0.0)

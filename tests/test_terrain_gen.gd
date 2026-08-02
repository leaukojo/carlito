extends GdUnitTestSuite
## TerrainGen pure fns: island falloff, noise remap, splat
## classification, chunk lattice, normals — hand-checkable numbers throughout, same
## discipline as Drivetrain. Generation must be deterministic from the seed (bake
## hashing and git diffs depend on it).

const Gen := preload("res://kit/terrain/terrain_gen.gd")


# --- island falloff ---


func test_falloff_interior_is_one() -> void:
	assert_float(Gen.island_falloff(0.0, 0.55, 0.95)).is_equal(1.0)
	assert_float(Gen.island_falloff(0.55, 0.55, 0.95)).is_equal(1.0)


func test_falloff_edge_is_zero() -> void:
	assert_float(Gen.island_falloff(0.95, 0.55, 0.95)).is_equal(0.0)
	assert_float(Gen.island_falloff(1.4, 0.55, 0.95)).is_equal(0.0)   # corner radius > 1


func test_falloff_midpoint_is_half() -> void:
	# t = 0.5 -> smoothstep 0.5 -> falloff 1 - 0.5.
	assert_float(Gen.island_falloff(0.75, 0.55, 0.95)).is_equal_approx(0.5, 0.001)


func test_falloff_degenerate_band_is_step() -> void:
	assert_float(Gen.island_falloff(0.4, 0.5, 0.5)).is_equal(1.0)
	assert_float(Gen.island_falloff(0.5, 0.5, 0.5)).is_equal(1.0)   # <= start wins
	assert_float(Gen.island_falloff(0.6, 0.5, 0.5)).is_equal(0.0)


# --- noise remap ---


func test_remap01_endpoints_and_clamp() -> void:
	assert_float(Gen.remap01(-1.0)).is_equal(0.0)
	assert_float(Gen.remap01(0.0)).is_equal(0.5)
	assert_float(Gen.remap01(1.0)).is_equal(1.0)
	assert_float(Gen.remap01(-3.0)).is_equal(0.0)
	assert_float(Gen.remap01(5.0)).is_equal(1.0)


# --- terrace ---


func test_terrace_off_when_step_out_of_range() -> void:
	# step01 <= 0 disables terracing; step01 >= 1 (band taller than the terrain) too.
	assert_float(Gen.terrace(0.37, 0.0, 0.6)).is_equal(0.37)
	assert_float(Gen.terrace(0.37, 1.0, 0.6)).is_equal(0.37)
	assert_float(Gen.terrace(0.37, 1.5, 0.6)).is_equal(0.37)


func test_terrace_flat_zone_snaps_to_plateau() -> void:
	# step01 = 0.25, half of each band flat: band [0.25, 0.5) is the plateau whose flat
	# level snaps to the nearest 8-bit value, round(1*0.25*255)/255 = 64/255, until the
	# ramp. h = 0.30 -> t 1.2, frac 0.2, inside the flat half -> stays at the plateau.
	assert_float(Gen.terrace(0.30, 0.25, 0.5)).is_equal_approx(64.0 / 255.0, 0.001)
	assert_float(Gen.terrace(0.27, 0.25, 0.5)).is_equal_approx(64.0 / 255.0, 0.001)


func test_terrace_flat_levels_land_on_grid() -> void:
	# Every flat plateau level must be exactly round(f*step01*255)/255 — the nearest
	# storable value to the grid plane painted tiles rest on. Probe the flat zone
	# (frac small) of several bands.
	var step01 := 0.2
	for k in [1, 2, 3, 4]:
		var h := (float(k) + 0.02) * step01           # just inside band k's flat zone
		var expected := roundf(float(k) * step01 * 255.0) / 255.0
		assert_float(Gen.terrace(h, step01, 0.6)).is_equal_approx(expected, 1e-6)


func test_terrace_preserves_band_centres_within_grid() -> void:
	# The ramp midpoint still maps close to itself (relief preserved); the nearest-value
	# snap only nudges it by <= 1/510, so it lands within a grid step of h.
	assert_float(Gen.terrace(0.375, 0.25, 0.5)).is_equal_approx(0.375, 1.0 / 255.0 + 0.001)
	assert_float(Gen.terrace(0.625, 0.25, 0.5)).is_equal_approx(0.625, 1.0 / 255.0 + 0.001)


func test_terrace_endpoints() -> void:
	assert_float(Gen.terrace(0.0, 0.25, 0.5)).is_equal(0.0)
	assert_float(Gen.terrace(1.0, 0.25, 0.5)).is_equal(1.0)


# --- radius ---


func test_radius01_center_and_edges() -> void:
	# 17x17 image: centre pixel (8,8), edge midpoints at r=1, corner beyond 1.
	assert_float(Gen.radius01(8, 8, 17, 17)).is_equal(0.0)
	assert_float(Gen.radius01(16, 8, 17, 17)).is_equal(1.0)
	assert_float(Gen.radius01(8, 0, 17, 17)).is_equal(1.0)
	assert_float(Gen.radius01(0, 0, 17, 17)).is_equal_approx(sqrt(2.0), 0.001)


# --- generation ---


func test_generate_is_deterministic_from_seed() -> void:
	var a := Gen.generate_heights(Gen.Preset.ISLAND, 7, 20.0, 3, 0.55, 0.95, 17, 17)
	var b := Gen.generate_heights(Gen.Preset.ISLAND, 7, 20.0, 3, 0.55, 0.95, 17, 17)
	var c := Gen.generate_heights(Gen.Preset.ISLAND, 8, 20.0, 3, 0.55, 0.95, 17, 17)
	assert_bool(a.get_data() == b.get_data()).is_true()
	assert_bool(a.get_data() == c.get_data()).is_false()


func test_island_border_is_sea_level() -> void:
	# Every border pixel has elliptical radius >= 1 >= falloff_end, so height 0 exactly.
	var img := Gen.generate_heights(Gen.Preset.ISLAND, 7, 20.0, 3, 0.55, 0.95, 17, 17)
	for x in 17:
		assert_float(img.get_pixel(x, 0).r).is_equal(0.0)
		assert_float(img.get_pixel(x, 16).r).is_equal(0.0)
	for y in 17:
		assert_float(img.get_pixel(0, y).r).is_equal(0.0)
		assert_float(img.get_pixel(16, y).r).is_equal(0.0)


func test_coast_roughness_zero_is_backcompat() -> void:
	# The default-path output (no coast_roughness arg) must stay byte-identical to an
	# explicit coast_roughness = 0 — the roughness code adds nothing when disabled.
	var plain := Gen.generate_heights(Gen.Preset.ISLAND, 7, 20.0, 3, 0.55, 0.95, 33, 33)
	var zero := Gen.generate_heights(Gen.Preset.ISLAND, 7, 20.0, 3, 0.55, 0.95, 33, 33,
			0, 0.6, 0.0)
	assert_bool(plain.get_data() == zero.get_data()).is_true()


func test_coast_roughness_is_deterministic_and_changes_shape() -> void:
	var a := Gen.generate_heights(Gen.Preset.ISLAND, 7, 20.0, 3, 0.55, 0.95, 33, 33,
			0, 0.6, 0.6)
	var b := Gen.generate_heights(Gen.Preset.ISLAND, 7, 20.0, 3, 0.55, 0.95, 33, 33,
			0, 0.6, 0.6)
	var plain := Gen.generate_heights(Gen.Preset.ISLAND, 7, 20.0, 3, 0.55, 0.95, 33, 33)
	assert_bool(a.get_data() == b.get_data()).is_true()          # deterministic per seed
	assert_bool(a.get_data() == plain.get_data()).is_false()     # roughness reshapes coast


func test_coast_roughness_border_stays_sea_level() -> void:
	# The unperturbed guard past r = 0.92 must zero every border pixel even with roughness.
	var img := Gen.generate_heights(Gen.Preset.ISLAND, 7, 20.0, 3, 0.55, 0.95, 33, 33,
			0, 0.6, 1.0)
	for x in 33:
		assert_float(img.get_pixel(x, 0).r).is_equal(0.0)
		assert_float(img.get_pixel(x, 32).r).is_equal(0.0)
	for y in 33:
		assert_float(img.get_pixel(0, y).r).is_equal(0.0)
		assert_float(img.get_pixel(32, y).r).is_equal(0.0)


func test_coast_roughness_ignored_off_island() -> void:
	# Non-falloff presets never build coast noise, so roughness is a no-op there.
	var plain := Gen.generate_heights(Gen.Preset.ROLLING_HILLS, 7, 20.0, 3, 0.0, 1.0, 17, 17)
	var rough := Gen.generate_heights(Gen.Preset.ROLLING_HILLS, 7, 20.0, 3, 0.0, 1.0, 17, 17,
			0, 0.6, 1.0)
	assert_bool(plain.get_data() == rough.get_data()).is_true()


func test_presets_scale_amplitude() -> void:
	# Preset amplitude bounds the image: hills never exceed 0.5, plains 0.15.
	var hills := Gen.generate_heights(Gen.Preset.ROLLING_HILLS, 7, 20.0, 3, 0.0, 1.0, 9, 9)
	var plains := Gen.generate_heights(Gen.Preset.PLAINS, 7, 20.0, 3, 0.0, 1.0, 9, 9)
	var hills_max := 0.0
	var plains_max := 0.0
	for y in 9:
		for x in 9:
			hills_max = maxf(hills_max, hills.get_pixel(x, y).r)
			plains_max = maxf(plains_max, plains.get_pixel(x, y).r)
	assert_float(hills_max).is_less_equal(0.5 + 0.01)
	assert_float(plains_max).is_less_equal(0.15 + 0.01)
	assert_float(plains_max).is_greater(0.0)


func test_is_uniform() -> void:
	assert_bool(Gen.is_uniform(PackedFloat32Array())).is_true()
	assert_bool(Gen.is_uniform(PackedFloat32Array([0.5, 0.5, 0.5]))).is_true()
	assert_bool(Gen.is_uniform(PackedFloat32Array([0.5, 0.5, 0.6]))).is_false()


# --- slope + normals ---


func test_slope_deg_flat_and_45() -> void:
	assert_float(Gen.slope_deg(0.0, 0.0, 0.0, 0.0, 1.0, 1.0)).is_equal(0.0)
	# Rise 2 m over a 2 m span on X -> gradient 1 -> 45 degrees.
	assert_float(Gen.slope_deg(0.0, 2.0, 0.0, 0.0, 1.0, 1.0)).is_equal_approx(45.0, 0.001)


func test_grid_normal_flat_and_ramp() -> void:
	var flat := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
	var n := Gen.grid_normal(flat, 3, 3, 1, 1)
	assert_float(n.y).is_equal_approx(1.0, 0.001)
	# Height = x on every row: gradient (1, 0) -> normal along (-1, 1, 0)/sqrt(2).
	var ramp := PackedFloat32Array([0, 1, 2, 0, 1, 2, 0, 1, 2])
	var r := Gen.grid_normal(ramp, 3, 3, 1, 1)
	assert_float(r.x).is_equal_approx(-1.0 / sqrt(2.0), 0.001)
	assert_float(r.y).is_equal_approx(1.0 / sqrt(2.0), 0.001)
	assert_float(r.z).is_equal_approx(0.0, 0.001)


# --- splat classification (sand_height 3, dirt 22 deg, rock 38 deg) ---


func test_classify_low_flat_is_sand() -> void:
	var w := Gen.classify_splat(0.5, 0.0, 3.0, 22.0, 38.0)
	assert_float(w.b).is_equal_approx(1.0, 0.001)
	assert_float(w.r + w.g + w.a).is_equal_approx(0.0, 0.001)


func test_classify_high_flat_is_grass() -> void:
	var w := Gen.classify_splat(10.0, 0.0, 3.0, 22.0, 38.0)
	assert_float(w.r).is_equal_approx(1.0, 0.001)


func test_classify_moderate_slope_is_dirt() -> void:
	var w := Gen.classify_splat(10.0, 22.0, 3.0, 22.0, 38.0)
	assert_float(w.g).is_equal_approx(1.0, 0.001)


func test_classify_steep_is_rock() -> void:
	var w := Gen.classify_splat(10.0, 45.0, 3.0, 22.0, 38.0)
	assert_float(w.a).is_equal_approx(1.0, 0.001)


func test_classify_weights_sum_to_one() -> void:
	for probe in [[2.0, 15.0], [3.5, 30.0], [0.0, 0.0], [8.0, 60.0], [1.0, 25.0]]:
		var w := Gen.classify_splat(probe[0], probe[1], 3.0, 22.0, 38.0)
		assert_float(w.r + w.g + w.b + w.a).is_equal_approx(1.0, 0.001)


func test_build_splatmap_dims_and_flat_sand() -> void:
	# Flat zero-height terrain below sand_height: every pixel fully sand (blue).
	var heights := Image.create(3, 3, false, Image.FORMAT_RGBF)
	heights.fill(Color(0, 0, 0))
	var splat := Gen.build_splatmap(heights, 10.0, 1.0, 1.0, 3.0, 22.0, 38.0)
	assert_int(splat.get_width()).is_equal(3)
	assert_int(splat.get_height()).is_equal(3)
	var w := splat.get_pixel(1, 1)
	assert_float(w.b).is_equal_approx(1.0, 0.01)   # RGBA8 quantization tolerance
	assert_float(w.r + w.g + w.a).is_equal_approx(0.0, 0.01)


# --- chunk lattice ---


func test_chunk_ranges_exact_square() -> void:
	# 65x65 verts = 64x64 cells at 32 -> 2x2 chunks of 32.
	var ranges := Gen.chunk_ranges(65, 65, 32)
	assert_int(ranges.size()).is_equal(4)
	for rect in ranges:
		assert_int(rect.size.x).is_equal(32)
		assert_int(rect.size.y).is_equal(32)


func test_chunk_ranges_remainder_covers_all_cells() -> void:
	# 66x34 verts = 65x33 cells at 32 -> widths 32,32,1 x heights 32,1 = 6 chunks.
	var ranges := Gen.chunk_ranges(66, 34, 32)
	assert_int(ranges.size()).is_equal(6)
	var area := 0
	for rect in ranges:
		area += rect.size.x * rect.size.y
	assert_int(area).is_equal(65 * 33)   # exact cover + no overlap (disjoint by grid)
	assert_bool(ranges[-1] == Rect2i(64, 32, 1, 1)).is_true()


func test_chunk_ranges_single_chunk_small_map() -> void:
	var ranges := Gen.chunk_ranges(5, 5, 64)
	assert_int(ranges.size()).is_equal(1)
	assert_bool(ranges[0] == Rect2i(0, 0, 4, 4)).is_true()


# --- import sidecar ---


func test_ensure_import_settings_writes_lossless_params() -> void:
	var png_path := "user://terrain_gen_test.png"
	var import_path := png_path + ".import"
	DirAccess.remove_absolute(import_path)
	Gen.ensure_import_settings(png_path)
	var cfg := ConfigFile.new()
	assert_int(cfg.load(import_path)).is_equal(OK)
	assert_str(String(cfg.get_value("remap", "importer"))).is_equal("texture")
	assert_int(int(cfg.get_value("params", "compress/mode"))).is_equal(0)
	assert_bool(bool(cfg.get_value("params", "mipmaps/generate"))).is_false()
	assert_int(int(cfg.get_value("params", "detect_3d/compress_to"))).is_equal(0)
	assert_bool(bool(cfg.get_value("params", "process/fix_alpha_border"))).is_false()
	DirAccess.remove_absolute(import_path)

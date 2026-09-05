extends GdUnitTestSuite
## HeightmapTerrain: world-space height query (raycast fallback). Pure image math.

const TerrainScript := preload("res://src/levels/base/heightmap_terrain.gd")


func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


func _flat(red: float) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBF)
	img.fill(Color(red, red, red))
	return _tex(img)


# A 2x1 image: red ramps 0 -> 1 across X (left -> right).
func _ramp_x() -> ImageTexture:
	var img := Image.create(2, 1, false, Image.FORMAT_RGBF)
	img.set_pixel(0, 0, Color(0, 0, 0))
	img.set_pixel(1, 0, Color(1, 1, 1))
	return _tex(img)


# Uniform RGBA splat texture (float format so weights are exact — see the class doc gotcha).
func _splat(color: Color) -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBAF)
	img.fill(color)
	return _tex(img)


# In-tree so global_position resolves (height_at returns world-space Y).
func _terrain(size: Vector2, height: float, pos := Vector3.ZERO) -> HeightmapTerrain:
	var t: HeightmapTerrain = auto_free(TerrainScript.new())
	t.terrain_size = size
	t.height = height
	t.position = pos
	add_child(t)
	return t


func test_flat_height_is_uniform() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.heightmap = _flat(0.5)
	assert_float(t.height_at(Vector3(0, 99, 0))).is_equal_approx(5.0, 0.001)
	assert_float(t.height_at(Vector3(1.5, 0, -1.5))).is_equal_approx(5.0, 0.001)


func test_null_heightmap_flat_at_node_y() -> void:
	var t := _terrain(Vector2(4, 4), 8.0, Vector3(0, 3, 0))
	assert_float(t.height_at(Vector3(5, 0, 5))).is_equal_approx(3.0, 0.001)


func test_ramp_interpolates_across_x() -> void:
	var t := _terrain(Vector2(2, 2), 10.0)   # extent +/-1 on X and Z
	t.heightmap = _ramp_x()
	assert_float(t.height_at(Vector3(-1, 0, 0))).is_equal_approx(0.0, 0.001)
	assert_float(t.height_at(Vector3(0, 0, 0))).is_equal_approx(5.0, 0.001)
	assert_float(t.height_at(Vector3(1, 0, 0))).is_equal_approx(10.0, 0.001)


func test_height_adds_node_offset() -> void:
	var t := _terrain(Vector2(4, 4), 8.0, Vector3(10, 2, -5))   # translated terrain
	t.heightmap = _flat(1.0)
	# query at world (10, _, -5) maps to local origin -> full height, plus node Y.
	assert_float(t.height_at(Vector3(10, 0, -5))).is_equal_approx(10.0, 0.001)


func test_chunked_mesh_builds_per_tile_and_height_matches_across_borders() -> void:
	# 4x4 cells at chunk_cells 2 -> 2x2 tiles, one MeshInstance3D each. A relief heightmap
	# is required: a uniform one collapses to a single flat quad (the few-polygon path).
	# The ramp is constant in Z, so the image-based height query returns the same value at
	# a fixed X on either side of the Z chunk seam.
	var t := _terrain(Vector2(4, 4), 10.0)
	t.chunk_cells = 2
	t.heightmap = _ramp_x()
	var chunks := t.get_node("Chunks")
	assert_int(chunks.get_child_count()).is_equal(4)
	for chunk in chunks.get_children():
		assert_object((chunk as MeshInstance3D).mesh).is_not_null()
	# X = 0 -> mid-ramp -> red 0.5 -> y 5.0, unchanged across the Z seam.
	assert_float(t.height_at(Vector3(0, 0, -1.5))).is_equal_approx(5.0, 0.001)
	assert_float(t.height_at(Vector3(0, 0, 1.5))).is_equal_approx(5.0, 0.001)


func test_rebuild_region_world_remeshes_touched_chunks_only_leaving_collision() -> void:
	# Incremental sculpt path: remesh from a live working image (not the property) and
	# leave collision for stroke-end. Flat 0.5 -> verts y=5; feed a flat-0.8 image -> y=8.
	var t := _terrain(Vector2(4, 4), 10.0)
	t.chunk_cells = 2
	t.heightmap = _flat(0.5)
	var work := Image.create(5, 5, false, Image.FORMAT_RGBF)
	work.fill(Color(0.8, 0.8, 0.8))
	t.rebuild_region_world(work, -10, 10, -10, 10)
	var maxy := 0.0
	for chunk in t.get_node("Chunks").get_children():
		for v in (chunk as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			maxy = maxf(maxy, v.y)
	assert_float(maxy).is_equal_approx(8.0, 0.001)   # meshes reflect the working image
	# Collision is untouched by a region rebuild — still the 0.5 heightmap (y=5).
	var shape := (t.get_node("Collision") as CollisionShape3D).shape as HeightMapShape3D
	assert_float(shape.map_data[0]).is_equal_approx(5.0, 0.001)


func test_rebuild_collision_from_image_updates_shape() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.heightmap = _flat(0.5)
	var work := Image.create(5, 5, false, Image.FORMAT_RGBF)
	work.fill(Color(0.8, 0.8, 0.8))
	t.rebuild_collision_from_image(work)
	var shape := (t.get_node("Collision") as CollisionShape3D).shape as HeightMapShape3D
	assert_float(shape.map_data[0]).is_equal_approx(8.0, 0.001)


func test_contains_xz_extent() -> void:
	var t := _terrain(Vector2(4, 4), 8.0, Vector3(10, 0, 0))   # extent +/-2 around x=10
	assert_bool(t.contains_xz(Vector3(11.9, 0, 1.9))).is_true()
	assert_bool(t.contains_xz(Vector3(12.5, 0, 0))).is_false()
	assert_bool(t.contains_xz(Vector3(10, 0, -2.5))).is_false()


# --- splat-paint friction: get_splat_weights + grip_at ---
# Only binary-exact float32 values (0, 0.25, 0.5, 0.75, 1.0) so is_equal is safe.


func test_splat_weights_single_channel() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(1, 0, 0, 0))   # channel 0 fully painted
	var w := t.get_splat_weights(Vector3.ZERO)
	assert_int(w.size()).is_equal(8)
	assert_float(w[0]).is_equal(1.0)
	assert_float(w[1]).is_equal(0.0)
	assert_float(w[3]).is_equal(0.0)
	assert_float(w[4]).is_equal(0.0)   # no splatmap2 -> channels 4..7 zero


func test_splat_weights_blend() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(0.5, 0.5, 0, 0))
	var w := t.get_splat_weights(Vector3.ZERO)
	assert_float(w[0]).is_equal(0.5)
	assert_float(w[1]).is_equal(0.5)


func test_grip_default_table_is_neutral() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(1, 0, 0, 0))   # painted, but default channel_grip is all 1.0
	assert_float(t.grip_at(Vector3.ZERO)).is_equal(1.0)


func test_grip_scales_by_channel() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(1, 0, 0, 0))
	t.channel_grip = PackedFloat32Array([0.25, 1, 1, 1, 1, 1, 1, 1])
	assert_float(t.grip_at(Vector3.ZERO)).is_equal(0.25)


func test_grip_blends_channels() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(0.5, 0.5, 0, 0))
	t.channel_grip = PackedFloat32Array([0.5, 1, 1, 1, 1, 1, 1, 1])
	# (0.5*0.5 + 0.5*1.0) / (0.5 + 0.5) = 0.75
	assert_float(t.grip_at(Vector3.ZERO)).is_equal(0.75)


func test_grip_unpainted_is_one() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	assert_float(t.grip_at(Vector3.ZERO)).is_equal(1.0)   # no splatmap
	t.splatmap = _splat(Color(0, 0, 0, 0))                # all-zero weights: still neutral
	assert_float(t.grip_at(Vector3.ZERO)).is_equal(1.0)


func test_grip_sharpens_like_the_shader() -> void:
	# A brush-falloff pixel: mostly grass with a little ice. The shader's pow(w, 8) makes it
	# draw as ~pure grass, so the grip must follow — raw weights would hand back 0.78 here,
	# an invisible slick apron around every painted patch.
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(0.75, 0.25, 0, 0))
	t.channel_grip = PackedFloat32Array([1, 0.12, 1, 1, 1, 1, 1, 1])
	assert_float(t.grip_at(Vector3.ZERO)).is_greater(0.99)


func test_grip_ignores_a_faint_trace() -> void:
	# Normalization alone makes weight MAGNITUDE irrelevant: a barely-there 0.05 of ice would
	# normalize to FULL ice. Sharpened, it falls under the shader's own unpainted threshold.
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(0.0625, 0, 0, 0))   # binary-exact faint trace of channel 0
	t.channel_grip = PackedFloat32Array([0.12, 1, 1, 1, 1, 1, 1, 1])
	assert_float(t.grip_at(Vector3.ZERO)).is_equal(1.0)


func test_grip_clamps_out_of_range_channels() -> void:
	# An author-typed negative would invert tire friction and disable the friction circle;
	# above 1 would raise mu past the tuned spec. Both clamp into [0, 1].
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(1, 0, 0, 0))
	t.channel_grip = PackedFloat32Array([-2, 1, 1, 1, 1, 1, 1, 1])
	assert_float(t.grip_at(Vector3.ZERO)).is_equal(0.0)
	t.channel_grip = PackedFloat32Array([3, 1, 1, 1, 1, 1, 1, 1])
	assert_float(t.grip_at(Vector3.ZERO)).is_equal(1.0)
	assert_bool("\n".join(t._get_configuration_warnings()).contains("channel_grip[0]")).is_true()


# --- single-channel coverage: channel_weight_at (the "is this soil?" query) ---


func test_channel_weight_reports_the_painted_channel() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(1, 0, 0, 0))
	assert_float(t.channel_weight_at(Vector3.ZERO, 0)).is_equal(1.0)
	assert_float(t.channel_weight_at(Vector3.ZERO, 1)).is_equal(0.0)


func test_channel_weight_reads_the_second_splatmap() -> void:
	# Channel 4 is splatmap2.R — level 1's "Field", the tractor's in-soil predicate.
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(0, 0, 0, 0))
	t.splatmap2 = _splat(Color(1, 0, 0, 0))
	assert_float(t.channel_weight_at(Vector3.ZERO, 4)).is_equal(1.0)
	assert_float(t.channel_weight_at(Vector3.ZERO, 5)).is_equal(0.0)


func test_channel_weight_is_zero_where_nothing_is_painted() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	assert_float(t.channel_weight_at(Vector3.ZERO, 4)).is_equal(0.0)   # no splatmap at all
	t.splatmap = _splat(Color(1, 0, 0, 0))
	# Base map painted but no splatmap2: channels 4..7 are unpainted by construction.
	assert_float(t.channel_weight_at(Vector3.ZERO, 4)).is_equal(0.0)
	# All-zero weights, and out-of-range channels, answer "not this channel" rather than 1.0 —
	# there is no neutral fallback here, unlike grip_at.
	t.splatmap = _splat(Color(0, 0, 0, 0))
	assert_float(t.channel_weight_at(Vector3.ZERO, 0)).is_equal(0.0)
	assert_float(t.channel_weight_at(Vector3.ZERO, 8)).is_equal(0.0)
	assert_float(t.channel_weight_at(Vector3.ZERO, -1)).is_equal(0.0)


func test_channel_weight_sharpens_and_ignores_a_faint_trace_like_grip() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	# A brush-falloff pixel the shader draws as ~pure grass: the field weight has to follow it
	# down, or the plough would find soil in a border the player sees as grass.
	t.splatmap = _splat(Color(0.75, 0, 0, 0))
	t.splatmap2 = _splat(Color(0.25, 0, 0, 0))
	assert_float(t.channel_weight_at(Vector3.ZERO, 4)).is_less(0.01)
	# And a faint trace of field over nothing else falls under the unpainted threshold.
	t.splatmap = _splat(Color(0, 0, 0, 0))
	t.splatmap2 = _splat(Color(0.0625, 0, 0, 0))
	assert_float(t.channel_weight_at(Vector3.ZERO, 4)).is_equal(0.0)


func test_splat2_size_mismatch_warns() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(1, 0, 0, 0))
	assert_array(t._get_configuration_warnings()).is_empty()
	var odd := Image.create(8, 8, false, Image.FORMAT_RGBAF)
	odd.fill(Color(0, 0, 0, 0))
	t.splatmap2 = _tex(odd)
	assert_bool("\n".join(t._get_configuration_warnings()).contains("splatmap2")).is_true()

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


## A response with only `s` set to `g` (every other surface 1.0), so a blend stays binary-exact.
func _response(s: int, g: float) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	r.resize(Surface.COUNT)
	r.fill(1.0)
	r[s] = g
	return r


## Channel 0 is `s`, the rest the default table.
func _with_channel0(t: HeightmapTerrain, s: int) -> void:
	var table := PackedInt32Array(HeightmapTerrain.DEFAULT_CHANNEL_SURFACE)
	table[0] = s
	t.channel_surface = table


## Channel 4 is Field, the rest the default table.
func _with_field4(t: HeightmapTerrain) -> void:
	var table := PackedInt32Array(HeightmapTerrain.DEFAULT_CHANNEL_SURFACE)
	table[4] = Surface.FIELD
	t.channel_surface = table


func test_drag_reads_the_channel_surface() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(1, 0, 0, 0))
	_with_channel0(t, Surface.MUD)
	assert_float(t.drag_at(Vector3.ZERO)).is_equal_approx(Surface.drag(Surface.MUD), 1e-6)
	_with_channel0(t, Surface.ASPHALT)
	assert_float(t.drag_at(Vector3.ZERO)).is_equal(0.0)


func test_drag_blends_channels() -> void:
	# Half Mud and half Asphalt (0): weights 0.5/0.5 -> half Mud's drag.
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(0.5, 0.5, 0, 0))
	t.channel_surface = PackedInt32Array([Surface.MUD, Surface.ASPHALT, 0, 0, 0, 0, 0, 0])
	assert_float(t.drag_at(Vector3.ZERO)).is_equal_approx(0.5 * Surface.drag(Surface.MUD), 1e-6)


func test_drag_unpainted_and_missing_splat_reads_asphalt() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	_with_channel0(t, Surface.MUD)
	assert_float(t.drag_at(Vector3.ZERO)).is_equal(0.0)   # no splatmap
	t.splatmap = _splat(Color(0, 0, 0, 0))
	assert_float(t.drag_at(Vector3.ZERO)).is_equal(0.0)   # painted nothing


func test_grip_without_a_response_is_the_surface_ref_grip() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(1, 0, 0, 0))   # the default table's channel 0 is Grass
	assert_float(t.grip_at(Vector3.ZERO, PackedFloat32Array())) \
			.is_equal_approx(Surface.ref_grip(Surface.GRASS), 1e-6)
	_with_channel0(t, Surface.ASPHALT)
	assert_float(t.grip_at(Vector3.ZERO, PackedFloat32Array())).is_equal(1.0)


func test_grip_reads_the_response_by_surface() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(1, 0, 0, 0))
	_with_channel0(t, Surface.SNOW)
	assert_float(t.grip_at(Vector3.ZERO, _response(Surface.SNOW, 0.25))).is_equal(0.25)
	# Not clamped: a tyre may out-grip the reference on its surface.
	assert_float(t.grip_at(Vector3.ZERO, _response(Surface.SNOW, 1.25))).is_equal(1.25)
	# A response too short for the surface falls back to its ref_grip.
	assert_float(t.grip_at(Vector3.ZERO, PackedFloat32Array([0.5]))) \
			.is_equal_approx(Surface.ref_grip(Surface.SNOW), 1e-6)


func test_grip_blends_channels() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(0.5, 0.5, 0, 0))
	t.channel_surface = PackedInt32Array([Surface.ICE, Surface.ASPHALT, 0, 0, 0, 0, 0, 0])
	# (0.5*0.5 + 0.5*1.0) / (0.5 + 0.5) = 0.75
	assert_float(t.grip_at(Vector3.ZERO, _response(Surface.ICE, 0.5))).is_equal(0.75)


func test_grip_unpainted_reads_asphalt() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	_with_channel0(t, Surface.ICE)
	assert_float(t.grip_at(Vector3.ZERO, PackedFloat32Array())).is_equal(1.0)   # no splatmap
	t.splatmap = _splat(Color(0, 0, 0, 0))   # all-zero weights: Asphalt, not channel 0
	assert_float(t.grip_at(Vector3.ZERO, PackedFloat32Array())).is_equal(1.0)
	# ...and the fitted tyre's Asphalt figure, not the reference's.
	assert_float(t.grip_at(Vector3.ZERO, _response(Surface.ASPHALT, 1.25))).is_equal(1.25)


func test_grip_sharpens_like_the_shader() -> void:
	# A brush-falloff pixel: mostly asphalt with a little ice. The shader's pow(w, 8) makes it
	# draw as ~pure asphalt, so the grip must follow — raw weights would hand back 0.78 here,
	# an invisible slick apron around every painted patch.
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(0.75, 0.25, 0, 0))
	t.channel_surface = PackedInt32Array([Surface.ASPHALT, Surface.ICE, 0, 0, 0, 0, 0, 0])
	assert_float(t.grip_at(Vector3.ZERO, PackedFloat32Array())).is_greater(0.99)


func test_grip_ignores_a_faint_trace() -> void:
	# Normalization alone makes weight MAGNITUDE irrelevant: a barely-there 0.05 of ice would
	# normalize to FULL ice. Sharpened, it falls under the shader's own unpainted threshold.
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(0.0625, 0, 0, 0))   # binary-exact faint trace of channel 0
	_with_channel0(t, Surface.ICE)
	assert_float(t.grip_at(Vector3.ZERO, PackedFloat32Array())).is_equal(1.0)


func test_an_unknown_surface_id_warns_and_reads_asphalt() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(1, 0, 0, 0))
	assert_array(t._get_configuration_warnings()).is_empty()
	_with_channel0(t, 99)
	assert_float(t.grip_at(Vector3.ZERO, PackedFloat32Array())).is_equal(1.0)
	assert_float(t.drag_at(Vector3.ZERO)).is_equal(0.0)
	assert_bool("\n".join(t._get_configuration_warnings()).contains("channel_surface[0]")).is_true()
	t.channel_surface = PackedInt32Array([Surface.ICE])   # short: channels 1..7 read Asphalt
	assert_bool("\n".join(t._get_configuration_warnings()).contains("1 entries")).is_true()


func test_channel_names_come_from_the_surfaces() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	assert_array(Array(t.channel_names())).is_equal(Array(HeightmapTerrain.default_channel_names()))
	_with_channel0(t, Surface.FIELD)
	assert_str(t.channel_names()[0]).is_equal("Field")
	assert_str(t.channel_names()[6]).is_equal("Asphalt")


# --- surface coverage: surface_weight_at (the "is this soil?" query) ---


func test_surface_weight_reports_the_painted_surface() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(1, 0, 0, 0))   # channel 0: Grass in the default table
	assert_float(t.surface_weight_at(Vector3.ZERO, Surface.GRASS)).is_equal(1.0)
	assert_float(t.surface_weight_at(Vector3.ZERO, Surface.DIRT)).is_equal(0.0)


func test_surface_weight_reads_the_second_splatmap() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	_with_field4(t)
	t.splatmap = _splat(Color(0, 0, 0, 0))
	t.splatmap2 = _splat(Color(1, 0, 0, 0))
	assert_float(t.surface_weight_at(Vector3.ZERO, Surface.FIELD)).is_equal(1.0)
	assert_float(t.surface_weight_at(Vector3.ZERO, Surface.MUD)).is_equal(0.0)


func test_surface_weight_sums_every_channel_holding_it() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.channel_surface = PackedInt32Array([Surface.FIELD, Surface.GRASS, Surface.FIELD, 0, 0, 0, 0, 0])
	t.splatmap = _splat(Color(0.5, 0.5, 0.5, 0))
	# Three equal weights, two of them Field.
	assert_float(t.surface_weight_at(Vector3.ZERO, Surface.FIELD)).is_equal_approx(2.0 / 3.0, 1e-6)


## The F3 readout's name: the surface with the most summed weight, Asphalt where unpainted.
func test_surface_at_names_the_heaviest_surface() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	assert_int(t.surface_at(Vector3.ZERO)).is_equal(Surface.ASPHALT)   # no splatmap
	t.channel_surface = PackedInt32Array([Surface.GRASS, Surface.FIELD, Surface.FIELD, 0, 0, 0, 0, 0])
	t.splatmap = _splat(Color(0.52, 0.5, 0.5, 0))
	# Grass is the heaviest channel; Field's two outweigh it (2 x (0.5 / 0.52)^8 = 1.46).
	assert_int(t.surface_at(Vector3.ZERO)).is_equal(Surface.FIELD)


func test_surface_weight_is_zero_where_nothing_is_painted() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	_with_field4(t)
	assert_float(t.surface_weight_at(Vector3.ZERO, Surface.FIELD)).is_equal(0.0)   # no splatmap
	t.splatmap = _splat(Color(1, 0, 0, 0))
	# Base map painted but no splatmap2: channels 4..7 are unpainted by construction.
	assert_float(t.surface_weight_at(Vector3.ZERO, Surface.FIELD)).is_equal(0.0)
	# All-zero weights and unknown surfaces answer "not this surface", never Asphalt's fallback.
	t.splatmap = _splat(Color(0, 0, 0, 0))
	assert_float(t.surface_weight_at(Vector3.ZERO, Surface.GRASS)).is_equal(0.0)
	assert_float(t.surface_weight_at(Vector3.ZERO, Surface.ASPHALT)).is_equal(0.0)
	assert_float(t.surface_weight_at(Vector3.ZERO, Surface.COUNT)).is_equal(0.0)
	assert_float(t.surface_weight_at(Vector3.ZERO, -1)).is_equal(0.0)


func test_surface_weight_sharpens_and_ignores_a_faint_trace_like_grip() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	_with_field4(t)
	# A brush-falloff pixel the shader draws as ~pure grass: the field weight has to follow it
	# down, or the plough would find soil in a border the player sees as grass.
	t.splatmap = _splat(Color(0.75, 0, 0, 0))
	t.splatmap2 = _splat(Color(0.25, 0, 0, 0))
	assert_float(t.surface_weight_at(Vector3.ZERO, Surface.FIELD)).is_less(0.01)
	# And a faint trace of field over nothing else falls under the unpainted threshold.
	t.splatmap = _splat(Color(0, 0, 0, 0))
	t.splatmap2 = _splat(Color(0.0625, 0, 0, 0))
	assert_float(t.surface_weight_at(Vector3.ZERO, Surface.FIELD)).is_equal(0.0)


func test_splat2_size_mismatch_warns() -> void:
	var t := _terrain(Vector2(4, 4), 10.0)
	t.splatmap = _splat(Color(1, 0, 0, 0))
	assert_array(t._get_configuration_warnings()).is_empty()
	var odd := Image.create(8, 8, false, Image.FORMAT_RGBAF)
	odd.fill(Color(0, 0, 0, 0))
	t.splatmap2 = _tex(odd)
	assert_bool("\n".join(t._get_configuration_warnings()).contains("splatmap2")).is_true()

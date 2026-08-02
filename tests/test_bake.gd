# GdUnit generated TestSuite
extends GdUnitTestSuite
## Unit tests for the level baker's pure logic: chunk assignment,
## vertex welding, spawn validation, hashing/normalization, and the manifest
## round-trip. Scene-level bake behaviour is exercised end-to-end by the CI bake
## check (tools/check_bakes.gd), not here.

const Baker := preload("res://kit/bake/level_baker.gd")


# ---------------------------------------------------------------- chunk keys

func test_chunk_key_quadrants() -> void:
	assert_that(Baker.chunk_key(Vector3(0, 0, 0), 48.0)).is_equal(Vector2i(0, 0))
	assert_that(Baker.chunk_key(Vector3(47.9, 5, 47.9), 48.0)).is_equal(Vector2i(0, 0))
	assert_that(Baker.chunk_key(Vector3(48.0, 0, 0), 48.0)).is_equal(Vector2i(1, 0))
	# floor semantics, not truncation: -0.1 belongs to chunk -1
	assert_that(Baker.chunk_key(Vector3(-0.1, 0, -48.1), 48.0)).is_equal(Vector2i(-1, -2))


func test_chunk_origin_roundtrip() -> void:
	var key := Vector2i(-2, 3)
	var origin := Baker.chunk_origin(key, 32.0)
	assert_that(origin).is_equal(Vector3(-64, 0, 96))
	assert_that(Baker.chunk_key(origin + Vector3(1, 0, 1), 32.0)).is_equal(key)


# ------------------------------------------------------------------- welding

func _tri(a: Vector3, b: Vector3, c: Vector3) -> PackedVector3Array:
	return PackedVector3Array([a, b, c])


func test_weld_snaps_near_vertices_bit_identical() -> void:
	# Two triangles sharing an edge, but the second's shared verts are off by less
	# than the weld epsilon (the classic tile-border crack).
	var soup := PackedVector3Array()
	soup.append_array(_tri(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)))
	soup.append_array(_tri(Vector3(1.0004, 0, 0.0003), Vector3(1, 0, 1), Vector3(-0.0002, 0, 1.0004)))
	var welded := Baker.weld_faces(soup)
	assert_int(welded.size()).is_equal(6)
	# shared corners are now bit-identical
	assert_that(welded[1]).is_equal(welded[3])   # (1,0,0)
	assert_that(welded[2]).is_equal(welded[5])   # (0,0,1)


func test_weld_drops_degenerate_triangles() -> void:
	# All three verts weld to the same point -> triangle vanishes.
	var soup := _tri(Vector3(0, 0, 0), Vector3(0.0002, 0, 0), Vector3(0, 0.0003, 0))
	assert_int(Baker.weld_faces(soup).size()).is_equal(0)


## Welding is an epsilon MERGE, not a snap-to-grid. Two verts a fraction of the epsilon
## apart but astride a grid cell boundary rounded to different cells and stayed distinct —
## the exact crack the weld exists to close, and position-dependent, so it passed every
## fixture and would have surfaced on one authored level as a wheel catching at one joint.
func test_weld_unifies_vertices_astride_a_grid_boundary() -> void:
	# 12.0004999 and 12.0005001 straddle the cell boundary at 12.0005 (epsilon 1 mm):
	# 0.2 micrometres apart, formerly two different vertices.
	var soup := PackedVector3Array()
	soup.append_array(_tri(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 12.0004999)))
	soup.append_array(_tri(Vector3(1, 0, 0), Vector3(1, 0, 12.0005001),
			Vector3(0, 0, 12.0005001)))
	var welded := Baker.weld_faces(soup)
	assert_int(welded.size()).is_equal(6)
	assert_that(welded[2]).is_equal(welded[5])   # the shared corner is bit-identical


func test_weld_keeps_vertices_further_apart_than_epsilon_distinct() -> void:
	# 3 mm apart with a 1 mm epsilon: a real gap, and merging it would move geometry.
	var soup := PackedVector3Array()
	soup.append_array(_tri(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)))
	soup.append_array(_tri(Vector3(1, 0, 0.003), Vector3(1, 0, 1), Vector3(0, 0, 1.003)))
	var welded := Baker.weld_faces(soup)
	assert_that(welded[2]).is_not_equal(welded[5])


func test_weld_is_deterministic() -> void:
	var soup := PackedVector3Array()
	soup.append_array(_tri(Vector3(0.30017, 1.2, -4.7), Vector3(5, 0, 0), Vector3(0, 0, 5)))
	assert_that(Baker.weld_faces(soup)).is_equal(Baker.weld_faces(soup.duplicate()))


# ----------------------------------------------------------- spawn validation

func _spawn(types: Array, water := false) -> Dictionary:
	return {"types": PackedStringArray(types), "is_water": water}


func test_validate_spawns_happy_path() -> void:
	var errors := Baker.validate_spawns(PackedStringArray(["car", "truck"]), "car",
			[_spawn([]), _spawn(["truck"])])
	assert_array(errors).is_empty()


func test_validate_spawns_no_markers() -> void:
	var errors := Baker.validate_spawns(PackedStringArray(["car"]), "car", [])
	assert_int(errors.size()).is_equal(1)
	assert_str(errors[0]).contains("no VehicleSpawn")


func test_validate_spawns_default_not_allowed() -> void:
	var errors := Baker.validate_spawns(PackedStringArray(["truck"]), "car", [_spawn([])])
	assert_bool("\n".join(errors).contains("not in allowed_vehicles")).is_true()


func test_validate_spawns_missing_type_coverage() -> void:
	var errors := Baker.validate_spawns(PackedStringArray(["car", "tractor"]), "car",
			[_spawn(["car"])])
	assert_bool("\n".join(errors).contains("'tractor'")).is_true()


func test_validate_spawns_boat_needs_water() -> void:
	var land_only := Baker.validate_spawns(PackedStringArray(["boat"]), "boat", [_spawn([])])
	assert_bool("\n".join(land_only).contains("water")).is_true()
	var with_water := Baker.validate_spawns(PackedStringArray(["boat"]), "boat",
			[_spawn([], true)])
	assert_array(with_water).is_empty()


func test_validate_spawns_land_vehicle_rejects_water_only() -> void:
	var errors := Baker.validate_spawns(PackedStringArray(["car"]), "car", [_spawn([], true)])
	assert_bool("\n".join(errors).contains("'car'")).is_true()


func test_validate_spawns_empty_allowed_checks_default_only() -> void:
	var errors := Baker.validate_spawns(PackedStringArray(), "car", [_spawn(["car"])])
	assert_array(errors).is_empty()


# ------------------------------------------------------------------- hashing

func test_normalize_text_line_endings() -> void:
	assert_str(Baker.normalize_text("a\r\nb\rc\nd")).is_equal("a\nb\nc\nd")


func test_hash_file_text_ignores_crlf() -> void:
	var lf := "user://bake_test_lf.tscn"
	var crlf := "user://bake_test_crlf.tscn"
	FileAccess.open(lf, FileAccess.WRITE).store_string("[node]\nkey = 1\n")
	FileAccess.open(crlf, FileAccess.WRITE).store_string("[node]\r\nkey = 1\r\n")
	assert_str(Baker.hash_file(lf)).is_equal(Baker.hash_file(crlf))


func test_hash_inputs_order_independent_and_content_sensitive() -> void:
	var a := "user://bake_test_a.tscn"
	var b := "user://bake_test_b.tscn"
	FileAccess.open(a, FileAccess.WRITE).store_string("alpha")
	FileAccess.open(b, FileAccess.WRITE).store_string("beta")
	var h1 := Baker.hash_inputs(PackedStringArray([a, b]))
	var h2 := Baker.hash_inputs(PackedStringArray([b, a]))
	assert_str(h1).is_equal(h2)
	FileAccess.open(b, FileAccess.WRITE).store_string("beta CHANGED")
	assert_str(Baker.hash_inputs(PackedStringArray([a, b]))).is_not_equal(h1)


func test_hash_extra_chunk_size_changes_hash() -> void:
	var a := "user://bake_test_a.tscn"
	FileAccess.open(a, FileAccess.WRITE).store_string("alpha")
	var paths := PackedStringArray([a])
	assert_str(Baker.hash_inputs(paths, Baker.hash_extra(48.0))) \
			.is_not_equal(Baker.hash_inputs(paths, Baker.hash_extra(32.0)))


func test_hash_missing_file_flagged_not_crashing() -> void:
	var h := Baker.hash_inputs(PackedStringArray(["user://bake_test_nope.tscn"]))
	assert_str(h).is_not_empty()


## Bake-adjacent CODE must be hashed explicitly. GDScript files report no dependencies at
## all, so road_builder.gd / scatter_base.gd / the baker itself are reachable from no
## resource edge: without this, editing the extruder's fold clamp and forgetting to bump
## BAKER_VERSION left every level "fresh" in CI while shipping the old geometry.
func test_bake_code_files_are_in_the_input_hash() -> void:
	var inputs := Baker.gather_bake_inputs("res://src/levels/island/level_1/level_1.tscn")
	for code in Baker.BAKE_CODE_INPUTS:
		assert_bool(inputs.has(code)).override_failure_message(
				"%s missing from the bake input hash" % code).is_true()


## The hash net covers resources ANYWHERE, not just res://kit/: a prop sub-scene or a
## LevelInfo .tres under res://src/ shapes the bake (or its gates) and used to escape.
## Runtime scripts stay out — they cannot change baker output, and hashing them would
## re-stale every level on unrelated gameplay edits.
func test_is_bake_input_keeps_resources_outside_kit_but_not_runtime_scripts() -> void:
	assert_bool(Baker.is_bake_input("res://src/levels/harbor/dock_props.tscn")).is_true()
	assert_bool(Baker.is_bake_input("res://src/levels/harbor/harbor_info.tres")).is_true()
	assert_bool(Baker.is_bake_input("res://src/levels/harbor/heightmap.png")).is_true()
	assert_bool(Baker.is_bake_input("res://kit/helpers/kit_piece.gd")).is_true()
	assert_bool(Baker.is_bake_input("res://src/levels/base/level.gd")).is_false()
	assert_bool(Baker.is_bake_input("res://addons/carlito_kit/palette_dock.gd")).is_false()


# ------------------------------------------------------------------ manifest

func test_manifest_roundtrip_and_paths() -> void:
	var level := "user://bake_test_level.tscn"
	assert_str(Baker.baked_scene_path(level)).is_equal("user://bake_test_level.baked.scn")
	assert_str(Baker.manifest_path(level)).is_equal("user://bake_test_level.bake.json")
	assert_that(Baker.write_manifest(level, "abc123", 48.0, {"chunks": 2})).is_equal(OK)
	var m := Baker.read_manifest(level)
	assert_int(int(m.get("baker_version", -1))).is_equal(Baker.BAKER_VERSION)
	assert_str(String(m.get("input_hash", ""))).is_equal("abc123")
	assert_float(float(m.get("chunk_size", 0.0))).is_equal_approx(48.0, 0.001)
	assert_int(int((m.get("stats", {}) as Dictionary).get("chunks", 0))).is_equal(2)


## The manifest stamps the OUTPUT too: freshness used to ask only whether the .baked.scn
## exists, so a truncated or hand-edited bake read fresh forever on a matching input hash.
func test_manifest_stamps_the_baked_scene_hash() -> void:
	var level := "user://bake_test_level3.tscn"
	Baker.write_manifest(level, "in", 48.0, {}, "outhash")
	assert_str(String(Baker.read_manifest(level).get("output_hash", ""))).is_equal("outhash")


func test_manifest_is_timestamp_free_idempotent() -> void:
	var level := "user://bake_test_level2.tscn"
	Baker.write_manifest(level, "h", 32.0, {"chunks": 1})
	var first := FileAccess.get_file_as_string(Baker.manifest_path(level))
	Baker.write_manifest(level, "h", 32.0, {"chunks": 1})
	assert_str(FileAccess.get_file_as_string(Baker.manifest_path(level))).is_equal(first)


# ------------------------------------------------------------ material keys

func test_material_key_merges_equal_materials_across_instances() -> void:
	var m1 := StandardMaterial3D.new()
	var m2 := StandardMaterial3D.new()
	m1.albedo_color = Color.RED
	m2.albedo_color = Color.RED
	assert_str(Baker.material_key(m1)).is_equal(Baker.material_key(m2))
	m2.albedo_color = Color.BLUE
	assert_str(Baker.material_key(m1)).is_not_equal(Baker.material_key(m2))
	assert_str(Baker.material_key(null)).is_equal("null")


## The whole kit shares one colormap atlas, so albedo alone cannot tell materials apart:
## keying on it merged an emissive lit-window material into the matte wall surface beside
## it, and whichever the merge saw first won — windows matte on one chunk, walls glowing on
## the next, from identical authoring. Every field that changes how a surface renders
## must split the key.
func test_material_key_separates_materials_that_render_differently() -> void:
	var base := StandardMaterial3D.new()
	base.albedo_color = Color.RED
	var key := Baker.material_key(base)

	var emissive := StandardMaterial3D.new()
	emissive.albedo_color = Color.RED
	emissive.emission_enabled = true
	emissive.emission = Color.WHITE
	assert_str(Baker.material_key(emissive)).is_not_equal(key)

	var rough := StandardMaterial3D.new()
	rough.albedo_color = Color.RED
	rough.roughness = 0.2
	assert_str(Baker.material_key(rough)).is_not_equal(key)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color.RED
	metal.metallic = 1.0
	assert_str(Baker.material_key(metal)).is_not_equal(key)

	var unshaded := StandardMaterial3D.new()
	unshaded.albedo_color = Color.RED
	unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	assert_str(Baker.material_key(unshaded)).is_not_equal(key)

	var tiled := StandardMaterial3D.new()
	tiled.albedo_color = Color.RED
	tiled.uv1_scale = Vector3(4, 4, 1)
	assert_str(Baker.material_key(tiled)).is_not_equal(key)

	# and materials that really are identical still merge (the reason keys exist)
	var twin := StandardMaterial3D.new()
	twin.albedo_color = Color.RED
	assert_str(Baker.material_key(twin)).is_equal(key)


# ------------------------------------------------------- surface accumulator

func _quad_arrays() -> Array:
	# One unit quad (two indexed triangles) with normals up and UVs.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	return arrays


func test_accumulator_offsets_indices_and_transforms_positions() -> void:
	var acc := Baker.SurfaceAccumulator.new()
	acc.append(_quad_arrays(), Transform3D.IDENTITY)
	acc.append(_quad_arrays(), Transform3D(Basis.IDENTITY, Vector3(10, 0, 0)))
	assert_int(acc.positions.size()).is_equal(8)
	assert_int(acc.indices.size()).is_equal(12)
	assert_int(acc.indices[6]).is_equal(4)  # second quad's indices offset by base
	assert_that(acc.positions[4]).is_equal(Vector3(10, 0, 0))


func test_accumulator_renormalizes_normals_under_uniform_scale() -> void:
	var acc := Baker.SurfaceAccumulator.new()
	var scaled := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 10.0), Vector3.ZERO)
	acc.append(_quad_arrays(), scaled)
	assert_float(acc.normals[0].length()).is_equal_approx(1.0, 0.0001)
	assert_that(acc.positions[1]).is_equal(Vector3(10, 0, 0))


func test_accumulator_backfills_missing_uv_and_color() -> void:
	var no_uv := _quad_arrays()
	no_uv[Mesh.ARRAY_TEX_UV] = null
	var with_col := _quad_arrays()
	with_col[Mesh.ARRAY_COLOR] = PackedColorArray([
		Color.RED, Color.RED, Color.RED, Color.RED])
	var acc := Baker.SurfaceAccumulator.new()
	acc.append(no_uv, Transform3D.IDENTITY)      # no uv, no color yet
	acc.append(with_col, Transform3D.IDENTITY)   # uv + color appear late
	assert_bool(acc.has_uv).is_true()
	assert_bool(acc.has_color).is_true()
	assert_int(acc.uvs.size()).is_equal(8)       # first quad zero-backfilled
	assert_int(acc.colors.size()).is_equal(8)
	assert_that(acc.colors[0]).is_equal(Color.WHITE)  # backfill is white, not transparent
	assert_that(acc.colors[4]).is_equal(Color.RED)
	# commit produces a well-formed two-quad surface
	var mesh := ArrayMesh.new()
	acc.commit(mesh, StandardMaterial3D.new())
	assert_int(mesh.get_surface_count()).is_equal(1)


## Geometric cross of a triangle; Godot's front face is the opposite direction, so an
## up-facing triangle's cross points DOWN (the road tests' convention).
func _tri_cross(pos: PackedVector3Array, idx: PackedInt32Array, t: int) -> Vector3:
	return (pos[idx[t + 1]] - pos[idx[t]]).cross(pos[idx[t + 2]] - pos[idx[t]])


## A mirroring transform (scale (-1, 1, 1) — the standard left-hand-variant trick) flips
## triangle handedness. The inverse-transpose keeps normals outward, but copying the index
## order verbatim left the winding reversed: the chunk mesh rendered inside-out under
## cull_back, so a mirrored pier was visible only from inside it.
func test_accumulator_preserves_winding_under_mirroring() -> void:
	var mirror := Transform3D(Basis.IDENTITY.scaled(Vector3(-1, 1, 1)), Vector3.ZERO)
	var acc := Baker.SurfaceAccumulator.new()
	acc.append(_quad_arrays(), mirror)
	assert_float(mirror.basis.determinant()).is_less(0.0)   # fixture really mirrors
	for t in range(0, acc.indices.size(), 3):
		# normals stay up, so the front face must stay up: cross . normal < 0
		assert_float(_tri_cross(acc.positions, acc.indices, t).dot(acc.normals[acc.indices[t]])) \
				.is_less(0.0)


## The same trap on the collision side: mirrored triangles entered the welded Drivable body
## back-to-front, making the deck one-way so the car fell through it.
func test_weld_pool_preserves_winding_under_mirroring() -> void:
	var tri := _tri(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1))
	var ctx := Baker.BakeContext.new()
	ctx.add_weld_faces(tri, Transform3D(Basis.IDENTITY.scaled(Vector3(-1, 1, 1)), Vector3.ZERO))
	var welded: PackedVector3Array = ctx.weld_pool
	assert_int(welded.size()).is_equal(3)
	var cross_src := (tri[1] - tri[0]).cross(tri[2] - tri[0])
	var cross_out := (welded[1] - welded[0]).cross(welded[2] - welded[0])
	assert_float(cross_out.dot(cross_src)).is_greater(0.0)   # same facing, not inverted


func test_accumulator_generates_sequential_indices_for_unindexed() -> void:
	var arrays := _quad_arrays()
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = null
	arrays[Mesh.ARRAY_INDEX] = null
	var acc := Baker.SurfaceAccumulator.new()
	acc.append(arrays, Transform3D.IDENTITY)
	assert_that(acc.indices).is_equal(PackedInt32Array([0, 1, 2]))


# ------------------------------------------------------------ scatter bake paths

const ScatterRegionScript := preload("res://kit/helpers/scatter_region.gd")
const ScatterItemScript := preload("res://kit/helpers/scatter_item.gd")


## Minimal in-code kit prefab: KitPiece root + one BoxMesh + one box DevCollision
## shape — enough to exercise both scatter render paths and the collision harvest.
func _scatter_prefab(mode: String, with_mesh := true) -> PackedScene:
	var root := Node3D.new()
	root.name = "Piece"
	root.set_script(preload("res://kit/helpers/kit_piece.gd"))
	root.set("collision_mode", mode)
	if with_mesh:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = BoxMesh.new()
		root.add_child(mi)
		mi.owner = root
	var body := StaticBody3D.new()
	body.name = "DevCollision"
	root.add_child(body)
	body.owner = root
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = BoxShape3D.new()
	body.add_child(cs)
	cs.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


## Bakeable level skeleton (never enters the tree, so no _ready side effects):
## root + car-friendly spawn + AuthoringRoot + one ScatterRegion with hand-set
## stored transforms — the baker must consume the STORED data, nothing else.
func _scatter_level(prefab: PackedScene, positions: Array, collision: bool,
		threshold_override: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "L"
	var spawn := Marker3D.new()
	spawn.name = "Spawn"
	spawn.set_script(load("res://src/levels/base/vehicle_spawn.gd"))
	root.add_child(spawn)
	var authoring := Node3D.new()
	authoring.name = "Authoring"
	authoring.set_script(preload("res://kit/helpers/authoring_root.gd"))
	root.add_child(authoring)

	var item: Resource = ScatterItemScript.new()
	item.set("prefab", prefab)
	item.set("collision", collision)
	item.set("bake_threshold_override", threshold_override)
	var region := Node3D.new()
	region.name = "Region"
	region.set_script(ScatterRegionScript)
	authoring.add_child(region)
	var items: Array[ScatterItem] = [item]
	region.set("items", items)
	var flat := PackedFloat32Array()
	for pos: Vector3 in positions:
		flat.append_array(PackedFloat32Array([pos.x, pos.y, pos.z, 0.0, 1.0]))
	var stored: Array[PackedFloat32Array] = [flat]
	region.set("stored_transforms", stored)
	return {"root": root, "region": region}


func test_scatter_above_threshold_bakes_multimesh_per_chunk() -> void:
	# threshold 2 with 3 instances across two 48 m chunks -> the MultiMesh path.
	var level: Dictionary = _scatter_level(_scatter_prefab("hull"),
			[Vector3(0, 0, 0), Vector3(1, 0, 1), Vector3(60, 0, 0)], true, 2)
	var result: Dictionary = Baker.bake(level.root)
	assert_bool(result.ok).is_true()
	var baked: Node3D = result.root

	var scatter := baked.get_node("Scatter")
	assert_int(scatter.get_child_count()).is_equal(2)   # one MMI per touched chunk
	var counts := []
	var total := 0
	for mmi: MultiMeshInstance3D in scatter.get_children():
		counts.append(mmi.multimesh.instance_count)
		total += mmi.multimesh.instance_count
	assert_int(total).is_equal(3)
	assert_bool(counts.has(2) and counts.has(1)).is_true()
	# instance transforms are chunk-local: the (60,0,0) instance sits at x=12 in
	# the chunk-(1,0) MMI positioned at x=48. MultiMesh instance data does not read
	# back through the headless RenderingServer (CI), so verify the MMI node's own
	# transform + count, and the pure conversion the baker applies to place instances.
	var far: MultiMeshInstance3D = scatter.get_node("scatter_0_1_0")
	assert_that(far.position).is_equal(Vector3(48, 0, 0))
	assert_int(far.multimesh.instance_count).is_equal(1)
	var locals := Baker.chunk_local_multimesh_transforms(
			[Transform3D(Basis.IDENTITY, Vector3(60, 0, 0))], Vector2i(1, 0), 48.0)
	assert_that(locals[0].origin).is_equal(Vector3(12, 0, 0))
	# geometry stored once: no verts merged into chunk meshes
	assert_int(baked.get_node("Chunks").get_child_count()).is_equal(0)
	# collision harvest identical to the prefab path: 2 + 1 shapes in chunk bodies
	var bodies := baked.get_node("Bodies")
	assert_int(bodies.get_node("body_0_0").get_child_count()).is_equal(2)
	assert_int(bodies.get_node("body_1_0").get_child_count()).is_equal(1)
	var stats: Dictionary = result.stats
	assert_int(int(stats.scatter_instances)).is_equal(3)
	assert_int(int(stats.scatter_multimeshes)).is_equal(2)
	assert_int(int(stats.shapes)).is_equal(3)
	baked.free()
	level.root.free()


func test_scatter_below_threshold_merges_like_prefabs() -> void:
	var level: Dictionary = _scatter_level(_scatter_prefab("hull"),
			[Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(4, 0, 0)], true, -1)
	var result: Dictionary = Baker.bake(level.root)
	assert_bool(result.ok).is_true()
	var baked: Node3D = result.root
	assert_object(baked.get_node_or_null("Scatter")).is_null()
	assert_int(baked.get_node("Chunks").get_child_count()).is_equal(1)   # merged verts
	assert_int(baked.get_node("Bodies").get_node("body_0_0").get_child_count()).is_equal(3)
	assert_int(int((result.stats as Dictionary).scatter_instances)).is_equal(3)
	assert_int(int((result.stats as Dictionary).scatter_multimeshes)).is_equal(0)
	baked.free()
	level.root.free()


func test_scatter_collision_off_adds_zero_physics_both_paths() -> void:
	for threshold in [2, -1]:   # MultiMesh path, then the merge path
		var level: Dictionary = _scatter_level(_scatter_prefab("hull"),
				[Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(4, 0, 0)], false, threshold)
		var result: Dictionary = Baker.bake(level.root)
		assert_bool(result.ok).is_true()
		var baked: Node3D = result.root
		assert_object(baked.get_node_or_null("Bodies")).is_null()
		assert_int(int((result.stats as Dictionary).shapes)).is_equal(0)
		baked.free()
		level.root.free()


func test_scatter_weld_prefab_is_a_bake_error() -> void:
	var level: Dictionary = _scatter_level(_scatter_prefab("weld"),
			[Vector3(0, 0, 0)], true, -1)
	var result: Dictionary = Baker.bake(level.root)
	assert_bool(result.ok).is_false()
	assert_bool("\n".join(result.errors as PackedStringArray).contains("weld")).is_true()
	level.root.free()


# ------------------------------------------------------- nested pieces / shape sharing


## Bakeable level skeleton with a KitPiece tree under Authoring (never entered into the
## tree, the baker's own operating mode).
func _piece_level(outer_mode: String, inner_mode: String) -> Node3D:
	var root := Node3D.new()
	root.name = "L"
	var spawn := Marker3D.new()
	spawn.name = "Spawn"
	spawn.set_script(load("res://src/levels/base/vehicle_spawn.gd"))
	root.add_child(spawn)
	var authoring := Node3D.new()
	authoring.name = "Authoring"
	authoring.set_script(preload("res://kit/helpers/authoring_root.gd"))
	root.add_child(authoring)
	var outer := _scatter_prefab(outer_mode).instantiate()
	authoring.add_child(outer)
	var inner := _scatter_prefab(inner_mode).instantiate()
	inner.name = "Inner"
	outer.add_child(inner)
	return root


## A nested KitPiece keeps its OWN collision mode. Inheriting the ancestor's broke the
## drivable invariant both ways: a "hull" railing grouped under a "weld" bridge had its
## triangles welded into the level-wide drivable body (drive up the handrail) while its
## hull shape was dropped; a "weld" ramp under a "box" warehouse never reached the
## drivable body at all, so the car fell through a ramp dev-play rendered solid.
func test_nested_kit_piece_keeps_its_own_collision_mode() -> void:
	# weld outer + hull inner: exactly one box welds (12 tris), the inner's shape is kept
	var outer_weld: Node3D = auto_free(_piece_level("weld", "hull"))
	var a: Dictionary = Baker.bake(outer_weld)
	assert_bool(a.ok).is_true()
	assert_int(int((a.stats as Dictionary).drivable_triangles)).is_equal(12)
	assert_int(int((a.stats as Dictionary).shapes)).is_equal(1)
	(a.root as Node).free()

	# and the reverse: the inner weld ramp reaches the drivable body, the outer box does not
	var outer_box: Node3D = auto_free(_piece_level("box", "weld"))
	var b: Dictionary = Baker.bake(outer_box)
	assert_bool(b.ok).is_true()
	assert_int(int((b.stats as Dictionary).drivable_triangles)).is_equal(12)
	assert_int(int((b.stats as Dictionary).shapes)).is_equal(1)
	(b.root as Node).free()


## Pieces that carry shapes but no mesh are legitimate authoring — the "nothing was
## collected" gate must not reject them for having zero vertices.
func test_collision_only_authoring_is_bakeable() -> void:
	var root := Node3D.new()
	root.name = "L"
	var spawn := Marker3D.new()
	spawn.name = "Spawn"
	spawn.set_script(load("res://src/levels/base/vehicle_spawn.gd"))
	root.add_child(spawn)
	var authoring := Node3D.new()
	authoring.name = "Authoring"
	authoring.set_script(preload("res://kit/helpers/authoring_root.gd"))
	root.add_child(authoring)
	authoring.add_child(_scatter_prefab("box", false).instantiate())
	var result: Dictionary = Baker.bake(root)
	assert_bool(result.ok).is_true()
	assert_int(int((result.stats as Dictionary).shapes)).is_equal(1)
	(result.root as Node).free()
	root.free()


## One duplicate per SOURCE shape, shared by every instance. Duplicating per instance gave
## a 3000-tree forest 3000 identical BoxShape3Ds in the packed scene and 3000 shapes in the
## physics server — the render side already stores scattered geometry once.
func test_baked_bodies_share_one_duplicate_per_source_shape() -> void:
	var level: Dictionary = _scatter_level(_scatter_prefab("hull"),
			[Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(4, 0, 0)], true, -1)
	var result: Dictionary = Baker.bake(level.root)
	assert_bool(result.ok).is_true()
	var body: Node = (result.root as Node).get_node("Bodies/body_0_0")
	assert_int(body.get_child_count()).is_equal(3)
	var first: Shape3D = (body.get_child(0) as CollisionShape3D).shape
	for cs: CollisionShape3D in body.get_children():
		assert_object(cs.shape).is_same(first)
	(result.root as Node).free()
	level.root.free()


func test_scatter_ground_hash_gate() -> void:
	var level: Dictionary = _scatter_level(_scatter_prefab("hull"),
			[Vector3(0, 0, 0)], true, -1)
	var root: Node3D = level.root
	var terrain := StaticBody3D.new()
	terrain.name = "Terrain"
	terrain.set_script(load("res://src/levels/base/heightmap_terrain.gd"))
	var img := Image.create(8, 8, false, Image.FORMAT_L8)
	img.fill(Color(0.5, 0.5, 0.5))
	terrain.set("heightmap", ImageTexture.create_from_image(img))
	root.add_child(terrain)

	# default stored_ground_hash "" no longer matches a level WITH terrain
	var errors: PackedStringArray = Baker.scatter_ground_errors(root)
	assert_int(errors.size()).is_equal(1)
	assert_bool(errors[0].contains("Regenerate")).is_true()
	assert_bool((Baker.bake(root) as Dictionary).ok).is_false()

	# storing the current hash (what Regenerate does) clears the gate
	level.region.set("stored_ground_hash", ScatterRegionScript.ground_hash(root))
	assert_array(Baker.scatter_ground_errors(root)).is_empty()

	# a region with no stored instances never gates (nothing bakes from it)
	var empty_stored: Array[PackedFloat32Array] = [PackedFloat32Array()]
	level.region.set("stored_transforms", empty_stored)
	level.region.set("stored_ground_hash", "whatever")
	assert_array(Baker.scatter_ground_errors(root)).is_empty()
	root.free()

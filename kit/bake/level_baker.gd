class_name LevelBaker
extends RefCounted
## Level bake tool. Walks a level's AuthoringRoot into the shipping form: render meshes
## merged per chunk, one StaticBody3D per chunk plus one level-wide welded Drivable body,
## and a manifest hash so CI fails on stale bakes. Pure helpers are static fns, unit-tested
## in tests/test_bake.gd. Never touches the scene tree, so editor and headless CLI agree.

## Bump on any bake-semantics change; stale-bake checks reject old-version manifests.
const BAKER_VERSION := 12

## The runtime node rail roads bake into; preloaded (not class_name'd) so it loads headless.
const Groups := preload("res://src/levels/base/carlito_groups.gd")
const RailTrackScript := preload("res://src/levels/base/rail_track.gd")

## Preloaded, not class_name'd: the baker runs headless from the CLI.
const Layers := preload("res://src/physics/collision_layers.gd")

## Bake-adjacent code no resource-dependency edge can reach; hashed explicitly. A new
## bake-adjacent file needs an entry; a semantic change bumps BAKER_VERSION instead.
const BAKE_CODE_INPUTS: PackedStringArray = [
	"res://kit/bake/level_baker.gd",
	"res://src/levels/base/carlito_groups.gd",
	"res://kit/helpers/road_builder.gd",
	"res://kit/helpers/scatter_base.gd",
	"res://src/levels/base/rail_track.gd",
	"res://src/physics/collision_layers.gd",
]

## Items with at least this many stored instances bake as one MultiMeshInstance3D per
## chunk x item instead of merging verts into chunk meshes; overridable per item.
const SCATTER_MULTIMESH_THRESHOLD := 64

## Weld snap distance (1 mm): vertices this close become bit-identical, so shared
## edges read as internal to Jolt instead of body seams.
const WELD_EPSILON := 0.001

## Text formats are hashed CRLF-normalized so line-ending drift doesn't flag a stale bake.
const TEXT_EXTS: PackedStringArray = ["tscn", "tres", "json", "gd", "import", "cfg", "md", "txt"]


# ---------------------------------------------------------------- pure helpers

## XZ chunk cell for a piece origin; a piece is never split across chunks.
static func chunk_key(origin: Vector3, chunk_size: float) -> Vector2i:
	return Vector2i(floori(origin.x / chunk_size), floori(origin.z / chunk_size))


## World-space origin of a chunk (its MeshInstance3D position; verts are chunk-local).
static func chunk_origin(key: Vector2i, chunk_size: float) -> Vector3:
	return Vector3(key.x * chunk_size, 0.0, key.y * chunk_size)


## World scatter transforms -> chunk-local; pure so it stays unit-testable headless.
static func chunk_local_multimesh_transforms(world_xforms: Array, key: Vector2i,
		chunk_size: float) -> Array[Transform3D]:
	var to_local := Transform3D(Basis.IDENTITY, -chunk_origin(key, chunk_size))
	var out: Array[Transform3D] = []
	for t in world_xforms:
		out.append(to_local * (t as Transform3D))
	return out


## Welds a triangle soup: vertices within `epsilon` become bit-identical; degenerate
## triangles drop. True epsilon merge, not grid-snap (a grid-snap leaves verts astride a
## cell boundary distinct, welding into a crack) — each vertex probes the surrounding 27
## cells in a fixed order, so output stays deterministic.
static func weld_faces(faces: PackedVector3Array, epsilon := WELD_EPSILON) -> PackedVector3Array:
	var out := PackedVector3Array()
	var cells := {}   # Vector3i cell -> Array[Vector3] canonical verts registered in it
	var eps2 := epsilon * epsilon
	var tri := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	for i in range(0, faces.size() - 2, 3):
		for j in 3:
			var v := faces[i + j]
			var key := Vector3i(floori(v.x / epsilon), floori(v.y / epsilon), floori(v.z / epsilon))
			var canon: Variant = _find_canonical(cells, key, v, eps2)
			if canon == null:
				if not cells.has(key):
					cells[key] = PackedVector3Array()
				var list: PackedVector3Array = cells[key]
				list.push_back(v)
				cells[key] = list
				tri[j] = v
			else:
				tri[j] = canon
		if tri[0] == tri[1] or tri[1] == tri[2] or tri[0] == tri[2]:
			continue
		out.push_back(tri[0])
		out.push_back(tri[1])
		out.push_back(tri[2])
	return out


## First registered vertex within epsilon of `v` in `key`'s cell + 26 neighbours; null if none.
static func _find_canonical(cells: Dictionary, key: Vector3i, v: Vector3,
		eps2: float) -> Variant:
	for dx in [0, -1, 1]:
		for dy in [0, -1, 1]:
			for dz in [0, -1, 1]:
				var probe := Vector3i(key.x + dx, key.y + dy, key.z + dz)
				if not cells.has(probe):
					continue
				for c: Vector3 in (cells[probe] as PackedVector3Array):
					if c.distance_squared_to(v) <= eps2:
						return c
	return null


## Normalizes line endings so the same file hashes identically on Windows and CI.
static func normalize_text(s: String) -> String:
	return s.replace("\r\n", "\n").replace("\r", "\n")


## Text formats hash as normalized text, binaries as raw bytes.
static func hash_file(path: String) -> String:
	if TEXT_EXTS.has(path.get_extension().to_lower()):
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			return "MISSING"
		return normalize_text(f.get_as_text()).sha256_text()
	var h := FileAccess.get_sha256(path)
	return h if h != "" else "MISSING"


## Combined input hash, order-independent over `paths` plus extra tokens; the manifest stamp.
static func hash_inputs(paths: PackedStringArray, extra := PackedStringArray()) -> String:
	var sorted := paths.duplicate()
	sorted.sort()
	var lines := PackedStringArray()
	for p in sorted:
		lines.append(p + ":" + hash_file(p))
	for e in extra:
		lines.append(String(e))
	return ("\n".join(lines)).sha256_text()


## Bake gate: validates spawn coverage. `spawns` items are {types, is_water}; empty types = any.
static func validate_spawns(allowed: PackedStringArray, default_vehicle: String,
		spawns: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	if spawns.is_empty():
		errors.append("level has no VehicleSpawn markers")
		return errors
	# allowed_vehicles lists families; default_vehicle is a variant, which can differ (e.g. "train").
	var default_family := VehicleCatalog.family_of(default_vehicle)
	if default_family == "":
		default_family = default_vehicle
	if not allowed.is_empty() and not allowed.has(default_family):
		errors.append("default vehicle '%s' (family '%s') is not in allowed_vehicles" % [
				default_vehicle, default_family])
	var types := allowed.duplicate()
	if default_family != "" and not types.has(default_family):
		types.append(default_family)
	for t in types:
		# Train is rail-guided (placed on a closed rail loop, not a VehicleSpawn marker).
		if t == "train":
			continue
		var wants_water := t == "boat"
		var found := false
		for s in spawns:
			var st: PackedStringArray = s.get("types", PackedStringArray())
			if (st.is_empty() or st.has(t)) and bool(s.get("is_water", false)) == wants_water:
				found = true
				break
		if not found:
			var kind := "water" if wants_water else "land"
			errors.append("no %s spawn accepts vehicle type '%s'" % [kind, t])
	return errors


## Splits one indexed triangle surface into per-chunk sub-surfaces by world centroid.
## Render-only — collision never splits (welds into the level-wide Drivable body).
static func split_arrays_by_chunk(arrays: Array, world_xform: Transform3D,
		chunk_size: float) -> Dictionary:
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Regular Arrays (by-reference): Packed*Arrays in a Dictionary are value types.
	var tri_lists := {}   # Vector2i -> Array of source vertex indices (3 per triangle)
	for i in range(0, idx.size() - 2, 3):
		var centroid := (pos[idx[i]] + pos[idx[i + 1]] + pos[idx[i + 2]]) / 3.0
		var key := chunk_key(world_xform * centroid, chunk_size)
		if not tri_lists.has(key):
			tri_lists[key] = []
		var list: Array = tri_lists[key]
		list.append(idx[i])
		list.append(idx[i + 1])
		list.append(idx[i + 2])

	var src_n: Variant = arrays[Mesh.ARRAY_NORMAL]
	var has_n: bool = src_n is PackedVector3Array \
			and (src_n as PackedVector3Array).size() == pos.size()
	var src_uv: Variant = arrays[Mesh.ARRAY_TEX_UV]
	var has_uv: bool = src_uv is PackedVector2Array \
			and (src_uv as PackedVector2Array).size() == pos.size()
	var src_col: Variant = arrays[Mesh.ARRAY_COLOR]
	var has_col: bool = src_col is PackedColorArray \
			and (src_col as PackedColorArray).size() == pos.size()

	var out := {}
	for key: Vector2i in tri_lists:
		var idx_remap := {}   # source index -> chunk-local index
		var cpos := PackedVector3Array()
		var cnrm := PackedVector3Array()
		var cuv := PackedVector2Array()
		var ccol := PackedColorArray()
		var cidx := PackedInt32Array()
		for si: int in tri_lists[key]:
			if not idx_remap.has(si):
				idx_remap[si] = cpos.size()
				cpos.append(pos[si])
				if has_n:
					cnrm.append((src_n as PackedVector3Array)[si])
				if has_uv:
					cuv.append((src_uv as PackedVector2Array)[si])
				if has_col:
					ccol.append((src_col as PackedColorArray)[si])
			cidx.append(idx_remap[si])
		var carrays := []
		carrays.resize(Mesh.ARRAY_MAX)
		carrays[Mesh.ARRAY_VERTEX] = cpos
		if has_n:
			carrays[Mesh.ARRAY_NORMAL] = cnrm
		if has_uv:
			carrays[Mesh.ARRAY_TEX_UV] = cuv
		if has_col:
			carrays[Mesh.ARRAY_COLOR] = ccol
		carrays[Mesh.ARRAY_INDEX] = cidx
		out[key] = carrays
	return out


## Semantic material key so identical materials merge into one surface instead of one
## per source file. Every field that changes rendering belongs here — albedo alone
## can't distinguish e.g. an emissive window material from a matte wall.
static func material_key(mat: Material) -> String:
	if mat == null:
		return "null"
	var bm := mat as BaseMaterial3D
	if bm == null:
		return "id:%d" % mat.get_instance_id()
	return "|".join(PackedStringArray([
		_texture_key(bm.albedo_texture),
		_texture_key(bm.normal_texture),
		_texture_key(bm.emission_texture),
		_texture_key(bm.orm_texture),
		bm.albedo_color.to_html(),
		"t%d" % bm.transparency,
		"c%d" % bm.cull_mode,
		"s%d" % bm.shading_mode,
		"d%d" % bm.depth_draw_mode,
		"b%d" % bm.billboard_mode,
		"v%s" % bm.vertex_color_use_as_albedo,
		"r%.4f" % bm.roughness,
		"m%.4f" % bm.metallic,
		"e%s:%s:%.4f" % [bm.emission_enabled, bm.emission.to_html(),
				bm.emission_energy_multiplier],
		"n%.4f" % bm.normal_scale,
		"u%s:%s" % [bm.uv1_scale, bm.uv1_offset],
		"p%d" % bm.render_priority,
	]))


## Stable identity for a material's texture slot: resource path if it has one, else instance.
static func _texture_key(tex: Texture2D) -> String:
	if tex == null:
		return "-"
	return tex.resource_path if not tex.resource_path.is_empty() \
			else "texid:%d" % tex.get_instance_id()


# ------------------------------------------------------------ dependency walk

## Files whose change flags a bake stale: level scene, transitive deps, BAKE_CODE_INPUTS, .import sidecars.
static func gather_bake_inputs(level_path: String) -> PackedStringArray:
	var seen := {level_path: true}
	var kept := {level_path: true}
	for p in BAKE_CODE_INPUTS:
		kept[p] = true
	var queue: Array[String] = [level_path]
	while not queue.is_empty():
		var p: String = queue.pop_back()
		for dep in ResourceLoader.get_dependencies(p):
			var dp := _dep_path(String(dep))
			if dp.is_empty() or seen.has(dp):
				continue
			seen[dp] = true
			queue.append(dp)
			if is_bake_input(dp):
				kept[dp] = true
	var out := PackedStringArray()
	for p: String in kept:
		out.append(p)
		if FileAccess.file_exists(p + ".import"):
			out.append(p + ".import")
	out.sort()
	return out


## Whether a dependency can change baker output: every resource except plugin code and
## scripts outside the kit. Runtime scripts can't change output, so hashing them would
## re-stale levels on unrelated edits.
static func is_bake_input(path: String) -> bool:
	if path.begins_with("res://kit/"):
		return true
	if path.begins_with("res://addons/"):
		return false
	var ext := path.get_extension().to_lower()
	return ext != "gd" and ext != "cs"


## Pulls the res:// path out of a get_dependencies entry, resolving a bare uid:// if needed.
static func _dep_path(dep: String) -> String:
	var best := ""
	for part in dep.split("::"):
		if part.begins_with("res://"):
			best = part
	if best.is_empty() and dep.begins_with("uid://"):
		var id := ResourceUID.text_to_id(dep.get_slice("::", 0))
		if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
			best = ResourceUID.get_id_path(id)
	return best


# ------------------------------------------------------------------- manifest

static func baked_scene_path(level_path: String) -> String:
	return level_path.get_basename() + ".baked.scn"


static func manifest_path(level_path: String) -> String:
	return level_path.get_basename() + ".bake.json"


## Timestamp-free so unchanged inputs re-bake byte-identical; output_hash catches a truncated/hand-edited bake.
static func write_manifest(level_path: String, input_hash: String, chunk_size: float,
		stats: Dictionary, output_hash := "") -> Error:
	var doc := {
		"baker_version": BAKER_VERSION,
		"level": level_path,
		"chunk_size": chunk_size,
		"input_hash": input_hash,
		"output_hash": output_hash,
		"stats": stats,
	}
	var f := FileAccess.open(manifest_path(level_path), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(doc, "\t") + "\n")
	return OK


static func read_manifest(level_path: String) -> Dictionary:
	var f := FileAccess.open(manifest_path(level_path), FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


## Extra hash tokens stamped alongside the file hashes; chunk_size so tuning it re-stales.
static func hash_extra(chunk_size: float) -> PackedStringArray:
	return PackedStringArray(["baker_version:%d" % BAKER_VERSION, "chunk_size:%s" % var_to_str(chunk_size)])


# ------------------------------------------------------------ scene discovery

## First AuthoringRoot under `root`; a walk, not a group lookup — level may be outside any tree.
static func find_authoring(root: Node) -> Node:
	return Groups.find_authoring(root)


## Spawn descriptors for validate_spawns, from VehicleSpawn markers (duck-typed on accepts()).
static func collect_spawn_descriptors(root: Node) -> Array:
	var out := []
	for node in root.find_children("*", "Marker3D", true, false):
		if node.has_method("accepts"):
			out.append({
				"types": node.get("vehicle_types"),
				"is_water": bool(node.get("is_water")),
			})
	return out


## Stale-scatter guard: a region whose stored_ground_hash no longer matches the terrain
## was snapped before a later sculpt. Terrain PNGs sit outside the input-hash net, so
## without this a sculpt ships floating/buried props CI-green; recovery is Regenerate.
static func scatter_ground_errors(level_root: Node) -> PackedStringArray:
	var errors := PackedStringArray()
	var regions: Array[Node] = []
	_find_scatter_nodes(level_root, regions)
	if regions.is_empty():
		return errors
	var current := String(regions[0].call("ground_hash", level_root))
	for region in regions:
		var total := 0
		for flat in (region.get("stored_transforms") as Array):
			total += int(region.call("stored_count", flat))
		if total == 0:
			continue
		if String(region.get("stored_ground_hash")) != current:
			errors.append("scatter region '%s': terrain changed since it was scattered — Regenerate or Re-snap to ground in the editor, then re-bake" % region.name)
	return errors


static func _find_scatter_nodes(node: Node, out: Array[Node]) -> void:
	if node.is_in_group(Groups.SCATTER):
		out.append(node)
	for child in node.get_children():
		_find_scatter_nodes(child, out)


# ----------------------------------------------------------------- bake proper

## Bakes the level rooted at `level_root` (need not be in a tree). Returns { ok, errors,
## root: Node3D or null, stats }; on ok, root is the assembled scene (caller packs+frees it).
static func bake(level_root: Node) -> Dictionary:
	var errors := PackedStringArray()
	var authoring := find_authoring(level_root)
	if authoring == null:
		return _fail(["level has no AuthoringRoot node — nothing to bake"])
	var chunk_size := float(authoring.get("chunk_size"))
	if chunk_size <= 0.0:
		return _fail(["AuthoringRoot.chunk_size must be > 0 (got %s)" % chunk_size])

	var info: Resource = level_root.get("info")
	var allowed: PackedStringArray = info.get("allowed_vehicles") if info != null else PackedStringArray()
	var default_vehicle := String(info.get("default_vehicle")) if info != null else "car"
	errors.append_array(validate_spawns(allowed, default_vehicle, collect_spawn_descriptors(level_root)))
	errors.append_array(scatter_ground_errors(level_root))

	var ctx := BakeContext.new()
	ctx.chunk_size = chunk_size
	_collect(authoring, _authoring_xform(level_root, authoring), ctx, errors)
	# Collision-only authoring is legitimate, so the gate is "nothing collected", not "no vertices".
	if ctx.total_vertices == 0 and ctx.body_shapes.is_empty() and ctx.weld_pool.is_empty():
		errors.append("AuthoringRoot has no bakeable content (GridMaps / KitPiece prefabs)")
	if not errors.is_empty():
		return _fail(errors)
	return {"ok": true, "errors": errors, "root": _assemble(ctx), "stats": ctx.stats()}


## Authoring transform relative to the level root, accumulated manually (may be untreed).
static func _authoring_xform(level_root: Node, authoring: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var node := authoring
	while node != null and node != level_root:
		if node is Node3D:
			xform = (node as Node3D).transform * xform
		node = node.get_parent()
	return xform


static func _fail(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "errors": errors, "root": null, "stats": {}}


## Recursive gather. GridMap cells are all drivable; KitPiece prefabs contribute render meshes plus collision per mode.
static func _collect(node: Node, xform: Transform3D, ctx: BakeContext,
		errors: PackedStringArray) -> void:
	for child in node.get_children():
		var cxform := xform
		if child is Node3D:
			cxform = xform * (child as Node3D).transform
		if child is GridMap:
			_collect_gridmap(child as GridMap, cxform, ctx, errors)
		elif child.is_in_group(Groups.KIT_PIECE):
			_collect_piece(child, cxform, ctx, errors)
		elif child.is_in_group(Groups.SCATTER):
			_collect_scatter(child, cxform, ctx, errors)
		elif child.is_in_group(Groups.ROAD):
			_collect_road(child, cxform, ctx, errors)
		else:
			_collect(child, cxform, ctx, errors)


static func _collect_gridmap(gm: GridMap, xform: Transform3D, ctx: BakeContext,
		errors: PackedStringArray) -> void:
	var ml := gm.mesh_library
	if ml == null:
		errors.append("GridMap '%s' has no MeshLibrary" % gm.name)
		return
	var cells := gm.get_used_cells()
	cells.sort()  # deterministic output
	for cell: Vector3i in cells:
		var item := gm.get_cell_item(cell)
		var mesh := ml.get_item_mesh(item)
		if mesh == null:
			continue
		var basis := gm.get_basis_with_orthogonal_index(gm.get_cell_item_orientation(cell))
		var cell_xform := xform * Transform3D(basis, gm.map_to_local(cell))
		var mesh_xform := cell_xform * ml.get_item_mesh_transform(item)
		# Key by where the geometry sits, not the anchor cell — a corner-anchored piece would else stretch the wrong chunk's AABB.
		var key := chunk_key(mesh_xform * mesh.get_aabb().get_center(), ctx.chunk_size)
		ctx.add_render_mesh(key, mesh, mesh_xform)
		ctx.add_weld_mesh(mesh, mesh_xform)


static func _collect_piece(piece: Node, xform: Transform3D, ctx: BakeContext,
		errors: PackedStringArray) -> void:
	var mode := String(piece.get("collision_mode"))
	var key := chunk_key(xform.origin, ctx.chunk_size)
	_collect_piece_content(piece, xform, key, mode, ctx, errors)


## Walks one piece's subtree under `mode`. A nested KitPiece re-enters _collect_piece to
## keep its own collision mode — inheriting the ancestor's broke the drivable invariant.
## `nested` is false only for scatter, whose template is pre-validated as a whole.
static func _collect_piece_content(node: Node, xform: Transform3D, key: Vector2i,
		mode: String, ctx: BakeContext, errors: PackedStringArray,
		nested := true) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			ctx.add_render_mesh(key, mi.mesh, xform)
			if mode == "weld":
				ctx.add_weld_mesh(mi.mesh, xform)
	elif node is CollisionShape3D and mode in ["box", "footprint", "hull", "multiconvex"]:
		var cs := node as CollisionShape3D
		if cs.shape != null:
			ctx.add_body_shape(key, cs.shape, xform)
	for child in node.get_children():
		var cxform := xform
		if child is Node3D:
			cxform = xform * (child as Node3D).transform
		if nested and child.is_in_group(Groups.KIT_PIECE):
			_collect_piece(child, cxform, ctx, errors)
		else:
			_collect_piece_content(child, cxform, key, mode, ctx, errors, nested)


## Scatter: consumes the region's stored transforms only, so editor and bake can't
## diverge. At/above the MultiMesh threshold the render side chunks into MultiMeshes
## over one merged item mesh; below it, instances route through the prefab merge path.
static func _collect_scatter(region: Node, xform: Transform3D, ctx: BakeContext,
		errors: PackedStringArray) -> void:
	var items: Array = region.get("items")
	var stored: Array = region.get("stored_transforms")
	for i in items.size():
		var item: Resource = items[i]
		if item == null or item.get("prefab") == null or i >= stored.size():
			continue
		var flat: PackedFloat32Array = stored[i]
		var count := int(region.call("stored_count", flat))
		if count == 0:
			continue
		var template: Node = (item.get("prefab") as PackedScene).instantiate()
		var mode := "none"
		if template.is_in_group(Groups.KIT_PIECE):
			mode = String(template.get("collision_mode"))
		if mode == "weld":
			errors.append("scatter region '%s' item %d: weld-mode prefabs cannot be scattered (drivable structures are placed, never scattered)" % [region.name, i])
			template.free()
			continue
		var use_collision: bool = bool(item.get("collision")) and mode != "none"
		var threshold := int(item.get("bake_threshold_override"))
		if threshold < 0:
			threshold = SCATTER_MULTIMESH_THRESHOLD

		var xforms: Array[Transform3D] = []
		for j in count:
			xforms.append(xform * (region.call("stored_transform", flat, j) as Transform3D))
		ctx.scatter_instances += count

		if count >= threshold:
			var mesh: ArrayMesh = region.call("build_item_mesh", template)
			# Swaps prefab materials for the bake's deduplicated copies, same as chunk merges.
			for si in mesh.get_surface_count():
				var mat := mesh.surface_get_material(si)
				var mk := material_key(mat)
				if not ctx.materials.has(mk):
					ctx.materials[mk] = mat.duplicate() if mat != null else null
				mesh.surface_set_material(si, ctx.materials[mk])
				ctx.total_vertices += (mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
						as PackedVector3Array).size()
			var mesh_index := ctx.add_scatter_mesh(mesh, bool(item.get("cast_shadow")))
			var entries: Array = region.call("shape_entries", template) if use_collision else []
			for t in xforms:
				var key := chunk_key(t.origin, ctx.chunk_size)
				ctx.add_multimesh(key, mesh_index, t)
				for entry: Array in entries:
					ctx.add_body_shape(key, entry[0], t * (entry[1] as Transform3D))
		else:
			for t in xforms:
				_collect_piece_content(template, t, chunk_key(t.origin, ctx.chunk_size),
						mode if use_collision else "none", ctx, errors, false)
		template.free()


## Spline road: duck-calls RoadPath's ribbon_surfaces() (works untreed). Render surfaces
## are chunk-bucketed for frustum culling; collision is never split — joins the
## level-wide Drivable body through the same weld as weld prefabs.
static func _collect_road(road: Node, xform: Transform3D, ctx: BakeContext,
		errors: PackedStringArray) -> void:
	if road.get("profile") == null:
		errors.append("RoadPath '%s' has no profile — assign one from kit/roads/" % road.name)
		return
	var entries: Array = road.call("ribbon_surfaces")
	if entries.is_empty():
		errors.append("RoadPath '%s' has no usable curve (needs at least 2 points)" % road.name)
		return
	var faces := PackedVector3Array()
	for e: Dictionary in entries:
		var buckets := split_arrays_by_chunk(e.arrays, xform, ctx.chunk_size)
		for key: Vector2i in buckets:
			ctx.add_render_arrays(key, e.material, buckets[key], xform)
		var pos: PackedVector3Array = e.arrays[Mesh.ARRAY_VERTEX]
		for i: int in (e.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
			faces.append(pos[i])
	ctx.add_weld_faces(faces, xform)
	ctx.roads += 1
	# The train rides the curve, which dies with AuthoringRoot unless copied into the baked scene.
	if road.has_method("get_rail_curve"):
		var rail_curve: Curve3D = road.call("get_rail_curve")
		if rail_curve != null:
			ctx.rail_tracks.append({
				"curve": rail_curve.duplicate(true),
				"xform": xform * (road.call("rail_local_xform") as Transform3D),
				"gauge": float(road.call("rail_gauge")),
				"closed": bool(road.call("is_rail_closed")),
			})


## Assembles Chunks/ (merged render meshes), Bodies/ (per-chunk StaticBody3D), Drivable
## (welded body). Everything is duplicated so the bake has zero kit dependencies.
static func _assemble(ctx: BakeContext) -> Node3D:
	var root := Node3D.new()
	root.name = "Baked"

	var chunks := Node3D.new()
	chunks.name = "Chunks"
	root.add_child(chunks)
	var chunk_keys := ctx.render.keys()
	chunk_keys.sort()
	for key: Vector2i in chunk_keys:
		var mesh := ArrayMesh.new()
		var groups: Dictionary = ctx.render[key]
		var mat_keys := groups.keys()
		mat_keys.sort()
		for mk: String in mat_keys:
			var acc: SurfaceAccumulator = groups[mk]
			acc.commit(mesh, ctx.materials[mk])
		var mi := MeshInstance3D.new()
		mi.name = "chunk_%d_%d" % [key.x, key.y]
		mi.mesh = mesh
		mi.position = chunk_origin(key, ctx.chunk_size)
		chunks.add_child(mi)

	if not ctx.body_shapes.is_empty():
		var bodies := Node3D.new()
		bodies.name = "Bodies"
		root.add_child(bodies)
		var body_keys := ctx.body_shapes.keys()
		body_keys.sort()
		# One duplicate per source shape, shared by every instance — per-instance gave a 3000-tree forest 3000 identical BoxShape3Ds.
		var shared := {}
		for key: Vector2i in body_keys:
			var body := StaticBody3D.new()
			body.name = "body_%d_%d" % [key.x, key.y]
			# Scenery; static, so its mask is only the two families that move.
			body.collision_layer = Layers.PROPS
			body.collision_mask = Layers.DYNAMIC
			bodies.add_child(body)
			for entry: Array in ctx.body_shapes[key]:
				var src_id := (entry[0] as Shape3D).get_instance_id()
				if not shared.has(src_id):
					shared[src_id] = (entry[0] as Shape3D).duplicate()
				var cs := CollisionShape3D.new()
				cs.shape = shared[src_id]
				cs.transform = entry[1]
				body.add_child(cs)

	if not ctx.multimesh.is_empty():
		var scatter := Node3D.new()
		scatter.name = "Scatter"
		root.add_child(scatter)
		var mm_keys := ctx.multimesh.keys()
		mm_keys.sort()
		for key: Vector2i in mm_keys:
			var groups: Dictionary = ctx.multimesh[key]
			var mesh_ids := groups.keys()
			mesh_ids.sort()
			for mid: int in mesh_ids:
				var list: Array = groups[mid]
				var locals := chunk_local_multimesh_transforms(list, key, ctx.chunk_size)
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = ctx.scatter_meshes[mid]
				mm.instance_count = locals.size()
				for j in locals.size():
					mm.set_instance_transform(j, locals[j])
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "scatter_%d_%d_%d" % [mid, key.x, key.y]
				mmi.multimesh = mm
				if not ctx.scatter_shadows[mid]:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mmi.position = chunk_origin(key, ctx.chunk_size)
				scatter.add_child(mmi)

	if not ctx.weld_pool.is_empty():
		var drivable := StaticBody3D.new()
		drivable.name = "Drivable"
		# The one level-wide welded body (standing rule 1).
		drivable.collision_layer = Layers.DRIVABLE
		drivable.collision_mask = Layers.DYNAMIC
		root.add_child(drivable)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(weld_faces(ctx.weld_pool))
		var cs := CollisionShape3D.new()
		cs.name = "WeldedCollision"
		cs.shape = shape
		drivable.add_child(cs)

	# Rails carry no geometry (the ribbon is already in Chunks + Drivable), just the curve.
	if not ctx.rail_tracks.is_empty():
		var rails := Node3D.new()
		rails.name = "Rails"
		root.add_child(rails)
		for i in ctx.rail_tracks.size():
			var entry: Dictionary = ctx.rail_tracks[i]
			var track: Node3D = RailTrackScript.new()
			track.name = "rail_%d" % i
			track.transform = entry["xform"]
			track.set("curve", entry["curve"])
			track.set("gauge", entry["gauge"])
			track.set("closed", entry["closed"])
			rails.add_child(track)

	_own_recursive(root, root)
	return root


static func _own_recursive(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own_recursive(child, owner_node)


# ------------------------------------------------------------------ save + check

## Full bake for a level scene file: load, bake, save, stamp manifest, verify no leaked
## kit deps. Returns {ok, errors, stats}. Entry point shared by editor button and CLI.
static func bake_level_file(level_path: String) -> Dictionary:
	var packed := load(level_path) as PackedScene
	if packed == null:
		return _fail(["cannot load level scene '%s'" % level_path])
	var level_root := packed.instantiate()
	var result := bake(level_root)
	var chunk_size := 0.0
	var authoring := find_authoring(level_root)
	if authoring != null:
		chunk_size = float(authoring.get("chunk_size"))
	level_root.free()
	if not result.ok:
		return result

	var baked_root: Node3D = result.root
	var out := PackedScene.new()
	var errors := PackedStringArray()
	if out.pack(baked_root) != OK:
		errors.append("failed to pack baked scene")
	else:
		var scn := baked_scene_path(level_path)
		var err := ResourceSaver.save(out, scn)
		if err != OK:
			errors.append("failed to save '%s' (error %d)" % [scn, err])
		else:
			for dep in ResourceLoader.get_dependencies(scn):
				var dp := _dep_path(String(dep))
				if dp.ends_with(".glb") or dp.contains("/kit/prefabs/") or dp.contains("/kit/palettes/"):
					errors.append("baked scene leaked authoring dependency: %s" % dp)
	baked_root.free()
	if errors.is_empty():
		var input_hash := hash_inputs(gather_bake_inputs(level_path), hash_extra(chunk_size))
		var output_hash := FileAccess.get_sha256(baked_scene_path(level_path))
		if write_manifest(level_path, input_hash, chunk_size, result.stats,
				output_hash) != OK:
			errors.append("failed to write manifest '%s'" % manifest_path(level_path))
	if not errors.is_empty():
		return _fail(errors)
	return {"ok": true, "errors": errors, "stats": result.stats}


## Freshness verdict, pure: "fresh" | "unbuilt" | "stale" | "missing". `disk_output_hash`
## is only compared when `baked_exists` — .baked.scn is untracked build output, so a
## fresh clone has the manifest without the artifact ("unbuilt", not stale).
static func freshness(manifest: Dictionary, current_input_hash: String, baked_exists: bool,
		disk_output_hash: String, scatter_errors: PackedStringArray) -> Dictionary:
	if manifest.is_empty():
		return {"status": "missing", "detail": "no bake manifest — run the bake tool"}
	if int(manifest.get("baker_version", -1)) != BAKER_VERSION:
		return {"status": "stale", "detail": "baked with baker v%s, current v%d" %
				[manifest.get("baker_version"), BAKER_VERSION]}
	if String(manifest.get("input_hash", "")) != current_input_hash:
		return {"status": "stale", "detail": "authoring inputs changed since last bake"}
	if baked_exists and String(manifest.get("output_hash", "")) != disk_output_hash:
		return {"status": "stale", "detail": "baked scene does not match its manifest — re-bake"}
	# Terrain PNGs sit outside the input hash's net, so stale scatter needs its own check.
	if not scatter_errors.is_empty():
		return {"status": "stale", "detail": scatter_errors[0]}
	if not baked_exists:
		return {"status": "unbuilt", "detail": "manifest fresh, no local .baked.scn"}
	return {"status": "fresh", "detail": ""}


## Freshness check for CI, per level: reads the manifest, authoring inputs and disk bake
## output, then defers to freshness() above. "no_authoring" for levels bake doesn't apply to.
static func check_level_file(level_path: String) -> Dictionary:
	var packed := load(level_path) as PackedScene
	if packed == null:
		return {"status": "error", "detail": "cannot load level scene '%s'" % level_path}
	var level_root := packed.instantiate()
	var authoring := find_authoring(level_root)
	# Read everything before freeing the tree: a freed node compares equal to null.
	# An empty AuthoringRoot is a freshly scaffolded level; bake output isn't required yet.
	var has_authoring := authoring != null and authoring.get_child_count() > 0
	var chunk_size := float(authoring.get("chunk_size")) if has_authoring else 0.0
	var scatter_errors := scatter_ground_errors(level_root)
	level_root.free()
	if not has_authoring:
		return {"status": "no_authoring", "detail": ""}

	var scn := baked_scene_path(level_path)
	var baked_exists := FileAccess.file_exists(scn)
	return freshness(read_manifest(level_path),
			hash_inputs(gather_bake_inputs(level_path), hash_extra(chunk_size)),
			baked_exists, FileAccess.get_sha256(scn) if baked_exists else "",
			scatter_errors)


# --------------------------------------------------------------- inner classes

## Accumulates everything one bake collects before assembly.
class BakeContext:
	var chunk_size := 48.0
	var render := {}          ## Vector2i chunk key -> { material_key: SurfaceAccumulator }
	var materials := {}       ## material_key -> duplicated Material
	var body_shapes := {}     ## Vector2i chunk key -> Array of [Shape3D, Transform3D]
	var weld_pool := PackedVector3Array()   ## world-space triangle soup for the drivable body
	var total_vertices := 0
	var scatter_meshes: Array[ArrayMesh] = []   ## merged item meshes, stored once
	var scatter_shadows: Array[bool] = []       ## parallel to scatter_meshes
	var multimesh := {}       ## Vector2i chunk key -> { mesh index -> Array of world Transform3D }
	var scatter_instances := 0
	var roads := 0
	var rail_tracks := []     ## {curve, xform, gauge, closed} per entry -> one RailTrack each

	func add_render_mesh(key: Vector2i, mesh: Mesh, world_xform: Transform3D) -> void:
		for si in mesh.get_surface_count():
			add_render_arrays(key, mesh.surface_get_material(si),
					mesh.surface_get_arrays(si), world_xform)

	## One raw surface into a chunk's per-material accumulator; road ribbons feed this directly.
	func add_render_arrays(key: Vector2i, mat: Material, arrays: Array,
			world_xform: Transform3D) -> void:
		var local := Transform3D(Basis.IDENTITY, -LevelBaker.chunk_origin(key, chunk_size)) * world_xform
		if not render.has(key):
			render[key] = {}
		var groups: Dictionary = render[key]
		var mk := LevelBaker.material_key(mat)
		if not materials.has(mk):
			materials[mk] = mat.duplicate() if mat != null else null
		if not groups.has(mk):
			groups[mk] = SurfaceAccumulator.new()
		(groups[mk] as SurfaceAccumulator).append(arrays, local)
		total_vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()

	func add_weld_mesh(mesh: Mesh, world_xform: Transform3D) -> void:
		add_weld_faces(mesh.get_faces(), world_xform)

	## A pre-built triangle soup into the level-wide weld pool. A mirroring transform
	## reverses each triangle so the welded body keeps its outward winding.
	func add_weld_faces(faces: PackedVector3Array, world_xform: Transform3D) -> void:
		if world_xform.basis.determinant() < 0.0:
			for i in range(0, faces.size() - 2, 3):
				weld_pool.push_back(world_xform * faces[i])
				weld_pool.push_back(world_xform * faces[i + 2])
				weld_pool.push_back(world_xform * faces[i + 1])
			return
		for v in faces:
			weld_pool.push_back(world_xform * v)

	func add_body_shape(key: Vector2i, shape: Shape3D, world_xform: Transform3D) -> void:
		if not body_shapes.has(key):
			body_shapes[key] = []
		(body_shapes[key] as Array).append([shape, world_xform])

	func add_scatter_mesh(mesh: ArrayMesh, shadow: bool) -> int:
		scatter_meshes.append(mesh)
		scatter_shadows.append(shadow)
		return scatter_meshes.size() - 1

	func add_multimesh(key: Vector2i, mesh_index: int, world_xform: Transform3D) -> void:
		if not multimesh.has(key):
			multimesh[key] = {}
		var groups: Dictionary = multimesh[key]
		if not groups.has(mesh_index):
			groups[mesh_index] = []
		(groups[mesh_index] as Array).append(world_xform)

	func stats() -> Dictionary:
		var surfaces := 0
		for key: Vector2i in render:
			surfaces += (render[key] as Dictionary).size()
		var shape_count := 0
		for key: Vector2i in body_shapes:
			shape_count += (body_shapes[key] as Array).size()
		var multimesh_count := 0
		for key: Vector2i in multimesh:
			multimesh_count += (multimesh[key] as Dictionary).size()
		return {
			"chunks": render.size(),
			"surfaces": surfaces,
			"vertices": total_vertices,
			"bodies": body_shapes.size(),
			"shapes": shape_count,
			"drivable_triangles": weld_pool.size() / 3.0 as int,
			"scatter_instances": scatter_instances,
			"scatter_multimeshes": multimesh_count,
			"roads": roads,
			"rail_tracks": rail_tracks.size(),
		}


## Merges mesh surfaces sharing a material into one surface, applying transforms at
## array level: positions by the full transform, normals by the inverse-transpose basis
## re-normalized, triangles reversed when the transform mirrors.
##
## ARRAY_TANGENT is dropped: the kit is flat-colour with no normal maps. A future normal
## map needs tangents given the same per-vertex treatment as normals here.
class SurfaceAccumulator:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var has_uv := false
	var has_color := false

	func append(arrays: Array, xform: Transform3D) -> void:
		var src_pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base := positions.size()
		for v in src_pos:
			positions.push_back(xform * v)

		var nbasis := xform.basis.inverse().transposed()
		var src_n: Variant = arrays[Mesh.ARRAY_NORMAL]
		if src_n is PackedVector3Array and (src_n as PackedVector3Array).size() == src_pos.size():
			for n: Vector3 in src_n:
				normals.push_back((nbasis * n).normalized())
		else:
			for i in src_pos.size():
				normals.push_back(Vector3.UP)

		var src_uv: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var uv_ok: bool = src_uv is PackedVector2Array \
				and (src_uv as PackedVector2Array).size() == src_pos.size()
		if uv_ok and not has_uv:
			has_uv = true
			uvs.resize(base)  # zero-fill earlier vertices
		if has_uv:
			if uv_ok:
				uvs.append_array(src_uv)
			else:
				uvs.resize(uvs.size() + src_pos.size())

		var src_col: Variant = arrays[Mesh.ARRAY_COLOR]
		var col_ok: bool = src_col is PackedColorArray \
				and (src_col as PackedColorArray).size() == src_pos.size()
		if col_ok and not has_color:
			has_color = true
			for i in base:
				colors.push_back(Color.WHITE)
		if has_color:
			if col_ok:
				colors.append_array(src_col)
			else:
				for i in src_pos.size():
					colors.push_back(Color.WHITE)

		# A mirroring transform (negative determinant) flips triangle handedness; copying
		# the index order verbatim left rendering inside-out under cull_back and let the
		# welded body's triangles enter back-to-front (the car fell through the deck).
		var flip := xform.basis.determinant() < 0.0
		var src_idx: Variant = arrays[Mesh.ARRAY_INDEX]
		var src: PackedInt32Array
		if src_idx is PackedInt32Array and (src_idx as PackedInt32Array).size() > 0:
			src = src_idx
		else:
			src = PackedInt32Array()
			src.resize(src_pos.size())
			for i in src_pos.size():
				src[i] = i
		if flip:
			for i in range(0, src.size() - 2, 3):
				indices.push_back(base + src[i])
				indices.push_back(base + src[i + 2])
				indices.push_back(base + src[i + 1])
		else:
			for ix: int in src:
				indices.push_back(base + ix)

	func commit(mesh: ArrayMesh, material: Material) -> int:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		if has_uv:
			arrays[Mesh.ARRAY_TEX_UV] = uvs
		if has_color:
			arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		# COMPRESS_ATTRIBUTES: normals octahedral-packed, UVs half-float, positions
		# quantized to 16 bits per chunk AABB (~1 mm step per 64 m chunk). Render only —
		# collision shapes are Shape3D, never quantized.
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
				Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		var si := mesh.get_surface_count() - 1
		if material != null:
			mesh.surface_set_material(si, material)
		return si

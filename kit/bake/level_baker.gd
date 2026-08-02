class_name LevelBaker
extends RefCounted
## The level bake tool. Reads a level's AuthoringRoot subtree
## (GridMap road palettes + KitPiece prefabs + ScatterRegion stored transforms), and
## produces the shipping form:
##  - render: static meshes merged per chunk (tunable chunk_size), one MeshInstance3D
##    per chunk with one surface per distinct material (batching), verts chunk-local;
##  - collision: one StaticBody3D per chunk holding the prefab-authored box/hull
##    shapes, plus ONE level-wide "Drivable" body whose ConcavePolygonShape3D is the
##    vertex-welded union of every drivable surface (road tiles, ramps, bridges,
##    piers) — a drivable structure is never split across bodies, so there are no
##    body-seam ghost collisions;
##  - a manifest JSON stamped with a hash of the authoring inputs so CI can fail on
##    stale bakes.
##
## Everything that can be pure is a static fn (weld, chunking, hashing, spawn
## validation) — unit-tested in tests/test_bake.gd, same discipline as Drivetrain.
## The baker never touches the scene tree: transforms are accumulated manually, so
## it runs identically from the editor Bake button and headless CLI scripts.

## Bump when bake semantics change: stale-bake checks treat old-version manifests
## as stale, forcing a re-bake after tool upgrades.
## v4: road extrusion anchors a ring at every interior curve control point (corner miters).
## v5: road extrusion fold-clamps the inside edge below the local turn radius and gives
## closed loops one shared bisector frame at the seam.
## v6: open-end rings use the exact endpoint handle tangent (finite difference yawed
## port-snapped ends against the tile face).
## v7: correctness pass — true epsilon welding (was grid snapping), nested KitPieces keep
## their own collision mode, mirrored transforms keep their winding, finer material keys,
## chunk keys from mesh AABB centres, bridge-base end caps, bounded end tangents.
## v10: rail roads additionally emit a RailTrack node (curve + gauge + closed flag) so the
## curve survives into the baked scene — AuthoringRoot is freed at load and stripped on
## export, and the train's consist sim rides that curve.
## v11: surfaces commit with ARRAY_FLAG_COMPRESS_ATTRIBUTES (see SurfaceAccumulator.commit).
const BAKER_VERSION := 11

## The runtime node rail roads bake into. A plain Node3D subclass with no editor API and
## no autoload dependency, so it loads in every mode the baker runs in.
const RailTrackScript := preload("res://src/levels/base/rail_track.gd")

## Bake-adjacent CODE that no resource dependency edge can reach: GDScript files report
## NO dependencies (verified — `ResourceLoader.get_dependencies` on a .gd returns an empty
## list), so a script is only in the net when a .tscn/.tres names it as an ext_resource.
## These shape bake OUTPUT and are named by nothing, so they are hashed explicitly —
## BAKER_VERSION stays the knob for semantic changes, but forgetting to bump it can no
## longer ship a silently-stale bake. rail_track.gd is here for the same reason: only this
## file preloads it, and its property names ARE part of every baked scene's node data.
const BAKE_CODE_INPUTS: PackedStringArray = [
	"res://kit/bake/level_baker.gd",
	"res://kit/helpers/road_builder.gd",
	"res://kit/helpers/scatter_base.gd",
	"res://src/levels/base/rail_track.gd",
]

## Scatter: items with at least this many stored instances bake as one
## MultiMeshInstance3D per chunk x item (geometry stored once) instead of merging
## their verts into the chunk meshes. ScatterItem.bake_threshold_override overrides
## per item.
const SCATTER_MULTIMESH_THRESHOLD := 64

## Weld snap distance (1 mm): vertices this close become bit-identical, so shared
## tile/ramp edges read as internal edges to Jolt instead of body seams.
const WELD_EPSILON := 0.001

## Extensions hashed as CRLF-normalized text (git/editor line-ending drift must not
## flag a bake stale); everything else is hashed as raw bytes.
const TEXT_EXTS: PackedStringArray = ["tscn", "tres", "json", "gd", "import", "cfg", "md", "txt"]


# ---------------------------------------------------------------- pure helpers

## XZ chunk cell for a piece origin. Pieces are assigned whole by their origin —
## a piece is never split across chunks.
static func chunk_key(origin: Vector3, chunk_size: float) -> Vector2i:
	return Vector2i(floori(origin.x / chunk_size), floori(origin.z / chunk_size))


## World-space origin of a chunk (its MeshInstance3D position; verts are stored
## relative to it for float precision and per-chunk culling AABBs).
static func chunk_origin(key: Vector2i, chunk_size: float) -> Vector3:
	return Vector3(key.x * chunk_size, 0.0, key.y * chunk_size)


## World scatter transforms -> chunk-local (their MultiMeshInstance3D sits at the
## chunk origin, so instance transforms drop the chunk offset — same convention as
## chunk render meshes). Extracted as a pure fn because MultiMesh instance data does
## not read back through the headless RenderingServer, so this is the only way the
## bake's chunk-local placement can be unit-tested (tests/test_bake.gd).
static func chunk_local_multimesh_transforms(world_xforms: Array, key: Vector2i,
		chunk_size: float) -> Array[Transform3D]:
	var to_local := Transform3D(Basis.IDENTITY, -chunk_origin(key, chunk_size))
	var out: Array[Transform3D] = []
	for t in world_xforms:
		out.append(to_local * (t as Transform3D))
	return out


## Weld a triangle soup: every vertex within `epsilon` of an already-seen vertex becomes
## bit-identical to it, and triangles that degenerate are dropped. The result is what the
## Drivable body's ConcavePolygonShape3D gets (§2 rule 2: welded, no interior seams).
##
## This is a true epsilon MERGE, not a snap-to-grid: rounding each vertex to a grid cell
## unifies verts that share a cell but leaves verts astride a cell boundary distinct, so
## two vertices microns apart could still weld into a crack — position-dependent, so it
## passes every fixture and shows up on exactly one authored level as a wheel that catches
## at one joint. Instead each vertex probes the 27 cells around it (a match must be within
## one cell per axis when the cell size IS epsilon) and adopts the first canonical vertex
## it finds, scanning cells and per-cell lists in a fixed order — so the output stays
## deterministic for a given input order, which the collect walk guarantees.
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


## First registered vertex within epsilon of `v`, searching `key`'s cell and its 26
## neighbours in a fixed order; null when there is none.
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


## Normalize line endings so the same file hashes the same on Windows and CI.
static func normalize_text(s: String) -> String:
	return s.replace("\r\n", "\n").replace("\r", "\n")


## Hash one file: text formats as normalized text, binaries as raw bytes.
static func hash_file(path: String) -> String:
	if TEXT_EXTS.has(path.get_extension().to_lower()):
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			return "MISSING"
		return normalize_text(f.get_as_text()).sha256_text()
	var h := FileAccess.get_sha256(path)
	return h if h != "" else "MISSING"


## Combined input hash: order-independent over `paths` (sorted internally) plus
## extra tokens (baker version, chunk size). This is the manifest stamp.
static func hash_inputs(paths: PackedStringArray, extra := PackedStringArray()) -> String:
	var sorted := paths.duplicate()
	sorted.sort()
	var lines := PackedStringArray()
	for p in sorted:
		lines.append(p + ":" + hash_file(p))
	for e in extra:
		lines.append(String(e))
	return ("\n".join(lines)).sha256_text()


## Validate the level's spawn coverage (bake gate). `spawns` is a list of
## {types: PackedStringArray, is_water: bool}; empty types = accepts any. Boats need
## a water spawn, land vehicles a land spawn. Returns human-readable errors.
static func validate_spawns(allowed: PackedStringArray, default_vehicle: String,
		spawns: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	if spawns.is_empty():
		errors.append("level has no VehicleSpawn markers")
		return errors
	# allowed_vehicles lists FAMILIES; default_vehicle is a VARIANT (legacy families spell them
	# the same, e.g. "car", so this only bites once a variant id differs — "bullet"/"train").
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
		# The train is rail-guided: it is placed on a closed rail loop, not at a VehicleSpawn
		# marker, so it is exempt from the per-type marker-coverage gate.
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


## Split one indexed triangle surface into per-chunk sub-surfaces, keyed by the WORLD
## triangle centroid's chunk (road ribbons: a road is long, so its render mesh is
## bucketed for frustum culling; `world_xform` is applied for KEYING ONLY — the output
## arrays stay in the source space, vertices remapped/deduped per chunk). Render-only:
## collision never splits (the ribbon welds into the single level-wide Drivable body,
## §2 rule 1a). Handles VERTEX/NORMAL/TEX_UV/COLOR channels — the same set
## SurfaceAccumulator merges, so a channel can never survive one path and vanish in the
## other; triangle count is conserved.
static func split_arrays_by_chunk(arrays: Array, world_xform: Transform3D,
		chunk_size: float) -> Dictionary:
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# regular Arrays (by-reference) during accumulation: Packed*Arrays stored in a
	# Dictionary are value types, so appending through the dict would mutate a copy
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


## Semantic material key so identical Kenney materials re-imported per GLB merge
## into one surface instead of one surface per source file.
##
## Every field that changes how the surface RENDERS belongs here. The whole kit shares one
## colormap.png atlas, so albedo alone is nowhere near enough to tell materials apart: an
## emissive lit-window material and a matte wall material differ in nothing else, and
## keying on albedo merged them into one surface whose material was whichever the merge
## happened to see first — windows going matte on one chunk and walls glowing on the next,
## from identical authoring.
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


## Stable identity for a material's texture slot: the resource path when it has one
## (the imported-per-GLB atlas case these keys exist to merge), else the instance.
static func _texture_key(tex: Texture2D) -> String:
	if tex == null:
		return "-"
	return tex.resource_path if not tex.resource_path.is_empty() \
			else "texid:%d" % tex.get_instance_id()


# ------------------------------------------------------------ dependency walk

## Every file whose change must flag a bake stale: the level scene itself, its transitive
## resource dependencies that can shape bake output (wherever they live), the explicit
## BAKE_CODE_INPUTS, and their .import sidecars. Sorted + deduped for a stable hash.
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


## Whether a dependency can change what the baker emits. The old rule — keep res://kit/
## only — was too narrow: an Authoring subtree that instances a prop sub-scene from
## res://src/, or a mesh/material saved outside the kit, is walked by _collect and merged
## into the bake, yet edits to it left the hash untouched and CI green. LevelInfo (a .tres
## under src/levels/) escaped the same way, so the spawn gate's verdict was cached.
##
## So: keep every resource, anywhere, EXCEPT plugin code and scripts outside the kit.
## Runtime scripts (level.gd, vehicles, water) cannot change baker output — the baker
## reads transforms, meshes and shapes, plus the duck-typed kit APIs — and hashing them
## would re-stale every level on unrelated gameplay edits. Kit scripts stay in (they ARE
## the duck-typed APIs), as do heightmap/splat PNGs: sculpting terrain moves scattered
## props, which is exactly what scatter_ground_errors also guards.
static func is_bake_input(path: String) -> bool:
	if path.begins_with("res://kit/"):
		return true
	if path.begins_with("res://addons/"):
		return false
	var ext := path.get_extension().to_lower()
	return ext != "gd" and ext != "cs"


## get_dependencies entries look like "uid://xx::type::res://path" (or subsets);
## pull out the res:// path, resolving a bare uid:// if that's all there is.
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


## Manifest is deliberately timestamp-free: re-baking unchanged inputs produces a
## byte-identical file (clean git diffs, deterministic CI). `output_hash` is the sha256 of
## the .baked.scn: without it the freshness check only asked whether the OUTPUT file
## exists, so a truncated, hand-edited or half-written bake read fresh forever.
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


## The extra hash tokens stamped alongside the file hashes. chunk_size is included
## so turning the knob flags the bake stale until re-baked.
static func hash_extra(chunk_size: float) -> PackedStringArray:
	return PackedStringArray(["baker_version:%d" % BAKER_VERSION, "chunk_size:%s" % var_to_str(chunk_size)])


# ------------------------------------------------------------ scene discovery

## First AuthoringRoot under `root` (duck-typed marker, see AuthoringRoot); null
## if the level has no kit authoring content.
static func find_authoring(root: Node) -> Node:
	if root.has_method("is_carlito_authoring"):
		return root
	for child in root.get_children():
		var found := find_authoring(child)
		if found != null:
			return found
	return null


## Spawn descriptors for validate_spawns, pulled off VehicleSpawn markers anywhere
## in the level (duck-typed on accepts()).
static func collect_spawn_descriptors(root: Node) -> Array:
	var out := []
	for node in root.find_children("*", "Marker3D", true, false):
		if node.has_method("accepts"):
			out.append({
				"types": node.get("vehicle_types"),
				"is_water": bool(node.get("is_water")),
			})
	return out


## Stale-scatter guard (shared by the bake gate and check_level_file): a region
## with stored instances whose stored_ground_hash no longer matches the level's
## terrain heightmaps was snapped against ground that has since been sculpted — the
## author must Regenerate in the editor (only that re-snaps), then re-bake. The
## terrain PNGs live beside the level scene, outside gather_bake_inputs' res://kit/
## net, so without this check a sculpt would ship floating/buried props CI-green.
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
	if node.has_method("is_carlito_scatter"):
		out.append(node)
	for child in node.get_children():
		_find_scatter_nodes(child, out)


# ----------------------------------------------------------------- bake proper

## Bake the level rooted at `level_root` (an instantiated level scene; it does NOT
## need to be inside a tree). Returns:
##   { ok: bool, errors: PackedStringArray, root: Node3D or null, stats: Dictionary }
## On ok, `root` is the assembled Baked scene root (caller packs + frees it).
static func bake(level_root: Node) -> Dictionary:
	var errors := PackedStringArray()
	var authoring := find_authoring(level_root)
	if authoring == null:
		return _fail(["level has no AuthoringRoot node — nothing to bake"])
	var chunk_size := float(authoring.get("chunk_size"))
	if chunk_size <= 0.0:
		return _fail(["AuthoringRoot.chunk_size must be > 0 (got %s)" % chunk_size])

	# Spawn validation is a bake gate: a level that can't spawn its vehicles must
	# not produce a shippable bake.
	var info: Resource = level_root.get("info")
	var allowed: PackedStringArray = info.get("allowed_vehicles") if info != null else PackedStringArray()
	var default_vehicle := String(info.get("default_vehicle")) if info != null else "car"
	errors.append_array(validate_spawns(allowed, default_vehicle, collect_spawn_descriptors(level_root)))
	# Stale-scatter is a bake gate too: sculpt-after-scatter must never
	# silently bake floating or buried props.
	errors.append_array(scatter_ground_errors(level_root))

	var ctx := BakeContext.new()
	ctx.chunk_size = chunk_size
	_collect(authoring, _authoring_xform(level_root, authoring), ctx, errors)
	# Collision-only authoring (pieces that carry shapes but no mesh) is legitimate, so
	# the gate is "nothing at all was collected", not "no vertices".
	if ctx.total_vertices == 0 and ctx.body_shapes.is_empty() and ctx.weld_pool.is_empty():
		errors.append("AuthoringRoot has no bakeable content (GridMaps / KitPiece prefabs)")
	if not errors.is_empty():
		return _fail(errors)
	return {"ok": true, "errors": errors, "root": _assemble(ctx), "stats": ctx.stats()}


## Authoring transform relative to the level root, accumulated manually (the level
## instance may not be in a tree, so global_transform is off-limits).
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


## Recursive gather. GridMap cells are all drivable — every generated palette is a set of
## road/ground TILES by construction (the recipes' "palette" pipeline; the wall and
## barrier meshlibs are road tiles that carry a wall along one edge, not free-standing
## walls, so welding them is right). KitPiece prefabs contribute render meshes plus
## collision per their mode.
static func _collect(node: Node, xform: Transform3D, ctx: BakeContext,
		errors: PackedStringArray) -> void:
	for child in node.get_children():
		var cxform := xform
		if child is Node3D:
			cxform = xform * (child as Node3D).transform
		if child is GridMap:
			_collect_gridmap(child as GridMap, cxform, ctx, errors)
		elif child.has_method("is_carlito_kit_piece"):
			_collect_piece(child, cxform, ctx, errors)
		elif child.has_method("is_carlito_scatter"):
			_collect_scatter(child, cxform, ctx, errors)
		elif child.has_method("is_carlito_road"):
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
	cells.sort()  # deterministic bake output
	for cell: Vector3i in cells:
		var item := gm.get_cell_item(cell)
		var mesh := ml.get_item_mesh(item)
		if mesh == null:
			continue
		var basis := gm.get_basis_with_orthogonal_index(gm.get_cell_item_orientation(cell))
		var cell_xform := xform * Transform3D(basis, gm.map_to_local(cell))
		var mesh_xform := cell_xform * ml.get_item_mesh_transform(item)
		# Key by where the GEOMETRY actually sits, not the anchor cell: the roads
		# palette's road-curve is a corner-anchored 2x2 sweep, so keying on the cell
		# origin filed up to three quarters of it under a chunk it does not overlap and
		# stretched that chunk's culling AABB by a full 24 m. The piece still moves whole.
		var key := chunk_key(mesh_xform * mesh.get_aabb().get_center(), ctx.chunk_size)
		ctx.add_render_mesh(key, mesh, mesh_xform)
		ctx.add_weld_mesh(mesh, mesh_xform)


static func _collect_piece(piece: Node, xform: Transform3D, ctx: BakeContext,
		errors: PackedStringArray) -> void:
	var mode := String(piece.get("collision_mode"))
	var key := chunk_key(xform.origin, ctx.chunk_size)
	_collect_piece_content(piece, xform, key, mode, ctx, errors)


## Walk one piece's subtree under `mode`. A nested KitPiece re-enters _collect_piece so it
## keeps its OWN collision mode: inheriting the ancestor's silently broke the drivable
## invariant both ways — a "hull" railing grouped under a "weld" bridge had its triangles
## welded into the level-wide drivable body (drive up the handrail, phantom wheel contacts)
## while its hull shape was dropped, and a "weld" ramp grouped under a "box" warehouse
## never reached the drivable body at all, so the car fell through a ramp that dev-play
## rendered solid.
##
## `nested` is false only for scatter, whose template subtree is validated as a whole
## before this runs (a scattered weld prefab is a bake error, and collision-off must stay
## off for every descendant) — generated scatter prefabs are flat anyway.
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
		if nested and child.has_method("is_carlito_kit_piece"):
			_collect_piece(child, cxform, ctx, errors)
		else:
			_collect_piece_content(child, cxform, key, mode, ctx, errors, nested)


## Scatter: consume the region's STORED transforms only — no
## expansion, no raycast, no physics here, so editor and bake can never diverge.
## Per item: at or above the MultiMesh threshold the render side becomes chunked
## MultiMeshes over ONE merged item mesh (an island forest never duplicates its
## verts into chunk meshes); below it every instance routes through the existing
## prefab merge path. Collision harvest is identical either way: the prefab's
## shapes per instance into the per-chunk bodies (collision-off items add zero
## physics). All prefab-shaped logic is duck-called on the region's script
## (stored_transform / build_item_mesh / shape_entries) so the stored layout has
## one owner.
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
		if template.has_method("is_carlito_kit_piece"):
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
			# Swap the prefab's materials for the bake's deduplicated copies, so the
			# baked scene never references kit resources (same rule as chunk merges).
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


## Spline road: duck-call the RoadPath's geometry API (ribbon_surfaces — the stored layout
## has one owner, and it depends only on the serialized Path child + profile, so it works
## on the baker's untreed instance). The weld soup is flattened from those same surfaces
## rather than from a second ribbon_faces() call, which re-ran adaptive sampling and the
## whole extrusion a second time per road for a byte-identical result.
## Render surfaces are chunk-bucketed by triangle centroid for frustum culling;
## collision is NOT split — every ribbon triangle joins the level-wide welded
## Drivable body through the same 1 mm snap as weld prefabs. No
## recursion into the road: Preview/DevCollision never exist off-tree, and the
## Path child carries no bakeable content of its own.
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
		# entries arrive slot-sorted (ribbon_surfaces sorts its keys), the same order
		# faces_from_surfaces walks, so the soup is byte-identical to ribbon_faces()
		var pos: PackedVector3Array = e.arrays[Mesh.ARRAY_VERTEX]
		for i: int in (e.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
			faces.append(pos[i])
	ctx.add_weld_faces(faces, xform)
	ctx.roads += 1
	# Rails: the ribbon above is only what you SEE and drive over — the train rides the
	# curve, which dies with AuthoringRoot unless it is copied into the baked scene. Duck
	# API (get_rail_curve() != null), never a class_name check; rail_local_xform() rather
	# than global_transform because this instance is untreed.
	if road.has_method("get_rail_curve"):
		var rail_curve: Curve3D = road.call("get_rail_curve")
		if rail_curve != null:
			ctx.rail_tracks.append({
				"curve": rail_curve.duplicate(true),
				"xform": xform * (road.call("rail_local_xform") as Transform3D),
				"gauge": float(road.call("rail_gauge")),
				"closed": bool(road.call("is_rail_closed")),
			})


## Assemble the Baked scene: Chunks/ (merged render meshes), Bodies/ (one
## StaticBody3D per chunk with the harvested shapes), Drivable (the single welded
## body). Everything the scene stores is duplicated so the bake has zero
## dependencies on kit prefabs, palettes, or GLBs (they're export-stripped).
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
		# One duplicate per SOURCE shape, shared by every instance that harvested it.
		# Duplicating per instance gave a 3000-tree forest 3000 identical BoxShape3Ds in
		# the packed scene and 3000 shapes in the physics server — the render side stores
		# scattered geometry once, and the collision side has no reason not to.
		var shared := {}
		for key: Vector2i in body_keys:
			var body := StaticBody3D.new()
			body.name = "body_%d_%d" % [key.x, key.y]
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
		root.add_child(drivable)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(weld_faces(ctx.weld_pool))
		var cs := CollisionShape3D.new()
		cs.name = "WeldedCollision"
		cs.shape = shape
		drivable.add_child(cs)

	# Rails carry no geometry of their own (the ribbon is already in Chunks + Drivable) —
	# just the curve the train needs. Collected in walk order, so the names are stable.
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

## Full bake for a level scene file: load, bake, save the .scn, stamp the manifest,
## and verify the saved bake leaked no kit dependencies. Returns
## {ok, errors, stats}. This is the one entry point the editor button and the CLI
## tools share.
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


## Freshness check for CI: "fresh" | "stale" | "missing" for a level that has
## kit authoring content, "no_authoring" for levels the bake doesn't apply to.
static func check_level_file(level_path: String) -> Dictionary:
	var packed := load(level_path) as PackedScene
	if packed == null:
		return {"status": "error", "detail": "cannot load level scene '%s'" % level_path}
	var level_root := packed.instantiate()
	var authoring := find_authoring(level_root)
	# read everything BEFORE freeing the tree: a freed node compares equal to null
	# An AuthoringRoot with no children is an empty canvas (a freshly scaffolded level):
	# the baker produces nothing for it, so demanding a bake output would fail CI on a
	# level nobody has authored yet. Anything painted into it re-arms the check.
	var has_authoring := authoring != null and authoring.get_child_count() > 0
	var chunk_size := float(authoring.get("chunk_size")) if has_authoring else 0.0
	var scatter_errors := scatter_ground_errors(level_root)
	level_root.free()
	if not has_authoring:
		return {"status": "no_authoring", "detail": ""}

	var manifest := read_manifest(level_path)
	if manifest.is_empty() or not FileAccess.file_exists(baked_scene_path(level_path)):
		return {"status": "missing", "detail": "no bake output — run the bake tool"}
	if int(manifest.get("baker_version", -1)) != BAKER_VERSION:
		return {"status": "stale", "detail": "baked with baker v%s, current v%d" %
				[manifest.get("baker_version"), BAKER_VERSION]}
	var current := hash_inputs(gather_bake_inputs(level_path), hash_extra(chunk_size))
	if String(manifest.get("input_hash", "")) != current:
		return {"status": "stale", "detail": "authoring inputs changed since last bake"}
	# The output itself, not just its existence: a truncated or hand-edited .baked.scn
	# used to pass forever on a matching input hash.
	var stamped := String(manifest.get("output_hash", ""))
	if stamped != FileAccess.get_sha256(baked_scene_path(level_path)):
		return {"status": "stale", "detail": "baked scene does not match its manifest — re-bake"}
	# Terrain PNGs sit outside the input hash's res://kit/ net, so stale scatter needs
	# its own check (and Regenerate — not just a re-bake — clears it).
	if not scatter_errors.is_empty():
		return {"status": "stale", "detail": scatter_errors[0]}
	return {"status": "fresh", "detail": ""}


# --------------------------------------------------------------- inner classes

## Accumulates everything one bake collects before assembly.
class BakeContext:
	var chunk_size := 48.0
	## Vector2i chunk key -> { material_key: SurfaceAccumulator }
	var render := {}
	## material_key -> duplicated Material stored in the baked scene
	var materials := {}
	## Vector2i chunk key -> Array of [Shape3D, Transform3D]
	var body_shapes := {}
	## world-space triangle soup for the single welded drivable body
	var weld_pool := PackedVector3Array()
	var total_vertices := 0
	## Scatter: merged item meshes, geometry stored ONCE (shared across chunks)
	var scatter_meshes: Array[ArrayMesh] = []
	## Parallel to scatter_meshes: whether that item's MultiMeshes cast shadows.
	var scatter_shadows: Array[bool] = []
	## Vector2i chunk key -> { mesh index -> Array of world Transform3D }
	var multimesh := {}
	var scatter_instances := 0
	## Spline roads collected
	var roads := 0
	## Rail roads: {curve: Curve3D, xform: Transform3D, gauge: float, closed: bool} per
	## entry -> one RailTrack each in the baked scene.
	var rail_tracks := []

	func add_render_mesh(key: Vector2i, mesh: Mesh, world_xform: Transform3D) -> void:
		for si in mesh.get_surface_count():
			add_render_arrays(key, mesh.surface_get_material(si),
					mesh.surface_get_arrays(si), world_xform)

	## One raw surface into a chunk's per-material accumulator — the shared dedup/merge
	## path add_render_mesh loops through, and what road ribbons (already split into
	## per-chunk arrays) feed directly.
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

	## A pre-built triangle soup into the level-wide weld pool (road ribbons).
	## A mirroring transform reverses each triangle so the welded body keeps its outward
	## winding — see SurfaceAccumulator.append for why that matters.
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


## Merges mesh surfaces that share a material into one surface, applying transforms
## at array level: positions by the full transform, normals rotated by the
## inverse-transpose basis and re-normalized (correct under ANY invertible basis, not
## just the uniform scales the kit uses — SurfaceTool.append_from leaves scaled normals
## unnormalized), and triangles reversed when the transform mirrors.
##
## ARRAY_TANGENT is deliberately dropped: the kit is flat-colour with no normal maps, and
## the bake is the only consumer. If a piece ever ships a normal map, tangents need the
## same per-vertex treatment as normals here — they will not appear by themselves.
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
			uvs.resize(base)  # zero-fill vertices appended before UVs appeared
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

		# A mirroring transform (negative determinant — scale (-1, 1, 1), the standard
		# left-hand-variant trick) flips triangle handedness. The inverse-transpose keeps
		# normals pointing outward, but copying the index order verbatim left the winding
		# reversed: the chunk mesh rendered inside-out under cull_back (a mirrored pier
		# visible only from within), and the same triangles entered the welded body
		# back-to-front, making the deck one-way so the car fell through it. Only the bake
		# saw this — dev-play uses the prefab's own shapes.
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
		# quantized to 16 bits across the surface AABB. ~38% off the stored mesh (the
		# baked scenes are 71% of the .pck) and the same cut again on per-frame vertex
		# fetch, which is what the web build is short of. Precision is the reason it is
		# safe HERE and nowhere else: a surface spans one 64 m chunk, so a position step
		# is ~1 mm. Collision is untouched — the welded drivable body and the per-chunk
		# shapes are Shape3D, not meshes, so nothing the car stands on is quantized.
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
				Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		var si := mesh.get_surface_count() - 1
		if material != null:
			mesh.surface_set_material(si, material)
		return si

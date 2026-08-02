@tool
extends RefCounted
## "Conform terrain under tiles" (palette toolbar button): flattens every overlapping
## HeightmapTerrain to the painted GridMap cells' BASE plane — the tiles' resting
## height — so a tile city sits on terrain without hand-stroking 12 m flatten pads.
## The RoadPath Conform discipline throughout: destructive-by-button, the pure pixel
## work is RoadBuilder.conform_rects (tested), one undoable _commit_generated action
## per terrain. Tile targets FLOOR-quantize to the 8-bit grid with an adjustable lift
## (terrain meets the highest step at or below base + lift — never above, so a tall
## island's coarse quantization can't poke terrain through a thin road deck); prefab
## targets keep the round-quantize closest meet. Editor-only (addons/), so editor API
## types are fine here.

const Recipe := preload("res://kit/helpers/kit_recipe.gd")
const BrushOps := preload("res://kit/helpers/brush_ops.gd")
const SplatPaint := preload("res://kit/helpers/splat_paint.gd")
const RECIPE_DIR := "res://kit/import"

## Flatten fade-out (m) beyond the tile footprint union — the RoadPath default.
const FALLOFF := 4.0

## Default tile lift (m): how far above the tile base plane the terrain may rise.
## Floor-quantized, so terrain lands on the highest 8-bit step at or below
## base + lift. Road decks are 0.24 m tall — keep the lift under that.
const DEFAULT_TILE_LIFT := 0.2

## Default flat apron (m) grown around each prefab building's footprint before the
## falloff drop starts — keeps the building off a "pedestal" edge.
const DEFAULT_PREFAB_APRON := 2.0

## Prefab families whose placed pieces flatten a terrain pad under themselves on Conform.
## Add/remove family names (from kit/import/*.json) to change behavior.
const CONFORM_PREFAB_FAMILIES: Array[String] = [
	"commercial-buildings", "industrial-buildings", "suburban-buildings",
	"racing-grandstands", "racing-pits", "racing-tents",
]
## Tile GridMaps excluded from Conform, by meshlib basename (all conform by default).
const CONFORM_EXCLUDE_MESHLIBS: Array[String] = []


## Per painted cell (sorted — deterministic first-wins rect order downstream):
## world-space XZ footprint rect + base-plane world height, as
## {rects: Array[Rect2], base_ys: PackedFloat32Array}. The footprint is the item
## mesh's AABB in the painted orientation — multi-cell tiles like the 2x2 road-curve
## / 3x3 roundabout overhang their anchor cell, so occupancy alone would leave their
## overhung cells unconformed — cached per (item, orientation). No editor APIs
## (tested in tests/test_road.gd against the real roads meshlib).
static func footprint_rects(grid: GridMap) -> Dictionary:
	var rects: Array[Rect2] = []
	var base_ys := PackedFloat32Array()
	var lib := grid.mesh_library
	if lib == null:
		return {"rects": rects, "base_ys": base_ys}
	var xf := grid.global_transform if grid.is_inside_tree() else grid.transform
	var cells := grid.get_used_cells()
	cells.sort()
	var footprints := {}   # Vector2i(item, orientation) -> Rect2 (grid-relative XZ)
	for cell: Vector3i in cells:
		var item := grid.get_cell_item(cell)
		var orient := grid.get_cell_item_orientation(cell)
		var key := Vector2i(item, orient)
		if not footprints.has(key):
			var mesh := lib.get_item_mesh(item)
			if mesh == null:
				footprints[key] = Rect2()
			else:
				# full mesh transform (its origin carries palette alignment offsets),
				# then the painted orientation, then the grid's world basis
				var mt := lib.get_item_mesh_transform(item)
				var cell_basis := grid.get_basis_with_orthogonal_index(orient)
				var aabb := mesh.get_aabb()
				var fp := Rect2()
				for ci in 8:
					var c := xf.basis * (cell_basis * (mt * aabb.get_endpoint(ci)))
					var p := Vector2(c.x, c.z)
					fp = Rect2(p, Vector2.ZERO) if ci == 0 else fp.expand(p)
				footprints[key] = fp
		var fp2: Rect2 = footprints[key]
		if not fp2.has_area():
			continue
		var origin := xf * grid.map_to_local(cell)
		rects.append(Rect2(fp2.position + Vector2(origin.x, origin.z), fp2.size))
		base_ys.append(origin.y)
	return {"rects": rects, "base_ys": base_ys}


## Conform every terrain under ALL painted tile GridMaps (any meshlib not excluded) plus
## every placed prefab building whose family is in CONFORM_PREFAB_FAMILIES, in one pass.
## Entry point for the palette dock's Conform button. tile_lift raises the tile targets
## (floor-quantized — see the class doc); prefab_apron grows each building footprint so
## flat ground extends past the walls before the falloff drop.
static func conform_all(scene_root: Node, tile_lift := DEFAULT_TILE_LIFT,
		prefab_apron := DEFAULT_PREFAB_APRON) -> void:
	if scene_root == null:
		push_warning("Kit: no scene open to conform.")
		return
	var authoring := _find_authoring(scene_root)
	if authoring == null:
		push_warning("Kit: no AuthoringRoot in the scene to conform under.")
		return

	var rects: Array[Rect2] = []
	var base_ys := PackedFloat32Array()
	var is_tile := PackedByteArray()

	# Every painted tile GridMap (skip excluded meshlibs); reuse footprint_rects verbatim.
	for node in authoring.find_children("*", "GridMap", true, false):
		var grid := node as GridMap
		if _meshlib_excluded(grid):
			continue
		var fps := footprint_rects(grid)
		var g_rects: Array[Rect2] = fps["rects"]
		var g_base: PackedFloat32Array = fps["base_ys"]
		for i in g_rects.size():
			rects.append(g_rects[i])
			base_ys.append(g_base[i])
			is_tile.append(1)

	# Every placed KitPiece (duck-typed) whose family is listed: footprint = merged
	# world-space AABB of its mesh descendants + the flat apron, target = the piece's
	# world origin Y.
	var recipe_cache := {}
	for node in authoring.find_children("*", "Node3D", true, false):
		if not node.has_method("is_carlito_kit_piece"):
			continue
		if not CONFORM_PREFAB_FAMILIES.has(piece_family(node, recipe_cache)):
			continue
		var fp := _piece_footprint(node as Node3D)
		if not fp.has_area():
			continue
		rects.append(fp.grow(maxf(prefab_apron, 0.0)))
		base_ys.append((node as Node3D).global_position.y)
		is_tile.append(0)

	if rects.is_empty():
		push_warning("Kit: no painted tiles or listed prefab buildings to conform under.")
		return
	_conform_terrains(scene_root, rects, base_ys, is_tile, tile_lift)


## Flatten every overlapping terrain to the given world-space XZ footprint rects + target
## base-plane world heights (paired arrays; is_tile flags tile entries). Tile targets get
## tile_lift added, then FLOOR-quantize to the terrain's 8-bit grid here (a per-rect
## constant, so pre-quantizing is exact; conform_rects' round downstream is then an
## identity) — terrain never rises past base + lift. Prefab targets stay unquantized and
## take conform_rects' round (closest meet). One undoable _commit_generated per terrain.
static func _conform_terrains(scene_root: Node, rects: Array[Rect2],
		base_ys: PackedFloat32Array, is_tile: PackedByteArray, tile_lift: float) -> void:
	var terrains: Array[Node] = []
	ScatterBase.find_terrains_under(scene_root, terrains)
	var touched := 0
	for t in terrains:
		var t3d := t as Node3D
		var half: Vector2 = t.get("terrain_size") * 0.5
		var t_rect := Rect2(t3d.global_position.x - half.x,
				t3d.global_position.z - half.y, half.x * 2.0, half.y * 2.0) \
				.grow(FALLOFF)
		var local_rects: Array[Rect2] = []
		var targets := PackedFloat32Array()
		var amp := maxf(float(t.get("height")), 0.001)
		var clamped := false
		for i in rects.size():
			if not t_rect.intersects(rects[i]):
				continue
			local_rects.append(Rect2(rects[i].position
					- Vector2(t3d.global_position.x, t3d.global_position.z),
					rects[i].size))
			var base_y := base_ys[i] + (tile_lift if is_tile[i] == 1 else 0.0)
			var tn := (base_y - t3d.global_position.y) / amp
			if tn < 0.0 or tn > 1.0:
				clamped = true
			tn = clampf(tn, 0.0, 1.0)
			if is_tile[i] == 1:
				tn = floorf(tn * 255.0) / 255.0
			targets.append(tn)
		if local_rects.is_empty():
			continue
		if clamped:
			push_warning("Kit: some footprints sit outside terrain '%s's height range — the flatten clamps there." % t.name)
		var img: Image = t._read_image()
		if img == null:
			push_warning("Kit: terrain '%s' has no heightmap to conform." % t.name)
			continue
		var dims: Vector2i = t._grid_dims()
		var dirty := RoadBuilder.conform_rects(img, local_rects, targets, FALLOFF,
				float(dims.x - 1), float(dims.y - 1))
		if not dirty.has_area():
			continue
		t._commit_generated("Conform terrain under tiles & buildings",
				[[&"heightmap", t.png_path_for("height"), img]], {})
		touched += 1
	if touched == 0:
		push_warning("Kit: no HeightmapTerrain overlaps the footprints — nothing conformed.")
	else:
		print("Kit: conformed %d terrain(s) under tiles & buildings." % touched)


## World-space XZ triangles (3 verts each) of every painted cell's ACTUAL item mesh —
## the paint footprint. Unlike footprint_rects' AABB rects (conform wants the full base
## pad), paint must not spill past the visible mesh: a 2x2 road-curve covers only part of
## its footprint, and only the curve itself may be painted. Faces cached per item
## (get_faces is not cheap); cells sorted (deterministic).
static func footprint_tris(grid: GridMap) -> PackedVector2Array:
	var out := PackedVector2Array()
	var lib := grid.mesh_library
	if lib == null:
		return out
	var xf := grid.global_transform if grid.is_inside_tree() else grid.transform
	var cells := grid.get_used_cells()
	cells.sort()
	var faces_cache := {}   # item -> PackedVector3Array (mesh faces incl. mesh transform)
	for cell: Vector3i in cells:
		var item := grid.get_cell_item(cell)
		if not faces_cache.has(item):
			var mesh := lib.get_item_mesh(item)
			if mesh == null:
				faces_cache[item] = PackedVector3Array()
			else:
				var mt := lib.get_item_mesh_transform(item)
				var faces := mesh.get_faces()
				var local := PackedVector3Array()
				local.resize(faces.size())
				for i in faces.size():
					local[i] = mt * faces[i]
				faces_cache[item] = local
		var local_faces: PackedVector3Array = faces_cache[item]
		if local_faces.is_empty():
			continue
		var cell_basis := grid.get_basis_with_orthogonal_index(
				grid.get_cell_item_orientation(cell))
		var origin := xf * grid.map_to_local(cell)
		for v in local_faces:
			var c := xf.basis * (cell_basis * v)
			out.append(Vector2(c.x + origin.x, c.z + origin.z))
	return out


## Default channel for "Paint splat under tiles" (6 = Asphalt in the stock channel names).
## Tile roads/tracks sit within RayWheel.SURFACE_GRIP_REACH of the conformed terrain, so
## the wheels read the ground splat through the deck — unpainted, a tile city street grips
## like the grass under it.
const DEFAULT_PAINT_CHANNEL := 6


## Paint every terrain's splat under the ACTUAL mesh of every painted tile
## (footprint_tris — a curve paints only the curve; prefab buildings are left alone —
## nothing drives through a wall, and grass up to it looks right). SplatPaint erodes the
## coverage by one splat pixel, so the paint stays hidden under the tile. Entry point for
## the palette dock's Paint-splat button. Destructive-by-button, pure pixel work in
## SplatPaint (tested), one undoable _commit_generated per terrain.
static func paint_all(scene_root: Node, channel := DEFAULT_PAINT_CHANNEL) -> void:
	if scene_root == null:
		push_warning("Kit: no scene open to paint under.")
		return
	var authoring := _find_authoring(scene_root)
	if authoring == null:
		push_warning("Kit: no AuthoringRoot in the scene to paint under.")
		return
	var tris := PackedVector2Array()
	for node in authoring.find_children("*", "GridMap", true, false):
		var grid := node as GridMap
		if _meshlib_excluded(grid):
			continue
		tris.append_array(footprint_tris(grid))
	if tris.is_empty():
		push_warning("Kit: no painted tiles to paint under.")
		return

	var terrains: Array[Node] = []
	ScatterBase.find_terrains_under(scene_root, terrains)
	var touched := 0
	for t in terrains:
		var t3d := t as Node3D
		var half: Vector2 = t.get("terrain_size") * 0.5
		var t_origin := Vector2(t3d.global_position.x, t3d.global_position.z)
		var local_tris := PackedVector2Array()
		local_tris.resize(tris.size())
		for i in tris.size():
			local_tris[i] = tris[i] - t_origin
		var img: Image = SplatPaint.decode(t.get("splatmap"))
		if img == null:
			push_warning("Kit: terrain '%s' has no usable splatmap — run Auto-splat first." % t.name)
			continue
		var img2: Image = SplatPaint.decode(t.get("splatmap2"))
		if img2 == null and channel >= 4:
			# The brush's convention: the second weight map appears on the first
			# stroke of a channel >= 4.
			img2 = Image.create(img.get_width(), img.get_height(), false,
					Image.FORMAT_RGBA8)
			img2.fill(Color(0, 0, 0, 0))
		if img2 != null and img2.get_size() != img.get_size():
			push_warning("Kit: terrain '%s's splatmap2 size differs from splatmap — repaint it at the base size first (see the terrain's config warning)." % t.name)
			continue
		var images: Array[Image] = [img]
		var units: Array[Color] = [BrushOps.unit_slice(channel, 0)]
		if img2 != null:
			images.append(img2)
			units.append(BrushOps.unit_slice(channel, 1))
		var dirty: Rect2i = SplatPaint.paint_tris(images, units, local_tris,
				half.x * 2.0, half.y * 2.0)
		if not dirty.has_area():
			continue
		var splat_path: String = t.png_path_for("splat")
		if splat_path.is_empty():
			continue   # png_path_for already warned (unsaved scene)
		var entries: Array = [[&"splatmap", splat_path, img]]
		if img2 != null:
			entries.append([&"splatmap2", t.png_path_for("splat2"), img2])
		t._commit_generated("Paint splat under tiles", entries, {})
		touched += 1
	if touched == 0:
		push_warning("Kit: no terrain splat under the painted tiles changed.")
	else:
		print("Kit: painted splat channel %d under tiles on %d terrain(s)." % [channel, touched])


## Whether a GridMap's meshlib basename is in CONFORM_EXCLUDE_MESHLIBS (or it has no lib).
static func _meshlib_excluded(grid: GridMap) -> bool:
	if grid.mesh_library == null:
		return true
	return CONFORM_EXCLUDE_MESHLIBS.has(grid.mesh_library.resource_path.get_file().get_basename())


## Merged world-space XZ AABB of a placed piece's MeshInstance3D descendants, as a Rect2.
static func _piece_footprint(piece: Node3D) -> Rect2:
	var rect := Rect2()
	var has := false
	for node in piece.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var mt := mi.global_transform
		var aabb := mi.mesh.get_aabb()
		for ci in 8:
			var c := mt * aabb.get_endpoint(ci)
			var p := Vector2(c.x, c.z)
			if not has:
				rect = Rect2(p, Vector2.ZERO)
				has = true
			else:
				rect = rect.expand(p)
	return rect if has else Rect2()


## Recipe family of a placed prefab, from its scene_file_path
## (res://kit/prefabs/<kit>/<name>.tscn) classified through the kit recipe; "" if unknown.
## recipe_cache maps kit -> families Array so each recipe JSON parses once per conform pass.
static func piece_family(piece: Node, recipe_cache: Dictionary) -> String:
	var path := piece.scene_file_path
	if path.is_empty():
		return ""
	var base := path.get_file().get_basename()
	var kit := path.get_base_dir().get_file()
	if kit.is_empty() or base.is_empty():
		return ""
	if not recipe_cache.has(kit):
		recipe_cache[kit] = _load_recipe_families(kit)
	var families: Array = recipe_cache[kit]
	if families.is_empty():
		return ""
	return String(Recipe.classify([base], families).assignments.get(base, ""))


static func _load_recipe_families(kit: String) -> Array:
	var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("%s/%s.json" % [RECIPE_DIR, kit]))
	if parsed is Dictionary:
		return (parsed as Dictionary).get("families", [])
	return []


static func _find_authoring(node: Node) -> Node:
	if node == null:
		return null
	if node.has_method("is_carlito_authoring"):
		return node
	for child in node.get_children():
		var found := _find_authoring(child)
		if found != null:
			return found
	return null

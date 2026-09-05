@tool
extends RefCounted
## "Conform terrain under tiles" (palette toolbar button): flattens every
## overlapping HeightmapTerrain to the painted GridMap cells' base plane.
## Destructive-by-button, one undoable action per terrain. Tile targets
## floor-quantize (terrain never rises past base + lift); prefab targets
## round-quantize to the closest meet.

const Groups := preload("res://src/levels/base/carlito_groups.gd")

const Recipe := preload("res://kit/helpers/kit_recipe.gd")
const BrushOps := preload("res://kit/helpers/brush_ops.gd")
const SplatPaint := preload("res://kit/helpers/splat_paint.gd")
const RECIPE_DIR := "res://kit/import"

const FALLOFF := 4.0  # flatten fade-out (m) beyond the tile footprint union

## Road decks are 0.24 m tall — keep the tile lift under that.
const DEFAULT_TILE_LIFT := 0.2

const DEFAULT_PREFAB_APRON := 2.0  # flat apron (m) grown before the falloff drop

## Prefab families that flatten a terrain pad under themselves on Conform.
const CONFORM_PREFAB_FAMILIES: Array[String] = [
	"commercial-buildings", "industrial-buildings", "suburban-buildings",
	"racing-grandstands", "racing-pits", "racing-tents",
]
const CONFORM_EXCLUDE_MESHLIBS: Array[String] = []


## Per painted cell: world-space XZ footprint rect (item mesh AABB in the
## painted orientation, cached per item/orientation) + base-plane height.
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


## Entry point for the palette dock's Conform button: every terrain under
## every painted tile GridMap plus every listed prefab building.
static func conform_all(scene_root: Node, tile_lift := DEFAULT_TILE_LIFT,
		prefab_apron := DEFAULT_PREFAB_APRON) -> void:
	if scene_root == null:
		push_warning("Kit: no scene open to conform.")
		return
	var authoring := Groups.find_authoring(scene_root)
	if authoring == null:
		push_warning("Kit: no AuthoringRoot in the scene to conform under.")
		return

	var rects: Array[Rect2] = []
	var base_ys := PackedFloat32Array()
	var is_tile := PackedByteArray()

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

	var recipe_cache := {}
	for node in authoring.find_children("*", "Node3D", true, false):
		if not node.is_in_group(Groups.KIT_PIECE):
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


## Flatten every overlapping terrain to the given footprint rects + target
## heights. Tile targets floor-quantize to the terrain's 8-bit grid here so
## terrain never rises past base + lift; prefab targets take conform_rects'
## round (closest meet).
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


## World-space XZ triangles of every painted cell's actual item mesh — unlike
## footprint_rects' AABB, paint must not spill past the visible mesh.
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


## 6 = Asphalt. Wheels read ground splat through the deck within grip reach,
## so an unpainted tile street grips like the grass under it.
const DEFAULT_PAINT_CHANNEL := 6


## Entry point for the palette dock's Paint-splat button. Destructive-by-button.
static func paint_all(scene_root: Node, channel := DEFAULT_PAINT_CHANNEL) -> void:
	if scene_root == null:
		push_warning("Kit: no scene open to paint under.")
		return
	var authoring := Groups.find_authoring(scene_root)
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


static func _meshlib_excluded(grid: GridMap) -> bool:
	if grid.mesh_library == null:
		return true
	return CONFORM_EXCLUDE_MESHLIBS.has(grid.mesh_library.resource_path.get_file().get_basename())


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


## Recipe family of a placed prefab; "" if unknown. recipe_cache memoizes the
## parsed JSON per kit for the conform pass.
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

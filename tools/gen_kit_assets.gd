extends SceneTree
## Kit asset generator: turns the CC0 GLBs under
## kit/raw/ into the two authoring surfaces, driven by the kit/import/*.json recipes.
##
## Recipes are FAMILIES-DRIVEN (single source of truth): one ordered `families` list
## classifies every GLB — first matching family wins, so ordering resolves overlaps and
## patterns stay simple. Each family declares a pipeline:
##   - "palette"  -> a MeshLibrary tile (kit/palettes/<kit>.meshlib): mesh with the kit's
##                   scale + alignment baked into the verts, materials deduped per kit, plus
##                   a trimesh dev shape so UNBAKED levels drive (the bake replaces GridMap
##                   collision with the single welded drivable body). Road/tile kits only.
##   - "prefab"   -> kit/prefabs/<kit>/<name>.tscn: a KitPiece root carrying collision_mode,
##                   a scaled ExtResource instance of the GLB, and a pre-built DevCollision
##                   StaticBody3D the baker harvests into per-chunk bodies.
##   - "exclude"  -> not emitted (requires a non-empty reason string).
##
## HAND-EDITED PREFABS: an asset override `{"manual": true}` makes the generator LEAVE the
## existing .tscn alone (it still counts for the coverage gate). That is the opt-out for
## pieces whose collision was tuned by hand in the editor — the generator would otherwise
## overwrite the hand work on the next regen. Say why in the recipe's `_notes`.
##
## UIDs: generated files keep whatever `uid://` they already had on disk. Re-minting one
## breaks every level .tscn that references the file by uid ("invalid UID: ... using text
## path instead" at load), so _keep_uid re-binds the old id before each save.
##
## COVERAGE GATE: every GLB under kit/raw/<kit>/ must match exactly one family, or the
## generator FAILS listing the unaccounted names — availability can no longer be an accident
## of pattern-writing. Per-family member counts are printed (catch-all families tagged) so an
## oversized "box everything else" bucket is visible, not silent.
##
## Run after --import (needs the GLB import cache):
##   godot --headless --path . --script res://tools/gen_kit_assets.gd            # all kits
##   godot --headless --path . --script res://tools/gen_kit_assets.gd -- racing  # one kit
##
## Meshlib item ids are preserved across regens (painted GridMaps reference them); see
## KitRecipe.assign_item_ids. Classification/id/coverage logic is pure + unit-tested in
## tests/test_kit_gen.gd (kit/helpers/kit_recipe.gd).
##
## Palette items get a MeshLibrary preview from kit/thumbs/<kit>/<name>.png when present, so
## the built-in GridMap palette shows pictures. Full thumb workflow, run locally:
##   godot --path . res://tools/gen_thumbs.tscn        # windowed render -> kit/thumbs PNGs
##   godot --headless --path . --import                # import the new PNGs
##   godot --headless --path . --script res://tools/gen_kit_assets.gd   # embed the previews

const Baker := preload("res://kit/bake/level_baker.gd")
const Recipe := preload("res://kit/helpers/kit_recipe.gd")
const KIT_PIECE_SCRIPT := "res://kit/helpers/kit_piece.gd"
const RECIPE_DIR := "res://kit/import"
const PREFAB_DIR := "res://kit/prefabs"
const THUMB_DIR := "res://kit/thumbs"
const DEFAULT_PREFAB_ALIGN := "center_floor"

var _exit_code := 0


func _init() -> void:
	var only := OS.get_cmdline_user_args()
	var dir := DirAccess.open(RECIPE_DIR)
	if dir == null:
		push_error("cannot open " + RECIPE_DIR)
		quit(1)
		return
	var recipes := []
	for f in dir.get_files():
		if f.ends_with(".json") and (only.is_empty() or only.has(f.get_basename())):
			recipes.append(RECIPE_DIR.path_join(f))
	recipes.sort()
	for path in recipes:
		_run_recipe(path)
	quit(_exit_code)


func _run_recipe(recipe_path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(recipe_path))
	if parsed == null or not parsed is Dictionary:
		_error("bad recipe json: " + recipe_path)
		return
	var recipe: Dictionary = parsed
	var kit := String(recipe.get("kit", recipe_path.get_file().get_basename()))
	var source := String(recipe.get("source", ""))
	var scale := float(recipe.get("scale", 1.0))
	var palette_block: Dictionary = recipe.get("palette", {})
	var families: Array = recipe.get("families", [])

	var verrs := Recipe.validate_families(families)
	if not verrs.is_empty():
		for e in verrs:
			_error("%s: %s" % [kit, e])
		return

	var dir := DirAccess.open(source)
	if dir == null:
		_error("%s: cannot open source '%s'" % [kit, source])
		return
	var names: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".glb"):
			names.append(f.get_basename())
	names.sort()

	# --- coverage gate ---
	var c := Recipe.classify(names, families)
	if not c.unaccounted.is_empty():
		_error("%s: %d unaccounted GLB(s) — add to a family or an explicit exclude: %s" %
				[kit, c.unaccounted.size(), ", ".join(c.unaccounted)])
		return

	# --- route accounted assets by their family's pipeline ---
	var fam_by_name := {}
	for fam: Dictionary in families:
		fam_by_name[String(fam.get("name", ""))] = fam
	var default_output := String(palette_block.get("output", ""))
	var palette_groups := {}                     # meshlib output -> {items:[], overrides:{}}
	var prefab_items := {}                       # name -> {mode, ov}
	var manual := []                             # hand-edited prefabs left untouched
	for name: String in c.assignments:
		var fam: Dictionary = fam_by_name[String(c.assignments[name])]
		var pipeline := String(fam.get("pipeline", "prefab"))
		var asset_ov: Dictionary = (fam.get("assets", {}) as Dictionary).get(name, {})
		match pipeline:
			"palette":
				# A palette family may route to its own meshlib (overlay layers like
				# barriers/walls/sand paint onto a separate GridMap that overlaps roads).
				var out := String(fam.get("palette_output", default_output))
				if not palette_groups.has(out):
					palette_groups[out] = {"items": [], "overrides": {}}
				(palette_groups[out].items as Array).append(name)
				palette_groups[out].overrides[name] = asset_ov
			"prefab":
				if bool(asset_ov.get("manual", false)):
					manual.append(name)
					continue
				var mode := String(asset_ov.get("collision_mode", fam.get("collision_mode", "box")))
				# per-family scale_mul (default 1.0) multiplies the kit scale — e.g. the
				# distant-skyline low-detail buildings are authored huge for the horizon; a
				# per-asset scale_mul stacks on top (e.g. parasols halved within their family).
				var eff_scale := scale * float(fam.get("scale_mul", 1.0)) \
						* float(asset_ov.get("scale_mul", 1.0))
				prefab_items[name] = {"mode": mode, "ov": asset_ov, "scale": eff_scale}
			"exclude":
				pass

	var mats := {}  # kit-wide material dedup: material_key -> duplicated Material
	if not palette_block.is_empty():
		var outs := palette_groups.keys()
		outs.sort()
		for out: String in outs:
			var grp: Dictionary = palette_groups[out]
			(grp.items as Array).sort()
			var pb := palette_block.duplicate()
			pb["output"] = out
			_build_palette(kit, source, scale, pb, grp.items, grp.overrides, mats)
	if not prefab_items.is_empty():
		_build_prefabs(kit, source, scale, prefab_items, mats)
	_report(kit, families, c.counts)
	if not manual.is_empty():
		manual.sort()
		print("[%s] manual (hand-edited, not regenerated): %s" % [kit, ", ".join(manual)])


## Per-kit visibility line: family=count, with (catch-all) tagged so an oversized default
## bucket surfaces (the failure the coverage gate targets).
func _report(kit: String, families: Array, counts: Dictionary) -> void:
	var parts := []
	for fam: Dictionary in families:
		var name := String(fam.get("name", ""))
		var tag := " (catch-all)" if Recipe.is_catch_all(fam) else ""
		parts.append("%s=%d%s" % [name, int(counts.get(name, 0)), tag])
	print("[%s] %s" % [kit, "  ".join(parts)])


# -------------------------------------------------------------------- palette

func _build_palette(kit: String, source: String, scale: float, palette: Dictionary,
		items: Array, overrides: Dictionary, mats: Dictionary) -> void:
	var output := String(palette["output"])
	var cell: Array = palette.get("cell_size", [1, 1, 1])
	var ml := load(output) as MeshLibrary if ResourceLoader.exists(output) else MeshLibrary.new()
	if ml == null:
		ml = MeshLibrary.new()
	# preserve ids painted GridMaps reference (KitRecipe.assign_item_ids, unit-tested)
	var existing := {}
	for id in ml.get_item_list():
		existing[ml.get_item_name(id)] = id
	var ids := Recipe.assign_item_ids(existing, items)
	# prune items this meshlib no longer produces (a removed GLB, or a family rerouted to
	# another overlay meshlib) — kept items keep their ids, so innocent painted cells survive.
	var keep := {}
	for n in items:
		keep[n] = true
	for id in ml.get_item_list():
		if not keep.has(ml.get_item_name(id)):
			ml.remove_item(id)

	for name in items:
		var geo := _load_geometry(source, name)
		if geo.is_empty():
			continue
		var ov: Dictionary = overrides.get(name, {})
		var xform := _palette_xform(scale, cell, palette, ov, geo.aabb)
		var mesh := _merged_mesh(geo.pairs, xform, mats)
		var id: int = ids[name]
		if not existing.has(name):
			ml.create_item(id)
		ml.set_item_name(id, name)
		ml.set_item_mesh(id, mesh)
		ml.set_item_mesh_transform(id, Transform3D.IDENTITY)
		ml.set_item_shapes(id, [mesh.create_trimesh_shape(), Transform3D.IDENTITY])
		# built-in GridMap palette shows pictures when a thumb exists (gen_thumbs.tscn,
		# then --import). Best-effort: an un-generated/-imported thumb just leaves it blank.
		var thumb := "%s/%s/%s.png" % [THUMB_DIR, kit, name]
		if ResourceLoader.exists(thumb):
			ml.set_item_preview(id, load(thumb))
	_make_dir_for(output)
	_keep_uid(output)
	var err := ResourceSaver.save(ml, output)
	if err != OK:
		_error("%s: failed to save %s (error %d)" % [kit, output, err])


func _palette_xform(scale: float, cell: Array, palette: Dictionary, ov: Dictionary,
		aabb: AABB) -> Transform3D:
	var off := Vector3(float(ov.get("x_offset", 0)), float(ov.get("y_offset", 0)),
			float(ov.get("z_offset", 0)))
	if String(ov.get("align", palette.get("align", "raw"))) == "corner":
		# Shared +X/+Z corner lands on (+cell/2, +cell/2) — the racing-kit lattice.
		off.x += float(cell[0]) * 0.5 - aabb.end.x * scale
		off.z += float(cell[2]) * 0.5 - aabb.end.z * scale
	return Transform3D(Basis.from_scale(Vector3.ONE * scale), off)


# -------------------------------------------------------------------- prefabs

func _build_prefabs(kit: String, source: String, scale: float, items: Dictionary,
		mats: Dictionary) -> void:
	var out_dir := PREFAB_DIR.path_join(kit)
	_make_dir_for(out_dir.path_join("x"))
	var piece_script := load(KIT_PIECE_SCRIPT)
	for name: String in items:
		var mode := String(items[name].mode)
		var ov: Dictionary = items[name].ov
		var pscale := float(items[name].get("scale", scale))  # per-family scale_mul applied
		var geo := _load_geometry(source, name)
		if geo.is_empty():
			continue
		var align := String(ov.get("align", DEFAULT_PREFAB_ALIGN))
		var off := Vector3(float(ov.get("x_offset", 0)), float(ov.get("y_offset", 0)),
				float(ov.get("z_offset", 0)))
		if align == "center_floor":
			var ctr: Vector3 = geo.aabb.get_center() * pscale
			off += Vector3(-ctr.x, -geo.aabb.position.y * pscale, -ctr.z)
		var xform := Transform3D(Basis.from_scale(Vector3.ONE * pscale), off)

		var piece_root := Node3D.new()
		piece_root.name = name.to_pascal_case()
		piece_root.set_script(piece_script)
		piece_root.set("collision_mode", mode)

		var model: Node3D = (geo.scene as PackedScene).instantiate()
		model.name = "Model"
		model.transform = xform
		piece_root.add_child(model)
		model.owner = piece_root

		_add_dev_collision(piece_root, mode, geo.pairs, xform, mats)

		var packed := PackedScene.new()
		var path := out_dir.path_join(name + ".tscn")
		if packed.pack(piece_root) != OK or _save_scene_stable(packed, path) != OK:
			_error("%s: failed to save prefab %s" % [kit, path])
		piece_root.free()


func _add_dev_collision(piece_root: Node3D, mode: String, pairs: Array,
		xform: Transform3D, mats: Dictionary) -> void:
	if mode == "none":
		return
	var body := StaticBody3D.new()
	body.name = "DevCollision"
	piece_root.add_child(body)
	body.owner = piece_root
	var shapes: Array[Dictionary] = []
	match mode:
		"box":
			var aabb := _transformed_aabb(pairs, xform)
			var box := BoxShape3D.new()
			box.size = aabb.size
			shapes.append({"shape": box, "xform": Transform3D(Basis.IDENTITY, aabb.get_center())})
		"footprint":
			shapes.append(_footprint_shape(pairs, xform))
		"hull":
			shapes.append({"shape": _merged_mesh(pairs, xform, mats).create_convex_shape(true, true),
					"xform": Transform3D.IDENTITY})
		"multiconvex":
			for s in _decompose(_merged_mesh(pairs, xform, mats)):
				shapes.append({"shape": s, "xform": Transform3D.IDENTITY})
		"weld":
			# dev-play stand-in only; the bake replaces this with the welded body
			shapes.append({"shape": _merged_mesh(pairs, xform, mats).create_trimesh_shape(),
					"xform": Transform3D.IDENTITY})
	for i in shapes.size():
		var cs := CollisionShape3D.new()
		cs.name = "Shape%d" % i
		cs.shape = shapes[i].shape
		cs.transform = shapes[i].xform
		body.add_child(cs)
		cs.owner = piece_root


## Fraction of the piece's height sampled as its "base slab" for footprint mode.
const FOOTPRINT_SLAB := 0.08

## Footprint mode: the XZ area the piece actually stands on (trunk, pole, base
## plate), extruded to the piece's FULL height — a tree is then only solid where
## its trunk is, instead of hitting the car on a canopy it should pass under.
## Box vs cylinder is decided by which cross-section is tighter (a round pole
## wants the cylinder; a rail or plate wants the box), never by taste.
func _footprint_shape(pairs: Array, xform: Transform3D) -> Dictionary:
	var aabb := _transformed_aabb(pairs, xform)
	var cut := aabb.position.y + maxf(aabb.size.y * FOOTPRINT_SLAB, 0.001)
	var slab := PackedVector2Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for pair: Array in pairs:
		var full: Transform3D = xform * (pair[1] as Transform3D)
		for v in (pair[0] as Mesh).get_faces():
			var w := full * v
			if w.y > cut:
				continue
			var p := Vector2(w.x, w.z)
			slab.append(p)
			lo = lo.min(p)
			hi = hi.max(p)
	if slab.is_empty():  # degenerate (no vertex in the slab) — fall back to the full AABB
		lo = Vector2(aabb.position.x, aabb.position.z)
		hi = Vector2(aabb.end.x, aabb.end.z)
	var mid := (lo + hi) * 0.5
	var half := (hi - lo) * 0.5
	var origin := Vector3(mid.x, aabb.get_center().y, mid.y)
	var radius := half.length()
	if not slab.is_empty():
		radius = 0.0
		for p in slab:
			radius = maxf(radius, p.distance_to(mid))
	var shape: Shape3D
	if PI * radius * radius < half.x * half.y * 4.0:
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = aabb.size.y
		shape = cyl
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(half.x * 2.0, aabb.size.y, half.y * 2.0)
		shape = box
	return {"shape": shape, "xform": Transform3D(Basis.IDENTITY, origin)}


## V-HACD decomposition for open structures (grandstands, gantries, dock houses);
## falls back to a single hull if the module yields nothing.
func _decompose(mesh: ArrayMesh) -> Array:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	var settings := MeshConvexDecompositionSettings.new()
	settings.max_convex_hulls = 16
	mi.create_multiple_convex_collisions(settings)
	var shapes := []
	for child in mi.get_children():
		for cs in child.get_children():
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape != null:
				shapes.append((cs as CollisionShape3D).shape)
	root.remove_child(mi)
	mi.free()
	if shapes.is_empty():
		shapes.append(mesh.create_convex_shape(true, true))
	return shapes


# -------------------------------------------------------------------- shared

## Load one GLB and flatten it to {scene, pairs: [[Mesh, Transform3D]...], aabb}.
## The AABB is exact (face-based), in unscaled model space.
func _load_geometry(source: String, name: String) -> Dictionary:
	var path := source.path_join(name + ".glb")
	var scene := load(path) as PackedScene
	if scene == null:
		_error("cannot load " + path)
		return {}
	var inst := scene.instantiate()
	var pairs := []
	_collect_meshes(inst, Transform3D.IDENTITY, pairs)
	inst.free()
	if pairs.is_empty():
		_error("no meshes in " + path)
		return {}
	var aabb := AABB()
	var first := true
	for pair: Array in pairs:
		for v in (pair[0] as Mesh).get_faces():
			var w: Vector3 = (pair[1] as Transform3D) * v
			if first:
				aabb = AABB(w, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(w)
	return {"scene": scene, "pairs": pairs, "aabb": aabb}


func _collect_meshes(node: Node, xform: Transform3D, pairs: Array) -> void:
	var nx := xform
	if node is Node3D:
		nx = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		pairs.append([(node as MeshInstance3D).mesh, nx])
	for child in node.get_children():
		_collect_meshes(child, nx, pairs)


## Merge all mesh pairs into one ArrayMesh (one surface per distinct material),
## with `xform` (scale + alignment) applied on top of each node transform.
## Materials are deduped kit-wide and duplicated so outputs never depend on GLBs.
func _merged_mesh(pairs: Array, xform: Transform3D, mats: Dictionary) -> ArrayMesh:
	var groups := {}  # material_key -> SurfaceAccumulator
	for pair: Array in pairs:
		var mesh: Mesh = pair[0]
		var full: Transform3D = xform * (pair[1] as Transform3D)
		for si in mesh.get_surface_count():
			var mat := mesh.surface_get_material(si)
			var mk := Baker.material_key(mat)
			if not mats.has(mk):
				mats[mk] = mat.duplicate() if mat != null else null
			if not groups.has(mk):
				groups[mk] = Baker.SurfaceAccumulator.new()
			(groups[mk] as Baker.SurfaceAccumulator).append(mesh.surface_get_arrays(si), full)
	var out := ArrayMesh.new()
	var keys := groups.keys()
	keys.sort()
	for mk: String in keys:
		(groups[mk] as Baker.SurfaceAccumulator).commit(out, mats[mk])
	return out


func _transformed_aabb(pairs: Array, xform: Transform3D) -> AABB:
	var aabb := AABB()
	var first := true
	for pair: Array in pairs:
		var full: Transform3D = xform * (pair[1] as Transform3D)
		for v in (pair[0] as Mesh).get_faces():
			var w := full * v
			if first:
				aabb = AABB(w, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(w)
	return aabb


## Godot 4.6 stamps a random per-node `unique_id` into every saved scene, so a
## regeneration that changes nothing real would still churn git and flag every
## bake stale. Save, then restore the previous bytes when the only difference is
## those ids — making re-runs of this tool idempotent for unchanged pieces.
var _unique_id_re := RegEx.create_from_string(" unique_id=\\d+")


## Re-bind the uid the file already has so ResourceSaver embeds it again instead of
## minting a fresh one. Without this, every regen silently invalidates the `uid://`
## references that placed levels store, and loading a level warns per reference.
func _keep_uid(path: String) -> void:
	var id := ResourceLoader.get_resource_uid(path)
	if id == ResourceUID.INVALID_ID:
		return
	if ResourceUID.has_id(id):
		ResourceUID.set_id(id, path)
	else:
		ResourceUID.add_id(id, path)


func _save_scene_stable(packed: PackedScene, path: String) -> Error:
	var before := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	_keep_uid(path)
	var err := ResourceSaver.save(packed, path)
	if err != OK or before.is_empty():
		return err
	var after := FileAccess.get_file_as_string(path)
	if after != before and _unique_id_re.sub(after, "", true) == _unique_id_re.sub(before, "", true):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(before)
	return OK


func _make_dir_for(path: String) -> void:
	DirAccess.open("res://").make_dir_recursive(path.get_base_dir().trim_prefix("res://"))


func _error(msg: String) -> void:
	push_error(msg)
	printerr(msg)
	_exit_code = 1

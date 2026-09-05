@tool
class_name ScatterBase
extends Node3D
## Shared core for the two scatter front-ends: the seeded footprint region (ScatterRegion)
## and the hand-painted canvas (ScatterCanvas). Both store one stride-5 packed array per
## item, region-local, so the baker and dev-play consume stored transforms only and can
## never diverge from the editor. Owns the item table, stored transforms/ground hash, the
## unowned preview/dev-collision subtree, the stale-scatter guard, jitter/spacing/slope
## knobs, and ground snapping; subclasses add only how the transforms are produced.
## Bake-adjacent code (LevelBaker.BAKE_CODE_INPUTS): invisible to the dependency walk as a
## base script, so it's hashed explicitly; bump BAKER_VERSION on semantic changes.

## Stored-transform layout: 5 floats per instance (x, y, z, yaw, uniform scale), region-local.
const Groups := preload("res://src/levels/base/carlito_groups.gd")
const STRIDE := 5
const RAY_UP := 1000.0

@export var items: Array[ScatterItem] = []:
	set(value):
		items = value
		_rebuild_preview_if_ready()
		if Engine.is_editor_hint():
			update_configuration_warnings()

@export_group("Placement")
## Minimum XZ distance between any two instances (all items). 0 disables.
@export var min_spacing := 2.0
## Total random yaw range, centred on 0 (360 = any facing).
@export_range(0.0, 360.0) var yaw_jitter_deg := 360.0
## Uniform scale jitter: each instance picks a scale in [x, y].
@export var scale_range := Vector2(0.85, 1.15)
## Instances landing on ground steeper than this are dropped.
@export_range(0.0, 89.0) var max_slope_deg := 30.0
@export_group("")

## The only thing dev-play and the baker read; STRIDE floats/instance, region-local. Hidden
## from the inspector — regenerated or painted, never hand-edited.
@export_storage var stored_transforms: Array[PackedFloat32Array] = []:
	set(value):
		stored_transforms = value
		_rebuild_preview_if_ready()
		if Engine.is_editor_hint() and not _live_editing:
			_refresh_stale()
## ground_hash() when the transforms were snapped — the stale guard.
@export_storage var stored_ground_hash := "":
	set(value):
		stored_ground_hash = value
		if Engine.is_editor_hint():
			_refresh_stale()

## Stale-guard recovery: re-snap every Y to current ground without re-rolling/re-painting.
## Instances with no ground under them are dropped. Editor-only, undoable.
@warning_ignore("unused_private_class_variable")
@export_tool_button("Re-snap to ground") var _resnap_action := _resnap_to_ground

var _stale := false
var _stale_accum := 0.0
var _live_editing := false


func _init() -> void:
	add_to_group(Groups.SCATTER)


## Bracket a live brush stroke: skips the per-assignment stale recompute until end_live_edit.
func begin_live_edit() -> void:
	_live_editing = true


func end_live_edit() -> void:
	_live_editing = false
	if Engine.is_editor_hint():
		_refresh_stale()


func _ready() -> void:
	_rebuild_preview()
	if Engine.is_editor_hint():
		_refresh_stale()
		update_configuration_warnings()
	else:
		set_process(false)


# --------------------------------------------------------------- stored decode

static func stored_transform(flat: PackedFloat32Array, index: int) -> Transform3D:
	var o := index * STRIDE
	var xf_basis := Basis(Vector3.UP, flat[o + 3]).scaled(Vector3.ONE * flat[o + 4])
	return Transform3D(xf_basis, Vector3(flat[o], flat[o + 1], flat[o + 2]))


static func stored_count(flat: PackedFloat32Array) -> int:
	@warning_ignore("integer_division")
	return flat.size() / STRIDE


static func spacing_ok(p: Vector2, spacing: float, grid: Dictionary) -> bool:
	var cell := Vector2i(floori(p.x / spacing), floori(p.y / spacing))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := cell + Vector2i(dx, dz)
			if not grid.has(key):
				continue
			for q: Vector2 in grid[key]:
				if p.distance_to(q) < spacing:
					return false
	return true


# ------------------------------------------------------------- ground hashing

## Hash of every terrain heightmap under `root`: image bytes plus name/position/size/
## height amplitude. Off-tree safe, so the baker can call it on an untreed level.
static func ground_hash(root: Node) -> String:
	var terrains: Array[Node] = []
	find_terrains_under(root, terrains)
	if terrains.is_empty():
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for t in terrains:
		var header := "%s|%s|%s|%s" % [t.name, var_to_str((t as Node3D).position),
				var_to_str(t.get("terrain_size")), var_to_str(t.get("height"))]
		ctx.update(header.to_utf8_buffer())
		var tex: Texture2D = t.get("heightmap")
		var img := tex.get_image() if tex != null else null
		if img == null:
			ctx.update("null".to_utf8_buffer())
			continue
		if img.is_compressed():
			img = img.duplicate()
			img.decompress()
		ctx.update(("%dx%d" % [img.get_width(), img.get_height()]).to_utf8_buffer())
		ctx.update(img.get_data())
	return ctx.finish().hex_encode()


static func find_terrains_under(node: Node, out: Array[Node]) -> void:
	if node is Node3D and node.has_method("height_at") and node.has_method("contains_xz"):
		out.append(node)
	for child in node.get_children():
		find_terrains_under(child, out)


## Ground snap fallback chain: physics ray straight down -> HeightmapTerrain bilinear
## sample -> empty (no Y=0 fallback). Returns {position, normal} or {}.
static func snap_ground(space: PhysicsDirectSpaceState3D, terrains: Array[Node],
		world: Vector3) -> Dictionary:
	if space != null:
		var from := Vector3(world.x, world.y + RAY_UP, world.z)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RAY_UP * 2.0)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return {"position": hit.position, "normal": hit.normal}
	for t in terrains:
		if t.contains_xz(world):
			var y: float = t.height_at(world)
			var e := 0.5
			var dx: float = (t.height_at(world + Vector3(e, 0, 0))
					- t.height_at(world - Vector3(e, 0, 0))) / (2.0 * e)
			var dz: float = (t.height_at(world + Vector3(0, 0, e))
					- t.height_at(world - Vector3(0, 0, e))) / (2.0 * e)
			return {"position": Vector3(world.x, y, world.z),
					"normal": Vector3(-dx, 1.0, -dz).normalized()}
	return {}


# ----------------------------------------------------------- item mesh building

## Merge a prefab's render meshes into one ArrayMesh, one surface per material. Duck-
## called by the baker, which swaps in deduplicated materials so the baked scene never
## references kit resources.
static func build_item_mesh(prefab_root: Node) -> ArrayMesh:
	var groups := {}   # material_key -> SurfaceAccumulator
	var mats := {}     # material_key -> Material
	var order: Array[String] = []
	_accumulate_item_meshes(prefab_root, Transform3D.IDENTITY, groups, mats, order)
	var mesh := ArrayMesh.new()
	for mk in order:
		(groups[mk] as LevelBaker.SurfaceAccumulator).commit(mesh, mats[mk])
	return mesh


static func _accumulate_item_meshes(node: Node, xform: Transform3D, groups: Dictionary,
		mats: Dictionary, order: Array[String]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var src := (node as MeshInstance3D).mesh
		for si in src.get_surface_count():
			var mat := src.surface_get_material(si)
			var mk := LevelBaker.material_key(mat)
			if not groups.has(mk):
				groups[mk] = LevelBaker.SurfaceAccumulator.new()
				mats[mk] = mat
				order.append(mk)
			(groups[mk] as LevelBaker.SurfaceAccumulator).append(src.surface_get_arrays(si), xform)
	for child in node.get_children():
		var cxform := xform
		if child is Node3D:
			cxform = xform * (child as Node3D).transform
		_accumulate_item_meshes(child, cxform, groups, mats, order)


static func shape_entries(prefab_root: Node) -> Array:
	var out: Array = []
	_gather_shapes(prefab_root, Transform3D.IDENTITY, out)
	return out


static func _gather_shapes(node: Node, xform: Transform3D, out: Array) -> void:
	if node is CollisionShape3D and (node as CollisionShape3D).shape != null:
		out.append([(node as CollisionShape3D).shape, xform])
	for child in node.get_children():
		var cxform := xform
		if child is Node3D:
			cxform = xform * (child as Node3D).transform
		_gather_shapes(child, cxform, out)


# --------------------------------------------------- preview / dev-play rendering

func _rebuild_preview_if_ready() -> void:
	if is_inside_tree():
		_rebuild_preview()


## Rebuild the unowned preview: one MultiMeshInstance3D per item; dev-play also gets a
## StaticBody3D per collision-on item. Editor gets visuals only, so its raycasts miss us.
func _rebuild_preview() -> void:
	var old := get_node_or_null(^"Preview")
	if old != null:
		old.free()
	var preview := Node3D.new()
	preview.name = "Preview"
	add_child(preview)
	for i in items.size():
		var item := items[i]
		if item == null or item.prefab == null or i >= stored_transforms.size():
			continue
		var flat := stored_transforms[i]
		var count := stored_count(flat)
		if count == 0:
			continue
		var template := item.prefab.instantiate()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = build_item_mesh(template)
		mm.instance_count = count
		for j in count:
			mm.set_instance_transform(j, stored_transform(flat, j))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Item%d" % i
		mmi.multimesh = mm
		preview.add_child(mmi)

		# Mirrors LevelBaker._collect_scatter: only box/footprint/hull/multiconvex get dev collision.
		var mode := "none"
		if template.is_in_group(Groups.KIT_PIECE):
			mode = String(template.get("collision_mode"))
		if not Engine.is_editor_hint() and item.collision and mode in ["box", "footprint", "hull", "multiconvex"]:
			var entries := shape_entries(template)
			if not entries.is_empty():
				var body := StaticBody3D.new()
				body.name = "Item%dCollision" % i
				preview.add_child(body)
				for j in count:
					var inst := stored_transform(flat, j)
					for entry: Array in entries:
						var cs := CollisionShape3D.new()
						cs.shape = entry[0]
						cs.transform = inst * (entry[1] as Transform3D)
						body.add_child(cs)
		template.free()


func _find_authoring_ancestor() -> Node:
	return Groups.authoring_ancestor(self)


# ------------------------------------------------------------------ re-snap

func _resnap_to_ground() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var root := owner if owner != null else self
	var terrains: Array[Node] = []
	find_terrains_under(root, terrains)
	var space := get_world_3d().direct_space_state
	var to_world := global_transform
	var world_to_local := to_world.affine_inverse()
	var before := stored_transforms   # kept rows rebuilt below, so this stays a valid undo value
	var after: Array[PackedFloat32Array] = []
	var dropped := 0
	for flat in stored_transforms:
		var kept := PackedFloat32Array()
		for j in stored_count(flat):
			var o := j * STRIDE
			var world := to_world * Vector3(flat[o], flat[o + 1], flat[o + 2])
			var hit := snap_ground(space, terrains, world)
			if hit.is_empty():
				dropped += 1
				continue
			var entry := flat.slice(o, o + STRIDE)
			var local := world_to_local * (hit.position as Vector3)
			entry[0] = local.x
			entry[1] = local.y
			entry[2] = local.z
			kept.append_array(entry)
		after.append(kept)
	if dropped > 0:
		push_warning("Scatter '%s': %d instance(s) had no ground under them and were dropped." % [name, dropped])
	var new_hash := ground_hash(root)
	if after == before and new_hash == stored_ground_hash:
		print("%s: already snapped to the current ground." % name)
		return
	var undo_redo = Engine.get_singleton(&"EditorInterface").get_editor_undo_redo()
	undo_redo.create_action("Re-snap scatter '%s' to ground" % name)
	undo_redo.add_do_property(self, &"stored_transforms", after)
	undo_redo.add_do_property(self, &"stored_ground_hash", new_hash)
	undo_redo.add_undo_property(self, &"stored_transforms", before)
	undo_redo.add_undo_property(self, &"stored_ground_hash", stored_ground_hash)
	undo_redo.commit_action()


# ----------------------------------------------------------- stale-scatter guard

## Editor-only slow poll: recompute the ground hash every few seconds (sculpting has no
## signal to react to).
func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	_stale_accum += delta
	if _stale_accum < 3.0:
		return
	_stale_accum = 0.0
	_refresh_stale()


func _refresh_stale() -> void:
	var now_stale := _compute_stale()
	if now_stale != _stale:
		_stale = now_stale
		update_configuration_warnings()


func _compute_stale() -> bool:
	var total := 0
	for flat in stored_transforms:
		total += stored_count(flat)
	if total == 0:
		return false
	return stored_ground_hash != ground_hash(owner if owner != null else self)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if items.is_empty():
		warnings.append("No items. In Items, Add Element, then open the element's dropdown and pick 'New ScatterItem' (it is a Resource — prefabs are dragged into ITS 'prefab' slot, not into the array).")
	if _stale:
		warnings.append("Terrain changed since these instances were placed — Regenerate or Re-snap to ground, then re-bake the level.")
	warnings.append_array(_extra_warnings())
	return warnings


func _extra_warnings() -> PackedStringArray:
	return PackedStringArray()

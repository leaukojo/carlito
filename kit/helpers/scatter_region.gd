@tool
class_name ScatterRegion
extends ScatterBase
## Seeded procedural fill region. Placed under the level's
## AuthoringRoot; fills a box/polygon footprint with weighted kit prefabs. The front-end that
## PRODUCES stored transforms by regeneration; everything downstream (preview, dev collision,
## bake, stale guard) lives in ScatterBase and is shared with the hand-painted ScatterCanvas.
##
## The stored-transform contract (non-negotiable): expansion happens exactly once, in
## the editor Regenerate button — it runs the pure seeded placement, ground-snaps every
## instance against the live edited scene, and STORES the final region-local transforms in the
## scene. The baker and dev-play only ever consume the stored transforms — no raycast, no
## expansion, no physics outside this file's editor path — so editor and bake can never
## diverge, and the CI hash story is just "transforms live in the .tscn".
##
## Pure placement logic (rejection sampling, area) is static and unit-tested in
## tests/test_scatter.gd; the shared mesh/shape/hash statics live on ScatterBase.

## Rejection-sampling budget: attempts per requested instance before giving up (dense + tightly
## spaced regions fill to less than the density target).
const ATTEMPTS_PER_TARGET := 8

# Footprint setters poke the editor gizmo (addons/carlito_kit/scatter_gizmo.gd draws the border
# while the node is selected); update_gizmos is a no-op in game.
@export_enum("box", "polygon") var footprint_kind := "box":
	set(value):
		footprint_kind = value
		update_gizmos()
## Box footprint: full X/Z extent, centred on the node origin (region-local).
@export var box_size := Vector2(32, 32):
	set(value):
		box_size = value
		update_gizmos()
## Polygon footprint: region-local XZ vertices (CW or CCW, may be concave).
@export var polygon := PackedVector2Array():
	set(value):
		polygon = value
		update_gizmos()

@export_group("Placement")
## Target instances per square metre (spacing may cap the reachable count).
@export var density := 0.05
@export var placement_seed := 0
@export_group("")

@warning_ignore("unused_private_class_variable")
@export_tool_button("Regenerate (expands + snaps + stores)") var _regen_action := _regenerate


# --------------------------------------------------------------- pure placement

## Deterministic seeded placement (pure static, unit-tested): rejection-sample points into the
## polygon with a min-spacing guarantee, assigning each accepted point a weighted item, a yaw
## and a uniform scale. Same params = bit-identical output.
## params: polygon (PackedVector2Array), density, min_spacing, seed,
##         weights (PackedFloat32Array, one per item), yaw_jitter_deg, scale_min, scale_max.
## Returns one PackedFloat32Array per item, 4 floats per instance (x, z, yaw, scale).
static func generate_placements(params: Dictionary) -> Array[PackedFloat32Array]:
	var weights: PackedFloat32Array = params.get("weights", PackedFloat32Array())
	var out: Array[PackedFloat32Array] = []
	for i in weights.size():
		out.append(PackedFloat32Array())
	var poly: PackedVector2Array = params.get("polygon", PackedVector2Array())
	var area := polygon_area(poly)
	var density_v := float(params.get("density", 0.0))
	if weights.is_empty() or area <= 0.0 or density_v <= 0.0:
		return out
	var total_weight := 0.0
	for w in weights:
		total_weight += maxf(w, 0.0)
	if total_weight <= 0.0:
		return out

	var spacing := float(params.get("min_spacing", 0.0))
	var yaw_jitter := deg_to_rad(float(params.get("yaw_jitter_deg", 360.0)))
	var scale_min := float(params.get("scale_min", 1.0))
	var scale_max := float(params.get("scale_max", 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(params.get("seed", 0))

	var bmin := poly[0]
	var bmax := poly[0]
	for p in poly:
		bmin = bmin.min(p)
		bmax = bmax.max(p)

	var target := int(round(area * density_v))
	var accepted := 0
	# Spatial hash with cell = spacing: any point closer than `spacing` must sit in one of the
	# 3x3 neighbouring cells, so the check is O(1) per attempt.
	var grid := {}
	for _attempt in target * ATTEMPTS_PER_TARGET:
		if accepted >= target:
			break
		var p := Vector2(rng.randf_range(bmin.x, bmax.x), rng.randf_range(bmin.y, bmax.y))
		if not Geometry2D.is_point_in_polygon(p, poly):
			continue
		if spacing > 0.0 and not spacing_ok(p, spacing, grid):
			continue
		var idx := weights.size() - 1
		var pick := rng.randf() * total_weight
		for i in weights.size():
			pick -= maxf(weights[i], 0.0)
			if pick <= 0.0:
				idx = i
				break
		var yaw := rng.randf_range(-0.5, 0.5) * yaw_jitter
		var scl := rng.randf_range(scale_min, scale_max)
		out[idx].append_array(PackedFloat32Array([p.x, p.y, yaw, scl]))
		if spacing > 0.0:
			var key := Vector2i(floori(p.x / spacing), floori(p.y / spacing))
			if not grid.has(key):
				grid[key] = PackedVector2Array()
			grid[key].append(p)
		accepted += 1
	return out


## Deterministic world-anchored lattice fill (pure static, unit-tested): one candidate per
## lattice cell whose centre falls inside `polygon`. The lattice is anchored to the world
## origin, so two overlapping or abutting fills produce ONE continuous grid — no seam, no
## double row. Item pick / yaw / scale are seeded per cell (integer cell coords + seed), so
## re-filling the same ground is idempotent.
## params: polygon (PackedVector2Array), step (Vector2), seed,
##         weights (PackedFloat32Array, one per item), yaw_jitter_deg, scale_min, scale_max.
## Returns one PackedFloat32Array per item, 4 floats per instance (x, z, yaw, scale) —
## same shape as generate_placements.
static func generate_grid_placements(params: Dictionary) -> Array[PackedFloat32Array]:
	var weights: PackedFloat32Array = params.get("weights", PackedFloat32Array())
	var out: Array[PackedFloat32Array] = []
	for i in weights.size():
		out.append(PackedFloat32Array())
	var poly: PackedVector2Array = params.get("polygon", PackedVector2Array())
	var step: Vector2 = params.get("step", Vector2.ONE)
	if weights.is_empty() or poly.size() < 3 or step.x <= 0.0 or step.y <= 0.0:
		return out
	var total_weight := 0.0
	for w in weights:
		total_weight += maxf(w, 0.0)
	if total_weight <= 0.0:
		return out

	var base_seed := int(params.get("seed", 0))
	var yaw_jitter := deg_to_rad(float(params.get("yaw_jitter_deg", 0.0)))
	var scale_min := float(params.get("scale_min", 1.0))
	var scale_max := float(params.get("scale_max", 1.0))

	var bmin := poly[0]
	var bmax := poly[0]
	for p in poly:
		bmin = bmin.min(p)
		bmax = bmax.max(p)
	# Cell i has its centre at (i + 0.5) * step: walk every cell index whose centre can land
	# inside the AABB.
	var i0 := floori(bmin.x / step.x)
	var i1 := ceili(bmax.x / step.x)
	var j0 := floori(bmin.y / step.y)
	var j1 := ceili(bmax.y / step.y)

	var rng := RandomNumberGenerator.new()
	for ci in range(i0, i1 + 1):
		for cj in range(j0, j1 + 1):
			var p := Vector2((float(ci) + 0.5) * step.x, (float(cj) + 0.5) * step.y)
			if not Geometry2D.is_point_in_polygon(p, poly):
				continue
			rng.seed = cell_seed(ci, cj, base_seed)
			var idx := weights.size() - 1
			var pick := rng.randf() * total_weight
			for i in weights.size():
				pick -= maxf(weights[i], 0.0)
				if pick <= 0.0:
					idx = i
					break
			var yaw := rng.randf_range(-0.5, 0.5) * yaw_jitter
			var scl := rng.randf_range(scale_min, scale_max)
			out[idx].append_array(PackedFloat32Array([p.x, p.y, yaw, scl]))
	return out


## Stable per-cell RNG seed for the grid sampler (order-independent, so a cell rolls the same
## item/yaw/scale no matter which fill visits it first).
static func cell_seed(ci: int, cj: int, base_seed: int) -> int:
	return hash(Vector3i(ci, cj, base_seed))


## Shoelace area of a simple polygon (absolute; winding-agnostic).
static func polygon_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var twice := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		twice += a.x * b.y - b.x * a.y
	return absf(twice) * 0.5


# ------------------------------------------------------- Regenerate (editor only)

## The one expansion site: pure placement -> ground snap against the live edited
## scene -> slope filter -> store region-local transforms + the ground hash, all as one
## undoable action.
func _regenerate() -> void:
	if not Engine.is_editor_hint():
		return
	if _find_authoring_ancestor() == null:
		push_warning("ScatterRegion: place the region under the level's AuthoringRoot before regenerating.")
		return
	if items.is_empty():
		push_warning("ScatterRegion: add at least one ScatterItem first.")
		return

	var placements := generate_placements(build_params())
	var level_root := owner if owner != null else self
	var terrains: Array[Node] = []
	find_terrains_under(level_root, terrains)
	var space := get_world_3d().direct_space_state
	var cos_max := cos(deg_to_rad(max_slope_deg))
	var inv := global_transform.affine_inverse()

	var new_stored: Array[PackedFloat32Array] = []
	var dropped := 0
	for i in placements.size():
		var flat := placements[i]
		var stored := PackedFloat32Array()
		@warning_ignore("integer_division")
		for j in flat.size() / 4:
			var o := j * 4
			var world := global_transform * Vector3(flat[o], 0.0, flat[o + 1])
			var hit := snap_ground(space, terrains, world)
			if hit.is_empty() or (hit.normal as Vector3).y < cos_max:
				dropped += 1
				continue
			var local: Vector3 = inv * (hit.position as Vector3)
			stored.append_array(PackedFloat32Array(
					[local.x, local.y, local.z, flat[o + 2], flat[o + 3]]))
		new_stored.append(stored)

	var new_hash := ground_hash(level_root)
	# Untyped: EditorUndoRedoManager is editor-only, and a type annotation would make this
	# @tool script fail to parse in exported builds. It is stripped from exports today (always
	# under AuthoringRoot), but keep it export-safe so it never becomes a runtime landmine.
	var undo_redo = Engine.get_singleton(&"EditorInterface").get_editor_undo_redo()
	undo_redo.create_action("Regenerate scatter '%s'" % name)
	undo_redo.add_do_property(self, &"stored_transforms", new_stored)
	undo_redo.add_undo_property(self, &"stored_transforms", stored_transforms)
	undo_redo.add_do_property(self, &"stored_ground_hash", new_hash)
	undo_redo.add_undo_property(self, &"stored_ground_hash", stored_ground_hash)
	undo_redo.commit_action()

	var total := 0
	for flat in stored_transforms:
		total += stored_count(flat)
	print("ScatterRegion '%s': stored %d instances (%d dropped by slope/ground)" %
			[name, total, dropped])


## Footprint + knobs -> generate_placements params. Public so the fixture builder can expand a
## region programmatically (flat ground, no editor).
func build_params() -> Dictionary:
	var weights := PackedFloat32Array()
	for item in items:
		weights.append(item.weight if item != null and item.prefab != null else 0.0)
	return {
		"polygon": footprint_polygon(),
		"density": density,
		"min_spacing": min_spacing,
		"seed": placement_seed,
		"weights": weights,
		"yaw_jitter_deg": yaw_jitter_deg,
		"scale_min": scale_range.x,
		"scale_max": scale_range.y,
	}


## The footprint as a region-local XZ polygon (box unifies into the polygon path). The gizmo
## keys on this method's presence, so only ScatterRegion (not ScatterCanvas) draws a border.
func footprint_polygon() -> PackedVector2Array:
	if footprint_kind == "polygon":
		return polygon
	var hx := box_size.x * 0.5
	var hz := box_size.y * 0.5
	return PackedVector2Array([
		Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)])

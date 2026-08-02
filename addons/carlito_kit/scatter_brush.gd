@tool
extends "res://addons/carlito_kit/brush_chassis.gd"
## Scatter brush. Rides the shared brush chassis; adds the
## scatter-specific half: PAINT lays instances into a selected ScatterCanvas density-per-stroke,
## ERASE removes them within the brush radius. The second front-end on the scatter core —
## it reuses the seeded sampler (ScatterRegion.generate_placements), the jitter knobs and ground
## snapping (ScatterBase), and the canvas's pure erase, so painted and regenerated scatter share
## one placement philosophy and one bake path.
##
## Editor-only by construction (editor/runtime split): the brush mutates the canvas's
## stored transforms (authored, serialized content) live during a stroke for feedback, and
## commits ONE undoable stored_transforms swap at stroke end (whole-array, like Regenerate — the
## arrays are small). No new runtime or baker code: the canvas is a ScatterBase, so it renders
## and bakes exactly as a ScatterRegion does.

const ScatterBaseScript := preload("res://kit/helpers/scatter_base.gd")

enum { OFF, PAINT, ERASE, RECT }

var mode := OFF

var _undo: EditorUndoRedoManager
var _canvas: ScatterCanvas = null

# Active-stroke state.
var _before: Array[PackedFloat32Array] = []   # snapshot for undo
var _before_hash := ""
var _work: Array[PackedFloat32Array] = []      # the array we mutate; pushed to the canvas at end
var _spacing_grid := {}                        # world XZ spatial hash (paint spacing)
var _cell_taken := {}                          # grid pattern: occupied lattice cells (Vector2i)
var _dab_seed := 0
var _dirty := false

# Two-click rect fill state, live between the first and second click (mirrors the terrain
# brush's ramp): the stored first corner.
var _rect_armed := false
var _rect_a := Vector3.ZERO

# Stroke-scoped live preview: the merged per-item mesh is built ONCE at stroke begin and reused
# every dab (index-matched to the canvas's items; null where an item has no prefab). Each dab
# only rewrites the MultiMesh instance transforms/count — no prefab re-instantiate, no re-merge.
var _live_mms: Array[MultiMesh] = []


func _init(undo: EditorUndoRedoManager) -> void:
	_undo = undo


# ------------------------------------------------------------------ plugin API

func set_target(canvas: ScatterCanvas) -> void:
	if canvas == _canvas:
		return
	_free_cursor()  # cursor lives under the canvas; a new target needs a new one
	_rect_armed = false  # a stored corner belongs to the canvas it was clicked on
	if is_instance_valid(_canvas):
		_canvas.end_live_edit()  # clear the flag if we swap targets mid-stroke
	_reset_stroke()
	_canvas = canvas


func set_mode(m: int) -> void:
	mode = m
	_rect_armed = false
	if mode == OFF:
		_hide_cursor()


func teardown() -> void:
	_free_cursor()
	_canvas = null


# ------------------------------------------------------------------ chassis virtuals

func _target_valid() -> bool:
	return Engine.is_editor_hint() and mode != OFF and is_instance_valid(_canvas)


## Rect cancel rides on top of the chassis loop, exactly like the terrain brush's ramp: Esc
## drops the stored corner and is consumed; right-click cancels too but is NOT consumed, so the
## editor still gets it for freelook.
func handle_input(camera: Camera3D, event: InputEvent) -> bool:
	if _rect_armed and _target_valid():
		if event is InputEventKey and event.pressed \
				and (event as InputEventKey).keycode == KEY_ESCAPE:
			_rect_armed = false
			return true
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			_rect_armed = false
	return super(camera, event)


func _cursor_parent() -> Node3D:
	return _canvas


func _cursor_color() -> Color:
	match mode:
		PAINT: return Color(0.4, 1.0, 0.45)
		RECT: return Color(0.5, 0.75, 1.0)
		_: return Color(1.0, 0.45, 0.4)


## In RECT mode the cursor is the pending rectangle (first corner -> cursor) plus a small
## marker ring at the stored corner; before the first click it is just the marker-less ring.
## Separate strips: one LINE_STRIP would join them with a stray chord.
func _cursor_strips(center: Vector3) -> Array[PackedVector3Array]:
	if mode != RECT:
		return super(center)
	var strips: Array[PackedVector3Array] = []
	if _rect_armed:
		strips.append(_rect_outline(_rect_a, center))
		strips.append(_small_ring(_rect_a))
	else:
		strips.append(_small_ring(center))
	return strips


## Closed XZ rectangle spanned by two world points, drawn flat at the higher of the two Ys so
## it stays readable when a corner sinks into a slope.
static func _rect_outline(a: Vector3, b: Vector3) -> PackedVector3Array:
	var y := maxf(a.y, b.y) + 0.25
	var x0 := minf(a.x, b.x)
	var x1 := maxf(a.x, b.x)
	var z0 := minf(a.z, b.z)
	var z1 := maxf(a.z, b.z)
	return PackedVector3Array([
		Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1),
		Vector3(x0, y, z1), Vector3(x0, y, z0)])


static func _small_ring(center: Vector3, r := 0.5) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in 17:
		var ang := TAU * float(i) / 16.0
		pts.append(center + Vector3(cos(ang) * r, 0.1, sin(ang) * r))
	return pts


## Ground point under the cursor: edited-scene physics ray -> terrain sample -> Y=0 plane (the
## shared fallback chain — a click never dead-drops). Returns a world Vector3.
func _project(camera: Camera3D, mouse: Vector2) -> Variant:
	if not is_instance_valid(_canvas):
		return null
	var origin := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var space := _canvas.get_world_3d().direct_space_state
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 100000.0)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return hit.position
	for t in _terrains():
		var xz: Variant = _ray_plane(origin, dir, (t as Node3D).global_position.y)
		if xz != null and t.contains_xz(xz):
			return Vector3((xz as Vector3).x, t.height_at(xz), (xz as Vector3).z)
	return _ray_plane(origin, dir, 0.0)


# ------------------------------------------------------------------ rect fill (two clicks)

func _click_mode() -> bool:
	return mode == RECT


func _click(center: Vector3) -> void:
	if not _rect_armed:
		_rect_a = center
		_rect_armed = true
		return
	_rect_armed = false
	_fill_rect(_rect_a, center)


## Lay the whole rectangle as ONE undoable action by running the normal stroke path once:
## begin (snapshot + live preview) -> a single polygon fill -> end (commit).
func _fill_rect(a: Vector3, b: Vector3) -> void:
	if not is_instance_valid(_canvas):
		return
	var x0 := minf(a.x, b.x)
	var x1 := maxf(a.x, b.x)
	var z0 := minf(a.z, b.z)
	var z1 := maxf(a.z, b.z)
	if x1 - x0 < 0.01 or z1 - z0 < 0.01:
		return
	var rect := PackedVector2Array([
		Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])
	_stroke_begin(a)
	# Ray origin Y: above both corners, so the down-ray finds ground at any height under the
	# rectangle (the rect selects an XZ area, never a height band).
	var probe_y := maxf(a.y, b.y)
	if _fill_polygon(rect, probe_y, func(_px: float, _pz: float): return true) > 0:
		_update_live_preview()
		_dirty = true
	_stroke_end()


# ------------------------------------------------------------------ stroke

func _stroke_begin(_center: Vector3) -> void:
	_dirty = false
	if not is_instance_valid(_canvas):
		return
	_before = _snapshot(_canvas.stored_transforms)
	_before_hash = _canvas.stored_ground_hash
	_work = _snapshot(_canvas.stored_transforms)
	# Pad to one array per item so a fresh canvas (empty stored_transforms) can be painted.
	while _work.size() < _canvas.items.size():
		_work.append(PackedFloat32Array())
	_rebuild_occupancy()
	_canvas.begin_live_edit()  # suppress the per-assignment stale recompute for the whole stroke
	_setup_live_preview()


func _stroke_apply(center: Vector3) -> void:
	if not is_instance_valid(_canvas):
		return
	# Only touch anything when a dab actually changes content — a paint dab that snaps nothing,
	# or an erase over empty ground, must not commit a no-op undo.
	var changed := false
	if mode == PAINT:
		changed = _paint_dab(center) > 0
	else:
		var before_total := _total(_work)
		_work = ScatterCanvas.erase_within(_work, _canvas.global_transform, center, radius)
		changed = _total(_work) < before_total
	if changed:
		_update_live_preview()  # cheap: rewrite MultiMesh transforms/count, no re-merge
		_dirty = true


func _stroke_end() -> void:
	if not is_instance_valid(_canvas):
		_reset_stroke()
		return
	if not _dirty:
		_canvas.end_live_edit()  # nothing changed; the live preview already matches the canvas
		_reset_stroke()
		return
	# Commit the accumulated work to the canvas ONCE: the stored_transforms setter rebuilds the
	# authoritative preview (freeing our stroke-scoped one) with stale still suppressed, then
	# end_live_edit does the single stale recompute for the whole stroke.
	var final := _work
	var level_root: Node = _canvas.owner if _canvas.owner != null else _canvas
	var new_hash := ScatterBaseScript.ground_hash(level_root)
	_canvas.stored_ground_hash = new_hash
	_canvas.stored_transforms = final
	_canvas.end_live_edit()

	var scene_root := EditorInterface.get_edited_scene_root()
	var label := "Erase scatter"
	if mode == PAINT:
		label = "Paint scatter"
	elif mode == RECT:
		label = "Fill scatter rect"
	_undo.create_action(label, UndoRedo.MERGE_DISABLE, scene_root)
	_undo.add_do_property(_canvas, &"stored_transforms", final)
	_undo.add_undo_property(_canvas, &"stored_transforms", _before)
	_undo.add_do_property(_canvas, &"stored_ground_hash", new_hash)
	_undo.add_undo_property(_canvas, &"stored_ground_hash", _before_hash)
	_undo.commit_action(false)  # edits are already live — don't re-run the do now
	_reset_stroke()


func _reset_stroke() -> void:
	_before = []
	_work = []
	_live_mms = []


# --------------------------------------------------------- stroke-scoped live preview

## Build the stroke's preview once: one MultiMesh per item over its merged mesh, under the
## canvas's "Preview" node (named to match ScatterBase._rebuild_preview, so the stroke-end
## stored_transforms assignment cleanly frees this and rebuilds the authoritative version).
func _setup_live_preview() -> void:
	var old := _canvas.get_node_or_null(^"Preview")
	if old != null:
		old.free()
	var preview := Node3D.new()
	preview.name = "Preview"
	_canvas.add_child(preview)  # unowned on purpose -> never serialized
	_live_mms = []
	for i in _canvas.items.size():
		var item: Resource = _canvas.items[i]
		if item == null or item.get("prefab") == null:
			_live_mms.append(null)
			continue
		var template: Node = (item.get("prefab") as PackedScene).instantiate()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ScatterBaseScript.build_item_mesh(template)
		template.free()
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Item%d" % i
		mmi.multimesh = mm
		preview.add_child(mmi)
		_live_mms.append(mm)
	_update_live_preview()


## Per-dab update: rewrite each item's MultiMesh instance count + transforms from `_work`. No
## prefab instancing or mesh merging — the meshes were built once in _setup_live_preview.
func _update_live_preview() -> void:
	for i in _live_mms.size():
		var mm: MultiMesh = _live_mms[i]
		if mm == null or i >= _work.size():
			continue
		var flat := _work[i]
		var count := ScatterBaseScript.stored_count(flat)
		mm.instance_count = count
		for j in count:
			mm.set_instance_transform(j, ScatterBaseScript.stored_transform(flat, j))


# ------------------------------------------------------------------ painting

## Lay one dab: fill the world-XZ square bounding the brush disc, keeping only the candidates
## inside the disc. Region-local transforms are appended to `_work`. Returns the number of
## instances actually placed (0 = nothing snapped, so the caller skips a no-op commit).
func _paint_dab(center: Vector3) -> int:
	var cx := center.x
	var cz := center.z
	var r2 := radius * radius
	var square := PackedVector2Array([
		Vector2(cx - radius, cz - radius), Vector2(cx + radius, cz - radius),
		Vector2(cx + radius, cz + radius), Vector2(cx - radius, cz + radius)])
	return _fill_polygon(square, center.y,
			func(px: float, pz: float): return (px - cx) * (px - cx) + (pz - cz) * (pz - cz) <= r2)


## The one placement path, shared by the disc dab and the rect fill, in both patterns: sample
## candidates over `poly` (random rejection sampler or world-anchored lattice, per the canvas's
## paint_pattern), drop the ones `keep` rejects, enforce the min-spacing hash / lattice-cell
## occupancy (both carry prior dabs AND existing instances, so density is even regardless of
## stroke speed and strokes never double up a cell), ground-snap, slope-filter, and append the
## region-local transform to `_work`. `probe_y` is only the ray start height — snapping is a
## straight-down ray, so the area is filled at whatever height the ground is.
func _fill_polygon(poly: PackedVector2Array, probe_y: float, keep: Callable) -> int:
	var weights := PackedFloat32Array()
	var any := false
	for item in _canvas.items:
		var w: float = item.weight if item != null and item.get("prefab") != null else 0.0
		weights.append(w)
		any = any or w > 0.0
	if not any:
		return 0

	var grid_mode: bool = _canvas.paint_pattern == "grid"
	var step: Vector2 = _canvas.grid_step
	var candidates: Array[PackedFloat32Array]
	if grid_mode:
		candidates = ScatterRegion.generate_grid_placements({
			"polygon": poly,
			"step": step,
			"seed": 0,  # per-cell seeding does the varying; a global offset would only reroll
			"weights": weights,
			"yaw_jitter_deg": _canvas.yaw_jitter_deg,
			"scale_min": _canvas.scale_range.x,
			"scale_max": _canvas.scale_range.y,
		})
	else:
		_dab_seed += 1
		candidates = ScatterRegion.generate_placements({
			"polygon": poly,
			"density": _canvas.paint_density,
			"min_spacing": _canvas.min_spacing,
			"seed": _dab_seed,
			"weights": weights,
			"yaw_jitter_deg": _canvas.yaw_jitter_deg,
			"scale_min": _canvas.scale_range.x,
			"scale_max": _canvas.scale_range.y,
		})

	var space := _canvas.get_world_3d().direct_space_state
	var terrains := _terrains()
	var cos_max := cos(deg_to_rad(_canvas.max_slope_deg))
	var inv := _canvas.global_transform.affine_inverse()
	var spacing := _canvas.min_spacing

	while _work.size() < _canvas.items.size():
		_work.append(PackedFloat32Array())

	var placed := 0
	for i in candidates.size():
		var flat := candidates[i]
		@warning_ignore("integer_division")
		for j in flat.size() / 4:
			var o := j * 4
			var px := flat[o]
			var pz := flat[o + 1]
			if not keep.call(px, pz):
				continue
			var cell := Vector2i(floori(px / step.x), floori(pz / step.y)) if grid_mode else Vector2i.ZERO
			if grid_mode:
				if _cell_taken.has(cell):
					continue
			elif spacing > 0.0 and not ScatterBaseScript.spacing_ok(Vector2(px, pz), spacing, _spacing_grid):
				continue
			var hit := ScatterBaseScript.snap_ground(space, terrains, Vector3(px, probe_y, pz))
			if hit.is_empty() or (hit.normal as Vector3).y < cos_max:
				continue
			var local: Vector3 = inv * (hit.position as Vector3)
			_work[i].append_array(PackedFloat32Array(
					[local.x, local.y, local.z, flat[o + 2], flat[o + 3]]))
			if grid_mode:
				_cell_taken[cell] = true
			else:
				_grid_add(Vector2(px, pz), spacing)
			placed += 1
	return placed


# ------------------------------------------------------------------ occupancy

## Seed both rejection structures from the instances already stored on the canvas: the
## min-spacing hash (random pattern) and the taken-lattice-cell set (grid pattern).
func _rebuild_occupancy() -> void:
	_spacing_grid = {}
	_cell_taken = {}
	var grid_mode: bool = _canvas.paint_pattern == "grid"
	var step: Vector2 = _canvas.grid_step
	var spacing := _canvas.min_spacing
	if grid_mode:
		if step.x <= 0.0 or step.y <= 0.0:
			return
	elif spacing <= 0.0:
		return
	var base := _canvas.global_transform
	for i in _work.size():
		var flat := _work[i]
		for j in ScatterBaseScript.stored_count(flat):
			var world := base * ScatterBaseScript.stored_transform(flat, j).origin
			if grid_mode:
				_cell_taken[Vector2i(floori(world.x / step.x), floori(world.z / step.y))] = true
			else:
				_grid_add(Vector2(world.x, world.z), spacing)


func _grid_add(p: Vector2, spacing: float) -> void:
	var key := Vector2i(floori(p.x / spacing), floori(p.y / spacing))
	if not _spacing_grid.has(key):
		_spacing_grid[key] = PackedVector2Array()
	_spacing_grid[key].append(p)


# ------------------------------------------------------------------ helpers

func _terrains() -> Array[Node]:
	var out: Array[Node] = []
	var level_root: Node = _canvas.owner if _canvas.owner != null else _canvas
	ScatterBaseScript.find_terrains_under(level_root, out)
	return out


static func _snapshot(src: Array[PackedFloat32Array]) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	for flat in src:
		out.append(flat.duplicate())
	return out


static func _total(work: Array[PackedFloat32Array]) -> int:
	var n := 0
	for flat in work:
		n += ScatterBaseScript.stored_count(flat)
	return n

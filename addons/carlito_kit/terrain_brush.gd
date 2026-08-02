@tool
extends "res://addons/carlito_kit/brush_chassis.gd"
## Terrain sculpt/paint brush. Rides the shared brush chassis; adds
## the terrain-specific half: raise / lower / smooth / flatten on the heightmap image, and
## 8-channel painting across the terrain's two splat weight images.
##
## Editor-only by construction: a brush edits image CONTENT only. It never swaps
## the terrain's exported heightmap/splatmap Texture2D (the one exception: painting a channel
## >= 4 on a terrain with no splatmap2 creates that PNG, and flush points the node at it), and
## never touches the terrain's saved
## material (so the scene always serializes the PNG reference, never a transient in-memory
## texture). Live feedback comes from remeshing the touched chunks straight off the working
## image (height) and a preview material_override on those chunks (paint) — the chunks are
## unowned, so nothing put on them can serialize. Edits accumulate in memory and are written
## to the PNGs only on SCENE SAVE (flush_all, wired to the plugin's _save_external_data) —
## never reimported per stroke. The heightmap/splat PNGs stay the sole artifact the runtime
## and baker already read.

## The height an eyedropper click sampled (world Y) -> the panel's fixed-height field.
signal height_picked(y: float)

const BrushOps := preload("res://kit/helpers/brush_ops.gd")
const TerrainGen := preload("res://kit/terrain/terrain_gen.gd")

# Brush modes (index-matched to the panel's buttons: 0 = Off .. 6 = Paint).
enum { OFF, RAISE, LOWER, SMOOTH, FLATTEN, RAMP, PAINT }

var mode := OFF
## Splat channel to paint, 0..7: 0..3 live in the splatmap (grass/dirt/sand/rock), 4..7 in
## the optional splatmap2. Names and colors are the terrain's (see HeightmapTerrain).
var channel := 0
## Square (Chebyshev) footprint instead of the round one — for pads that meet flush. Sculpt
## and paint honour it; the ramp has its own swept shape and ignores it.
var square := false
## Flatten target: off = level to the height the drag started at (the default), on = level to
## `flatten_height` (world Y) regardless of where the drag starts.
var flatten_fixed := false
var flatten_height := 0.0
## Quantize the flatten target to multiples of this many metres (0 = off).
var snap_step := 0.0
## Snap the brush centre onto the road GridMap's cell lattice (XZ), so pads and ramps line up
## with the tiles dropped on them. Uses `_grid` when set, else a 12 m lattice at world origin
## (what a RoadsTiles node would use) so you can sculpt before placing tiles.
var grid_snap := false

var _undo: EditorUndoRedoManager
var _terrain: HeightmapTerrain = null
## The road GridMap to snap to (may be null — then the fallback lattice applies). Set by the
## plugin when the terrain is selected. GridMap is a core type, safe to annotate here.
var _grid: GridMap = null

# Per-terrain edit session, kept until scene save (flush) or plugin exit — so deselecting
# doesn't drop uncommitted work and undo stays coherent across reselection.
# id -> { terrain, height:Image, splat:Image, splat2:Image,
#         splat_tex:ImageTexture, splat2_tex:ImageTexture, preview_mat:ShaderMaterial,
#         height_dirty:bool, splat_dirty:bool, splat2_dirty:bool }
var _sessions := {}

# Active-stroke state. A paint stroke edits BOTH splat images (painting any channel has to
# fade the seven others, which straddle the two), so the snapshots come in pairs; a sculpt
# stroke only fills the first.
var _stroke_kind := "height"
var _stroke_action := "Sculpt terrain"  # undo label; also names the ramp and the fill
var _stroke_before: Image = null   # full snapshot at stroke begin (dirty region carved out at end)
var _stroke_before2: Image = null  # ditto for splat2 (paint strokes only)
var _dirty := Rect2i()
var _dirty_any := false
var _flatten_target := 0.0
# The mode the running stroke actually applies (modifiers folded in), frozen at _stroke_begin.
var _eff_mode := OFF

# Two-click ramp state: the stored start point and its normalized height, live between the
# first and second click.
var _ramp_armed := false
var _ramp_a := Vector3.ZERO
var _ramp_a_h := 0.0
# One-shot eyedropper: the next click samples a height instead of stroking.
var _pick_armed := false


func _init(undo: EditorUndoRedoManager) -> void:
	_undo = undo


# ------------------------------------------------------------------ plugin API

func set_target(terrain: HeightmapTerrain) -> void:
	if terrain == _terrain:
		return
	_free_cursor()  # cursor lives under the terrain; a new target needs a new one
	_cancel_pending()  # a stored ramp point belongs to the terrain it was clicked on
	_terrain = terrain


## The road GridMap the grid-snap uses (may be null — the fallback lattice then applies).
func set_grid(g: GridMap) -> void:
	_grid = g


## The GridMap's vertical cell size (metres) — the plugin pushes this into the flatten snap
## step when grid-snap turns on. Falls back to the roads palette's 3 m cell when no GridMap.
func grid_cell_y() -> float:
	return _grid.cell_size.y if is_instance_valid(_grid) else 3.0


func set_mode(m: int) -> void:
	mode = m
	_cancel_pending()
	if mode == OFF:
		_hide_cursor()


## Arm the eyedropper: the next viewport click reports the surface height it hits instead of
## editing. One-shot — it disarms whether it fires or gets cancelled.
func arm_pick() -> void:
	_pick_armed = true


## Drop any half-finished click interaction (a stored ramp start, an armed eyedropper).
func _cancel_pending() -> void:
	_ramp_armed = false
	_pick_armed = false


## Write every dirty session's working image back to its PNG and reimport once (PNGs are
## saved on scene save, never per stroke). Called from the plugin's _save_external_data hook.
func flush_all() -> void:
	for id: int in _sessions:
		var s: Dictionary = _sessions[id]
		var terrain: HeightmapTerrain = s.terrain
		if not is_instance_valid(terrain):
			continue
		if s.height_dirty and s.height != null:
			_flush_image(terrain, "height", s.height)
			s.height_dirty = false
		if s.splat_dirty and s.splat != null:
			_flush_image(terrain, "splat", s.splat)
			s.splat_dirty = false
		if s.splat2_dirty and s.splat2 != null:
			_flush_image(terrain, "splat2", s.splat2)
			s.splat2_dirty = false
		# The reimported PNGs are now the real splatmaps, so dropping the preview can't pop.
		_drop_preview(s)
		_heal_material(terrain)


func teardown() -> void:
	_free_cursor()
	for id: int in _sessions:
		var s: Dictionary = _sessions[id]
		_drop_preview(s)
		var terrain: HeightmapTerrain = s.terrain
		if is_instance_valid(terrain):
			terrain.source_image_replaced.disconnect(s.on_replaced)
	_sessions.clear()
	_terrain = null


# ------------------------------------------------------------------ chassis virtuals

func _target_valid() -> bool:
	return Engine.is_editor_hint() and mode != OFF and is_instance_valid(_terrain)


## Ramp cancel rides on top of the chassis loop. Esc drops the stored start point (or an armed
## eyedropper) and is consumed; right-click does the same but is deliberately NOT consumed, so
## the editor still gets it for freelook — swallowing right-click would trade the camera
## control the author uses constantly for a cancel they need rarely.
func handle_input(camera: Camera3D, event: InputEvent) -> bool:
	if (_ramp_armed or _pick_armed) and _target_valid():
		if event is InputEventKey and event.pressed \
				and (event as InputEventKey).keycode == KEY_ESCAPE:
			_cancel_pending()
			return true
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			_cancel_pending()
	return super(camera, event)


## The mode a stroke actually runs in: Shift smooths from any sculpt mode, Ctrl swaps raise
## and lower. Paint and ramp have no modifier meaning and pass through. Frozen into _eff_mode
## at _stroke_begin so letting go of a key mid-drag can't switch tools under the author.
func _effective_mode() -> int:
	if mode == OFF or mode == PAINT or mode == RAMP:
		return mode
	if shift_pressed:
		return SMOOTH
	if ctrl_pressed:
		if mode == RAISE:
			return LOWER
		if mode == LOWER:
			return RAISE
	return mode


func _cursor_parent() -> Node3D:
	return _terrain


## Tints to the mode the next (or running) stroke will actually apply, so holding Ctrl/Shift
## shows what it will do before the click.
func _cursor_color() -> Color:
	match (_eff_mode if _stroking else _effective_mode()):
		RAISE:
			return Color(0.4, 1.0, 0.45)
		LOWER:
			return Color(1.0, 0.5, 0.4)
		SMOOTH:
			return Color(0.45, 0.7, 1.0)
		FLATTEN:
			return Color(1.0, 0.9, 0.4)
		RAMP:
			return Color(0.85, 0.55, 1.0)
		PAINT:
			# The cursor wears the channel's own (per-level, editable) color.
			return _terrain.channel_color(channel) if is_instance_valid(_terrain) else Color.GRAY
	return Color.WHITE


## The cursor plus, while a ramp start point is stored, a marker ring at it.
func _cursor_strips(center: Vector3) -> Array[PackedVector3Array]:
	var strips: Array[PackedVector3Array] = [_cursor_points(center)]
	if _ramp_armed:
		strips.append(_ring(_ramp_a.x, _ramp_a.z, maxf(radius * 0.25, 0.5), 16))
	return strips


## Cursor outline that hugs the LIVE surface (the working image, not the stale PNG the node
## still points at), so it tracks sculpting in progress. Square mode walks the four edges with
## the same vertex budget as the ring, so the outline drapes over bumps the same way.
func _cursor_points(center: Vector3) -> PackedVector3Array:
	if not square:
		return _ring(center.x, center.z, radius, CURSOR_SEGMENTS)
	var pts := PackedVector3Array()
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1),
			Vector2(-1, -1)]
	var per := maxi(roundi(CURSOR_SEGMENTS / 4.0), 1)  # same vertex budget as the ring
	for i in 4:
		for j in per:
			var o: Vector2 = (corners[i] as Vector2).lerp(corners[i + 1], float(j) / float(per)) \
					* radius
			pts.append(_surface_point(center.x + o.x, center.z + o.y))
	pts.append(_surface_point(center.x - radius, center.z - radius))  # close the loop
	return pts


## A surface-hugging ring of `segments` sides, centred on world XZ.
func _ring(x: float, z: float, r: float, segments: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in segments + 1:
		var ang := TAU * float(i) / float(segments)
		pts.append(_surface_point(x + cos(ang) * r, z + sin(ang) * r))
	return pts


## A world point sitting just above the live surface (the lift keeps the line off the mesh).
func _surface_point(x: float, z: float) -> Vector3:
	return Vector3(x, _surface_y(x, z) + 0.05, z)


## Ground point under the cursor by iterating ray vs. heightfield (no physics — editor space
## isn't reliably populated, and we want the terrain surface specifically, not a placed prop).
## A few refinements converge for non-overhang terrain.
func _project(camera: Camera3D, mouse: Vector2) -> Variant:
	if not is_instance_valid(_terrain):
		return null
	var origin := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var p: Variant = _ray_plane(origin, dir, _terrain.global_position.y)
	for _i in 4:
		if p == null:
			return null
		var q: Variant = _ray_plane(origin, dir, _surface_y((p as Vector3).x, (p as Vector3).z))
		if q == null:
			break
		p = q
	if grid_snap and p != null:
		p = _snap_center(p as Vector3)
	return p


## Snap a world point's XZ onto the GridMap cell CENTRES, keeping its Y (re-sampled by the
## caller as needed). Reads the GridMap's own cell size / origin / centre flags when present,
## else a 12 m centre-true lattice at world origin (what a RoadsTiles node would use). The
## half-cell offset for a centre-true axis is baked into the lattice origin (verified: a
## (12,3,12) GridMap centres cell 0 at local 6, not 0).
func _snap_center(p: Vector3) -> Vector3:
	var size_x := 12.0
	var size_z := 12.0
	var org_x := 0.0
	var org_z := 0.0
	var center_x := true
	var center_z := true
	if is_instance_valid(_grid):
		size_x = _grid.cell_size.x
		size_z = _grid.cell_size.z
		org_x = _grid.global_position.x
		org_z = _grid.global_position.z
		center_x = _grid.cell_center_x
		center_z = _grid.cell_center_z
	if center_x:
		org_x += size_x * 0.5
	if center_z:
		org_z += size_z * 0.5
	var s := BrushOps.snap_to_grid(p.x, p.z, size_x, size_z, org_x, org_z)
	return Vector3(s.x, p.y, s.y)


# ------------------------------------------------------------------ click tools (ramp, eyedropper)

## Ramp and eyedropper are click tools, not drags, so they take the chassis's click seam
## rather than the stroke loop.
func _click_mode() -> bool:
	return _pick_armed or mode == RAMP


func _click(center: Vector3) -> void:
	if _pick_armed:
		_pick_armed = false
		height_picked.emit(_surface_y(center.x, center.z))
		return
	if _ramp_armed:
		_apply_ramp(center)
		return
	var work := _work_for(_terrain, "height")
	if work == null:
		push_warning("Kit brush: generate a heightmap first.")
		return
	_ramp_a = center
	_ramp_a_h = _sample_work_red(work, center.x, center.z)
	_ramp_armed = true


## Second ramp click: lay the whole A->B ramp as ONE edit, then hand it to the stroke-end path
## for the collision rebuild and the single undoable action a drag stroke gets.
func _apply_ramp(b_center: Vector3) -> void:
	_ramp_armed = false
	var work := _work_for(_terrain, "height")
	if work == null:
		return
	_stroke_kind = "height"
	_stroke_action = "Ramp terrain"
	_stroke_before = work.duplicate()
	_stroke_before2 = null
	_dirty_any = false
	var r := _px_radii(work)
	var dirty := BrushOps.stamp_ramp(work, _world_to_px(work, _ramp_a), _ramp_a_h,
			_world_to_px(work, b_center), _sample_work_red(work, b_center.x, b_center.z),
			r.x, r.y, strength, falloff)
	if dirty.size == Vector2i.ZERO:
		_stroke_before = null
		return
	_dirty = dirty
	_dirty_any = true
	_terrain.rebuild_region_world(work,
			minf(_ramp_a.x, b_center.x) - radius, maxf(_ramp_a.x, b_center.x) + radius,
			minf(_ramp_a.z, b_center.z) - radius, maxf(_ramp_a.z, b_center.z) + radius)
	_repush_preview(_terrain)
	_mark_dirty(_terrain, "height")
	_stroke_end()


## Flood the whole terrain with the selected channel (the panel's bucket). Strength and falloff
## have no say — a fill is a fill. Reuses the stroke path's snapshot -> region-undo machinery,
## with the dirty rect covering the whole image, so a fill undoes like any other paint.
func fill_terrain() -> void:
	if not is_instance_valid(_terrain):
		return
	var work := _work_for(_terrain, "splat")
	if work == null:
		push_warning("Kit brush: auto-splat the terrain first.")
		return
	var work2 := _work_for(_terrain, "splat2")
	_stroke_kind = "splat"
	_stroke_action = "Fill terrain"
	_stroke_before = work.duplicate()
	_stroke_before2 = work2.duplicate()
	_dirty = BrushOps.fill_splat(work, BrushOps.unit_slice(channel, 0))
	BrushOps.fill_splat(work2, BrushOps.unit_slice(channel, 1))
	_dirty_any = true
	_refresh_splat(_terrain)
	_mark_dirty(_terrain, "splat")
	_mark_dirty(_terrain, "splat2")
	_stroke_end()


# ------------------------------------------------------------------ stroke

func _stroke_begin(center: Vector3) -> void:
	_eff_mode = _effective_mode()
	_stroke_kind = "splat" if _eff_mode == PAINT else "height"
	_stroke_action = "Paint terrain" if _eff_mode == PAINT else "Sculpt terrain"
	var work := _work_for(_terrain, _stroke_kind)
	_stroke_before = null
	_stroke_before2 = null
	_dirty_any = false
	if work == null:
		push_warning("Kit brush: %s first." % ("auto-splat the terrain" if _stroke_kind == "splat"
				else "generate a heightmap"))
		return
	_stroke_before = work.duplicate()
	if _eff_mode == PAINT:
		_stroke_before2 = _work_for(_terrain, "splat2").duplicate()
	if _eff_mode == FLATTEN:
		_flatten_target = _flatten_target_for(center, work)


## The normalized height a flatten stroke pulls toward: the fixed field or the height under
## the drag's start, snapped to `snap_step` either way (so "level to the nearest 3 m" works
## whether the author typed the height or picked it off the ground). Everything happens in
## world Y — the metres the author thinks in — and converts to normalized at the end.
func _flatten_target_for(center: Vector3, work: Image) -> float:
	var base_y := _terrain.global_position.y
	var y := flatten_height if flatten_fixed \
			else base_y + _sample_work_red(work, center.x, center.z) * _terrain.height
	if snap_step > 0.0:
		y = snappedf(y, snap_step)
	return clampf((y - base_y) / maxf(_terrain.height, 1e-3), 0.0, 1.0)


## Brush radius in pixels on each image axis. A world-circular brush on a non-square terrain
## is an ellipse in image space, so the two differ.
func _px_radii(img: Image) -> Vector2:
	var ts := _terrain.terrain_size
	return Vector2(radius / maxf(ts.x, 1e-3) * float(img.get_width() - 1),
			radius / maxf(ts.y, 1e-3) * float(img.get_height() - 1))


func _stroke_apply(center: Vector3) -> void:
	if _stroke_before == null:
		return
	var work := _work_for(_terrain, _stroke_kind)
	if work == null:
		return
	var c := _world_to_px(work, center)
	var r := _px_radii(work)

	var dirty: Rect2i
	if _eff_mode == PAINT:
		# Both images take the same kernel with their own slice of the unit vector, so the
		# channel painted rises and every other channel — in either image — fades.
		dirty = BrushOps.stamp_splat(work, c.x, c.y, r.x, r.y,
				BrushOps.unit_slice(channel, 0), strength, falloff, square)
		BrushOps.stamp_splat(_work_for(_terrain, "splat2"), c.x, c.y, r.x, r.y,
				BrushOps.unit_slice(channel, 1), strength, falloff, square)
	else:
		dirty = BrushOps.stamp_height(work, c.x, c.y, r.x, r.y, _eff_mode - RAISE, strength,
				falloff, _flatten_target, square)
	if dirty.size == Vector2i.ZERO:
		return
	_dirty = dirty if not _dirty_any else _dirty.merge(dirty)
	_dirty_any = true

	if _eff_mode == PAINT:
		_refresh_splat(_terrain)
		_mark_dirty(_terrain, "splat")
		_mark_dirty(_terrain, "splat2")
	else:
		# Remesh only the chunks under the brush footprint (never a full rebuild
		# per stroke). Collision is deferred to stroke end.
		_terrain.rebuild_region_world(work, center.x - radius, center.x + radius,
				center.z - radius, center.z + radius)
		_repush_preview(_terrain)
		_mark_dirty(_terrain, "height")


func _stroke_end() -> void:
	if not _dirty_any or _stroke_before == null:
		_stroke_before = null
		_stroke_before2 = null
		return
	var work := _work_for(_terrain, _stroke_kind)
	if _stroke_kind == "height":
		_terrain.rebuild_collision_from_image(work)  # catch physics up once, at stroke end

	# Undo snapshots only the touched region of each side — of both images for a paint
	# stroke (same dirty rect: one kernel stamped into both).
	var kinds := ["splat", "splat2"] if _stroke_kind == "splat" else ["height"]
	var befores := [_stroke_before, _stroke_before2]
	_stroke_before = null
	_stroke_before2 = null
	var pos := _dirty.position
	var scene_root := EditorInterface.get_edited_scene_root()
	_undo.create_action(_stroke_action, UndoRedo.MERGE_DISABLE, scene_root)
	for i in kinds.size():
		var kind: String = kinds[i]
		var before_region := (befores[i] as Image).get_region(_dirty)
		var after_region := _work_for(_terrain, kind).get_region(_dirty)
		_undo.add_do_method(self, "_apply_region", _terrain, kind, after_region, pos)
		_undo.add_undo_method(self, "_apply_region", _terrain, kind, before_region, pos)
		_undo.add_do_reference(after_region)
		_undo.add_undo_reference(before_region)
	_undo.commit_action(false)  # edits are already live — don't re-run the do now


## Undo/redo target: blit a saved region back into the working image and refresh the visual.
## Robust to the terrain no longer being the current target (re-derives the session).
func _apply_region(terrain: HeightmapTerrain, kind: String, region: Image, pos: Vector2i) -> void:
	if not is_instance_valid(terrain):
		return
	var work := _work_for(terrain, kind)
	if work == null:
		return
	work.blit_rect(region, Rect2i(Vector2i.ZERO, region.get_size()), pos)
	_mark_dirty(terrain, kind)
	if kind == "splat" or kind == "splat2":
		_refresh_splat(terrain)
		return
	var lo := _px_to_world(terrain, work, pos)
	var hi := _px_to_world(terrain, work, pos + region.get_size())
	terrain.rebuild_region_world(work, minf(lo.x, hi.x), maxf(lo.x, hi.x),
			minf(lo.y, hi.y), maxf(lo.y, hi.y))
	_repush_preview(terrain)
	terrain.rebuild_collision_from_image(work)


# ------------------------------------------------------------------ session / image helpers

## The working image for `kind` ("height" / "splat" / "splat2"), decoded from the terrain's
## texture on first touch. splat2 is the exception: a terrain that has never been painted with
## a channel >= 4 has no splatmap2, so one is created all-zero (= no extra weight anywhere,
## the shader's own default) sized like the splatmap — the first such stroke just works, and
## flush writes the new PNG. Sizing off the splatmap is enough because a paint stroke without
## a splatmap is refused in _stroke_begin.
func _work_for(terrain: HeightmapTerrain, kind: String) -> Image:
	var id := terrain.get_instance_id()
	if not _sessions.has(id):
		# Bound callable kept in the session so teardown can disconnect the exact same one
		# (the node would otherwise keep this RefCounted brush alive).
		var on_replaced := _on_source_replaced.bind(terrain)
		_sessions[id] = {
			"terrain": terrain, "height": null, "splat": null, "splat2": null,
			"splat_tex": null, "splat2_tex": null, "preview_mat": null,
			"height_dirty": false, "splat_dirty": false, "splat2_dirty": false,
			"on_replaced": on_replaced,
		}
		terrain.source_image_replaced.connect(on_replaced)
	var s: Dictionary = _sessions[id]
	if kind == "height":
		if s.height == null:
			s.height = _decode(terrain.heightmap, Image.FORMAT_L8)
		return s.height
	if kind == "splat2":
		if s.splat2 == null:
			s.splat2 = _decode(terrain.splatmap2, Image.FORMAT_RGBA8)
		if s.splat2 == null:
			var base: Image = _work_for(terrain, "splat")
			if base == null:
				return null
			s.splat2 = Image.create(base.get_width(), base.get_height(), false,
					Image.FORMAT_RGBA8)
			(s.splat2 as Image).fill(Color(0, 0, 0, 0))
		return s.splat2
	if s.splat == null:
		s.splat = _decode(terrain.splatmap, Image.FORMAT_RGBA8)
	return s.splat


func _mark_dirty(terrain: HeightmapTerrain, kind: String) -> void:
	var s: Dictionary = _sessions[terrain.get_instance_id()]
	s[kind + "_dirty"] = true


## The terrain replaced one of its source images (Generate / Auto-splat / road Conform / an
## inspector assignment / an undo of those): drop our working copy so the next touch decodes
## the new one. Without this the session keeps the PRE-button pixels and the next stroke
## flushes them back — Auto-splat would visibly "come undone" on the next paint.
##
## Dropping an unflushed dirty image here is the intended outcome, not a loss: those buttons
## overwrite hand work by design (and undoably), and our own flush only ever assigns a
## texture whose PNG it just wrote.
func _on_source_replaced(kind: String, terrain: HeightmapTerrain) -> void:
	var s: Dictionary = _sessions.get(terrain.get_instance_id(), {})
	if s.is_empty():
		return
	s[kind] = null
	s[kind + "_dirty"] = false
	if kind != "height":
		s[kind + "_tex"] = null  # the transient preview texture mirrored the dropped image


## Show live paint without touching the SAVED material: throwaway ImageTextures (updated in
## place per sample) for BOTH weight images feed a duplicate of the material, applied as
## material_override on the terrain's unowned chunk MeshInstance3Ds. Writing the transient
## textures into the saved material instead would embed the whole raw images into the .tscn
## on save.
func _refresh_splat(terrain: HeightmapTerrain) -> void:
	var work := _work_for(terrain, "splat")
	if work == null:
		return
	var s: Dictionary = _sessions[terrain.get_instance_id()]
	s.splat_tex = _live_texture(s.splat_tex, work)
	s.splat2_tex = _live_texture(s.splat2_tex, _work_for(terrain, "splat2"))
	if s.preview_mat == null:
		if not (terrain.material is ShaderMaterial):
			return
		s.preview_mat = (terrain.material as ShaderMaterial).duplicate() as ShaderMaterial
	var mat: ShaderMaterial = s.preview_mat
	mat.set_shader_parameter(&"splatmap", s.splat_tex)
	mat.set_shader_parameter(&"splatmap2", s.splat2_tex)
	_push_preview(terrain, mat)


## Create-or-update the transient ImageTexture mirroring a working image.
func _live_texture(tex: ImageTexture, img: Image) -> ImageTexture:
	if img == null:
		return tex
	if tex == null:
		return ImageTexture.create_from_image(img)
	tex.update(img)
	return tex


## (Re)apply the preview material to the terrain's current chunk nodes. Called after every
## paint sample and after any incremental remesh — _build_chunk recreates chunks with
## material_override = terrain.material, dropping the preview.
func _push_preview(terrain: HeightmapTerrain, mat: Material) -> void:
	var container := terrain.get_node_or_null(^"Chunks")
	if container == null:
		return
	for child in container.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = mat


## Re-apply the live preview after an incremental remesh, if this terrain has one. A full
## rebuild() from an inspector edit mid-session also recreates chunks; that loses the preview
## until the next paint sample, which is acceptable.
func _repush_preview(terrain: HeightmapTerrain) -> void:
	var s: Dictionary = _sessions.get(terrain.get_instance_id(), {})
	if s.get("preview_mat") != null:
		_push_preview(terrain, s.preview_mat)


## Restore the chunks to the saved material and drop the preview.
func _drop_preview(s: Dictionary) -> void:
	if s.get("preview_mat") == null:
		return
	var terrain: HeightmapTerrain = s.terrain
	if is_instance_valid(terrain):
		_push_preview(terrain, terrain.material)
	s.preview_mat = null


## Tripwire + self-heal: the saved material must never hold a pathless (transient) splatmap
## texture — that is what embeds a raw image into the .tscn on save.
func _heal_material(terrain: HeightmapTerrain) -> void:
	var mat := terrain.material as ShaderMaterial
	if mat == null:
		return
	for param: StringName in [&"splatmap", &"splatmap2"]:
		var value: Variant = mat.get_shader_parameter(param)
		if value is ImageTexture and (value as ImageTexture).resource_path.is_empty():
			mat.set_shader_parameter(param,
					terrain.splatmap if param == &"splatmap" else terrain.splatmap2)
			push_warning("Kit brush: transient %s found on the saved material — reset to the "
					% param + "terrain's texture. The live preview should never write to it.")


func _flush_image(terrain: HeightmapTerrain, kind: String, img: Image) -> void:
	var path := terrain.png_path_for(kind)
	if path.is_empty():
		return
	var err := img.save_png(path)
	if err != OK:
		push_error("Kit brush: failed to write %s (%s)" % [path, error_string(err)])
		return
	TerrainGen.ensure_import_settings(path)
	var fs := EditorInterface.get_resource_filesystem()
	fs.update_file(path)
	fs.reimport_files(PackedStringArray([path]))
	var tex := ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE)
	# Assigning the reimported PNG texture (same res:// path -> unchanged scene reference)
	# refreshes the node off disk: its setter full-rebuilds (height) or repushes the splat
	# param, so live state and saved artifact agree.
	if kind == "height":
		terrain.heightmap = tex
	elif kind == "splat2":
		terrain.splatmap2 = tex
	else:
		terrain.splatmap = tex


func _decode(tex: Texture2D, fmt: int) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	elif img.get_format() != fmt:
		img = img.duplicate()
	if img.get_format() != fmt:
		img.convert(fmt)
	return img


# ------------------------------------------------------------------ world <-> image mapping

## World surface Y under (x, z): the live working image when a height session exists (so the
## cursor and projection track in-progress sculpting), else the terrain's committed sample.
func _surface_y(x: float, z: float) -> float:
	if is_instance_valid(_terrain):
		var s: Dictionary = _sessions.get(_terrain.get_instance_id(), {})
		if s.get("height") != null:
			return _terrain.global_position.y + _sample_work_red(s.height, x, z) * _terrain.height
	return _terrain.height_at(Vector3(x, 0, z)) if is_instance_valid(_terrain) else 0.0


func _world_to_px(img: Image, world: Vector3) -> Vector2i:
	var ts := _terrain.terrain_size
	var gp := _terrain.global_position
	var u := (world.x - gp.x + ts.x * 0.5) / maxf(ts.x, 1e-3)
	var v := (world.z - gp.z + ts.y * 0.5) / maxf(ts.y, 1e-3)
	return Vector2i(roundi(u * float(img.get_width() - 1)), roundi(v * float(img.get_height() - 1)))


## Inverse of _world_to_px, returning world XZ as a Vector2 (x, z).
func _px_to_world(terrain: HeightmapTerrain, img: Image, px: Vector2i) -> Vector2:
	var ts := terrain.terrain_size
	var gp := terrain.global_position
	var u := float(px.x) / maxf(float(img.get_width() - 1), 1.0)
	var v := float(px.y) / maxf(float(img.get_height() - 1), 1.0)
	return Vector2(gp.x - ts.x * 0.5 + u * ts.x, gp.z - ts.y * 0.5 + v * ts.y)


## Bilinear red-channel sample of the working image at world XZ (matches HeightmapTerrain's
## height_at mapping, so live and committed surfaces line up).
func _sample_work_red(img: Image, x: float, z: float) -> float:
	var ts := _terrain.terrain_size
	var gp := _terrain.global_position
	var u := clampf((x - gp.x + ts.x * 0.5) / maxf(ts.x, 1e-3), 0.0, 1.0)
	var v := clampf((z - gp.z + ts.y * 0.5) / maxf(ts.y, 1e-3), 0.0, 1.0)
	var iw := img.get_width()
	var ih := img.get_height()
	var fx := u * float(iw - 1)
	var fy := v * float(ih - 1)
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var x1 := mini(x0 + 1, iw - 1)
	var y1 := mini(y0 + 1, ih - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var top := lerpf(img.get_pixel(x0, y0).r, img.get_pixel(x1, y0).r, tx)
	var bot := lerpf(img.get_pixel(x0, y1).r, img.get_pixel(x1, y1).r, tx)
	return lerpf(top, bot, ty)

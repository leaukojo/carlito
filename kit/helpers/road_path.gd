@tool
class_name RoadPath
extends Node3D
## Spline road: owns a Path3D child ("Path", edited via the built-in path gizmo or the
## addon's Draw mode) and extrudes a low-poly ribbon along its curve from a RoadProfile.
## Placed under a level's Authoring node; at bake the ribbon joins the level-wide welded
## drivable body; unbaked dev-play gets a dev trimesh here. Ribbon derives from curve +
## profile alone (never reads terrain), so bake output depends only on the scene file.
## Conform terrain is destructive-by-button: flattens overlapping HeightmapTerrain under
## the ribbon with a side falloff, one write per terrain, undoable. Authoring order:
## terrain -> roads + conform -> splat -> scatter. No junctions, no lane markings, no
## traffic. No editor-only type annotations in this @tool script (breaks export parse).

## Default for fresh roads: the city preset (its colors match the roads-GridMap tiles).
const DEFAULT_PROFILE_PATH := "res://kit/roads/city_profile.tres"

const Groups := preload("res://src/levels/base/carlito_groups.gd")
const BrushOps := preload("res://kit/helpers/brush_ops.gd")
const SplatPaint := preload("res://kit/helpers/splat_paint.gd")

## Lateral inset (m) Paint splat keeps inside the paved edge, so bilinear bleed stays
## under the deck instead of peeking past the ribbon.
const SPLAT_PAINT_INSET := 1.0

## Cross-section + materials. Auto-assigned the city preset via a plain property set
## (not a preload default) so it hash-tracks. The baker errors on a null profile.
@export var profile: RoadProfile:
	set(value):
		if profile != null and profile.changed.is_connected(_mark_dirty):
			profile.changed.disconnect(_mark_dirty)
		profile = value
		if profile != null and not profile.changed.is_connected(_mark_dirty):
			profile.changed.connect(_mark_dirty)
		_mark_dirty()
## Roll the ribbon by the curve's per-point tilt (path gizmo tilt handles).
@export var banking := false:
	set(value):
		banking = value
		_mark_dirty()
## Longest ribbon segment (m) on straights; curvature subdivides below it.
@export var max_segment_length := 6.0:
	set(value):
		max_segment_length = maxf(value, 0.5)
		_mark_dirty()
## Tangent swing (degrees) a single segment may span before it is subdivided.
@export var max_segment_angle_deg := 6.0:
	set(value):
		max_segment_angle_deg = maxf(value, 0.1)
		_mark_dirty()

@export_group("Draw / drape")
## Ground clearance (m) for Draw mode and Drape, so the ribbon never starts buried.
@export var draw_clearance := 0.3
## Snap every curve point's Y to terrain + draw_clearance. Editor-only, undoable.
@warning_ignore("unused_private_class_variable")
@export_tool_button("Drape curve onto terrain") var _drape_action := _drape_curve
## Give every interior point Catmull-Rom handles. Editor-only, undoable.
@warning_ignore("unused_private_class_variable")
@export_tool_button("Smooth curve (Catmull-Rom)") var _smooth_action := _smooth_curve
## Reverse the curve's point order (the ribbon itself is direction-invariant).
@warning_ignore("unused_private_class_variable")
@export_tool_button("Reverse direction") var _reverse_action := _reverse_curve

@export_group("Conform terrain")
## Blend band (m) beyond the full ribbon half-width over which the flatten fades out.
@export var conform_falloff := 4.0
## Terrain flattens this far (m) below the road surface (z-fighting guard). The
## profile's drop skirt must absorb this + one height step; conform warns if it can't.
@export var conform_epsilon := 0.05
@warning_ignore("unused_private_class_variable")
@export_tool_button("Conform terrain (destructive)") var _conform_action := _conform_terrain

@export_group("Paint splat")
## Paints `splat_channel` under the deck so RayWheel's grip matches the road. Destructive
## and additive: swapping profile doesn't repaint; recovery is Auto-splat then repaint.
@warning_ignore("unused_private_class_variable")
@export_tool_button("Paint splat under road (destructive)") var _paint_splat_action := _paint_splat

var _dirty := false


func _init() -> void:
	add_to_group(Groups.ROAD)


func _ready() -> void:
	_ensure_path()
	if Engine.is_editor_hint() and profile == null:
		profile = load(DEFAULT_PROFILE_PATH)
	_rebuild_road()


## The serialized Path3D child is the bake input; curve_changed covers point edits AND
## curve swaps.
func _ensure_path() -> void:
	var path := get_node_or_null(^"Path") as Path3D
	if path == null:
		path = Path3D.new()
		path.name = "Path"
		var curve := Curve3D.new()
		curve.add_point(Vector3.ZERO)
		curve.add_point(Vector3(0, 0, 12))
		path.curve = curve
		add_child(path)
	if Engine.is_editor_hint():
		# Deferred: _ready runs inside add_child, before our own owner is assigned.
		call_deferred(&"_own_path", path)
	if not path.curve_changed.is_connected(_mark_dirty):
		path.curve_changed.connect(_mark_dirty)


func _own_path(path: Path3D) -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(path) or not is_inside_tree():
		return
	var target := owner if owner != null else get_tree().edited_scene_root
	if target != null and path.owner != target:
		path.owner = target


func _mark_dirty() -> void:
	if _dirty or not is_inside_tree():
		return
	_dirty = true
	call_deferred(&"_rebuild_road")


## Rebuild the unowned preview + dev collision. Dev collision exists only outside the
## editor, so editor raycasts never hit our own ribbon.
func _rebuild_road() -> void:
	_dirty = false
	if not is_inside_tree():
		return
	var old := get_node_or_null(^"Preview")
	if old != null:
		old.free()
	var old_col := get_node_or_null(^"DevCollision")
	if old_col != null:
		old_col.free()
	if Engine.is_editor_hint():
		update_configuration_warnings()
	var entries := ribbon_surfaces()
	if entries.is_empty():
		return
	var mesh := ArrayMesh.new()
	for e: Dictionary in entries:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, e.arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, e.material)
	var mi := MeshInstance3D.new()
	mi.name = "Preview"
	mi.mesh = mesh
	add_child(mi)
	if not Engine.is_editor_hint():
		var body := StaticBody3D.new()
		body.name = "DevCollision"
		add_child(body)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(ribbon_faces())
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)


# ------------------------------------------------------------------ geometry API
# Duck-called by the baker on an untreed level instance.


## [{material, arrays}] in RoadPath-local space. Empty when profile null or curve unusable.
func ribbon_surfaces() -> Array:
	var surfaces := _build_curve_surfaces()
	if surfaces.is_empty():
		return []
	var mats: Array = profile.materials()
	var out := []
	var keys := surfaces.keys()
	keys.sort()
	for slot: int in keys:
		out.append({"material": mats[slot], "arrays": surfaces[slot]})
	return out


func ribbon_faces() -> PackedVector3Array:
	return RoadBuilder.faces_from_surfaces(_build_curve_surfaces())


## Shared build: cross-section -> adaptive offsets -> extrude, then compose the Path3D
## child transform.
func _build_curve_surfaces() -> Dictionary:
	if profile == null:
		return {}
	var path := get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null:
		return {}
	var cs: Dictionary = profile.cross_section()
	if (cs.points as PackedVector2Array).size() < 2:
		return {}
	var offsets := RoadBuilder.adaptive_offsets(path.curve, max_segment_length,
			max_segment_angle_deg)
	if offsets.size() < 2:
		return {}
	var surfaces := RoadBuilder.extrude(path.curve, cs.points, cs.mats, offsets, banking)
	if path.transform != Transform3D.IDENTITY:
		for slot in surfaces:
			surfaces[slot] = RoadBuilder.transform_surface_arrays(surfaces[slot], path.transform)
	return surfaces


# ---------------------------------------------------------------- rail node API
# Shared verbatim with RailTrack (src/levels/base/rail_track.gd), which the baker emits
# so the curve survives baked levels (AuthoringRoot is freed at load / stripped on
# export); unbaked play has no RailTrack, so this answers instead. Discovery is
# has_method("get_rail_curve") and non-null result, never a marker method. Duck-called
# on an untreed instance, so nothing here touches global_transform.


func get_rail_curve() -> Curve3D:
	if profile == null or not profile.has_method("is_carlito_rail_profile"):
		return null
	var path := get_node_or_null(^"Path") as Path3D
	return path.curve if path != null else null


func rail_local_xform() -> Transform3D:
	var path := get_node_or_null(^"Path") as Path3D
	return path.transform if path != null else Transform3D.IDENTITY


func rail_to_world() -> Transform3D:
	return global_transform * rail_local_xform()


func rail_gauge() -> float:
	return float(profile.get("gauge")) if get_rail_curve() != null else 0.0


func is_rail_closed() -> bool:
	return RoadBuilder.is_closed_loop(get_rail_curve())


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if _find_authoring_ancestor() == null:
		warnings.append("RoadPath must sit under the level's Authoring node to be baked.")
	if profile == null:
		warnings.append("No profile — assign one from kit/roads/.")
	var path := get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null or path.curve.point_count < 2:
		warnings.append("The Path child's curve needs at least 2 points.")
	else:
		var dup: int = RoadBuilder.first_coincident_index(path.curve)
		if dup >= 0:
			warnings.append(("Curve points %d and %d coincide (a zero-length segment) — " +
					"delete the duplicate or Curve3D spams 'Zero length interval' errors.") % [
					dup - 1, dup])
		if profile != null:
			# A loop closed by eye leaves a gap past the bake's 1 mm weld.
			var gap: float = RoadBuilder.endpoint_gap(path.curve)
			if gap > 0.0 and gap < profile.full_half_width() \
					and not RoadBuilder.is_closed_loop(path.curve):
				warnings.append(("The curve's endpoints are %.2f m apart — too close to " +
						"be separate ends, too far to close the loop. Drag the last point " +
						"exactly onto the first, or the seam stays open in the baked " +
						"collision.") % gap)
			var radius: float = RoadBuilder.min_turn_radius(path.curve,
					max_segment_length, max_segment_angle_deg)
			if radius < profile.full_half_width():
				warnings.append(("Turn radius %.1f m is under the ribbon's %.1f m " +
						"half-width — the inside edge pinches into a slit there. " +
						"Widen the turn (Arc draw mode keeps radii safe).") % [
						radius, profile.full_half_width()])
	return warnings


func _find_authoring_ancestor() -> Node:
	return Groups.authoring_ancestor(self)


# ------------------------------------------------------------------ drape curve


func _drape_curve() -> void:
	if not Engine.is_editor_hint():
		return
	var path := get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null or path.curve.point_count == 0:
		push_warning("RoadPath: no curve points to drape.")
		return
	var terrains: Array[Node] = []
	ScatterBase.find_terrains_under(owner if owner != null else self, terrains)
	if terrains.is_empty():
		push_warning("RoadPath: no HeightmapTerrain in the scene to drape onto.")
		return
	var curve := path.curve
	var to_world := global_transform * path.transform
	var world_to_local := to_world.affine_inverse()
	var before := PackedVector3Array()
	var after := PackedVector3Array()
	var missed := 0
	for i in curve.point_count:
		var p := curve.get_point_position(i)
		before.append(p)
		var w := to_world * p
		var did_snap := false
		for t in terrains:
			if t.contains_xz(w):
				w.y = float(t.height_at(w)) + draw_clearance
				did_snap = true
				break
		if did_snap:
			p = world_to_local * w
		else:
			missed += 1
		after.append(p)
	if missed > 0:
		push_warning("RoadPath '%s': %d point(s) over no terrain kept their height." % [name, missed])
	if after == before:
		return
	var undo_redo = Engine.get_singleton(&"EditorInterface").get_editor_undo_redo()
	undo_redo.create_action("Drape road '%s' onto terrain" % name)
	undo_redo.add_do_method(self, &"_set_curve_point_positions", after)
	undo_redo.add_undo_method(self, &"_set_curve_point_positions", before)
	undo_redo.commit_action()


func _set_curve_point_positions(positions: PackedVector3Array) -> void:
	var path := get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null:
		return
	for i in mini(positions.size(), path.curve.point_count):
		path.curve.set_point_position(i, positions[i])


func _smooth_curve() -> void:
	if not Engine.is_editor_hint():
		return
	var path := get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null or path.curve.point_count < 3:
		push_warning("RoadPath: need at least 3 curve points to smooth.")
		return
	var curve := path.curve
	var before_in := PackedVector3Array()
	var before_out := PackedVector3Array()
	var after_in := PackedVector3Array()
	var after_out := PackedVector3Array()
	for i in curve.point_count:
		before_in.append(curve.get_point_in(i))
		before_out.append(curve.get_point_out(i))
		if i == 0 or i == curve.point_count - 1:
			after_in.append(curve.get_point_in(i))
			after_out.append(curve.get_point_out(i))
			continue
		var h: Dictionary = RoadBuilder.smooth_handles(curve.get_point_position(i - 1),
				curve.get_point_position(i), curve.get_point_position(i + 1))
		after_in.append(h["in"])
		after_out.append(h["out"])
	if after_in == before_in and after_out == before_out:
		return
	var undo_redo = Engine.get_singleton(&"EditorInterface").get_editor_undo_redo()
	undo_redo.create_action("Smooth road '%s' curve" % name)
	undo_redo.add_do_method(self, &"_set_curve_handles", after_in, after_out)
	undo_redo.add_undo_method(self, &"_set_curve_handles", before_in, before_out)
	undo_redo.commit_action()


func _set_curve_handles(ins: PackedVector3Array, outs: PackedVector3Array) -> void:
	var path := get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null:
		return
	for i in mini(ins.size(), path.curve.point_count):
		path.curve.set_point_in(i, ins[i])
		path.curve.set_point_out(i, outs[i])


func _reverse_curve() -> void:
	if not Engine.is_editor_hint():
		return
	var path := get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null or path.curve.point_count < 2:
		push_warning("RoadPath: the curve needs at least 2 points to reverse.")
		return
	var undo_redo = Engine.get_singleton(&"EditorInterface").get_editor_undo_redo()
	undo_redo.create_action("Reverse road '%s' direction" % name)
	undo_redo.add_do_method(self, &"_apply_reverse")
	undo_redo.add_undo_method(self, &"_apply_reverse")
	undo_redo.commit_action()


## Reverse the curve's point order in place: swaps each point's in/out handles, no
## negation. Ribbon geometry is invariant (RoadBuilder flips right with tangent).
func _apply_reverse() -> void:
	var path := get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null:
		return
	var curve := path.curve
	var n := curve.point_count
	var pos := PackedVector3Array()
	var ins := PackedVector3Array()
	var outs := PackedVector3Array()
	var tilts := PackedFloat32Array()
	for i in n:
		var j := n - 1 - i
		pos.append(curve.get_point_position(j))
		ins.append(curve.get_point_out(j))
		outs.append(curve.get_point_in(j))
		tilts.append(curve.get_point_tilt(j))
	for i in n:
		curve.set_point_position(i, pos[i])
		curve.set_point_in(i, ins[i])
		curve.set_point_out(i, outs[i])
		curve.set_point_tilt(i, tilts[i])


# --------------------------------------------------------------- conform terrain
# Editor-only, destructive-by-button. Heavy lifting is pure (RoadBuilder.conform_
# heights); PNG write / undo reuses HeightmapTerrain._commit_generated verbatim.


func _conform_terrain() -> void:
	if not Engine.is_editor_hint():
		return
	if profile == null:
		push_warning("RoadPath: assign a profile before conforming.")
		return
	if profile.base_depth > 0.0:
		# A bridge spans the gap on its own box; flattening terrain would bury the piers.
		push_warning("RoadPath '%s': bridge profile (base_depth > 0) — Conform skipped; the bridge carries over the gap instead of flattening it." % name)
		return
	var path := get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null or path.curve.point_count < 2:
		push_warning("RoadPath: the curve needs at least 2 points.")
		return
	var curve := path.curve
	var length := curve.get_baked_length()
	if length < 0.001:
		push_warning("RoadPath: the curve has no length.")
		return

	# Samples at the extrusion's ring offsets target the ribbon's chordal surface, not
	# the analytic curve, which sits above the chords over a crest.
	var to_world := global_transform * path.transform
	var offsets := RoadBuilder.adaptive_offsets(curve, max_segment_length,
			max_segment_angle_deg)
	var world := PackedVector3Array()
	for o in offsets:
		world.append(to_world * curve.sample_baked(o))
	# Deck extruded on the ribbon's own frames; conform_heights rasterizes it as the
	# plateau, since the centerline projection alone mis-heights steep + yawing segments.
	var fw: float = profile.full_half_width()
	var deck_surfaces: Dictionary = RoadBuilder.extrude(curve,
			PackedVector2Array([Vector2(-fw, 0), Vector2(fw, 0)]),
			PackedInt32Array([0]), offsets, banking)
	var deck_world := PackedVector3Array()
	for v in RoadBuilder.faces_from_surfaces(deck_surfaces):
		deck_world.append(to_world * v)

	var terrains: Array[Node] = []
	ScatterBase.find_terrains_under(owner if owner != null else self, terrains)
	var reach: float = profile.full_half_width() + conform_falloff
	var touched := 0
	for t in terrains:
		if not _overlaps_terrain(t, world, reach):
			continue
		var img: Image = t._read_image()
		if img == null:
			push_warning("RoadPath: terrain '%s' has no heightmap to conform." % t.name)
			continue
		var t3d := t as Node3D
		var amp := maxf(float(t.get("height")), 0.001)
		# The skirt must absorb epsilon plus one 8-bit height step or the seam can open.
		var height_step := amp / 255.0
		if profile.edge_drop < conform_epsilon + height_step:
			push_warning("RoadPath '%s': profile edge_drop %.2f < conform_epsilon %.2f + terrain '%s' height step %.3f — raise the profile's edge_drop (or lower the terrain height) or the skirt seam can open." % [name, profile.edge_drop, conform_epsilon, t.name, height_step])
		var clamped := false
		var samples := PackedVector3Array()
		for w in world:
			var tn := (w.y - conform_epsilon - t3d.global_position.y) / amp
			if tn < 0.0 or tn > 1.0:
				clamped = true
			samples.append(Vector3(w.x - t3d.global_position.x,
					w.z - t3d.global_position.z, clampf(tn, 0.0, 1.0)))
		if clamped:
			push_warning("RoadPath: parts of '%s' sit outside terrain '%s's height range — the flatten clamps there." % [name, t.name])
		var deck := PackedVector3Array()
		for w in deck_world:
			deck.append(Vector3(w.x - t3d.global_position.x,
					w.z - t3d.global_position.z,
					clampf((w.y - conform_epsilon - t3d.global_position.y) / amp,
							0.0, 1.0)))
		var dims: Vector2i = t._grid_dims()
		# Plateau spans the full ribbon half-width including skirt.
		var dirty := RoadBuilder.conform_heights(img, samples,
				profile.full_half_width(), conform_falloff,
				float(dims.x - 1), float(dims.y - 1), deck)
		if not dirty.has_area():
			continue
		t._commit_generated("Conform terrain to road '%s'" % name,
				[[&"heightmap", t.png_path_for("height"), img]], {})
		touched += 1
	if touched == 0:
		push_warning("RoadPath: no HeightmapTerrain overlaps this road — nothing conformed.")
	else:
		print("RoadPath '%s': conformed %d terrain(s)." % [name, touched])


# ------------------------------------------------------------------ paint splat
# Editor-only, destructive-by-button. Same footprint as Conform, but writes the
# terrain's splat images across the paved half-width minus SPLAT_PAINT_INSET (never
# the skirted full width, so the paint stays hidden under the deck). Pure pixel work
# is SplatPaint (tested); the PNG write / undo reuses _commit_generated verbatim.


func _paint_splat() -> void:
	if not Engine.is_editor_hint():
		return
	if profile == null:
		push_warning("RoadPath: assign a profile before painting.")
		return
	if profile.base_depth > 0.0:
		# A bridge spans the gap clear of the terrain; wheels never sample ground splat.
		push_warning("RoadPath '%s': bridge profile (base_depth > 0) — Paint splat skipped; wheels on the bridge deck never read the ground splat below." % name)
		return
	var path := get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null:
		return
	var curve := path.curve
	if curve.get_baked_length() < 0.001:
		push_warning("RoadPath: the curve has no length.")
		return

	# Same sample/deck geometry as Conform, but at the inset paved width.
	var channel: int = profile.splat_channel
	var pw: float = profile.paved_half_width() - SPLAT_PAINT_INSET
	if pw <= 0.0:
		push_warning("RoadPath '%s': profile too narrow to paint under (paved half-width %.2f m <= %.1f m inset)." % [name, profile.paved_half_width(), SPLAT_PAINT_INSET])
		return
	var to_world := global_transform * path.transform
	var offsets := RoadBuilder.adaptive_offsets(curve, max_segment_length,
			max_segment_angle_deg)
	var world := PackedVector3Array()
	for o in offsets:
		world.append(to_world * curve.sample_baked(o))
	var deck_surfaces: Dictionary = RoadBuilder.extrude(curve,
			PackedVector2Array([Vector2(-pw, 0), Vector2(pw, 0)]),
			PackedInt32Array([0]), offsets, banking)
	var deck_world := PackedVector3Array()
	for v in RoadBuilder.faces_from_surfaces(deck_surfaces):
		deck_world.append(to_world * v)

	var terrains: Array[Node] = []
	ScatterBase.find_terrains_under(owner if owner != null else self, terrains)
	var touched := 0
	for t in terrains:
		if not _overlaps_terrain(t, world, pw):
			continue
		var img: Image = SplatPaint.decode(t.get("splatmap"))
		if img == null:
			push_warning("RoadPath: terrain '%s' has no usable splatmap — run Auto-splat first." % t.name)
			continue
		var img2: Image = SplatPaint.decode(t.get("splatmap2"))
		if img2 == null and channel >= 4:
			# splatmap2 holds channels 4-7; created on the first stroke that needs it.
			img2 = Image.create(img.get_width(), img.get_height(), false,
					Image.FORMAT_RGBA8)
			img2.fill(Color(0, 0, 0, 0))
		if img2 != null and img2.get_size() != img.get_size():
			push_warning("RoadPath: terrain '%s's splatmap2 size differs from splatmap — repaint it at the base size first (see the terrain's config warning)." % t.name)
			continue
		var t3d := t as Node3D
		var samples := PackedVector2Array()
		for w in world:
			samples.append(Vector2(w.x - t3d.global_position.x,
					w.z - t3d.global_position.z))
		var deck := PackedVector2Array()
		for w in deck_world:
			deck.append(Vector2(w.x - t3d.global_position.x,
					w.z - t3d.global_position.z))
		var images: Array[Image] = [img]
		var units: Array[Color] = [BrushOps.unit_slice(channel, 0)]
		if img2 != null:
			images.append(img2)
			units.append(BrushOps.unit_slice(channel, 1))
		var size: Vector2 = t.get("terrain_size")
		var dirty := SplatPaint.paint_strip(images, units, samples, pw,
				size.x, size.y, deck)
		if not dirty.has_area():
			continue
		var splat_path: String = t.png_path_for("splat")
		if splat_path.is_empty():
			continue
		var entries: Array = [[&"splatmap", splat_path, img]]
		if img2 != null:
			entries.append([&"splatmap2", t.png_path_for("splat2"), img2])
		t._commit_generated("Paint splat under road '%s'" % name, entries, {})
		touched += 1
	if touched == 0:
		push_warning("RoadPath: no terrain splat under this road changed.")
	else:
		print("RoadPath '%s': painted splat channel %d on %d terrain(s)." % [name, channel, touched])


## Whether any centerline sample lands within `pad` of the terrain's XZ rect.
func _overlaps_terrain(t: Node, world: PackedVector3Array, pad: float) -> bool:
	var t3d := t as Node3D
	var half: Vector2 = t.get("terrain_size") * 0.5
	for w in world:
		if absf(w.x - t3d.global_position.x) <= half.x + pad \
				and absf(w.z - t3d.global_position.z) <= half.y + pad:
			return true
	return false

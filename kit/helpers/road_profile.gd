@tool
class_name RoadProfile
extends Resource
## Cross-section recipe for RoadPath ribbons: lane/shoulder/
## edge-line widths, an edge drop skirt, and one flat-color material per strip kind
## (the Kenney low-poly look — no textures). Presets live in kit/roads/ (asphalt with a
## painted edge line, gravel without) so gather_bake_inputs hash-tracks them; editing a
## preset color re-stales every bake that references it.
##
## The profile is consumed as a generic breakpoint list (cross_section), so the extruder
## (RoadBuilder) never knows about lanes or shoulders — and the pure fns here get the
## usual test discipline (tests/test_road.gd).

## Material slot indices in cross_section().mats (index-matched to materials()).
const SLOT_SURFACE := 0
const SLOT_EDGE_LINE := 1
const SLOT_SHOULDER := 2
const SLOT_BASE := 3

## Half the paved driving surface: the full road is two lanes, lane_width each side.
@export var lane_width := 3.5:
	set(value):
		lane_width = value
		emit_changed()
## Shoulder strip outside the edge line, each side.
@export var shoulder_width := 0.6:
	set(value):
		shoulder_width = value
		emit_changed()
## Painted edge line between lane and shoulder. 0 removes the line (gravel).
@export var edge_line_width := 0.15:
	set(value):
		edge_line_width = value
		emit_changed()
## How far the outermost skirt drops below the road surface (hides the terrain seam).
@export var edge_drop := 0.3:
	set(value):
		edge_drop = value
		emit_changed()
## Lateral run of the drop skirt. 0 removes the skirt (the drop is ignored).
@export var drop_run := 0.5:
	set(value):
		drop_run = value
		emit_changed()
## Terrain paint channel RoadPath's "Paint splat under road" writes under the deck (0..7
## into the terrain's channel_names / channel_grip tables — stock names: 6 = Asphalt,
## 7 = Gravel). Lives on the profile because the profile IS the surface: swapping a road
## to the gravel preset makes the next repaint write gravel. Repainting is still a
## button — changing this (or any width) does NOT touch already-painted splat.
@export_range(0, 7) var splat_channel := 6:
	set(value):
		splat_channel = value
		emit_changed()
## Bridge underside: a solid box (two vertical walls + a bottom strip) hanging this far
## below the road's outer edge. 0 = no base (default) — every non-bridge profile stays
## byte-identical. Deep enough should reach below the gap it spans (e.g. under sea level).
@export var base_depth := 0.0:
	set(value):
		base_depth = value
		emit_changed()
@export var surface_material: Material:
	set(value):
		surface_material = value
		emit_changed()
@export var edge_line_material: Material:
	set(value):
		edge_line_material = value
		emit_changed()
@export var shoulder_material: Material:
	set(value):
		shoulder_material = value
		emit_changed()
@export var base_material: Material:
	set(value):
		base_material = value
		emit_changed()


## The extruder's input: {points: PackedVector2Array, mats: PackedInt32Array}.
## points are (lateral, y) breakpoints left->right (+lateral = frame right), y relative
## to the curve; mats[i] is the material slot of the strip between points i and i+1.
## Zero-width strips are dropped HERE (gravel's edge line, a zero drop_run skirt), so
## the extruder never sees degenerate quads. Mirror-symmetric by construction.
func cross_section() -> Dictionary:
	var l := maxf(lane_width, 0.0)
	var e := maxf(edge_line_width, 0.0)
	var s := maxf(shoulder_width, 0.0)
	var d := maxf(drop_run, 0.0)
	var xs := PackedFloat32Array([
		-(l + e + s + d), -(l + e + s), -(l + e), -l,
		l, l + e, l + e + s, l + e + s + d])
	var ys := PackedFloat32Array([-edge_drop, 0, 0, 0, 0, 0, 0, -edge_drop])
	var slots := PackedInt32Array([SLOT_SHOULDER, SLOT_SHOULDER, SLOT_EDGE_LINE,
			SLOT_SURFACE, SLOT_EDGE_LINE, SLOT_SHOULDER, SLOT_SHOULDER])
	var points := PackedVector2Array()
	var mats := PackedInt32Array()
	for i in slots.size():
		if xs[i + 1] - xs[i] <= 0.0001:
			continue
		if points.is_empty():
			points.append(Vector2(xs[i], ys[i]))
		points.append(Vector2(xs[i + 1], ys[i + 1]))
		mats.append(slots[i])
	# Bridge base: continue the open polyline around a box below the outer edges — right
	# wall down, bottom right->left, left wall back up to the top-left corner. The
	# extruder winds all three strips outward-facing for free (top faces up; the box
	# faces out/down — road_builder's RH-normal is the inverse of Godot's front face).
	# NOT routed through the lateral-only zero-width filter above (it would drop the
	# vertical walls); base_depth > 0 guarantees non-degenerate walls, 2*half-width the
	# bottom. paved/full_half_width are unchanged — the box adds no lateral reach.
	if base_depth > 0.0 and points.size() >= 2:
		var left := points[0]
		var right := points[points.size() - 1]
		points.append(Vector2(right.x, right.y - base_depth))   # right wall
		points.append(Vector2(left.x, left.y - base_depth))     # bottom
		points.append(left)                                     # left wall
		mats.append_array(PackedInt32Array([SLOT_BASE, SLOT_BASE, SLOT_BASE]))
	return {"points": points, "mats": mats}


## Slot index -> Material, matching cross_section().mats.
func materials() -> Array:
	return [surface_material, edge_line_material, shoulder_material, base_material]


## Half-width of the flattened band conform targets (lane + line + shoulder).
func paved_half_width() -> float:
	return maxf(lane_width, 0.0) + maxf(edge_line_width, 0.0) + maxf(shoulder_width, 0.0)


## Full ribbon half-width including the drop skirt (conform's dirty-rect bound).
func full_half_width() -> float:
	return paved_half_width() + maxf(drop_run, 0.0)

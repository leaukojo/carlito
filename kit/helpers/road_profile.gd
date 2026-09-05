@tool
class_name RoadProfile
extends Resource
## Cross-section recipe for RoadPath ribbons: lane/shoulder/edge-line widths, an edge
## drop skirt, and one flat-color material per strip kind. Presets live in kit/roads/, so
## editing a preset color re-stales every bake that references it. Consumed as a generic
## breakpoint list (cross_section), so the extruder never knows about lanes or shoulders.

## Material slot indices.
const SLOT_SURFACE := 0
const SLOT_EDGE_LINE := 1
const SLOT_SHOULDER := 2
const SLOT_BASE := 3

## Half the paved driving surface (m): the full road is two lanes, lane_width each side.
@export var lane_width := 3.5:
	set(value):
		lane_width = value
		emit_changed()
## Shoulder strip (m) outside the edge line, each side.
@export var shoulder_width := 0.6:
	set(value):
		shoulder_width = value
		emit_changed()
## Painted edge line width (m). 0 removes the line (gravel).
@export var edge_line_width := 0.15:
	set(value):
		edge_line_width = value
		emit_changed()
## Skirt drop (m) below the road surface, hides the terrain seam.
@export var edge_drop := 0.3:
	set(value):
		edge_drop = value
		emit_changed()
## Lateral run (m) of the drop skirt. 0 removes the skirt.
@export var drop_run := 0.5:
	set(value):
		drop_run = value
		emit_changed()
## Terrain paint channel "Paint splat under road" writes (6=Asphalt, 7=Gravel); changing
## this does not touch already-painted splat.
@export_range(0, 7) var splat_channel := 6:
	set(value):
		splat_channel = value
		emit_changed()
## Bridge underside depth (m): a solid box hanging below the road's outer edge. 0 = no base.
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


## The extruder's input: {points, mats}. points are (lateral, y) breakpoints left->right;
## zero-width strips are dropped here, so the extruder never sees degenerate quads.
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
	# Bridge base box, not routed through the zero-width filter (it would drop the walls).
	if base_depth > 0.0 and points.size() >= 2:
		var left := points[0]
		var right := points[points.size() - 1]
		points.append(Vector2(right.x, right.y - base_depth))   # right wall
		points.append(Vector2(left.x, left.y - base_depth))     # bottom
		points.append(left)                                     # left wall
		mats.append_array(PackedInt32Array([SLOT_BASE, SLOT_BASE, SLOT_BASE]))
	return {"points": points, "mats": mats}


func materials() -> Array:
	return [surface_material, edge_line_material, shoulder_material, base_material]


func paved_half_width() -> float:
	return maxf(lane_width, 0.0) + maxf(edge_line_width, 0.0) + maxf(shoulder_width, 0.0)


func full_half_width() -> float:
	return paved_half_width() + maxf(drop_run, 0.0)

@tool
class_name ScatterCanvas
extends ScatterBase
## Hand-painted scatter. Placed under the level's AuthoringRoot; the
## second front-end on the scatter core. Where ScatterRegion fills a footprint by
## regeneration, ScatterCanvas stores instances the author PAINTS in with the scatter brush
## (addons/carlito_kit/scatter_brush.gd) — density-per-stroke placement plus radius erase, using
## the same jitter knobs (yaw/scale/spacing/slope on ScatterBase) and the same seeded sampler
## (ScatterRegion.generate_placements) and ground snapping.
##
## The stored-transform contract is identical to the region's: brush strokes append/remove
## region-local stride-5 transforms in the scene (authored content — serialized, CI-hashed,
## undoable), and the baker / dev-play consume STORED transforms only. So a canvas renders and
## bakes through the exact same ScatterBase + LevelBaker path as a region (MultiMesh preview,
## MultiMesh-above-threshold / prefab-merge-below at bake, identical collision harvest). This
## node adds only the paint-density knob and one pure erase helper (unit-tested in
## tests/test_scatter.gd); all the interaction lives in the editor brush, never here.

## Target instances per square metre a paint dab lays down (the brush multiplies by its dab
## area). min_spacing still caps how dense a stroke can actually get.
@export var paint_density := 0.08

## Placement pattern the brush uses. "random" is the seeded rejection sampler (paint_density +
## min_spacing); "grid" lays one instance per world-anchored lattice cell (grid_step), for corn
## rows, orchards and neat grass patches — density and min_spacing are ignored there.
@export_enum("random", "grid") var paint_pattern := "random"
## Grid pattern only: world-space lattice step in metres (X, Z). Anchored to the world origin,
## so separate strokes and rect fills continue the same lattice.
@export var grid_step := Vector2(1.0, 1.0)


## Return `stored` with every instance whose world XZ is within `radius` of `center` removed —
## the pure core of the brush's erase, across all items. `base_xform` is the canvas's world
## transform (stored transforms are region-local). Pure/static so it is unit-tested.
static func erase_within(stored: Array[PackedFloat32Array], base_xform: Transform3D,
		center: Vector3, radius: float) -> Array[PackedFloat32Array]:
	var r2 := radius * radius
	var cx := center.x
	var cz := center.z
	var out: Array[PackedFloat32Array] = []
	for flat in stored:
		var kept := PackedFloat32Array()
		for j in stored_count(flat):
			var world := base_xform * stored_transform(flat, j).origin
			var dx := world.x - cx
			var dz := world.z - cz
			if dx * dx + dz * dz > r2:
				kept.append_array(flat.slice(j * STRIDE, j * STRIDE + STRIDE))
		out.append(kept)
	return out


func _extra_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not items.is_empty():
		var total := 0
		for flat in stored_transforms:
			total += stored_count(flat)
		if total == 0:
			warnings.append("No instances painted yet. Select this canvas, open the Scatter Brush dock, pick Paint, and drag in the 3D view.")
	return warnings

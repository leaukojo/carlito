@tool
class_name ScatterCanvas
extends ScatterBase
## Hand-painted scatter: the second front-end on the scatter core. Where ScatterRegion
## fills a footprint by regeneration, ScatterCanvas stores instances the author paints in
## with the scatter brush (addons/carlito_kit/scatter_brush.gd), sharing ScatterBase's
## jitter knobs, seeded sampler, ground snapping, and stored-transform contract. This
## node adds only the paint-density knob and one pure erase helper
## (tests/test_scatter.gd); interaction lives in the editor brush.

## Target instances/m^2 a paint dab lays down. min_spacing still caps density.
@export var paint_density := 0.08

## "random" = seeded rejection sampler; "grid" = one instance per lattice cell (grid_step).
@export_enum("random", "grid") var paint_pattern := "random"
## Grid pattern only: world-space lattice step (m), anchored to the world origin.
@export var grid_step := Vector2(1.0, 1.0)


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

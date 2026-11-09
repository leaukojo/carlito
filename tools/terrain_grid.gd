extends RefCounted
## World <-> pixel mapping for a level generator's working heightmap and splat images, in
## HeightmapTerrain's own convention: the grid spans [-span/2, +span/2] about the terrain's
## origin, `iw` x `ih` pixels across. A generator that writes its terrain at the world origin
## passes `Vector3.ZERO`.

const BrushOps := preload("res://kit/helpers/brush_ops.gd")

var span: Vector2
var origin: Vector3
var height: float     ## world Y of a white pixel
var iw: int
var ih: int
var sx: float         ## pixels per metre on X
var sz: float


func _init(terrain_span: Vector2, terrain_origin: Vector3, terrain_height: float,
		width: int, depth: int) -> void:
	span = terrain_span
	origin = terrain_origin
	height = terrain_height
	iw = width
	ih = depth
	sx = float(iw - 1) / maxf(span.x, 0.001)
	sz = float(ih - 1) / maxf(span.y, 0.001)


## World Y -> the 0..1 a heightmap pixel stores.
func norm(y: float) -> float:
	return clampf(y / maxf(height, 0.001), 0.0, 1.0)


## World X -> pixel column, clamped onto the image.
func px_x(x: float) -> int:
	return clampi(int(round((x - origin.x + span.x * 0.5) * sx)), 0, iw - 1)


func px_z(z: float) -> int:
	return clampi(int(round((z - origin.z + span.y * 0.5) * sz)), 0, ih - 1)


func world_x(px: int) -> float:
	return float(px) / sx - span.x * 0.5 + origin.x


func world_z(pz: int) -> float:
	return float(pz) / sz - span.y * 0.5 + origin.z


## Flatten `rect` (world XZ) to `target_y` with a soft blend ring `margin` wide, using the
## square brush stamp. Falloff derives from the longer half-extent so the hard core covers both
## axes (BrushOps' square brush measures one Chebyshev distance against per-axis radii).
func flatten(img: Image, rect: Rect2, target_y: float, margin: float) -> void:
	var half_x := rect.size.x * 0.5 + margin
	var half_z := rect.size.y * 0.5 + margin
	var falloff := margin / maxf(half_x, half_z)
	var c := rect.get_center()
	BrushOps.stamp_height(img, px_x(c.x), px_z(c.y), half_x * sx, half_z * sz,
			BrushOps.FLATTEN, 1.0, falloff, norm(target_y), true)

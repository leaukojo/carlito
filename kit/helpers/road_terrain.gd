extends RefCounted
## A road's footprint on a terrain, and the two destructive writes under it: Conform (flatten
## the heightmap) and Paint (the splat channel). The one core behind RoadPath's editor buttons
## and the level generators (`tools/road_gen.gd`). Static, deterministic, editor-free
## (tests/test_road_terrain.gd). The pixel work is RoadBuilder.conform_heights and
## SplatPaint.paint_strip; this file owns the sampling and the terrain-local frame.

const BrushOps := preload("res://kit/helpers/brush_ops.gd")
const SplatPaint := preload("res://kit/helpers/splat_paint.gd")


## The footprint of `curve` at `half_width`, moved by `xform` (the curve's frame in the
## terrain's world): {samples: the centreline at the extrusion's ring offsets, so a write
## targets the ribbon's chordal surface, not the analytic curve above it over a crest; deck: the
## triangle vertices of a strip extruded on the ribbon's own frames, since the centreline's
## projection alone mis-heights steep, yawing segments}.
static func footprint(curve: Curve3D, half_width: float, banking: bool, max_seg_len: float,
		max_seg_angle: float, xform := Transform3D.IDENTITY) -> Dictionary:
	var offsets := RoadBuilder.adaptive_offsets(curve, max_seg_len, max_seg_angle)
	var samples := PackedVector3Array()
	for o in offsets:
		samples.append(xform * curve.sample_baked(o))
	var deck_surfaces: Dictionary = RoadBuilder.extrude(curve,
			PackedVector2Array([Vector2(-half_width, 0), Vector2(half_width, 0)]),
			PackedInt32Array([0]), offsets, banking)
	var deck := PackedVector3Array()
	for v in RoadBuilder.faces_from_surfaces(deck_surfaces):
		deck.append(xform * v)
	return {"samples": samples, "deck": deck}


## World height `y`, less `epsilon`, as a share of a terrain `height` m tall at `origin_y`:
## what the heightmap stores, unclamped (outside [0, 1] the terrain cannot reach it).
static func height_norm(y: float, origin_y: float, height: float, epsilon: float) -> float:
	return (y - epsilon - origin_y) / height


## A centreline sample of `fp` sits outside the terrain's height range, so `conform` clamps there.
static func leaves_height_range(fp: Dictionary, origin_y: float, height: float,
		epsilon: float) -> bool:
	for w: Vector3 in fp["samples"]:
		var n := height_norm(w.y, origin_y, height, epsilon)
		if n < 0.0 or n > 1.0:
			return true
	return false


## Flatten `heights` under the footprint `fp` to `epsilon` below the road, flat over
## `half_width` and blending out over `falloff` m. The terrain is centred on `origin`, `span` m
## across (x, z) and `height` m tall. Returns the dirty pixel rect; an empty one means the road
## missed the terrain.
static func conform(heights: Image, fp: Dictionary, half_width: float, falloff: float,
		origin: Vector3, span: Vector2, height: float, epsilon: float) -> Rect2i:
	return RoadBuilder.conform_heights(heights, _terrain_local(fp["samples"], origin, height,
			epsilon), half_width, falloff, span.x, span.y,
			_terrain_local(fp["deck"], origin, height, epsilon))


## Paint splat `channel` at full strength under the footprint `fp`, `half_width` either side,
## into `images` (the splatmap, then splatmap2 where the terrain has one). The terrain is
## centred on `origin`, `span` m across (x, z). Returns the dirty pixel rect.
static func paint(images: Array[Image], channel: int, fp: Dictionary, half_width: float,
		origin: Vector3, span: Vector2) -> Rect2i:
	var units: Array[Color] = []
	for i in images.size():
		units.append(BrushOps.unit_slice(channel, i))
	return SplatPaint.paint_strip(images, units, _terrain_xz(fp["samples"], origin),
			half_width, span.x, span.y, _terrain_xz(fp["deck"], origin))


## World points as conform_heights' (x, z, clamped height share) triples.
static func _terrain_local(world: PackedVector3Array, origin: Vector3, height: float,
		epsilon: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for w in world:
		out.append(Vector3(w.x - origin.x, w.z - origin.z,
				clampf(height_norm(w.y, origin.y, height, epsilon), 0.0, 1.0)))
	return out


static func _terrain_xz(world: PackedVector3Array, origin: Vector3) -> PackedVector2Array:
	var out := PackedVector2Array()
	for w in world:
		out.append(Vector2(w.x - origin.x, w.z - origin.z))
	return out

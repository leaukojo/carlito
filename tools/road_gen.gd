## RoadPath's Conform and Paint splat, headless: the editor buttons go through
## EditorUndoRedoManager, so a generator that owns its terrain calls this pure core on its working
## images instead. The footprint is the same one RoadPath uses: centreline samples at the
## extrusion's ring offsets, plus a deck strip extruded on the ribbon's own frames.
## COMPROMISE: RoadPath (`kit/helpers/road_path.gd`) still carries its own copy; folding it onto
## this file re-stales every level it builds, so it waits for a commit that rebakes anyway.

const BrushOps := preload("res://kit/helpers/brush_ops.gd")
const SplatPaint := preload("res://kit/helpers/splat_paint.gd")

## RoadPath's export defaults, so an editor Conform on a generated road replays it.
const MAX_SEG_LEN := 6.0
const MAX_SEG_ANGLE := 6.0
const CONFORM_EPSILON := 0.05


## World-space footprint of `curve` (in the terrain's frame) at `half_width`: {samples: the
## centreline at the ring offsets, deck: the extruded strip's triangle vertices}.
static func footprint(curve: Curve3D, half_width: float, banking := false) -> Dictionary:
	var offsets := RoadBuilder.adaptive_offsets(curve, MAX_SEG_LEN, MAX_SEG_ANGLE)
	var samples := PackedVector3Array()
	for o in offsets:
		samples.append(curve.sample_baked(o))
	var deck_surfaces: Dictionary = RoadBuilder.extrude(curve,
			PackedVector2Array([Vector2(-half_width, 0), Vector2(half_width, 0)]),
			PackedInt32Array([0]), offsets, banking)
	return {"samples": samples, "deck": RoadBuilder.faces_from_surfaces(deck_surfaces)}


## Flatten `heights` (a `size` m square terrain at the origin, `height` m white) under the road's
## full width, blending out over `falloff` m. Returns the dirty pixel rect; an empty one means
## the road missed the terrain.
static func conform(heights: Image, curve: Curve3D, profile: Resource, falloff: float,
		size: float, height: float) -> Rect2i:
	var fw: float = profile.call("full_half_width")
	var fp := footprint(curve, fw)
	var samples := PackedVector3Array()
	for w: Vector3 in fp["samples"]:
		samples.append(Vector3(w.x, w.z, clampf((w.y - CONFORM_EPSILON) / height, 0.0, 1.0)))
	var deck := PackedVector3Array()
	for v: Vector3 in fp["deck"]:
		deck.append(Vector3(v.x, v.z, clampf((v.y - CONFORM_EPSILON) / height, 0.0, 1.0)))
	return RoadBuilder.conform_heights(heights, samples, fw, falloff, size, size, deck)


## Paint the profile's splat channel into both weight images under the road, at the paved
## half-width less RoadPath.SPLAT_PAINT_INSET, so the paint stays hidden under the deck and a
## conformed road grips like asphalt instead of like the grass under it. False (and nothing
## painted) when the profile is too narrow to paint under.
static func paint(splat: Image, splat2: Image, curve: Curve3D, profile: Resource,
		size: float) -> bool:
	var channel: int = profile.get("splat_channel")
	var pw: float = float(profile.call("paved_half_width")) - RoadPath.SPLAT_PAINT_INSET
	if pw <= 0.0:
		return false
	var fp := footprint(curve, pw)
	var samples := PackedVector2Array()
	for w: Vector3 in fp["samples"]:
		samples.append(Vector2(w.x, w.z))
	var deck := PackedVector2Array()
	for v: Vector3 in fp["deck"]:
		deck.append(Vector2(v.x, v.z))
	var images: Array[Image] = [splat, splat2]
	var units: Array[Color] = [
		BrushOps.unit_slice(channel, 0), BrushOps.unit_slice(channel, 1),
	]
	SplatPaint.paint_strip(images, units, samples, pw, size, size, deck)
	return true

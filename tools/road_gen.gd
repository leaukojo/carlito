## RoadPath's Conform and Paint splat, headless: the editor buttons go through
## EditorUndoRedoManager, so a generator that owns its terrain calls the shared core
## (`kit/helpers/road_terrain.gd`) on its working images instead, at RoadPath's export defaults
## and on a square terrain centred on the origin.

const RoadTerrain := preload("res://kit/helpers/road_terrain.gd")

## RoadPath's export defaults, so an editor Conform on a generated road replays it.
const MAX_SEG_LEN := 6.0
const MAX_SEG_ANGLE := 6.0
const CONFORM_EPSILON := 0.05


## Flatten `heights` (a `size` m square terrain at the origin, `height` m white) under the road's
## full width, blending out over `falloff` m. Returns the dirty pixel rect; an empty one means
## the road missed the terrain.
static func conform(heights: Image, curve: Curve3D, profile: Resource, falloff: float,
		size: float, height: float) -> Rect2i:
	var fw: float = profile.call("full_half_width")
	return RoadTerrain.conform(heights,
			RoadTerrain.footprint(curve, fw, false, MAX_SEG_LEN, MAX_SEG_ANGLE), fw, falloff,
			Vector3.ZERO, Vector2(size, size), height, CONFORM_EPSILON)


## Paint the profile's splat channel into both weight images under the road, at the paved
## half-width less RoadPath.SPLAT_PAINT_INSET, so the paint stays hidden under the deck and a
## conformed road grips like asphalt instead of like the grass under it. False (and nothing
## painted) when the profile is too narrow to paint under.
static func paint(splat: Image, splat2: Image, curve: Curve3D, profile: Resource,
		size: float) -> bool:
	var pw: float = float(profile.call("paved_half_width")) - RoadPath.SPLAT_PAINT_INSET
	if pw <= 0.0:
		return false
	var images: Array[Image] = [splat, splat2]
	RoadTerrain.paint(images, profile.get("splat_channel"),
			RoadTerrain.footprint(curve, pw, false, MAX_SEG_LEN, MAX_SEG_ANGLE), pw,
			Vector3.ZERO, Vector2(size, size))
	return true

@tool
class_name LevelShot
extends Resource
## The camera framing used for a level's screenshot card (the picture on the level-select
## button). Saved as a SIDE-CAR resource next to the level scene — `<level>_shot.tres` —
## deliberately NOT a node in the level: every level `.tscn` is a bake input, so a node
## would re-stale the bake on every re-frame. Nothing in the level scene references this
## file, so bakes never see it.
##
## Written by the kit's Polish tab (Set thumbnail view) from the editor viewport framing;
## read by `tools/gen_level_thumbs.gd`, which renders the PNG. Runtime-safe: no editor
## APIs (the capture tool loads it in game mode).

## Where the card PNGs live. Under `src/` on purpose: `kit/thumbs/*` and `tools/*` are
## export-excluded, and level-select needs these at runtime.
const THUMB_DIR := "res://src/ui/level_thumbs"

## Fallback framing: a fixed 3/4 view from above, and how much slack to leave around the
## bounding sphere so the coastline is not cropped.
const OVERVIEW_DIR := Vector3(0.6, 0.45, 1.0)
## Below 1.0 the bounding sphere is cropped — wanted: a level's subject is a round island in
## a square terrain, so a tight frame fills the card instead of ringing it with sea.
const OVERVIEW_MARGIN := 0.8
const DEFAULT_FOV := 60.0

@export var camera_transform: Transform3D = Transform3D.IDENTITY
@export_range(20.0, 110.0, 0.5) var fov: float = DEFAULT_FOV


## `res://.../level_1.tscn` -> `res://.../level_1_shot.tres`.
static func path_for(level_scene_path: String) -> String:
	return level_scene_path.get_basename() + "_shot.tres"


## The saved framing for a level scene, or null when the author never set one
## (the capture tool then falls back to `overview()`).
static func load_for(level_scene_path: String) -> LevelShot:
	var path := path_for(level_scene_path)
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as LevelShot


static func thumb_path(level_id: String) -> String:
	return "%s/%s.png" % [THUMB_DIR, level_id]


## Default overview: look down OVERVIEW_DIR at the centre of `bounds` from far enough that
## its bounding sphere fits the frustum. Same math as the kit thumbnailer's framing.
static func overview(bounds: AABB, view_fov: float) -> Transform3D:
	var center := bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.5, 0.01)
	var dist := radius / sin(deg_to_rad(maxf(view_fov, 1.0) * 0.5)) * OVERVIEW_MARGIN
	var eye := center + OVERVIEW_DIR.normalized() * dist
	return Transform3D(Basis.IDENTITY, eye).looking_at(center, Vector3.UP)

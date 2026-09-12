@tool
class_name LevelShot
extends Resource
## The camera framing for a level's screenshot card. Saved as a side-car resource
## (`<level>_shot.tres`), deliberately not a node — every level `.tscn` is a bake input,
## so a node would re-stale the bake on every re-frame. Written by the kit's Polish tab;
## read by `tools/gen_level_thumbs.gd`. Runtime-safe: no editor APIs.

## Under `src/`: `kit/thumbs/*` and `tools/*` are export-excluded, but level-select needs this at runtime.
const THUMB_DIR := CardImport.LEVEL_THUMB_DIR

const OVERVIEW_DIR := Vector3(0.6, 0.45, 1.0)   # fallback: fixed 3/4 view from above
const OVERVIEW_MARGIN := 0.8   # below 1.0 the bounding sphere crops
const DEFAULT_FOV := 60.0

@export var camera_transform: Transform3D = Transform3D.IDENTITY
@export_range(20.0, 110.0, 0.5) var fov: float = DEFAULT_FOV
## Keeps the spawned default vehicle in frame instead of freeing it (endless levels with no
## other landmark need the vehicle to read as anything but an empty rectangle).
@export var keep_vehicle := false


static func path_for(level_scene_path: String) -> String:
	return level_scene_path.get_basename() + "_shot.tres"


static func load_for(level_scene_path: String) -> LevelShot:
	var path := path_for(level_scene_path)
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as LevelShot


static func thumb_path(level_id: String) -> String:
	return "%s/%s.png" % [THUMB_DIR, level_id]


## Default overview: look down OVERVIEW_DIR at `bounds`' centre from far enough to fit.
static func overview(bounds: AABB, view_fov: float) -> Transform3D:
	var center := bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.5, 0.01)
	var dist := radius / sin(deg_to_rad(maxf(view_fov, 1.0) * 0.5)) * OVERVIEW_MARGIN
	var eye := center + OVERVIEW_DIR.normalized() * dist
	return Transform3D(Basis.IDENTITY, eye).looking_at(center, Vector3.UP)

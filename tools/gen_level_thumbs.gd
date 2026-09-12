extends Node
## Level card generator: renders the screenshot on each level-select button, to
## src/ui/level_thumbs/<level_id>.png, framed from the level's side-car `<level>_shot.tres`
## (no saved view gets a geometry-bounds overview). Must run WINDOWED. Instantiates the
## level for real, so `Level._ready` swaps in the baked scene — bake first.

const ShotStage := preload("res://tools/shot_stage.gd")
const SceneBounds := preload("res://src/ui/scene_bounds.gd")

const SIZE := Vector2i(640, 360)  # 16:9, 2x the card so it stays crisp
const SETTLE_FRAMES := 40  # terrain mesh build + sky/water shader compile before read-back
const SETTLE_FRAMES_VEHICLE := 90  # a kept vehicle also needs to drop/float onto ground or water
const NEAR := 0.25
const FAR := 6000.0  # islands sit inside a 1900 m far-sea ring
const FOG_HAZE := 0.25  # fog_density * shot distance — see _thin_fog

var _viewport: SubViewport
var _camera: Camera3D


func _ready() -> void:
	var only := OS.get_cmdline_user_args()
	DirAccess.open("res://").make_dir_recursive(LevelShot.THUMB_DIR.trim_prefix("res://"))
	var written := 0
	var failed := 0
	for entry in LevelRegistry.LEVELS:
		var id := String(entry["id"])
		if not only.is_empty() and not only.has(id):
			continue
		if await _shoot(id, String(entry["scene"])):
			written += 1
		else:
			failed += 1
	print("[level thumbs] wrote %d image(s), %d failed" % [written, failed])
	get_tree().quit(1 if failed > 0 else 0)


## Render one level into a throwaway SubViewport and save its PNG. Each level gets a fresh
## viewport (`own_world_3d`) since the level brings its own WorldEnvironment/Sun.
func _shoot(id: String, scene_path: String) -> bool:
	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		push_error("cannot load level scene " + scene_path)
		return false

	_viewport = ShotStage.build_viewport(SIZE)
	add_child(_viewport)

	var level := packed.instantiate() as Node3D
	_viewport.add_child(level)  # runs Level._ready: baked swap + default vehicle

	var shot := LevelShot.load_for(scene_path)
	var keep_vehicle := shot != null and shot.keep_vehicle

	var lvl := level as Level
	if lvl != null:
		if lvl.vehicle != null and not keep_vehicle:
			lvl.vehicle.queue_free()  # landscape only
			lvl.vehicle = null
		if lvl.camera != null:
			lvl.camera.current = false  # the chase camera must not own the viewport

	var subject := _subject_aabb(level)
	_camera = Camera3D.new()
	_camera.near = NEAR
	_camera.far = FAR
	if shot != null:
		_camera.fov = shot.fov
		_camera.global_transform = shot.camera_transform
	else:
		_camera.fov = LevelShot.DEFAULT_FOV
		_camera.global_transform = LevelShot.overview(subject, _camera.fov)
		print("[level thumbs] %s: no saved view, framed an overview" % id)
	_viewport.add_child(_camera)
	_camera.current = true  # set after the level, so it wins over the ChaseCamera
	_thin_fog(level, _camera.global_position.distance_to(subject.get_center()))

	await ShotStage.settle(get_tree(), SETTLE_FRAMES_VEHICLE if keep_vehicle else SETTLE_FRAMES)
	var out := LevelShot.thumb_path(id)
	var ok := ShotStage.save_capture(_viewport, out)

	_viewport.queue_free()
	_viewport = null
	_camera = null

	if not ok:
		return false
	CardImport.ensure_import_settings(out)
	print("[level thumbs] %s -> %s" % [id, out])
	return true


## Fog is tuned for ground-level driving, so a 700 m shot is a white sheet; thin to a fixed
## haze at the shot's own distance. Safe to mutate — Environment is duplicated per level.
func _thin_fog(level: Node3D, dist: float) -> void:
	for node in level.find_children("*", "WorldEnvironment", true, false):
		var env := (node as WorldEnvironment).environment
		if env == null or not env.fog_enabled:
			continue
		env.fog_density = minf(env.fog_density, FOG_HAZE / maxf(dist, 1.0))
		return


## No-saved-view overview frames the terrain, not the whole level (the sea plane stretches
## ~1900 m out). Terrains duck-typed on `terrain_size`; no terrain falls back to everything.
func _subject_aabb(level: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in level.find_children("*", "Node3D", true, false):
		var n3d := node as Node3D
		if n3d == null or not "terrain_size" in n3d:
			continue
		var box := SceneBounds.world_aabb([n3d])
		if box.size == Vector3.ZERO:
			continue
		out = box if first else out.merge(box)
		first = false
	return SceneBounds.world_aabb([level]) if first else out

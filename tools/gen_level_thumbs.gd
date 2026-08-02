extends Node
## Level card generator: renders the screenshot shown on each level-select button, to
## src/ui/level_thumbs/<level_id>.png. The framing comes from the level's side-car
## `<level>_shot.tres` (LevelShot, written by the kit's Polish tab ▸ Set thumbnail view);
## a level with no saved view gets an overview framed from its geometry bounds.
##
## MUST run WINDOWED (a real GPU context) — headless has no renderer, so the SubViewport
## captures come back blank. It is a GAME-MODE tool scene, not --script, for two reasons:
## --script mode cannot load level scenes at all (autoload identifiers don't compile), and
## only a live SceneTree renders frames.
##   godot --path . res://tools/gen_level_thumbs.tscn              # every registry level
##   godot --path . res://tools/gen_level_thumbs.tscn -- level_1   # one level
##
## The level is instantiated for real, so `Level._ready` swaps in the BAKED scene: what the
## card shows is what the player drives (a stale bake shoots stale geometry — bake first).
## The auto-spawned vehicle is freed again: cards are landscape only.

const SIZE := Vector2i(640, 360)  # 16:9, 2x the card so it stays crisp
const SETTLE_FRAMES := 40  # terrain mesh build + sky/water shader compile before read-back
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
## viewport: `own_world_3d` isolates it, but the level brings its own WorldEnvironment/Sun,
## and reusing one stage across levels would mean two environments in one world.
func _shoot(id: String, scene_path: String) -> bool:
	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		push_error("cannot load level scene " + scene_path)
		return false

	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var level := packed.instantiate() as Node3D
	_viewport.add_child(level)  # runs Level._ready: baked swap + default vehicle

	var lvl := level as Level
	if lvl != null:
		if lvl.vehicle != null:
			lvl.vehicle.queue_free()  # landscape only
			lvl.vehicle = null
		if lvl.camera != null:
			lvl.camera.current = false  # the chase camera must not own the viewport

	var subject := _subject_aabb(level)
	_camera = Camera3D.new()
	_camera.near = NEAR
	_camera.far = FAR
	var shot := LevelShot.load_for(scene_path)
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

	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	var img := _viewport.get_texture().get_image()

	_viewport.queue_free()
	_viewport = null
	_camera = null

	if img == null:
		push_error("blank capture for " + scene_path)
		return false
	var out := LevelShot.thumb_path(id)
	if img.save_png(out) != OK:
		push_error("cannot write " + out)
		return false
	CardImport.ensure_import_settings(out)
	print("[level thumbs] %s -> %s" % [id, out])
	return true


## Fog is tuned for driving at ground level (density 0.003 — half a kilometre of visibility),
## so a card shot from 700 m up is a white sheet. Thin it to a fixed amount of haze at the
## shot's own distance: the picture keeps the game's atmosphere without dissolving into it.
## Safe to mutate — Level._ready gives every level a duplicated Environment.
func _thin_fog(level: Node3D, dist: float) -> void:
	for node in level.find_children("*", "WorldEnvironment", true, false):
		var env := (node as WorldEnvironment).environment
		if env == null or not env.fog_enabled:
			continue
		env.fog_density = minf(env.fog_density, FOG_HAZE / maxf(dist, 1.0))
		return


## What the no-saved-view overview frames: the TERRAIN, not the whole level. The sea plane
## and the skyline ring stretch ~1900 m out, so framing every visual would put the camera so
## far back that the island is a speck behind the fog. Terrains are duck-typed on
## `terrain_size` (the same shape the kit tools use), and their built chunk meshes give the
## real height, not the heightmap's full scale. A level without terrain (the garage) falls
## back to everything visible.
func _subject_aabb(level: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in level.find_children("*", "Node3D", true, false):
		var n3d := node as Node3D
		if n3d == null or not "terrain_size" in n3d:
			continue
		var box := _world_aabb(n3d)
		if box.size == Vector3.ZERO:
			continue
		out = box if first else out.merge(box)
		first = false
	return _world_aabb(level) if first else out


## World-space bounds of every visible piece under `root`.
func _world_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for vi in _visuals(root):
		var local := vi.get_aabb()
		var g := vi.global_transform
		for i in 8:
			var corner := local.position + Vector3(
					local.size.x if (i & 1) else 0.0,
					local.size.y if (i & 2) else 0.0,
					local.size.z if (i & 4) else 0.0)
			var w := g * corner
			if first:
				out = AABB(w, Vector3.ZERO)
				first = false
			else:
				out = out.expand(w)
	return out


func _visuals(node: Node) -> Array[VisualInstance3D]:
	var found: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_visuals(child))
	return found

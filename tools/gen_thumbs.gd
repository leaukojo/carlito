extends Node
## Kit thumbnail generator: renders a 128x128 preview PNG for every prefab/palette asset a
## recipe emits, to kit/thumbs/<kit>/<name>.png (gen_kit_assets.gd embeds them as
## MeshLibrary previews). Must run WINDOWED. Regenerates only locally, never CI.

const Recipe := preload("res://kit/helpers/kit_recipe.gd")
const ShotStage := preload("res://tools/shot_stage.gd")
const SceneBounds := preload("res://src/ui/scene_bounds.gd")
const RECIPE_DIR := "res://kit/import"
const THUMB_DIR := "res://kit/thumbs"
const SIZE := 128
const VIEW_DIR := Vector3(1.0, 0.75, 1.0)  # fixed 3/4 iso angle, shared by every thumb
const BACKDROP := Color(0.16, 0.17, 0.20)  # neutral dark slate (reads in editor + dock)

var _viewport: SubViewport
var _camera: Camera3D
var _exit_code := 0


func _ready() -> void:
	_build_stage()
	var total := 0
	var recipes: Variant = Recipe.recipe_paths(RECIPE_DIR, OS.get_cmdline_user_args())
	if recipes == null:
		get_tree().quit(1)
		return
	for path: String in recipes:
		total += await _run_recipe(path)
	print("[thumbs] wrote %d image(s)" % total)
	get_tree().quit(_exit_code)


## One neutral stage reused across every asset: isolated world, backdrop env, key light,
## and a perspective camera repositioned per-asset to frame its AABB.
func _build_stage() -> void:
	_viewport = ShotStage.build_viewport(Vector2i(SIZE, SIZE))
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKDROP
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.88)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -50, 0)
	key.light_energy = 1.3
	_viewport.add_child(key)

	_camera = Camera3D.new()
	_camera.fov = 30.0
	_viewport.add_child(_camera)


func _run_recipe(recipe_path: String) -> int:
	var loaded := Recipe.load_recipe(recipe_path)  # a recipe gen_kit_assets would refuse renders none
	if loaded.has("errors"):
		for e in loaded.errors:
			push_error(e)
		_exit_code = 1
		return 0
	var kit: String = loaded.kit
	var source: String = loaded.source
	var c: Dictionary = loaded.classified
	var fam_by_name: Dictionary = loaded.fam_by_name

	var out_dir := THUMB_DIR.path_join(kit)
	DirAccess.open("res://").make_dir_recursive(out_dir.trim_prefix("res://"))
	var written := 0
	for asset_name: String in c.assignments:
		var fam: Dictionary = fam_by_name[String(c.assignments[asset_name])]
		if String(fam.get("pipeline", "prefab")) == "exclude":
			continue
		if await _render_one(source.path_join(asset_name + ".glb"), out_dir.path_join(asset_name + ".png")):
			written += 1
	print("[thumbs] %s: %d" % [kit, written])
	return written


func _render_one(glb_path: String, out_path: String) -> bool:
	var packed := load(glb_path) as PackedScene
	if packed == null:
		push_error("cannot load " + glb_path)
		return false
	var inst := packed.instantiate() as Node3D
	if inst == null:
		push_error("not a Node3D scene: " + glb_path)
		return false
	_viewport.add_child(inst)

	var aabb := SceneBounds.world_aabb([inst])
	if aabb.size == Vector3.ZERO:
		_viewport.remove_child(inst)
		inst.free()
		push_error("no visible geometry in " + glb_path)
		return false
	_frame(aabb)

	# A couple of ticks let the added mesh + moved camera land in the captured texture.
	await ShotStage.settle(get_tree(), 2)
	var ok := ShotStage.save_capture(_viewport, out_path)

	_viewport.remove_child(inst)
	inst.free()

	return ok


## Point the camera down VIEW_DIR at the AABB centre, far enough that the bounding
## sphere fits the frustum (with a small margin).
func _frame(aabb: AABB) -> void:
	var center := aabb.get_center()
	var radius := maxf(aabb.size.length() * 0.5, 0.01)
	var dist := radius / sin(deg_to_rad(_camera.fov * 0.5)) * 1.1
	var dir := VIEW_DIR.normalized()
	_camera.position = center + dir * dist
	_camera.look_at(center, Vector3.UP)
	_camera.near = maxf(0.01, dist - radius * 2.0)
	_camera.far = dist + radius * 2.0 + 1.0


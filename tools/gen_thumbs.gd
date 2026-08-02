extends Node
## Kit thumbnail generator: renders a 128x128
## preview PNG for every prefab/palette asset a recipe emits, to kit/thumbs/<kit>/<name>.png.
## gen_kit_assets.gd then embeds them as MeshLibrary item previews (the built-in GridMap
## palette shows pictures) and the palette dock loads them from disk.
##
## MUST run WINDOWED (a real GPU context) — headless has no renderer, so the SubViewport
## captures come back blank. It is a GAME-MODE tool scene, not --script, for the same reason
## bake_levels is: it never touches level scenes, but running as a scene gives a live
## SceneTree whose frames actually render.
##   godot --path . res://tools/gen_thumbs.tscn            # all kits
##   godot --path . res://tools/gen_thumbs.tscn -- racing  # one kit (faster iteration)
##
## Asset selection reuses the SAME classification as the generator (KitRecipe, single source
## of truth): every accounted, non-excluded GLB gets a thumb. The raw GLB scene is rendered
## (faithful materials), framed to fit its AABB from a fixed 3/4 angle over a neutral backdrop.
## Thumbs regenerate ONLY with this tool (local, like palette regen — never CI).

const Recipe := preload("res://kit/helpers/kit_recipe.gd")
const RECIPE_DIR := "res://kit/import"
const THUMB_DIR := "res://kit/thumbs"
const SIZE := 128
const VIEW_DIR := Vector3(1.0, 0.75, 1.0)  # fixed 3/4 iso angle, shared by every thumb
const BACKDROP := Color(0.16, 0.17, 0.20)  # neutral dark slate (reads in editor + dock)

var _viewport: SubViewport
var _camera: Camera3D


func _ready() -> void:
	_build_stage()
	var only := OS.get_cmdline_user_args()
	var code := 0
	var total := 0
	var dir := DirAccess.open(RECIPE_DIR)
	if dir == null:
		push_error("cannot open " + RECIPE_DIR)
		get_tree().quit(1)
		return
	var recipes := []
	for f in dir.get_files():
		if f.ends_with(".json") and (only.is_empty() or only.has(f.get_basename())):
			recipes.append(RECIPE_DIR.path_join(f))
	recipes.sort()
	for path in recipes:
		total += await _run_recipe(path)
	print("[thumbs] wrote %d image(s)" % total)
	get_tree().quit(code)


## One neutral stage reused across every asset: isolated world, backdrop env, key light,
## and a perspective camera repositioned per-asset to frame its AABB.
func _build_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(recipe_path))
	if parsed == null or not parsed is Dictionary:
		push_error("bad recipe json: " + recipe_path)
		return 0
	var recipe: Dictionary = parsed
	var kit := String(recipe.get("kit", recipe_path.get_file().get_basename()))
	var source := String(recipe.get("source", ""))
	var families: Array = recipe.get("families", [])

	var src := DirAccess.open(source)
	if src == null:
		push_error("%s: cannot open source '%s'" % [kit, source])
		return 0
	var names: Array[String] = []
	for f in src.get_files():
		if f.ends_with(".glb"):
			names.append(f.get_basename())
	names.sort()

	var c := Recipe.classify(names, families)
	var fam_by_name := {}
	for fam: Dictionary in families:
		fam_by_name[String(fam.get("name", ""))] = fam

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

	var aabb := _world_aabb(inst)
	if aabb.size == Vector3.ZERO:
		_viewport.remove_child(inst)
		inst.free()
		push_error("no visible geometry in " + glb_path)
		return false
	_frame(aabb)

	# UPDATE_ALWAYS renders each frame; a couple of ticks let the added mesh + moved
	# camera land in the captured texture before read-back.
	await get_tree().process_frame
	await get_tree().process_frame
	var img := _viewport.get_texture().get_image()

	_viewport.remove_child(inst)
	inst.free()

	if img == null:
		push_error("blank capture for " + glb_path)
		return false
	return img.save_png(out_path) == OK


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

@tool
extends RefCounted
## Polish tab's level-card tools: save the current 3D viewport framing as the level's
## screenshot camera, and shoot the card PNG from it. The framing is a side-car resource
## (`<level>_shot.tres`, LevelShot), never a node in the level, so re-framing never re-stales
## the bake. Shooting spawns a second Godot process running `tools/gen_level_thumbs.tscn` to
## render the baked, running level; it blocks the editor for a few seconds.

const CAPTURE_SCENE := "res://tools/gen_level_thumbs.tscn"


static func save_view(scene_root: Node) -> void:
	var level_path := _level_path(scene_root)
	if level_path.is_empty():
		return
	var cam := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if cam == null:
		push_warning("Kit: no 3D viewport camera to read a thumbnail view from.")
		return
	var shot := LevelShot.new()
	shot.camera_transform = cam.global_transform
	shot.fov = cam.fov
	var out := LevelShot.path_for(level_path)
	if ResourceSaver.save(shot, out) != OK:
		push_warning("Kit: could not write " + out)
		return
	EditorInterface.get_resource_filesystem().update_file(out)
	print("Kit: saved thumbnail view for '%s' (fov %.1f) -> %s"
			% [level_path.get_file(), shot.fov, out])


static func shoot(scene_root: Node) -> void:
	var level_path := _level_path(scene_root)
	if level_path.is_empty():
		return
	var id := _level_id(level_path)
	if id.is_empty():
		push_warning("Kit: '%s' is not in LevelRegistry — level-select only shows registered "
				% level_path.get_file() + "levels, so it has no card to shoot.")
		return
	if LevelShot.load_for(level_path) == null:
		print("Kit: no saved thumbnail view for '%s' — shooting a generated overview." % id)

	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"),
			CAPTURE_SCENE, "--", id])
	var output := []
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	for line in output:
		print(String(line).strip_edges())
	if code != 0:
		push_warning("Kit: thumbnail capture failed (exit %d) — see the output above." % code)
		return
	EditorInterface.get_resource_filesystem().scan()
	print("Kit: shot the level card for '%s'." % id)


## The edited scene's file path, or "" (with a warning) when there is nothing to work on.
static func _level_path(scene_root: Node) -> String:
	if scene_root == null:
		push_warning("Kit: no scene open.")
		return ""
	if scene_root.scene_file_path.is_empty():
		push_warning("Kit: save the level scene first — its thumbnail files sit next to it.")
		return ""
	return scene_root.scene_file_path


static func _level_id(level_path: String) -> String:
	for entry in LevelRegistry.LEVELS:
		if String(entry["scene"]) == level_path:
			return String(entry["id"])
	return ""

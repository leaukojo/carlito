extends Node
## CLI bake runner: bakes registered levels headless with the same LevelBaker the editor
## Bake button uses. Game-mode tool scene, not --script (level scenes type against
## BaseVehicle, which needs the InputRouter autoload registered to compile). With no args,
## bakes every LevelRegistry level with a non-empty AuthoringRoot (the same predicate as
## check_bakes); with explicit paths, a missing AuthoringRoot is an error.

const Baker := preload("res://kit/bake/level_baker.gd")
const Registry := preload("res://src/shell/level_registry.gd")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var explicit := not args.is_empty()
	var paths: Array[String] = []
	if explicit:
		for a in args:
			paths.append("res://" + String(a).trim_prefix("res://"))
	else:
		for entry: Dictionary in Registry.LEVELS:
			paths.append(String(entry["scene"]))

	var code := 0
	var baked := 0
	var skipped := 0
	var failed := 0
	for path in paths:
		if not explicit and not _has_authoring(path):
			print("[bake] %s: no AuthoringRoot content, skipped" % path)
			skipped += 1
			continue
		var result: Dictionary = Baker.bake_level_file(path)
		if result.ok:
			baked += 1
			var s: Dictionary = result.stats
			print("[bake] %s: OK — %d chunks, %d surfaces + %d scatter multimeshes (est. draw calls, budget <500 §5.4), %d verts, %d body shapes, %d drivable tris, %d scatter instances" %
					[path, s.chunks, s.surfaces, s.scatter_multimeshes, s.vertices,
					s.shapes, s.drivable_triangles, s.scatter_instances])
		else:
			code = 1
			failed += 1
			for e in result.errors:
				printerr("[bake] %s: %s" % [path, e])
	# The completion sentinel CI requires (with 0 failed): headless exit codes are unreliable.
	print("[bake] complete: %d baked, %d skipped, %d failed" % [baked, skipped, failed])
	get_tree().quit(code)


func _has_authoring(path: String) -> bool:
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var root := packed.instantiate()
	var found := Baker.has_bakeable_authoring(Baker.find_authoring(root))
	root.free()
	return found

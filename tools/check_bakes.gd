extends Node
## CI stale-bake check: for every registered level with an
## AuthoringRoot, recompute the authoring-input hash and compare it against the
## committed bake manifest. Exits non-zero on any missing or stale bake, so
## "repainted the GridMap, forgot to re-bake" cannot ship. Game-mode tool scene for
## the same autoload-compilation reason as bake_levels.gd:
##   godot --headless --path . res://tools/check_bakes.tscn

const Baker := preload("res://kit/bake/level_baker.gd")
const Registry := preload("res://src/shell/level_registry.gd")


func _ready() -> void:
	var code := 0
	for entry: Dictionary in Registry.LEVELS:
		var path := String(entry["scene"])
		var result: Dictionary = Baker.check_level_file(path)
		match String(result.status):
			"no_authoring":
				print("[check-bakes] %s: no kit authoring content, skipped" % path)
			"fresh":
				print("[check-bakes] %s: fresh" % path)
			_:
				code = 1
				printerr("[check-bakes] %s: %s — %s (re-bake: tools/bake_levels.tscn or the AuthoringRoot Bake button, then commit %s + %s)" %
						[path, result.status, result.detail,
						Baker.baked_scene_path(path), Baker.manifest_path(path)])
	get_tree().quit(code)

extends GdUnitTestSuite
## Nothing in the game, the suite or `--editor` loads a `res://tools/` script, so a parse error
## there (a deleted constant a measure tool still names) passes every other gate. Loading a
## script compiles it without running it: an `extends SceneTree` tool's `_init` and a `@tool`
## node's `_ready` fire only on instantiation.

const TOOLS_DIR := "res://tools"


static func _scripts_under(dir: String, out: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_scripts_under(dir.path_join(sub), out)
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == "gd":
			out.append(dir.path_join(file))


func test_every_tool_script_compiles() -> void:
	var paths := PackedStringArray()
	_scripts_under(TOOLS_DIR, paths)
	assert_array(paths).is_not_empty()
	var broken := PackedStringArray()
	for path in paths:
		var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as Script
		if script == null or not script.can_instantiate():
			broken.append(path)
	assert_array(broken) \
		.override_failure_message("tool scripts that do not compile (the SCRIPT ERROR lines "
				+ "above say why): %s" % [broken]) \
		.is_empty()

extends Node
## CI stale-bake check: for every registered level with an AuthoringRoot, recompute the
## authoring-input hash and compare it against the committed bake manifest. Exits non-zero
## on any missing or stale bake. The .baked.scn itself is untracked build output, so a
## level whose manifest verifies with no artifact on disk reads "unbuilt" and passes.
## Game-mode tool scene, same autoload-compilation reason as bake_levels.gd:
##   godot --headless --path . res://tools/check_bakes.tscn

const Baker := preload("res://kit/bake/level_baker.gd")
const Registry := preload("res://src/shell/level_registry.gd")


func _ready() -> void:
	var code := 0
	var fresh := 0
	var unbuilt := 0
	var stale := 0
	var skipped := 0
	for entry: Dictionary in Registry.LEVELS:
		var path := String(entry["scene"])
		var result: Dictionary = Baker.check_level_file(path)
		match String(result.status):
			"no_authoring":
				skipped += 1
				print("[check-bakes] %s: no kit authoring content, skipped" % path)
			"fresh":
				fresh += 1
				print("[check-bakes] %s: fresh" % path)
			"unbuilt":
				# Not a failure: a fresh clone/CI checkout arrives with the manifest and no
				# artifact, and the manifest verified is the whole staleness question.
				unbuilt += 1
				print("[check-bakes] %s: manifest fresh, no local .baked.scn (run tools/bake_levels.tscn)"
						% path)
			_:
				code = 1
				stale += 1
				printerr("[check-bakes] %s: %s — %s (re-bake: tools/bake_levels.tscn or the AuthoringRoot Bake button, then commit %s)" %
						[path, result.status, result.detail, Baker.manifest_path(path)])
				# Per-file hash dump: a stale verdict this run has always been a cross-platform
				# text-hash mismatch (a text format missing from Baker.TEXT_EXTS hashed as raw
				# bytes, which differ Windows CRLF vs Linux LF checkout) rather than a genuine
				# content change. Printed here so CI itself names the offending file instead of
				# a re-run with an ad hoc debug patch.
				for f in Baker.gather_bake_inputs(path):
					print("[check-bakes][hash] %s : %s" % [f, Baker.hash_file(f)])
	# Completion sentinel, printed only once every level has been checked. Callers must
	# read this rather than the process exit code: headless Godot can finish the whole
	# check and still die during teardown (intermittent SIGSEGV), turning a clean run into
	# a non-zero exit. No sentinel means the run did not finish — treat that as failure too.
	print("[check-bakes] complete: %d fresh, %d unbuilt, %d stale, %d skipped" %
			[fresh, unbuilt, stale, skipped])
	get_tree().quit(code)

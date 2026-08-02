@tool
class_name AuthoringRoot
extends Node3D
## The authoring container of a level: every GridMap palette and
## KitPiece prefab an author places goes under this node. It is the bake tool's
## input and never ships — Level frees it at runtime when a baked scene exists,
## and the export plugin strips it from exported scenes entirely.
##
## Bake output lands next to the level scene by convention:
##   <level>.baked.scn  +  <level>.bake.json (input-hash manifest, checked by CI).

## Chunk edge length in world units (the knob trading frustum
## culling for batching; the §5.4 draw-call budget is the guardrail).
@export var chunk_size := 48.0

@export_tool_button("Bake level (save scene first)") var bake_action := _bake_pressed


## Duck-typing marker: baker, Level, and the export-strip plugin detect this node
## via has_method() so CLI runs never depend on class_name cache state.
func is_carlito_authoring() -> bool:
	return true


func _bake_pressed() -> void:
	var level_root := owner if owner != null else get_parent()
	if level_root == null or level_root.scene_file_path.is_empty():
		push_error("AuthoringRoot: can't bake — no owning level scene (save the scene first)")
		return
	# Bakes from the file on disk so the stamped hash matches what git sees; unsaved
	# edits are invisible to it. The button label reminds authors to Ctrl+S first.
	var result: Dictionary = LevelBaker.bake_level_file(level_root.scene_file_path)
	if result.ok:
		print("Bake OK: %s -> %s" % [level_root.scene_file_path, str(result.stats)])
	else:
		for e in result.errors:
			push_error("Bake failed: %s" % e)

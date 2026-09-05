@tool
class_name AuthoringRoot
extends Node3D
## The authoring container of a level: every GridMap palette and KitPiece prefab goes
## under this node. Bake tool input, never ships — Level frees it at runtime when a
## baked scene exists, and export strips it entirely.

## Chunk edge length (m): trades frustum culling for batching.
@export var chunk_size := 48.0

@export_tool_button("Bake level (save scene first)") var bake_action := _bake_pressed

const Groups := preload("res://src/levels/base/carlito_groups.gd")


## `_init`, not `_enter_tree`: the baker walks a level scene never added to a tree.
func _init() -> void:
	add_to_group(Groups.AUTHORING)


func _bake_pressed() -> void:
	var level_root := owner if owner != null else get_parent()
	if level_root == null or level_root.scene_file_path.is_empty():
		push_error("AuthoringRoot: can't bake — no owning level scene (save the scene first)")
		return
	# Bakes from disk so the stamped hash matches git; unsaved edits are invisible to it.
	var result: Dictionary = LevelBaker.bake_level_file(level_root.scene_file_path)
	if result.ok:
		print("Bake OK: %s -> %s" % [level_root.scene_file_path, str(result.stats)])
	else:
		for e in result.errors:
			push_error("Bake failed: %s" % e)

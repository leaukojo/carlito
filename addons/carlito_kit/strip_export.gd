@tool
extends EditorExportPlugin
## Export-time counterpart of Level._setup_baked: strips each exported scene's
## AuthoringRoot subtree (GridMap palettes + KitPiece prefabs) so the pck ships only
## baked geometry. export_presets.cfg's exclude_filter drops the raw kit assets too.

const Groups := preload("res://src/levels/base/carlito_groups.gd")

## Bump when customization logic changes; Godot caches customized scenes keyed by this.
const CONFIG_HASH := 0xC2417001


func _get_name() -> String:
	return "carlito_kit_strip_authoring"


func _begin_customize_scenes(_platform: EditorExportPlatform, _features: PackedStringArray) -> bool:
	return true


func _customize_scene(scene: Node, _path: String) -> Node:
	var authoring := Groups.find_authoring(scene)
	if authoring == null:
		return null  # untouched — lets the export cache skip re-processing
	authoring.get_parent().remove_child(authoring)
	authoring.free()
	return scene


func _get_customization_configuration_hash() -> int:
	return CONFIG_HASH

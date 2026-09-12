@tool
extends EditorExportPlugin
## Export-time counterpart of Level._setup_baked: strips each exported scene's
## AuthoringRoot subtree (GridMap palettes + KitPiece prefabs) so the pck ships only
## baked geometry. export_presets.cfg's exclude_filter drops the raw kit assets too.
## Also ships the bake weights table (LevelRegistry.SHIPPED_WEIGHTS), since an island's bake
## is not in the main pack for the level-select card to measure.

const Groups := preload("res://src/levels/base/carlito_groups.gd")

## Bump when customization logic changes; Godot caches customized scenes keyed by this.
const CONFIG_HASH := 0xC2417001


func _get_name() -> String:
	return "carlito_kit_strip_authoring"


## Keys sorted, so the main pack and every level pack of one build carry identical bytes and
## the level packs' patch diff leaves the table out of them.
func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String,
		_flags: int) -> void:
	add_file(LevelRegistry.SHIPPED_WEIGHTS,
			JSON.stringify(LevelRegistry.bake_weights(), "", true).to_utf8_buffer(), false)


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

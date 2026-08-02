@tool
extends EditorExportPlugin
## Export-time counterpart of Level._setup_baked: every exported
## scene loses its AuthoringRoot subtree (GridMap palettes + KitPiece prefabs), so
## the pck ships only baked geometry. Combined with the export_presets.cfg
## exclude_filter (kit GLBs / palettes / prefabs), authoring data never reaches
## the web build — the shared colormap textures still ship because baked
## materials reference them.

## Bump when the customization logic changes: Godot caches customized scenes
## keyed by this hash.
const CONFIG_HASH := 0xC2417001


func _get_name() -> String:
	return "carlito_kit_strip_authoring"


func _begin_customize_scenes(_platform: EditorExportPlatform, _features: PackedStringArray) -> bool:
	return true


func _customize_scene(scene: Node, _path: String) -> Node:
	var authoring := _find_authoring(scene)
	if authoring == null:
		return null  # untouched — lets the export cache skip re-processing
	authoring.get_parent().remove_child(authoring)
	authoring.free()
	return scene


func _get_customization_configuration_hash() -> int:
	return CONFIG_HASH


## Same duck-typed marker contract as LevelBaker.find_authoring / Level.
static func _find_authoring(node: Node) -> Node:
	if node.has_method("is_carlito_authoring"):
		return node
	for child in node.get_children():
		var found := _find_authoring(child)
		if found != null:
			return found
	return null

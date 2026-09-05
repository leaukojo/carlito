@tool
extends EditorInspectorPlugin
## Swaps ScatterItem's `prefab` resource slot for the kit-prefab dropdowns in prefab_picker.gd.

const PrefabPicker := preload("res://addons/carlito_kit/prefab_picker.gd")


func _can_handle(object: Object) -> bool:
	return object is ScatterItem


func _parse_property(_object: Object, type: Variant.Type, prop_name: String,
		_hint: PropertyHint, _hint_string: String, _usage: int, _wide: bool) -> bool:
	if prop_name != "prefab" or type != TYPE_OBJECT:
		return false
	add_property_editor(prop_name, PrefabPicker.new(), false, "Prefab")
	return true

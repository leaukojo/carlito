extends RefCounted
## Shared read of a vehicle scene's ROOT node off its PackedScene state, never an instance: a
## scene instanced only to be asked a question leaves orphan sub-scenes behind. Asserts through
## gdUnit, so a sweep over `spec_of` fails on a missing spec instead of passing on zero variants.

const _ObjectAssert := preload("res://addons/gdUnit4/src/asserts/GdUnitObjectAssertImpl.gd")


## The value `scene_path`'s root stores for `prop`, or null when the scene leaves it unset.
static func root_property(scene_path: String, prop: StringName) -> Variant:
	var scene := load(scene_path) as PackedScene
	_ObjectAssert.new(scene).override_failure_message("cannot load " + scene_path).is_not_null()
	if scene == null:
		return null
	var state := scene.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == prop:
			return state.get_node_property_value(0, i)
	return null


## The VehicleSpec on `scene_path`'s root, asserted present.
static func spec_in(scene_path: String) -> VehicleSpec:
	var spec := root_property(scene_path, &"spec") as VehicleSpec
	_ObjectAssert.new(spec).override_failure_message(
			"%s: no VehicleSpec in the root's `spec`" % scene_path).is_not_null()
	return spec


## Catalog `variant`'s shipped spec, asserted present.
static func spec_of(variant: String) -> VehicleSpec:
	return spec_in(VehicleCatalog.scene_of(variant))

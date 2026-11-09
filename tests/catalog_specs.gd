extends RefCounted
## `VehicleCatalog`'s root reads (`root_property`, `spec_in`) with gdUnit asserts, so a sweep over
## `spec_of` fails on a missing spec instead of passing on zero variants.

const _ObjectAssert := preload("res://addons/gdUnit4/src/asserts/GdUnitObjectAssertImpl.gd")


## The value `scene_path`'s root stores for `prop`, or null when the scene leaves it unset.
static func root_property(scene_path: String, prop: StringName) -> Variant:
	_ObjectAssert.new(load(scene_path) as PackedScene).override_failure_message(
			"cannot load " + scene_path).is_not_null()
	return VehicleCatalog.root_property(scene_path, prop)


## The VehicleSpec on `scene_path`'s root, asserted present.
static func spec_in(scene_path: String) -> VehicleSpec:
	var spec := root_property(scene_path, &"spec") as VehicleSpec
	_ObjectAssert.new(spec).override_failure_message(
			"%s: no VehicleSpec in the root's `spec`" % scene_path).is_not_null()
	return spec


## Catalog `variant`'s shipped spec, asserted present.
static func spec_of(variant: String) -> VehicleSpec:
	return spec_in(VehicleCatalog.scene_of(variant))

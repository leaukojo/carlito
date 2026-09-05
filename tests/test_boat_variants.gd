extends GdUnitTestSuite
## Watercraft variants pinned against gen_boat_variants.gd RECIPE. Fix failures in recipe,
## not .tscn; re-run `godot --headless --path . res://tools/gen_boat_variants.tscn` to regen.
## Compares EFFECTIVE values (overrides + defaults), not presence of lines.
## Not pinned: probe_points, prop_offset, keel_offset, center_of_mass (derived from hull AABB).

const Gen := preload("res://tools/gen_boat_variants.gd")
const BoatScript := preload("res://src/vehicles/boat/boat.gd")

## Node `@export`s `_build_scene` copies VERBATIM out of a variant's `VARIANTS` entry. The rest of
## what it writes is derived (see the header).
const SCENE_KNOBS := [
	"float_depth", "thrust_force", "rudder_torque", "drag_long", "drag_lat", "drag_yaw",
]
## `VehicleSpec` fields `_build_spec` copies straight out of `BOAT_BASE`, same for every variant.
const SHARED_SPEC_FIELDS := [
	"idle_rpm", "redline_rpm", "reverse_ratio", "final_drive", "efficiency",
	"shift_up_rpm", "shift_down_rpm",
]


# --- roster -------------------------------------------------------------------

## A variant added to the catalog or to the recipe but not the other: the catalog would offer a
## boat the regen path does not maintain, or the recipe would write a boat nothing can select.
func test_recipe_and_catalog_agree_on_the_boat_roster() -> void:
	var recipe := PackedStringArray(Gen.VARIANTS.keys())
	recipe.sort()
	var catalog := VehicleCatalog.variants_in_family("boat")
	catalog.sort()
	assert_array(Array(recipe)).is_equal(Array(catalog))


# --- scene overrides ----------------------------------------------------------

## Read through the SceneState rather than `instantiate()`: the state carries only the scene's own
## overrides, so nothing here can be satisfied by a value the engine would compute at load. What a
## missing override means is the SCRIPT DEFAULT, which is what `_boat_defaults` supplies.
func test_scene_knobs_match_the_recipe() -> void:
	var defaults := _boat_defaults()
	for variant: String in Gen.VARIANTS:
		var ov: Dictionary = Gen.VARIANTS[variant]
		var props := _root_overrides(Gen.OUT_DIR.path_join(variant + ".tscn"))
		for knob: String in SCENE_KNOBS:
			var actual := float(props[knob]) if props.has(knob) else float(defaults[knob])
			var how := "override" if props.has(knob) else "boat.gd default, no override"
			var msg := "%s.tscn %s (%s)" % [variant, knob, how]
			assert_float(actual).override_failure_message(msg).is_equal_approx(float(ov[knob]), 1e-4)


# --- spec fields --------------------------------------------------------------

func test_spec_mass_and_steer_speed_match_the_recipe() -> void:
	for variant: String in Gen.VARIANTS:
		var ov: Dictionary = Gen.VARIANTS[variant]
		var spec := _spec(variant)
		assert_float(spec.mass) \
			.override_failure_message("%s_spec.tres mass" % variant) \
			.is_equal_approx(float(ov["mass"]), 1e-4)
		# steer_speed is the one per-variant override with a BOAT_BASE fallback.
		var expected := float(ov.get("steer_speed", Gen.BOAT_BASE["steer_speed"]))
		assert_float(spec.steer_speed) \
			.override_failure_message("%s_spec.tres steer_speed" % variant) \
			.is_equal_approx(expected, 1e-4)


## The curve is the ONE derived spec field cheap enough to re-derive honestly: the baseline
## points with every y scaled by the variant's `torque_mul`, which is `_scaled_curve`.
func test_spec_torque_curve_is_the_baseline_scaled_by_torque_mul() -> void:
	for variant: String in Gen.VARIANTS:
		var ov: Dictionary = Gen.VARIANTS[variant]
		var flat: Array = Gen.BOAT_BASE["torque_curve"]
		var mul := float(ov["torque_mul"])
		var curve := _spec(variant).torque_curve
		@warning_ignore("integer_division")
		var points := flat.size() / 2
		assert_int(curve.size()) \
			.override_failure_message("%s_spec.tres torque_curve length" % variant) \
			.is_equal(points)
		for i in points:
			assert_float(curve[i].x) \
				.override_failure_message("%s_spec.tres torque_curve[%d].x" % [variant, i]) \
				.is_equal_approx(float(flat[i * 2]), 1e-3)
			assert_float(curve[i].y) \
				.override_failure_message("%s_spec.tres torque_curve[%d].y" % [variant, i]) \
				.is_equal_approx(float(flat[i * 2 + 1]) * mul, 1e-3)


func test_spec_gear_ratios_match_the_baseline() -> void:
	var base: Array = Gen.BOAT_BASE["gear_ratios"]
	for variant: String in Gen.VARIANTS:
		var ratios := _spec(variant).gear_ratios
		assert_int(ratios.size()) \
			.override_failure_message("%s_spec.tres gear_ratios length" % variant) \
			.is_equal(base.size())
		for i in base.size():
			assert_float(ratios[i]) \
				.override_failure_message("%s_spec.tres gear_ratios[%d]" % [variant, i]) \
				.is_equal_approx(float(base[i]), 1e-4)


func test_spec_shared_drivetrain_fields_match_the_baseline() -> void:
	for variant: String in Gen.VARIANTS:
		var spec := _spec(variant)
		for field: String in SHARED_SPEC_FIELDS:
			assert_float(float(spec.get(field))) \
				.override_failure_message("%s_spec.tres %s" % [variant, field]) \
				.is_equal_approx(float(Gen.BOAT_BASE[field]), 1e-4)


# --- helpers ------------------------------------------------------------------

## Property name -> value for the scene's ROOT node (index 0), explicit overrides only.
func _root_overrides(path: String) -> Dictionary:
	var scene := load(path) as PackedScene
	assert_object(scene).override_failure_message("cannot load " + path).is_not_null()
	var state := scene.get_state()
	var out := {}
	for i in state.get_node_property_count(0):
		out[String(state.get_node_property_name(0, i))] = state.get_node_property_value(0, i)
	return out


## `boat.gd`'s own `@export` defaults, for the knobs a scene may legitimately leave out. Built
## from a loose instance: `_ready()` needs a tree, so nothing physics- or autoload-shaped runs.
func _boat_defaults() -> Dictionary:
	var boat := BoatScript.new() as Node
	var out := {}
	for knob: String in SCENE_KNOBS:
		out[knob] = boat.get(knob)
	boat.free()
	return out


func _spec(variant: String) -> VehicleSpec:
	var path: String = Gen.OUT_DIR.path_join(variant + "_spec.tres")
	var spec := load(path) as VehicleSpec
	assert_object(spec).override_failure_message("cannot load " + path).is_not_null()
	return spec

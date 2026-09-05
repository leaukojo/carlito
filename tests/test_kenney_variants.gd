extends GdUnitTestSuite
## Kenney variants pin generated specs to the recipe. Spec read via scene, never by
## path (orphan specs silently hide regens). Omitted values are not drift. Derived
## fields are re-derived, never transcribed. Two traps inherited from boat tests.

const Gen := preload("res://tools/gen_kenney_vehicles.gd")

## Scalars a variant may override (field -> recipe key mapping).
const SPEC_OVERRIDABLE := {
	"mass": "mass", "final_drive": "final_drive", "steer_speed": "steer_speed",
}
const DRIVE_OVERRIDABLE := {
	"rolling_resistance": "crr", "mu_long": "mu_long", "mu_lat": "mu_lat",
	"handbrake_grip": "handbrake_grip", "max_steer_deg": "max_steer_deg",
	"min_steer_frac": "min_steer_frac", "steer_falloff_speed": "steer_falloff_speed",
}
## Baseline-only fields: overrides silently dropped (test_no_variant_overrides catches this).
const SPEC_BASELINE_ONLY := {
	"idle_rpm": "idle_rpm", "redline_rpm": "redline_rpm", "reverse_ratio": "reverse_ratio",
	"efficiency": "efficiency", "shift_up_rpm": "shift_up_rpm",
	"shift_down_rpm": "shift_down_rpm",
}
const DRIVE_BASELINE_ONLY := {
	"wheel_inertia": "wheel_inertia", "rest_length": "rest_length",
	"spring_rate": "spring_rate", "damper_bump": "damper_bump",
	"damper_rebound": "damper_rebound", "max_suspension_force": "max_suspension_force",
}
## Driveline flags: had gone missing once (now pinned).
const DRIVELINE_FLAGS := ["rear_diff_lockable", "front_axle_engageable", "retarder_equipped"]
## Driven flags: must not default to false (missing key means baseline's answer).
const DRIVEN_FLAGS := ["driven_front", "driven_rear"]

## Recipe-only keys: routing or derivation inputs.
const META_KEYS := [
	"family",         # contract family: picks the vehicle script and the default baseline
	"base",           # feel baseline when it differs from the family (the heavy vans)
	"torque_mul",     # scales the baseline curve
	"cd", "cl",       # aero coefficients, applied to the MEASURED frontal box
	"com_z", "front_weight",  # the two ways a recipe may state the longitudinal balance
	"gear_ratios",    # a whole array, overridable
	"speed_limit_kmh",
	"wheels", "wheel_x_out",  # wheel models and the outboard push
	"_id",            # stamped in by `_ready`, never authored
]


# --- roster -------------------------------------------------------------------

## Catalog and recipe rosters must match (regen maintenance vs selector coverage).
func test_recipe_and_catalog_agree_on_the_kenney_roster() -> void:
	var recipe := PackedStringArray(Gen.VARIANTS.keys())
	recipe.sort()
	var catalog := PackedStringArray()
	for variant in VehicleCatalog.VARIANTS:
		if VehicleCatalog.scene_of(variant).begins_with(Gen.OUT_DIR):
			catalog.append(variant)
	catalog.sort()
	assert_array(Array(recipe)).is_equal(Array(catalog))


## Family picks script and baseline (mismatch puts ordinary chassis under J1939 truck).
func test_recipe_and_catalog_agree_on_every_family() -> void:
	for variant: String in Gen.VARIANTS:
		assert_str(String(Gen.VARIANTS[variant]["family"])) \
				.override_failure_message("%s: recipe family vs catalog" % variant) \
				.is_equal(VehicleCatalog.family_of(variant))


## Scene must carry its generated spec (orphan-spec failure made red).
func test_each_scene_carries_its_own_generated_spec() -> void:
	for variant: String in Gen.VARIANTS:
		var spec := _spec_of(variant)
		assert_object(spec).override_failure_message("%s.tscn declares no spec" % variant) \
				.is_not_null()
		assert_str(spec.resource_path) \
				.override_failure_message("%s.tscn loads someone else's spec" % variant) \
				.is_equal(Gen.OUT_DIR.path_join(variant + "_spec.tres"))


## Script chosen by family, not variant (heavy vans are car family, not J1939).
func test_each_scene_runs_the_script_its_family_declares() -> void:
	for variant: String in Gen.VARIANTS:
		var family := String(Gen.VARIANTS[variant]["family"])
		var expected := String(Gen.FAMILY_SCRIPTS.get(family, Gen.BASE_SCRIPT))
		var script := _root_property(variant, &"script") as Script
		assert_object(script).override_failure_message("%s.tscn has no script" % variant) \
				.is_not_null()
		assert_str(script.resource_path) \
				.override_failure_message("%s.tscn script (family %s)" % [variant, family]) \
				.is_equal(expected)


# --- verbatim recipe values ---------------------------------------------------

## Driveline flags went missing once and are now pinned.
func test_driveline_flags_match_the_recipe() -> void:
	for variant: String in Gen.VARIANTS:
		var ov: Dictionary = Gen.VARIANTS[variant]
		var b := _baseline(variant)
		var gd := _spec_of(variant).ground_drive
		for flag: String in DRIVELINE_FLAGS:
			var expected := bool(ov.get(flag, b.get(flag, false)))
			assert_bool(bool(gd.get(flag))) \
					.override_failure_message("%s_spec.tres %s" % [variant, flag]) \
					.is_equal(expected)


## Driven layout defaults to baseline (not false) when missing.
func test_driven_layout_matches_the_recipe() -> void:
	for variant: String in Gen.VARIANTS:
		var ov: Dictionary = Gen.VARIANTS[variant]
		var b := _baseline(variant)
		var gd := _spec_of(variant).ground_drive
		for flag: String in DRIVEN_FLAGS:
			assert_bool(bool(gd.get(flag))) \
					.override_failure_message("%s_spec.tres %s" % [variant, flag]) \
					.is_equal(bool(ov.get(flag, b[flag])))


func test_overridable_scalars_match_the_recipe() -> void:
	for variant: String in Gen.VARIANTS:
		_assert_scalars(variant, _spec_of(variant), SPEC_OVERRIDABLE, true)
		_assert_scalars(variant, _spec_of(variant).ground_drive, DRIVE_OVERRIDABLE, true)


func test_baseline_only_scalars_match_the_baseline() -> void:
	for variant: String in Gen.VARIANTS:
		_assert_scalars(variant, _spec_of(variant), SPEC_BASELINE_ONLY, false)
		_assert_scalars(variant, _spec_of(variant).ground_drive, DRIVE_BASELINE_ONLY, false)


## Baseline-only overrides are silently dropped (same invisible drift, other direction).
func test_no_variant_overrides_a_baseline_only_field() -> void:
	var honoured := META_KEYS.duplicate()
	honoured.append_array(SPEC_OVERRIDABLE.values())
	honoured.append_array(DRIVE_OVERRIDABLE.values())
	honoured.append_array(DRIVELINE_FLAGS)
	honoured.append_array(DRIVEN_FLAGS)
	for variant: String in Gen.VARIANTS:
		for key: String in Gen.VARIANTS[variant]:
			assert_bool(honoured.has(key)) \
					.override_failure_message(
						"VARIANTS['%s'] declares '%s', which _build_spec never reads off a "
						% [variant, key] + "variant — the value is dropped silently") \
					.is_true()


## Speed limits: variant override, baseline fallback, default 0 (ungoverned).
func test_speed_limits_match_the_recipe() -> void:
	for variant: String in Gen.VARIANTS:
		var ov: Dictionary = Gen.VARIANTS[variant]
		var expected := float(ov.get("speed_limit_kmh", _baseline(variant).get(
				"speed_limit_kmh", 0.0)))
		assert_float(_spec_of(variant).speed_limit_kmh) \
				.override_failure_message("%s_spec.tres speed_limit_kmh" % variant) \
				.is_equal_approx(expected, 1e-4)


func test_gear_ratios_match_the_recipe() -> void:
	for variant: String in Gen.VARIANTS:
		var expected: Array = Gen.VARIANTS[variant].get(
				"gear_ratios", _baseline(variant)["gear_ratios"])
		var ratios := _spec_of(variant).gear_ratios
		assert_int(ratios.size()) \
				.override_failure_message("%s_spec.tres gear_ratios length" % variant) \
				.is_equal(expected.size())
		for i in expected.size():
			assert_float(ratios[i]) \
					.override_failure_message("%s_spec.tres gear_ratios[%d]" % [variant, i]) \
					.is_equal_approx(float(expected[i]), 1e-4)


## COM.y is verbatim (family figure); COM.z is measured (geometry case).
func test_com_y_matches_the_baseline() -> void:
	for variant: String in Gen.VARIANTS:
		assert_float(_spec_of(variant).center_of_mass.y) \
				.override_failure_message("%s_spec.tres center_of_mass.y" % variant) \
				.is_equal_approx(float(_baseline(variant)["com_y"]), 1e-4)


## Single radius across kit (tractor's big wheel is VISUAL only).
func test_every_body_runs_the_kit_wheel_radius() -> void:
	for variant: String in Gen.VARIANTS:
		assert_float(_spec_of(variant).ground_drive.wheel_radius) \
				.override_failure_message("%s_spec.tres wheel_radius" % variant) \
				.is_equal_approx(Gen.WHEEL_RADIUS, 1e-4)


# --- re-derived values --------------------------------------------------------

## Curve is baseline points with y scaled by torque_mul (re-derived, not transcribed).
func test_torque_curve_is_the_baseline_scaled_by_torque_mul() -> void:
	for variant: String in Gen.VARIANTS:
		var flat: Array = _baseline(variant)["torque_curve"]
		var mul := float(Gen.VARIANTS[variant].get("torque_mul", 1.0))
		var curve := _spec_of(variant).torque_curve
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


## The brakes are re-derived by the generator's own function, on a copy of the shipped spec, so
## what is pinned is the DERIVATION and not the number: `brake_torque` is `BRAKE_GRIP_FRAC` x the
## tyre's per-wheel ceiling (floored by the transmissible-drive hierarchy) and `handbrake_torque`
## is 0.75 x the launch torque at idle + 25 % throttle. A hand-edited brake in a `.tres` — the
## fiction the whole derivation exists to stop — fails here whatever value it carries.
##
## Brakes are re-derived (catalog owns force-hierarchy satisfaction, not here).
func test_brakes_are_what_the_generator_derives_from_the_tyre() -> void:
	var gen := _gen()
	for variant: String in Gen.VARIANTS:
		var shipped := _spec_of(variant)
		var scratch := shipped.duplicate(true) as VehicleSpec
		scratch.ground_drive.brake_torque = 0.0
		scratch.ground_drive.handbrake_torque = 0.0
		gen._derive_brakes(scratch, scratch.ground_drive, variant)
		assert_float(shipped.ground_drive.brake_torque) \
				.override_failure_message("%s_spec.tres brake_torque" % variant) \
				.is_equal_approx(scratch.ground_drive.brake_torque, 1e-3)
		assert_float(shipped.ground_drive.handbrake_torque) \
				.override_failure_message("%s_spec.tres handbrake_torque" % variant) \
				.is_equal_approx(scratch.ground_drive.handbrake_torque, 1e-3)


## Drag and downforce areas measure the same box (invariant: cl/cd ratio via snap).
func test_downforce_and_drag_measure_the_same_body() -> void:
	for variant: String in Gen.VARIANTS:
		var ov: Dictionary = Gen.VARIANTS[variant]
		var gd := _spec_of(variant).ground_drive
		var cl := float(ov.get("cl", 0.0))
		if is_zero_approx(cl):
			assert_float(gd.downforce_area) \
					.override_failure_message("%s_spec.tres declares no wing" % variant) \
					.is_equal(0.0)
			continue
		var cd := float(ov.get("cd", _baseline(variant)["cd"]))
		assert_float(gd.downforce_area) \
				.override_failure_message("%s_spec.tres downforce_area vs drag_area" % variant) \
				.is_equal_approx(gd.drag_area * cl / cd, 0.02)


## Measured geometry is re-analyzed (not transcribed; catches asset changes).
func test_measured_geometry_still_matches_the_models() -> void:
	var gen := _gen()
	for variant: String in Gen.VARIANTS:
		var ov: Dictionary = Gen.VARIANTS[variant]
		var b := _baseline(variant)
		var wheels: Array = ov.get("wheels", Gen.FAMILY_WHEELS[String(ov["family"])])
		var geo: Dictionary = gen._analyze(
				Gen.MODELS.path_join(variant + ".glb"), wheels)
		assert_bool(geo.is_empty()) \
				.override_failure_message("%s.glb could not be analyzed" % variant).is_false()
		var spec := _spec_of(variant)
		var gd := spec.ground_drive
		var box: AABB = geo["box"]
		var cd := float(ov.get("cd", b["cd"]))
		var area := float(roundi(cd * Gen.FRONTAL_FILL * box.size.x * box.size.y * 100.0)) / 100.0
		assert_float(gd.drag_area) \
				.override_failure_message("%s_spec.tres drag_area (measured box %.3f x %.3f)"
					% [variant, box.size.x, box.size.y]) \
				.is_equal_approx(area, 1e-4)
		assert_float(spec.center_of_mass.z) \
				.override_failure_message("%s_spec.tres center_of_mass.z" % variant) \
				.is_equal_approx(gen._com_z(geo, ov), 1e-4)
		var stations: PackedVector3Array = gen._wheel_positions(
				geo, spec, gd, float(ov.get("wheel_x_out", 0.0)))
		assert_int(gd.wheel_positions.size()) \
				.override_failure_message("%s_spec.tres wheel_positions length" % variant) \
				.is_equal(stations.size())
		for i in stations.size():
			assert_vector(gd.wheel_positions[i]) \
					.override_failure_message("%s_spec.tres wheel_positions[%d]" % [variant, i]) \
					.is_equal_approx(stations[i], Vector3.ONE * 1e-4)


# --- helpers ------------------------------------------------------------------

## Generator Node for instance-method derivations (no regen, array cleanup).
func _gen() -> Node:
	return auto_free(Gen.new()) as Node


## Baseline by variant's `base` or contract family ("van" is feel-only baseline).
func _baseline(variant: String) -> Dictionary:
	var ov: Dictionary = Gen.VARIANTS[variant]
	return Gen.BASELINES[String(ov.get("base", ov["family"]))]


## Spec via scene state (not instantiation, to avoid orphan sub-scenes).
func _spec_of(variant: String) -> VehicleSpec:
	return _root_property(variant, &"spec") as VehicleSpec


func _root_property(variant: String, prop: StringName) -> Variant:
	var scene := load(Gen.OUT_DIR.path_join(variant + ".tscn")) as PackedScene
	assert_object(scene).override_failure_message("cannot load " + variant).is_not_null()
	var state := scene.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == prop:
			return state.get_node_property_value(0, i)
	return null


## Check scalar field overrides (fields map spec field -> recipe key).
func _assert_scalars(variant: String, res: Resource, fields: Dictionary,
		overridable: bool) -> void:
	var ov: Dictionary = Gen.VARIANTS[variant]
	var b := _baseline(variant)
	for field: String in fields:
		var key: String = fields[field]
		var expected := float(ov.get(key, b[key])) if overridable else float(b[key])
		var how := "recipe" if overridable and ov.has(key) else "baseline"
		assert_float(float(res.get(field))) \
				.override_failure_message("%s_spec.tres %s (from the %s)" % [variant, field, how]) \
				.is_equal_approx(expected, 1e-4)

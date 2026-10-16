extends GdUnitTestSuite
## Kenney variants pin generated specs to the recipe. Spec read via scene, never by
## path (orphan specs silently hide regens). Omitted values are not drift. Derived
## fields are re-derived, never transcribed. Two traps inherited from boat tests.

const Gen := preload("res://tools/gen_kenney_vehicles.gd")
const StableSave := preload("res://tools/stable_save.gd")

## Scalars a variant may override (field -> recipe key mapping).
const SPEC_OVERRIDABLE := {
	"mass": "mass", "final_drive": "final_drive", "steer_speed": "steer_speed",
	"engine_inertia": "engine_inertia", "coupling": "coupling",
	"shift_up_light_rpm": "shift_up_light_rpm", "shift_down_light_rpm": "shift_down_light_rpm",
	"kickdown_pedal": "kickdown_pedal", "shift_dwell_s": "shift_dwell_s",
	"shift_handover_s": "shift_handover_s", "shift_cut_s": "shift_cut_s",
	"yaw_dynamic_index": "yaw_index",
}
const DRIVE_OVERRIDABLE := {
	"rolling_resistance": "crr", "mu_long": "mu_long", "mu_lat": "mu_lat",
	"rear_lat_grip": "rear_lat_grip",
	"max_steer_deg": "max_steer_deg",
	# Brake hardware: declared classes, never derived (the split is; see the brake test below).
	"brake_torque": "brake_torque", "handbrake_torque": "handbrake_torque",
	"park_pawl_torque": "park_pawl_torque",
	"min_steer_frac": "min_steer_frac", "steer_falloff_speed": "steer_falloff_speed",
	"anti_roll_rate": "anti_roll_rate",
	"anti_roll_rate_rear": "anti_roll_rate_rear",
	"cornering_peak_load": "cornering_peak_load",
	"diff_bias_front": "diff_bias_front", "diff_bias_rear": "diff_bias_rear",
	"centre_diff_bias": "centre_diff_bias",
	"hill_hold": "hill_hold",
}
## Baseline-only fields: overrides silently dropped (test_no_variant_overrides catches this).
const SPEC_BASELINE_ONLY := {
	"idle_rpm": "idle_rpm", "redline_rpm": "redline_rpm", "reverse_ratio": "reverse_ratio",
	"efficiency": "efficiency", "engine_brake_frac": "engine_brake_frac",
	"engine_friction_frac": "engine_friction_frac",
	"launch_engage_s": "launch_engage_s",
	"clutch_reserve": "clutch_reserve",
	"converter_stall_ratio": "converter_stall_ratio",
	"lockup_gear": "lockup_gear",
	"launch_rpm_over_idle": "launch_rpm_over_idle",
	"shift_up_rpm": "shift_up_rpm",
	"shift_down_rpm": "shift_down_rpm",
	"skip_shifts": "skip_shifts",
	"start_gear_max": "start_gear_max",
}
const DRIVE_BASELINE_ONLY := {
	"wheel_inertia": "wheel_inertia", "rest_length": "rest_length",
	"max_suspension_force": "max_suspension_force",
	"load_sensitivity": "load_sensitivity",
	"hill_hold_s": "hill_hold_s",
}
## Springs and dampers: verbatim from a baseline that states them, re-derived on one that states a
## `ride_hz` (test_springs_are_what_the_generator_derives).
const SUSPENSION := ["spring_rate", "damper_bump", "damper_rebound", "spring_rate_rear",
		"damper_bump_rear", "damper_rebound_rear"]
## Driveline (and twin-tyre) flags: had gone missing once (now pinned).
const DRIVELINE_FLAGS := ["rear_diff_lockable", "front_axle_engageable", "retarder_equipped",
		"centre_diff_rigid", "abs_equipped", "tcs_equipped", "brake_engages_front_axle",
		"rear_twin_tyres"]
## Driven flags: must not default to false (missing key means baseline's answer).
const DRIVEN_FLAGS := ["driven_front", "driven_rear"]

## Recipe-only keys: routing or derivation inputs.
const META_KEYS := [
	"family",         # contract family: picks the vehicle script and the default baseline
	"base",           # feel baseline when it differs from the family (the heavy vans)
	"torque_mul",     # scales the baseline curve
	"cd", "cl",       # aero coefficients, applied to the MEASURED frontal box
	"com_y",          # body-space height of the COM over the road, overriding the family figure
	"com_y_frac",     # the same height as a fraction of the body's AABB top (a rescale)
	"front_weight",   # the longitudinal balance, as the front axle's static share
	"gear_ratios",    # a whole array, overridable
	"speed_limit_kmh",
	"wheels", "wheel_x_out",  # wheel models and the outboard push
	"ride_lift",      # chassis raised over the wheels (shallow arches)
	"scale",          # per-variant body scale, multiplied into KIT_SCALE by _analyze
	"ride_hz",        # spring derivation input over the baseline's (_suspension_recipe)
	"_id",            # stamped in by `_ready`, never authored
]

## Yaw dynamic index k²/(a·b) per class, min-max of NHTSA's measured vehicles (SAE 1999-01-1336;
## driver only, no outriggers, IPMD v5 / VIMF, yaw within 3 %): cars n 35, SUVs 44, vans 29
## (1.5-2.5 t), pickups 36.
const YAW_INDEX_BANDS := {
	"car": Vector2(0.93, 1.20), "suv": Vector2(0.91, 1.19), "van": Vector2(0.84, 1.17),
	"pickup": Vector2(0.85, 1.02),
}
## The class a declaring body is judged against; any other car-family body is "car".
const YAW_CLASS := {
	"suv": "suv", "suv-luxury": "suv", "van": "van", "pickup": "pickup", "pickup-flat": "pickup",
	"delivery": "van", "delivery-flat": "van", "ambulance": "van",
}
## Bodies left on Jolt's tensor (index 0): no measured figure for their class.
const YAW_COMPUTED := ["race", "race-future", "garbage-truck", "firetruck", "tractor-kenney"]


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


## COM.y is verbatim (the recipe's own figure, else the family's) unless the recipe states it
## as `com_y_frac`, which is measured off the body's AABB and checked with COM.z in the
## geometry case. COM.z is always measured.
func test_com_y_matches_the_recipe() -> void:
	for variant: String in Gen.VARIANTS:
		var ov: Dictionary = Gen.VARIANTS[variant]
		if ov.has("com_y_frac"):
			continue
		assert_float(_spec_of(variant).center_of_mass.y) \
				.override_failure_message("%s_spec.tres center_of_mass.y" % variant) \
				.is_equal_approx(float(ov.get("com_y", _baseline(variant)["com_y"])), 1e-4)


## A declared yaw index sits inside its class's measured band; an undeclared one is a stated
## unsourced class, never a forgotten override.
func test_every_declared_yaw_index_sits_in_its_class_band() -> void:
	for variant: String in Gen.VARIANTS:
		var index := _spec_of(variant).yaw_dynamic_index
		if index <= 0.0:
			assert_bool(YAW_COMPUTED.has(variant)) \
					.override_failure_message("%s runs Jolt's yaw tensor but is not in YAW_COMPUTED"
						% variant).is_true()
			continue
		var cls := String(YAW_CLASS.get(variant, "car"))
		var band: Vector2 = YAW_INDEX_BANDS[cls]
		assert_float(index) \
				.override_failure_message("%s yaw index %.2f outside the %s band %.2f-%.2f"
					% [variant, index, cls, band.x, band.y]) \
				.is_between(band.x, band.y)


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


## The axle split is the one derived brake figure: `brake_bias_front` is the generator's own
## proportioning (`_front_brake_share`) re-run on the shipped spec, so a hand-edited split fails
## whatever value it carries. The hardware it splits is the recipe's (DRIVE_OVERRIDABLE).
func test_the_brake_split_is_what_the_generator_proportions() -> void:
	var gen := _gen()
	for variant: String in Gen.VARIANTS:
		var shipped := _spec_of(variant)
		var gd := shipped.ground_drive
		var want: float = 0.0 if gd.brake_engages_front_axle else gen._front_brake_share(shipped, gd,
				gen._static_sag(_suspension(gen, variant), shipped, gd))
		assert_float(gd.brake_bias_front) \
				.override_failure_message("%s_spec.tres brake_bias_front" % variant) \
				.is_equal_approx(want, 1e-6)


## The retarder's rating is the recipe's, on the bodies that carry one.
func test_the_retarder_rating_is_the_recipes() -> void:
	for variant: String in Gen.VARIANTS:
		var ov: Dictionary = Gen.VARIANTS[variant]
		var b: Dictionary = Gen.BASELINES[String(ov.get("base", ov["family"]))]
		assert_float(_spec_of(variant).ground_drive.retarder_rating_nm) \
				.override_failure_message("%s_spec.tres retarder_rating_nm" % variant) \
				.is_equal_approx(float(ov.get("retarder_rating_nm", b.get("retarder_rating_nm", 0.0))),
						1e-3)


## Springs, dampers and link slopes are the generator's derivation on a copy of the shipped spec, as
## the brakes are: a hand-edited rate or slope fails whatever value it carries. A baseline with no
## `ride_hz` states its springs, which ship verbatim.
func test_springs_are_what_the_generator_derives() -> void:
	var gen := _gen()
	for variant: String in Gen.VARIANTS:
		var b := _suspension(gen, variant)
		var shipped := _spec_of(variant)
		var scratch := shipped.duplicate(true) as VehicleSpec
		var gd := scratch.ground_drive
		for field: String in SUSPENSION:
			gd.set(field, 0.0)
		gd.anti_dive_slope = 0.0
		gd.anti_squat_slope = 0.0
		if b.has("ride_hz"):
			gen._derive_springs(scratch, gd, b)
		else:
			for field: String in SUSPENSION:
				gd.set(field, float(b[field]))
		gen._derive_link_slopes(scratch, gd, b, gen._static_sag(b, scratch, gd))
		for field: String in SUSPENSION + ["anti_dive_slope", "anti_squat_slope"]:
			assert_float(float(shipped.ground_drive.get(field))) \
					.override_failure_message("%s_spec.tres %s" % [variant, field]) \
					.is_equal_approx(float(gd.get(field)), 1e-4)


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
				Gen.MODELS.path_join(variant + ".glb"), wheels,
				float(ov.get("scale", 1.0)))
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
		# `com_y_frac` makes COM.y a measured figure too, so it is checked here beside COM.z
		# rather than in test_com_y_matches_the_recipe, which owns the verbatim case.
		if ov.has("com_y_frac"):
			var get_f := func(key: String) -> float: return float(ov.get(key, b[key]))
			assert_float(spec.center_of_mass.y) \
					.override_failure_message("%s_spec.tres center_of_mass.y (%.2f of AABB top)"
						% [variant, float(ov["com_y_frac"])]) \
					.is_equal_approx(gen._com_y(get_f, geo, ov), 1e-4)
		var stations: PackedVector3Array = gen._wheel_positions(
				geo, gd, gen._static_sag(_suspension(gen, variant), spec, gd),
				float(ov.get("wheel_x_out", 0.0)),
				float(ov.get("ride_lift", 0.0)))
		assert_int(gd.wheel_positions.size()) \
				.override_failure_message("%s_spec.tres wheel_positions length" % variant) \
				.is_equal(stations.size())
		for i in stations.size():
			assert_vector(gd.wheel_positions[i]) \
					.override_failure_message("%s_spec.tres wheel_positions[%d]" % [variant, i]) \
					.is_equal_approx(stations[i], Vector3.ONE * 1e-4)


# --- regen idempotence --------------------------------------------------------

## A regen of an up-to-date scene is a no-op. Breaks when a new generated child is missing from
## GENERATED_CHILDREN (the next regen transplants the old copy beside the new one) or a hand `;`
## comment sits in the scene (a regen drops it).
func test_regen_reproduces_every_shipped_scene() -> void:
	var gen := _gen()
	var scratch := "user://test_kenney_regen.tscn"
	for variant: String in Gen.VARIANTS:
		var ov: Dictionary = Gen.VARIANTS[variant]
		var family := String(ov["family"])
		var geo: Dictionary = gen._analyze(Gen.MODELS.path_join(variant + ".glb"),
				ov.get("wheels", Gen.FAMILY_WHEELS[family]), float(ov.get("scale", 1.0)))
		var scene_path := Gen.OUT_DIR.path_join(variant + ".tscn")
		var packed: PackedScene = gen._build_scene(variant,
				load(String(Gen.FAMILY_SCRIPTS.get(family, Gen.BASE_SCRIPT))),
				load(Gen.OUT_DIR.path_join(variant + "_spec.tres")), geo)
		var shipped := FileAccess.get_file_as_string(scene_path)
		# A regen saves over the shipped path, where the saver reuses each ext_resource's id;
		# hand the scratch path the same ids or every one reads as changed.
		for m in RegEx.create_from_string(
				"\\[ext_resource [^\\]]*path=\"([^\"]*)\" id=\"([^\"]*)\"").search_all(shipped):
			(load(m.get_string(1)) as Resource).set_id_for_path(scratch, m.get_string(2))
		assert_int(ResourceSaver.save(packed, scratch)).is_equal(OK)
		var rebuilt := StableSave.restore_uids(shipped, FileAccess.get_file_as_string(scratch))
		assert_str(StableSave.churn_key(rebuilt)) \
				.override_failure_message(("%s.tscn changes on regen: a generated child missing "
					+ "from GENERATED_CHILDREN, a hand `;` comment, or a regen not yet run") % variant) \
				.is_equal(StableSave.churn_key(shipped))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))


# --- helpers ------------------------------------------------------------------

## Generator Node for instance-method derivations (no regen, array cleanup).
func _gen() -> Node:
	return auto_free(Gen.new()) as Node


## Baseline by variant's `base` or contract family ("van" is feel-only baseline).
func _baseline(variant: String) -> Dictionary:
	var ov: Dictionary = Gen.VARIANTS[variant]
	return Gen.BASELINES[String(ov.get("base", ov["family"]))]


## The suspension recipe `_build_spec` derives from: the baseline plus the variant's `ride_hz`.
func _suspension(gen: Node, variant: String) -> Dictionary:
	return gen._suspension_recipe(_baseline(variant), Gen.VARIANTS[variant])


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

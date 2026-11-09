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
	"float_depth", "thrust_force", "rudder_torque", "drag_long", "drag_sq", "waterline_length",
	"drag_lat", "drag_yaw", "sail_area", "sheet_max_deg",
]
const BoatSailScript := preload("res://src/vehicles/boat/boat_sail.gd")
const BoatTelemetryScript := preload("res://src/vehicles/boat/boat_telemetry.gd")
const VehicleMathScript := preload("res://src/vehicles/base/vehicle_math.gd")
const WorldConditions := preload("res://src/levels/base/world_conditions.gd")
const DELTA := 1.0 / 60.0
const BOW := Vector3(0.0, 0.0, -1.0)
const STBD := Vector3(1.0, 0.0, 0.0)
## `VehicleSpec` fields `_build_spec` copies straight out of `BOAT_BASE`, same for every variant.
const SHARED_SPEC_FIELDS := [
	"idle_rpm", "redline_rpm", "reverse_ratio", "final_drive", "efficiency",
	"shift_up_rpm", "shift_down_rpm", "shift_up_light_rpm", "shift_down_light_rpm",
	"kickdown_pedal", "shift_dwell_s", "skip_shifts", "shift_handover_s", "start_gear_max",
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


## `sail_center` is a declared knob like the two above and not a derived one like `prop_offset`,
## but it is a Vector3, so it cannot ride the float sweep. A rig with an area and no centre of
## effort would apply its whole force at the origin and never heel the hull.
func test_sail_center_matches_the_recipe() -> void:
	var defaults := _boat_defaults()
	for variant: String in Gen.VARIANTS:
		var ov: Dictionary = Gen.VARIANTS[variant]
		var props := _root_overrides(Gen.OUT_DIR.path_join(variant + ".tscn"))
		var actual: Vector3 = props["sail_center"] if props.has("sail_center") \
				else defaults["sail_center"]
		assert_vector(actual) \
			.override_failure_message("%s.tscn sail_center" % variant) \
			.is_equal_approx(ov["sail_center"] as Vector3, Vector3.ONE * 1e-4)


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
## points with every y scaled by the variant's `torque_mul`, which is `VehicleGenIO.scaled_curve`.
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


# --- the hull law's shipped figures (docs/boat.md § Hull drag) ----------------------------------
## Steady states solved in code, not driven: the forward balance only, no leeway, heel or pitch.

## The speedboats are planing hulls: linear, so thrust / drag_long is their top speed.
func test_the_speedboats_are_linear_planing_hulls() -> void:
	for variant in ["boat-speed-a", "boat-speed-j"]:
		var ov: Dictionary = Gen.VARIANTS[variant]
		assert_float(float(ov["drag_sq"])).override_failure_message(variant).is_equal(0.0)
		assert_float(float(ov["waterline_length"])).override_failure_message(variant).is_equal(0.0)


## A ~5 hp outboard on a displacement hull tops out near hull speed, not past it.
func test_the_sailboat_motors_at_about_hull_speed() -> void:
	var ov: Dictionary = Gen.VARIANTS["boat-sail-a"]
	var top := _settle(func(_v: float) -> float: return float(ov["thrust_force"]), ov)
	assert_float(top).is_between(2.6, 2.8)
	assert_float(top / BoatScript.hull_speed(float(ov["waterline_length"]), _g())) \
		.is_between(1.0, 1.15)


## A hard breeze (CONDITIONS STRONG, no gust) on the beam, the sheet trimmed for the most drive:
## the rig grows with the wind squared, and the wave wall stops it near hull speed. A linear
## hull runs it to 5.9 m/s here.
func test_the_sailboat_on_a_strong_beam_reach_stays_near_hull_speed() -> void:
	var ov: Dictionary = Gen.VARIANTS["boat-sail-a"]
	var wind := -STBD * WorldConditions.WIND_STRONG_SPEED   # from starboard, blowing to port
	var drive := func(v: float) -> float:
		var aw := BoatTelemetryScript.apparent_wind(BOW * v, wind, Basis.IDENTITY)
		var best := 0.0
		for i in 101:
			var boom := BoatSailScript.boom_angle(i / 100.0, aw.y, float(ov["sheet_max_deg"]))
			best = maxf(best, BoatSailScript.force(aw, boom, float(ov["sail_area"]), BOW, STBD)
					.dot(BOW))
		return best
	var top := _settle(drive, ov)
	var vh := BoatScript.hull_speed(float(ov["waterline_length"]), _g())
	assert_float(top).override_failure_message("settled at %.2f m/s" % top).is_less(vh * 1.3)
	assert_float(top).is_greater(vh)   # a breeze that hard still sails her past it


## The forward speed where `push(v)` meets the hull's forward drag plus the windage, by bisection.
func _settle(push: Callable, ov: Dictionary) -> float:
	var mass := float(ov["mass"])
	var windage_long := float(_boat_defaults()["windage_long"])
	var lo := 0.0
	var hi := 20.0
	for _i in 60:
		var v := (lo + hi) * 0.5
		var drag := VehicleMathScript.damped_force(v, float(ov["drag_long"]), mass, DELTA,
				BoatScript.wave_drag_sq(v, float(ov["drag_sq"]), float(ov["waterline_length"]),
				_g())) + VehicleMathScript.damped_force(v, windage_long, mass, DELTA)
		if float(push.call(v)) + drag > 0.0:
			lo = v
		else:
			hi = v
	return lo


func _g() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity"))


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
	out["sail_center"] = boat.get("sail_center")
	out["windage_long"] = boat.get("windage_long")
	boat.free()
	return out


func _spec(variant: String) -> VehicleSpec:
	var path: String = Gen.OUT_DIR.path_join(variant + "_spec.tres")
	var spec := load(path) as VehicleSpec
	assert_object(spec).override_failure_message("cannot load " + path).is_not_null()
	return spec

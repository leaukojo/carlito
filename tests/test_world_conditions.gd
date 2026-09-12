extends GdUnitTestSuite
## WorldConditions: preset cycling, the FROM->TOWARD conversion, the never-mutate-authored rule,
## and Level.set_conditions restoring the authored side-cars on LEVEL.

const WC := preload("res://src/levels/base/world_conditions.gd")


# --- preset cycling --------------------------------------------------------------

func test_next_preset_cycles_level_calm_light_strong_and_wraps() -> void:
	assert_int(WC.next_preset(WC.Preset.LEVEL)).is_equal(WC.Preset.CALM)
	assert_int(WC.next_preset(WC.Preset.CALM)).is_equal(WC.Preset.LIGHT)
	assert_int(WC.next_preset(WC.Preset.LIGHT)).is_equal(WC.Preset.STRONG)
	assert_int(WC.next_preset(WC.Preset.STRONG)).is_equal(WC.Preset.LEVEL)


# --- compass label -----------------------------------------------------------------

func test_compass_label_for_all_eight_points() -> void:
	var want := ["NORTH", "NORTHEAST", "EAST", "SOUTHEAST", "SOUTH", "SOUTHWEST", "WEST", "NORTHWEST"]
	for i in want.size():
		assert_str(WC.compass_label(float(i) * WC.DIRECTION_STEP_DEG)) \
			.override_failure_message("point %d" % i).is_equal(want[i])


func test_compass_label_wraps_past_a_full_turn_and_below_zero() -> void:
	assert_str(WC.compass_label(360.0)).is_equal("NORTH")
	assert_str(WC.compass_label(-45.0)).is_equal("NORTHWEST")


# --- wind_for ------------------------------------------------------------------------

func test_wind_for_level_returns_the_authored_instance_including_null() -> void:
	var authored := WindField.new()
	assert_object(WC.wind_for(WC.Preset.LEVEL, authored, 0.0)).is_same(authored)
	assert_object(WC.wind_for(WC.Preset.LEVEL, null, 0.0)).is_null()


func test_wind_for_calm_is_null() -> void:
	var authored := WindField.new()
	authored.speed = 20.0
	assert_object(WC.wind_for(WC.Preset.CALM, authored, 0.0)).is_null()


func test_wind_for_light_and_strong_are_new_resources_with_the_stated_speeds() -> void:
	var authored := WindField.new()
	var light: WindField = WC.wind_for(WC.Preset.LIGHT, authored, 0.0)
	var strong: WindField = WC.wind_for(WC.Preset.STRONG, authored, 0.0)
	assert_object(light).is_not_same(authored)
	assert_object(strong).is_not_same(authored)
	assert_float(light.speed).is_equal(WC.WIND_LIGHT_SPEED)
	assert_float(light.gust_speed).is_equal(WC.WIND_LIGHT_GUST)
	assert_float(strong.speed).is_equal(WC.WIND_STRONG_SPEED)
	assert_float(strong.gust_speed).is_equal(WC.WIND_STRONG_GUST)


func test_wind_for_converts_from_degrees_to_the_toward_heading() -> void:
	# FROM north (0) blows TOWARD south (180); WindField.base_vector(180, ...) points +Z.
	var w: WindField = WC.wind_for(WC.Preset.STRONG, null, 0.0)
	assert_float(w.direction_deg).is_equal_approx(180.0, 1e-6)
	var g := WindField.gust(w.gust_seed, 0.0, w.gust_speed)
	var base_only: Vector3 = w.vector_at(0.0) - Vector3(g.x, 0.0, g.y)
	assert_vector(base_only) \
		.is_equal_approx(Vector3(0.0, 0.0, WC.WIND_STRONG_SPEED), Vector3.ONE * 1e-4)


func test_wind_for_never_mutates_the_authored_resource() -> void:
	var authored := WindField.new()
	authored.speed = 3.0
	authored.direction_deg = 55.0
	WC.wind_for(WC.Preset.STRONG, authored, 90.0)
	assert_float(authored.speed).is_equal(3.0)
	assert_float(authored.direction_deg).is_equal(55.0)


# --- current_for ---------------------------------------------------------------------

func test_current_for_level_returns_the_authored_instance_including_null() -> void:
	var authored := CurrentField.new()
	assert_object(WC.current_for(WC.Preset.LEVEL, authored, 0.0)).is_same(authored)
	assert_object(WC.current_for(WC.Preset.LEVEL, null, 0.0)).is_null()


func test_current_for_calm_is_null() -> void:
	var authored := CurrentField.new()
	authored.drift = 3.0
	assert_object(WC.current_for(WC.Preset.CALM, authored, 0.0)).is_null()


func test_current_for_light_and_strong_are_new_resources_with_the_stated_drift() -> void:
	var authored := CurrentField.new()
	var light: CurrentField = WC.current_for(WC.Preset.LIGHT, authored, 0.0)
	var strong: CurrentField = WC.current_for(WC.Preset.STRONG, authored, 0.0)
	assert_object(light).is_not_same(authored)
	assert_object(strong).is_not_same(authored)
	assert_float(light.drift).is_equal(WC.CURRENT_LIGHT_DRIFT)
	assert_float(strong.drift).is_equal(WC.CURRENT_STRONG_DRIFT)
	# A player-picked current is a steady push for the session, not an authored tide cycle.
	assert_float(strong.tide_period_s).is_equal(0.0)


func test_current_for_converts_from_degrees_to_the_toward_heading_like_wind() -> void:
	var c: CurrentField = WC.current_for(WC.Preset.STRONG, null, 0.0)
	assert_float(c.set_deg).is_equal_approx(180.0, 1e-6)


func test_current_for_never_mutates_the_authored_resource() -> void:
	var authored := CurrentField.new()
	authored.drift = 1.5
	authored.set_deg = 10.0
	WC.current_for(WC.Preset.LIGHT, authored, 200.0)
	assert_float(authored.drift).is_equal(1.5)
	assert_float(authored.set_deg).is_equal(10.0)


# --- Level.set_conditions --------------------------------------------------------------

func test_level_set_conditions_level_restores_the_authored_wind_after_a_strong_override() -> void:
	var level: Level = auto_free(Level.new())
	var authored := WindField.new()
	authored.speed = 2.0
	authored.direction_deg = 30.0
	level.wind = authored
	level._capture_conditions()

	level.set_conditions(WC.Preset.STRONG, WC.Preset.LEVEL, 0.0)
	assert_object(level.wind).is_not_same(authored)
	assert_float(level.wind.speed).is_equal(WC.WIND_STRONG_SPEED)

	level.set_conditions(WC.Preset.LEVEL, WC.Preset.LEVEL, 0.0)
	assert_object(level.wind).is_same(authored)

extends GdUnitTestSuite
## Deep links: ?level=&vehicle= asks for configuration on boot. Validation: stale links
## fall back to shell default, not boot into nothing.


func test_parses_both_keys() -> void:
	var p := BootParams.parse_query("?level=level_3&vehicle=semi")
	assert_str(String(p["level"])).is_equal("level_3")
	assert_str(String(p["vehicle"])).is_equal("semi")


func test_no_query_means_no_opinion() -> void:
	for q in ["", "?", "?foo=bar", "&&"]:
		var p := BootParams.parse_query(q)
		assert_str(String(p["level"])).is_equal("")
		assert_str(String(p["vehicle"])).is_equal("")


func test_unknown_ids_are_dropped_not_kept() -> void:
	var p := BootParams.parse_query("level=level_99&vehicle=hovercraft")
	assert_str(String(p["level"])).is_equal("")
	assert_str(String(p["vehicle"])).is_equal("")


## A link names a VARIANT (the V axis), not the family the garage picks: "semi", not "truck".
func test_vehicle_is_the_variant_axis() -> void:
	assert_bool(BootParams.is_vehicle("semi")).is_true()
	assert_bool(BootParams.is_vehicle("truck")).is_false()


## The keyboard-drives-a-challenge override: either the user arg or the env var asks for it.
func test_challenge_keys_come_from_the_arg_or_the_env() -> void:
	assert_bool(BootParams.wants_challenge_keys(PackedStringArray(["--challenge-keys"]), "")).is_true()
	assert_bool(BootParams.wants_challenge_keys(PackedStringArray(), "1")).is_true()
	assert_bool(BootParams.wants_challenge_keys(PackedStringArray(["--level=flatland"]), "")).is_false()


## The debug challenge boot: the arg overrides the env var, and `--challenge-keys` is not it.
func test_challenge_comes_from_the_arg_or_the_env() -> void:
	assert_str(BootParams.parse_challenge(PackedStringArray(["--challenge=dev_box_stop"]), "")) \
			.is_equal("dev_box_stop")
	assert_str(BootParams.parse_challenge(PackedStringArray(), "dev_box_stop")).is_equal("dev_box_stop")
	assert_str(BootParams.parse_challenge(PackedStringArray(["--challenge=a"]), "b")).is_equal("a")
	assert_str(BootParams.parse_challenge(PackedStringArray(["--challenge-keys"]), "")).is_equal("")


## Dev fixtures are hidden from level select but reachable by link — that is how CARLITO_LEVEL
## smokes them in CI.
func test_level_ids_cover_the_whole_registry() -> void:
	for entry in LevelRegistry.LEVELS:
		var id := String(entry["id"])
		assert_bool(BootParams.is_level(id)).is_true()
		assert_str(LevelRegistry.scene_of(id)).is_equal(String(entry["scene"]))
		assert_str(LevelRegistry.id_of(String(entry["scene"]))).is_equal(id)


func test_registry_lookups_reject_unknowns() -> void:
	assert_str(LevelRegistry.scene_of("level_99")).is_equal("")
	assert_str(LevelRegistry.id_of("res://nope.tscn")).is_equal("")


func test_values_are_uri_decoded_and_later_keys_win() -> void:
	# The local command line is folded into the same parser, and it appends CARLITO_LEVEL
	# first so an explicit --level= overrides it.
	var p := BootParams.parse_query("level=garage&level=level_2")
	assert_str(String(p["level"])).is_equal("level_2")
	assert_str(String(BootParams.parse_query("vehicle=%73emi")["vehicle"])).is_equal("semi")

extends GdUnitTestSuite
## UserSettings: the SETTINGS page's choices, validated by type on read-back, pointed at a scratch
## file so the suite never touches the player's `user://settings.cfg`.

const SCRATCH := "user://user_settings_test.cfg"


func before_test() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(SCRATCH)


func test_an_unset_store_reads_the_defaults() -> void:
	var s := UserSettings.new(SCRATCH)
	for key in UserSettings.DEFAULTS:
		assert_that(s.value(key)).is_equal(UserSettings.DEFAULTS[key])


func test_every_setting_round_trips_through_the_file() -> void:
	var s := UserSettings.new(SCRATCH)
	s.set_value("density", Dashboard.Density.FULL)
	s.set_value("ui_scale", 1.35)
	s.set_value("extended_debug", true)
	s.set_value("key_softening", 0.65)
	s.set_value("tcs_off", true)
	var again := UserSettings.new(SCRATCH)
	assert_int(again.value("density")).is_equal(Dashboard.Density.FULL)
	assert_float(again.value("ui_scale")).is_equal_approx(1.35, 1e-6)
	assert_bool(again.value("extended_debug")).is_true()
	assert_float(again.value("key_softening")).is_equal_approx(0.65, 1e-6)
	assert_bool(again.value("tcs_off")).is_true()


## A wrong type or an unknown key is skipped on read and dropped on the next write.
func test_a_hand_edited_file_keeps_only_what_fits() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(UserSettings.SECTION, "ui_scale", 1)
	cfg.set_value(UserSettings.SECTION, "tcs_off", "yes")
	cfg.set_value(UserSettings.SECTION, "ghost", 3)
	cfg.save(SCRATCH)
	var s := UserSettings.new(SCRATCH)
	assert_float(s.value("ui_scale")).is_equal(1.0)
	assert_bool(s.value("tcs_off")).is_false()
	s.set_value("ghost", 4)
	s.set_value("extended_debug", "on")
	assert_bool(s.value("extended_debug")).is_false()
	s.set_value("density", Dashboard.Density.OFF)
	var written := ConfigFile.new()
	written.load(SCRATCH)
	assert_bool(written.has_section_key(UserSettings.SECTION, "ghost")).is_false()
	assert_bool(written.get_value(UserSettings.SECTION, "tcs_off")).is_false()


func test_a_memory_only_store_keeps_nothing() -> void:
	var s := UserSettings.new("")
	s.set_value("tcs_off", true)
	assert_bool(s.value("tcs_off")).is_true()
	assert_bool(UserSettings.new("").value("tcs_off")).is_false()


## Headless runs (the smoke run, CI) never write the player's file.
func test_headless_runs_use_no_file() -> void:
	assert_str(UserSettings.store_path(true)).is_empty()
	assert_str(UserSettings.store_path(false)).is_equal(UserSettings.PATH)


## The garage's tyre per variant survives a reload; a variant never picked reads "" (the stock).
func test_the_tyre_per_variant_round_trips_through_the_file() -> void:
	var s := UserSettings.new(SCRATCH)
	s.set_tyre("sedan", "winter")
	s.set_tyre("pickup", "mud")
	s.set_tyre("sedan", "summer")
	var again := UserSettings.new(SCRATCH)
	assert_str(again.tyre_of("sedan")).is_equal("summer")
	assert_str(again.tyre_of("pickup")).is_equal("mud")
	assert_str(again.tyre_of("taxi")).is_empty()


## A hand-edited tyre entry that is not String -> String is dropped; a store that is not a
## dictionary reads as none picked. Whether a kept id is known or fits is judged on fitting.
func test_a_hand_edited_tyre_store_keeps_only_strings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(UserSettings.SECTION, "tyres", {"sedan": "winter", "pickup": 3, 4: "mud",
			"taxi": "no_such_class"})
	cfg.save(SCRATCH)
	var s := UserSettings.new(SCRATCH)
	assert_str(s.tyre_of("sedan")).is_equal("winter")
	assert_str(s.tyre_of("pickup")).is_empty()
	assert_str(s.tyre_of("taxi")).is_equal("no_such_class")
	assert_int((s.value("tyres") as Dictionary).size()).is_equal(2)

	cfg.set_value(UserSettings.SECTION, "tyres", "winter")
	cfg.save(SCRATCH)
	assert_str(UserSettings.new(SCRATCH).tyre_of("sedan")).is_empty()

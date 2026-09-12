extends GdUnitTestSuite
## ChallengeProgress: best times per challenge, validated on read-back, pointed at a scratch file
## so the suite never touches the player's `user://challenges.cfg`.

const SCRATCH := "user://challenge_progress_test.cfg"
const IDS := ["car_start", "car_turns", "truck_abs"]


func before_test() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(SCRATCH)


func _store() -> ChallengeProgress:
	return ChallengeProgress.new(SCRATCH, PackedStringArray(IDS))


func test_a_pass_round_trips_through_the_file() -> void:
	var p := _store()
	assert_bool(p.is_done("car_start")).is_false()
	assert_bool(is_inf(p.best_time("car_start"))).is_true()
	assert_bool(p.record_pass("car_start", 42.5)).is_true()
	var again := _store()
	assert_bool(again.is_done("car_start")).is_true()
	assert_float(again.best_time("car_start")).is_equal(42.5)
	assert_bool(again.is_done("car_turns")).is_false()


func test_only_a_faster_pass_replaces_the_best() -> void:
	var p := _store()
	assert_bool(p.record_pass("car_turns", 40.0)).is_true()
	assert_bool(p.record_pass("car_turns", 45.0)).is_false()
	assert_float(p.best_time("car_turns")).is_equal(40.0)
	assert_bool(p.record_pass("car_turns", 38.0)).is_true()
	assert_float(_store().best_time("car_turns")).is_equal(38.0)


func test_unknown_ids_and_nonsense_times_are_ignored() -> void:
	var p := _store()
	assert_bool(p.record_pass("ghost", 10.0)).is_false()
	for t in [0.0, -1.0, NAN, INF]:
		assert_bool(p.record_pass("car_start", t)).is_false()
	assert_bool(p.is_done("car_start")).is_false()


## A renamed challenge or a hand-edited value must not break the file: it is skipped on read and
## dropped on the next write.
func test_a_hand_edited_file_keeps_only_what_is_valid() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(ChallengeProgress.SECTION, "car_start", 12.0)
	cfg.set_value(ChallengeProgress.SECTION, "ghost", 5.0)
	cfg.set_value(ChallengeProgress.SECTION, "car_turns", "fast")
	cfg.set_value(ChallengeProgress.SECTION, "truck_abs", -3.0)
	cfg.save(SCRATCH)
	var p := _store()
	assert_float(p.best_time("car_start")).is_equal(12.0)
	assert_bool(p.is_done("ghost")).is_false()
	assert_bool(p.is_done("car_turns")).is_false()
	assert_bool(p.is_done("truck_abs")).is_false()
	p.record_pass("truck_abs", 30.0)
	var written := ConfigFile.new()
	written.load(SCRATCH)
	assert_bool(written.has_section_key(ChallengeProgress.SECTION, "ghost")).is_false()
	assert_bool(written.has_section_key(ChallengeProgress.SECTION, "car_turns")).is_false()


func test_reset_forgets_every_pass_on_disk_too() -> void:
	var p := _store()
	p.record_pass("car_start", 20.0)
	p.record_pass("truck_abs", 30.0)
	p.reset()
	assert_bool(p.is_done("car_start")).is_false()
	var again := _store()
	assert_bool(again.is_done("car_start")).is_false()
	assert_bool(again.is_done("truck_abs")).is_false()


func test_a_memory_only_store_keeps_nothing() -> void:
	var p := ChallengeProgress.new("", PackedStringArray(IDS))
	assert_bool(p.record_pass("car_start", 20.0)).is_true()
	assert_bool(p.is_done("car_start")).is_true()
	assert_bool(ChallengeProgress.new("", PackedStringArray(IDS)).is_done("car_start")).is_false()


## Headless runs (the smoke run, CI) never write the player's file.
func test_headless_runs_use_no_file() -> void:
	assert_str(ChallengeProgress.store_path(true)).is_empty()
	assert_str(ChallengeProgress.store_path(false)).is_equal(ChallengeProgress.PATH)

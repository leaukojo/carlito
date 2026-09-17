extends GdUnitTestSuite
## Level.has_spawn_for: the same walk `_spawn_vehicle` uses to find (or refuse) a VehicleSpawn,
## exposed so the vehicle selector can refuse DRIVE with a reason instead of `_spawn_vehicle`
## silently `push_error`-ing and leaving the old vehicle in place.

func _level_with_spawn(types: PackedStringArray) -> Level:
	var level := auto_free(Level.new()) as Level
	var spawn := VehicleSpawn.new()
	spawn.vehicle_types = types
	level.add_child(spawn)
	add_child(level)
	return level


func test_has_spawn_for_true_when_a_spawn_accepts_the_family() -> void:
	var level := _level_with_spawn(PackedStringArray(["car"]))
	assert_bool(level.has_spawn_for(&"car")).is_true()


func test_has_spawn_for_false_when_no_spawn_accepts_the_family() -> void:
	var level := _level_with_spawn(PackedStringArray(["car"]))
	assert_bool(level.has_spawn_for(&"boat")).is_false()


func test_has_spawn_for_any_type_spawn_accepts_every_family() -> void:
	var level := _level_with_spawn(PackedStringArray())
	assert_bool(level.has_spawn_for(&"tractor")).is_true()


## The train ignores VehicleSpawn markers entirely (root CLAUDE.md, rule: rail-guided) — a spawn
## that lists "train" must not make this true; only a closed rail loop does.
func test_has_spawn_for_train_reads_the_rail_loop_not_a_spawn_marker() -> void:
	var level := _level_with_spawn(PackedStringArray(["train"]))
	assert_bool(level.has_spawn_for(&"train")).is_false()

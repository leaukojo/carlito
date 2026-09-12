# GdUnit generated TestSuite
extends GdUnitTestSuite
## Level packs (src/shell/level_packs.gd): which levels ship in one, what a pack is called, and
## which cached files a new build throws away. The fetch itself only runs on the web.


## A first visit and every failed load land on the boot default, so it must come from the
## main pack with no download in front of it.
func test_the_boot_default_ships_in_the_main_pack() -> void:
	var boot := preload("res://src/shell/boot.gd")
	assert_bool(LevelPacks.is_packed(LevelRegistry.scene_of(boot.DEFAULT_LEVEL))).is_false()


func test_islands_are_packed_and_the_garage_is_not() -> void:
	assert_bool(LevelPacks.is_packed(LevelRegistry.scene_of("level_3"))).is_true()
	assert_bool(LevelPacks.is_packed(LevelRegistry.scene_of("garage"))).is_false()


## Off the web every island is on disk, so nothing is ever fetched.
func test_nothing_needs_a_fetch_locally() -> void:
	for entry in LevelRegistry.LEVELS:
		assert_bool(LevelPacks.needs_fetch(String(entry["scene"]))).is_false()


func test_a_pack_is_named_after_the_build_it_patches() -> void:
	assert_str(LevelPacks.pack_name("c2-1a2b3c4d", "level_5")).is_equal("c2-1a2b3c4d.level_5.pck")


## A delta pack mounts only over the main pack it was exported against, so an older build's
## packs are dead weight.
func test_stale_keeps_only_this_builds_packs() -> void:
	var files := PackedStringArray(["c2-aaaa.level_1.pck", "c2-bbbb.level_1.pck",
			"c2-bbbb.level_3.pck", "c2-aaaa.level_3.pck"])
	assert_array(Array(LevelPacks.stale(files, "c2-bbbb"))).contains_exactly(
			["c2-aaaa.level_1.pck", "c2-aaaa.level_3.pck"])

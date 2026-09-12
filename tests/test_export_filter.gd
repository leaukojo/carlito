# GdUnit generated TestSuite
extends GdUnitTestSuite
## The Web preset ships every resource minus its `exclude_filter`, and an excluded file a
## shipped scene depends on is simply absent from the .pck — the exported build dies with
## `No loader found for resource`, which no local run reproduces (docs/deploying.md § The web
## export). This walks every baked level's dependencies against the filter, so a kit texture
## may be name-excluded only while no baked level reaches it; an island's own folder is the
## exception, since it ships in its level pack instead (docs/deploying.md § Level packs).
## Reads the real .baked.scn: CI bakes before the suite; locally, run tools/bake_levels.tscn
## first.

const Baker := preload("res://kit/bake/level_baker.gd")


## Every key of the preset section named `preset_name`, or of its `.options` section; empty
## when there is none.
func _preset(preset_name: String, options := false) -> Dictionary:
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://export_presets.cfg")).is_equal(OK)
	for section in cfg.get_sections():
		if section.ends_with(".options") \
				or String(cfg.get_value(section, "name", "")) != preset_name:
			continue
		var target := section + ".options" if options else section
		var out := {}
		for key in cfg.get_section_keys(target):
			out[key] = cfg.get_value(target, key)
		return out
	return {}


func _preset_names() -> PackedStringArray:
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://export_presets.cfg")).is_equal(OK)
	var out := PackedStringArray()
	for section in cfg.get_sections():
		if not section.ends_with(".options"):
			out.append(String(cfg.get_value(section, "name", "")))
	return out


static func _filters(preset: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for f in String(preset.get("exclude_filter", "")).split(","):
		if not f.strip_edges().is_empty():
			out.append(f.strip_edges())
	return out


func _web_exclude_filters() -> PackedStringArray:
	return _filters(_preset("Web"))


## The exporter's own test: a filter matches the path with or without `res://`, and `*`
## crosses directories.
static func _excluded(path: String, filters: PackedStringArray) -> bool:
	for f in filters:
		if path.matchn(f) or path.trim_prefix("res://").matchn(f):
			return true
	return false


static func _packed_levels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in LevelRegistry.LEVELS:
		if LevelPacks.is_packed(String(entry["scene"])):
			out.append(entry)
	return out


## The exclude entry that drops a level's whole folder.
static func _folder_filter(entry: Dictionary) -> String:
	return String(entry["scene"]).get_base_dir().trim_prefix("res://") + "/*"


func test_filter_matching_mirrors_the_exporter() -> void:
	var filters := _web_exclude_filters()
	assert_bool(filters.is_empty()).is_false()
	assert_bool(_excluded("res://kit/raw/racing/fenceStraight.glb", filters)).is_true()
	assert_bool(_excluded("res://kit/raw/racing/flagCheckers_checkers.png", filters)).is_false()


## The main pack carries exactly the levels that are not packed.
func test_the_main_pack_leaves_out_every_packed_level() -> void:
	var filters := _web_exclude_filters()
	for entry in LevelRegistry.LEVELS:
		var scene := String(entry["scene"])
		assert_bool(_excluded(scene, filters)).override_failure_message(
				"%s: main pack exclusion disagrees with LevelPacks.is_packed" % scene
				).is_equal(LevelPacks.is_packed(scene))


## A level pack is exported as a patch against the main pack, and a patch also records as
## DELETED every main-pack file its own preset would not export: mounting it takes them away.
## So a level's preset exports everything the main one does, with only the OTHER packed levels
## still excluded, and exports every file the same way: a different texture format or script
## mode is a different file set, which the patch would delete from the main pack or copy whole.
## Delta encoding keeps the scenes whose exported bytes differ from run to run (their generated
## node ids) at a few bytes each instead of a full copy.
func test_every_packed_level_has_a_preset_that_exports_the_main_pack_too() -> void:
	var main := _preset("Web")
	var main_options := _preset("Web", true)
	var main_filters := _filters(main)
	var root_filter := LevelPacks.PACK_ROOT.trim_prefix("res://") + "*"
	assert_bool(main_filters.has(root_filter)).is_true()
	var packed := _packed_levels()
	assert_array(packed).is_not_empty()
	for entry in packed:
		var p := _preset("Web " + String(entry["id"]))
		assert_dict(p).override_failure_message(
				"no \"Web %s\" preset in export_presets.cfg" % entry["id"]).is_not_empty()
		if p.is_empty():
			continue
		var expected := Array(main_filters)
		expected.erase(root_filter)
		for other in packed:
			if other != entry:
				expected.append(_folder_filter(other))
		assert_array(Array(_filters(p))).contains_exactly_in_any_order(expected)
		for key in ["export_filter", "include_filter", "script_export_mode", "custom_features",
				"dedicated_server"]:
			assert_str(str(p.get(key))).override_failure_message(
					"Web %s: %s differs from the main preset" % [entry["id"], key]
					).is_equal(str(main.get(key)))
		var options := _preset("Web " + String(entry["id"]), true)
		for key in ["vram_texture_compression/for_desktop", "vram_texture_compression/for_mobile"]:
			assert_str(str(options.get(key))).override_failure_message(
					"Web %s: %s differs from the main preset" % [entry["id"], key]
					).is_equal(str(main_options.get(key)))
		assert_bool(bool(p["patch_delta_encoding"])).is_true()
		# Delta-encoded, Godot's own caches read short on mount ("Reading less data than
		# requested"); shipped whole they cost ~33 KB raw a pack.
		var no_delta := String(p["patch_delta_exclude_filters"])
		assert_str(no_delta).contains("uid_cache.bin")
		assert_str(no_delta).contains("global_script_class_cache.cfg")


## CI exports one pack per "Web <id>" preset: each must still name a packed level.
func test_no_level_preset_outlives_its_level() -> void:
	for preset_name in _preset_names():
		if not preset_name.begins_with("Web "):
			continue
		var scene := LevelRegistry.scene_of(preset_name.trim_prefix("Web "))
		assert_bool(LevelPacks.is_packed(scene)).override_failure_message(
				"preset \"%s\" names no packed level" % preset_name).is_true()


func test_no_baked_level_depends_on_an_export_excluded_file() -> void:
	var filters := _web_exclude_filters()
	var baked := 0
	var offenders: Array[String] = []
	for entry in LevelRegistry.LEVELS:
		var scn := Baker.baked_scene_path(String(entry["scene"]))
		if not FileAccess.file_exists(scn):
			continue
		baked += 1
		# A packed level's own folder ships in its pack; any other island's does not.
		var own := String(entry["scene"]).get_base_dir() + "/" \
				if LevelPacks.is_packed(String(entry["scene"])) else ""
		var seen := {scn: true}
		var queue: Array[String] = [scn]
		while not queue.is_empty():
			var p: String = queue.pop_back()
			for dep in ResourceLoader.get_dependencies(p):
				var dp := Baker._dep_path(String(dep))
				if dp.is_empty() or seen.has(dp):
					continue
				seen[dp] = true
				queue.append(dp)
				if _excluded(dp, filters) and (own.is_empty() or not dp.begins_with(own)):
					offenders.append("%s -> %s" % [scn, dp])
	assert_int(baked).override_failure_message(
			"no .baked.scn on disk, nothing walked: run tools/bake_levels.tscn").is_greater(0)
	assert_array(offenders).override_failure_message(
			"baked levels depend on files the Web preset's exclude_filter drops:\n%s"
			% "\n".join(offenders)).is_empty()

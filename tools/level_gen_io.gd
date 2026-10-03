## File output shared by the level generators (`gen_*.gd`): PNG and text writers and the
## LevelInfo resource text. `write_*` log under the generator's `tag` and report failure, for the
## Node-mode tools that exit with a code; `save_*` assert, for the SceneTree one-shots.


## Saves `img` as a lossless terrain PNG and writes its import settings; false (and a printed
## error) when the save fails.
static func write_png(img: Image, path: String, tag: String) -> bool:
	if img.save_png(path) != OK:
		printerr("[%s] failed to write %s" % [tag, path])
		return false
	TerrainGen.ensure_import_settings(path)
	print("[%s] wrote %s" % [tag, path])
	return true


static func write_text(path: String, text: String, tag: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[%s] cannot write %s" % [tag, path])
		return
	f.store_string(text)
	print("[%s] wrote %s" % [tag, path])


static func save_png(img: Image, path: String) -> void:
	var err := img.save_png(path)
	assert(err == OK, "save_png failed for %s" % path)
	TerrainGen.ensure_import_settings(path)


static func save_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert(f != null, "cannot write %s" % path)
	f.store_string(text)


## The level's LevelInfo `.tres`. `load_steps` stamps the header's (ignored, but committed)
## `load_steps=2`.
static func info_text(title: String, allowed: PackedStringArray, default_vehicle: String,
		load_steps := false) -> String:
	return """[gd_resource type="Resource" script_class="LevelInfo"%s format=3]

[ext_resource type="Script" path="res://src/levels/base/level_info.gd" id="1_info"]

[resource]
script = ExtResource("1_info")
display_name = "%s"
allowed_vehicles = PackedStringArray("%s")
default_vehicle = "%s"
""" % [" load_steps=2" if load_steps else "", title, '", "'.join(allowed), default_vehicle]

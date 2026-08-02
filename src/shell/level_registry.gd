class_name LevelRegistry
extends Object
## The shell's list of playable levels. The level-select screen reads this;
## levels are self-contained scenes, so adding one is a new entry here
## plus its `.tscn`. `name` is a plain-text menu label (LevelInfo.display_name is the
## in-level authority; kept here too so select needn't load every scene to build a list).
## `desc` is menu-only flavor text, shown while a card is hovered or focused; `id` also
## names the card screenshot (`LevelShot.thumb_path`).
##
## `dev: true` entries are test assets, not shipped content: level-select hides them, but
## the bake/check tools and the CARLITO_LEVEL smoke still iterate the full list, so CI
## covers them.
##
## The five island levels are independent playgrounds: level_1 is dressed; 2-5 ship
## generated terrain + auto-splat and an empty AuthoringRoot, ready to author
## (see tools/gen_islands.gd).

const LEVELS: Array[Dictionary] = [
	{ "id": "garage", "name": "Garage", "scene": "res://src/levels/garage/garage.tscn",
		"desc": "Indoor workshop. Swap vehicles and read the dashboard with nothing to hit." },
	{ "id": "level_1", "name": "Level 1 - Island", "scene": "res://src/levels/island/level_1/level_1.tscn",
		"desc": "Dressed island: farm fields for hitch, PTO and draft work, coast roads, open water." },
	{ "id": "level_2", "name": "Level 2 - Mountain", "scene": "res://src/levels/island/level_2/level_2.tscn",
		"desc": "Mountain island: long grades to load the engine, tight bends to break traction." },
	{ "id": "level_3", "name": "Level 3 - City", "scene": "res://src/levels/island/level_3/level_3.tscn",
		"desc": "City island: gridded streets, parked traffic, a harbor front to launch the boat." },
	{ "id": "level_4", "name": "Level 4 - Racing", "scene": "res://src/levels/island/level_4/level_4.tscn",
		"desc": "Racing island: a circuit with pits and grandstands. Top speed, brakes and slip." },
	{ "id": "level_5", "name": "Level 5 - Railway", "scene": "res://src/levels/island/level_5/level_5.tscn",
		"desc": "Railway island: a closed loop for the train, with road and water alongside." },
]


## Scene path for a level id, "" if unknown. The id is the stable name: it is what a deep
## link (`?level=`), the saved session and CARLITO_LEVEL all carry, so nothing outside this
## file has to know where a level scene lives.
static func scene_of(id: String) -> String:
	for entry in LEVELS:
		if String(entry["id"]) == id:
			return String(entry["scene"])
	return ""


## The id of a loaded level, from its scene path; "" if it is not a registered level.
## The inverse of scene_of, so the shell can save "where you were" as an id.
static func id_of(scene_path: String) -> String:
	for entry in LEVELS:
		if String(entry["scene"]) == scene_path:
			return String(entry["id"])
	return ""


## The whole registry row for a scene path, empty when unregistered. The loading screen
## dresses itself from this (name + card picture) knowing only what it was asked to load.
static func entry_of(scene_path: String) -> Dictionary:
	for entry in LEVELS:
		if String(entry["scene"]) == scene_path:
			return entry
	return {}


## Bytes of a level's baked scene — the artifact that dominates how long you wait for it
## (the city is ~14 MB, the mountain 0.7). 0 when there is no bake to measure: the garage is
## an indoor scene and ships none.
##
## Only the .baked.scn is counted, and that is a deliberate limit: it is the one level file
## that survives export as itself, so this number reads the same locally and in the shipped
## build. The terrain heightmap/splat PNGs become .ctex on export and cannot be measured at
## runtime at all. Same path convention as Level._setup_baked / LevelBaker.baked_scene_path.
static func weight_bytes(scene_path: String) -> int:
	var f := FileAccess.open(scene_path.get_basename() + ".baked.scn", FileAccess.READ)
	if f == null:
		return 0
	var n := int(f.get_length())
	f.close()
	return n


## That weight as menu text ("0.7 MB", "14 MB"); "" when there is no bake to report.
static func weight_text(scene_path: String) -> String:
	var mb := float(weight_bytes(scene_path)) / 1048576.0
	if mb <= 0.0:
		return ""
	return ("%.1f MB" % mb) if mb < 10.0 else ("%d MB" % roundi(mb))

class_name LevelRegistry
extends Object
## Shell's playable-levels list: add a new entry + .tscn. `name` is menu label, `desc` is
## flavor text, `id` names the scene and screenshot. `dev: true` entries hidden from
## level-select but included in bake/check/smoke tests.

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
	{ "id": "level_6", "name": "Level 6 - Skyport", "scene": "res://src/levels/island/level_6/level_6.tscn",
		"desc": "Drone bench: pads at altitude, a mast slalom, and a canyon that takes the satellites away." },
]


## Scene path for a level id, "" if unknown. The id is the stable name a deep link
## (`?level=`), saved session, and CARLITO_LEVEL all carry.
static func scene_of(id: String) -> String:
	for entry in LEVELS:
		if String(entry["id"]) == id:
			return String(entry["scene"])
	return ""


## Inverse of scene_of, so the shell can save "where you were" as an id.
static func id_of(scene_path: String) -> String:
	for entry in LEVELS:
		if String(entry["scene"]) == scene_path:
			return String(entry["id"])
	return ""


## Whole registry row for a scene path, empty when unregistered.
static func entry_of(scene_path: String) -> Dictionary:
	for entry in LEVELS:
		if String(entry["scene"]) == scene_path:
			return entry
	return {}


## Bytes of a level's baked scene, the artifact that dominates load wait. 0 when there is no
## bake (the garage ships none). Only .baked.scn is counted: the one level file that survives
## export as itself, so the number reads the same locally and shipped — the terrain PNGs
## become .ctex on export and can't be measured at runtime.
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

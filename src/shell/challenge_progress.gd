class_name ChallengeProgress
extends RefCounted
## Which challenges the player has passed and their best times, in `user://challenges.cfg`
## (IndexedDB on web). Always on: it is independent of ShellPrefs, whose ENABLED switch is off for
## boot-path testing and must not take progress with it. A pass is always timed, so "done" is
## simply "has a best time" — one stored fact, not two that could disagree.
##
## Everything read back is validated: an id the registry no longer lists, or a value that is not a
## positive finite number of seconds, is ignored (and dropped on the next write), so a renamed
## challenge or a hand-edited file cannot break it.

const PATH := "user://challenges.cfg"
const SECTION := "best"

var _path := ""    ## "" = memory only, never written
var _known := PackedStringArray()
var _best: Dictionary[String, float] = {}


## `store` "" keeps everything in memory. `known_ids` are the ids a read-back may keep.
func _init(store: String, known_ids: PackedStringArray) -> void:
	_path = store
	_known = known_ids
	_load()


## The game's store over the registry's ids. The shell opens it once and keeps it; it is not
## cached in a static var, because objects held there outlive the engine's exit check and are
## reported as leaks.
static func open() -> ChallengeProgress:
	return ChallengeProgress.new(store_path(DisplayServer.get_name() == "headless"),
			ChallengeRegistry.ids())


## Where the game's store lives: nowhere for a headless run (the smoke run and CI), so they never
## write the player's file.
static func store_path(headless: bool) -> String:
	return "" if headless else PATH


func is_done(id: String) -> bool:
	return _best.has(id)


## Best time in seconds, INF when never passed.
func best_time(id: String) -> float:
	return _best.get(id, INF)


## Record a pass; true when it is a new best. An unknown id or a nonsense time is ignored.
func record_pass(id: String, seconds: float) -> bool:
	if not _known.has(id) or not _valid_time(seconds) or seconds >= best_time(id):
		return false
	_best[id] = seconds
	_save()
	return true


## Forget every pass (RESET PROGRESS, behind its confirmation).
func reset() -> void:
	_best.clear()
	_save()


func _load() -> void:
	if _path == "":
		return
	var cfg := ConfigFile.new()
	if cfg.load(_path) != OK or not cfg.has_section(SECTION):
		return
	for id in cfg.get_section_keys(SECTION):
		var v: Variant = cfg.get_value(SECTION, id)
		if _known.has(id) and (v is float or v is int) and _valid_time(float(v)):
			_best[id] = float(v)


func _save() -> void:
	if _path == "":
		return
	var cfg := ConfigFile.new()
	for id in _best:
		cfg.set_value(SECTION, id, _best[id])
	cfg.save(_path)


static func _valid_time(seconds: float) -> bool:
	return is_finite(seconds) and seconds > 0.0

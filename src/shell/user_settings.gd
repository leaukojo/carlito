class_name UserSettings
extends RefCounted
## The SETTINGS page's choices and the garage's tyre class per variant, in `user://settings.cfg`
## (IndexedDB on web), so a reload keeps them. CONDITIONS and the gearbox stay session-only
## (boot.gd).
##
## Read back by type only: a value whose type is not its default's is ignored (and dropped on the
## next write). Range is its owner's job (Dashboard, UiScale, DebugOverlay, InputRouter), whose
## setter validates a saved value exactly as it does a press; a stored tyre is judged when it is
## fitted (`WheelDrive.fit_tyre`: an unknown or unfitting class reads as the stock).

const KeyShaper := preload("res://src/input/key_shaper.gd")

const PATH := "user://settings.cfg"
const SECTION := "settings"
## Every key the store keeps, with its default, which also fixes its type.
const DEFAULTS := {
	"density": Dashboard.Density.COMPACT,
	"ui_scale": UiScale.USER_DEFAULT,
	"extended_debug": false,
	"key_softening": KeyShaper.DEFAULT_SOFTENING,
	"tcs_off": false,
	"tyres": {},  ## variant -> TyreClass id (`tyre_of`, `set_tyre`)
}

var _path := ""    ## "" = memory only, never written
var _values := DEFAULTS.duplicate(true)


## `store` "" keeps everything in memory.
func _init(store: String) -> void:
	_path = store
	_load()


## The game's store. Opened once by the shell and kept there, as `ChallengeProgress.open`.
static func open() -> UserSettings:
	return UserSettings.new(store_path(DisplayServer.get_name() == "headless"))


## Where the game's store lives: nowhere for a headless run (the smoke run and CI), so they never
## write the player's file.
static func store_path(headless: bool) -> String:
	return "" if headless else PATH


## The stored value of `key` (a DEFAULTS key), its default when never set.
func value(key: String) -> Variant:
	return _values[key]


## Record a choice and write the file. An unknown key or a value of the wrong type is ignored.
func set_value(key: String, v: Variant) -> void:
	if not _fits(key, v):
		return
	v = type_convert(v, typeof(DEFAULTS[key]))
	if v == _values[key]:
		return
	_values[key] = v
	_save()


## The tyre class id stored for `variant`, "" when none was picked (the stock).
func tyre_of(variant: String) -> String:
	return String((_values["tyres"] as Dictionary).get(variant, ""))


## Record `id` as `variant`'s tyre and write the file.
func set_tyre(variant: String, id: String) -> void:
	var tyres := (_values["tyres"] as Dictionary).duplicate()
	tyres[variant] = id
	set_value("tyres", tyres)


func _load() -> void:
	if _path == "":
		return
	var cfg := ConfigFile.new()
	if cfg.load(_path) != OK or not cfg.has_section(SECTION):
		return
	for key in cfg.get_section_keys(SECTION):
		var v: Variant = cfg.get_value(SECTION, key)
		if _fits(key, v):
			_values[key] = type_convert(v, typeof(DEFAULTS[key]))
	_values["tyres"] = _strings_only(_values["tyres"])


func _save() -> void:
	if _path == "":
		return
	var cfg := ConfigFile.new()
	for key in _values:
		cfg.set_value(SECTION, key, _values[key])
	cfg.save(_path)


## A known key, and a value of its default's type (an int is taken for a float default: a
## hand-edited `1` is a scale of 1.0).
static func _fits(key: String, v: Variant) -> bool:
	if not DEFAULTS.has(key):
		return false
	var want := typeof(DEFAULTS[key])
	return typeof(v) == want or (want == TYPE_FLOAT and typeof(v) == TYPE_INT)


## `d`'s String -> String entries; a hand-edited entry of any other type is dropped.
static func _strings_only(d: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in d:
		if typeof(k) == TYPE_STRING and typeof(d[k]) == TYPE_STRING:
			out[k] = d[k]
	return out

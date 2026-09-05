class_name ShellPrefs
extends RefCounted
## The handful of things the shell remembers between visits, in one `user://` file: last
## level+variant, first-run coach cue seen, cluster density, UI scale.
##
## Everything read back is validated (through BootParams etc.) before being handed out — a
## saved id is as stale-able as a link, so the shell must fall back rather than boot into
## nothing. Writes are whole-file and rare, so no flush/dirty bookkeeping.

const PATH := "user://shell.cfg"
const SECTION := "shell"

## Persistence is off: remembered state is confusing during boot path testing. _config() and
## setters skip the load/save while false. Flip to true to re-enable all four keys at once.
const ENABLED := false

static var _cfg: ConfigFile = null


## Where the player last was, as {level, vehicle}; unknown/absent ids come back empty.
static func load_boot() -> Dictionary:
	var cfg := _config()
	var level := String(cfg.get_value(SECTION, "level", ""))
	var vehicle := String(cfg.get_value(SECTION, "vehicle", ""))
	return {
		"level": level if BootParams.is_level(level) else "",
		"vehicle": vehicle if BootParams.is_vehicle(vehicle) else "",
	}


static func save_boot(level: String, vehicle: String) -> void:
	if not ENABLED:
		return
	var cfg := _config()
	cfg.set_value(SECTION, "level", level)
	cfg.set_value(SECTION, "vehicle", vehicle)
	cfg.save(PATH)


## Whether the first-run cue has already been shown in this browser / on this machine.
static func coach_seen() -> bool:
	return bool(_config().get_value(SECTION, "coach_seen", false))


static func mark_coach_seen() -> void:
	if not ENABLED:
		return
	var cfg := _config()
	cfg.set_value(SECTION, "coach_seen", true)
	cfg.save(PATH)


## Cluster density (Dashboard.Density), stored/validated as Dashboard's string key.
static func dashboard_density() -> int:
	return Dashboard.setting_from_key(String(_config().get_value(SECTION, "dashboard", "auto")))


static func set_dashboard_density(setting: int) -> void:
	if not ENABLED:
		return
	var cfg := _config()
	cfg.set_value(SECTION, "dashboard", Dashboard.key_of(setting))
	cfg.save(PATH)


## UI-size multiplier, clamped to UiScale's range.
static func ui_scale() -> float:
	var f := float(_config().get_value(SECTION, "ui_scale", UiScale.USER_DEFAULT))
	return clampf(f, UiScale.USER_STEPS[0], UiScale.USER_STEPS[UiScale.USER_STEPS.size() - 1])


static func set_ui_scale(factor: float) -> void:
	if not ENABLED:
		return
	var cfg := _config()
	cfg.set_value(SECTION, "ui_scale", factor)
	cfg.save(PATH)


## Parsed file, loaded once. Missing/corrupt file is treated as empty.
static func _config() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		if ENABLED:
			_cfg.load(PATH)
	return _cfg

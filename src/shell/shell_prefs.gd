class_name ShellPrefs
extends RefCounted
## The handful of things the shell remembers between visits, in one `user://` file.
##
## Today: where you were driving (level + variant) so a reload resumes it, whether the
## first-run coaching cue has been shown, and how dense the instrument cluster is.
##
## Everything read back is VALIDATED through BootParams before it is handed out — a saved id
## is just as stale-able as a link, and the shell must fall back to its default rather than
## boot into nothing. Writes are whole-file and rare (a level load, a vehicle swap), so there
## is no flush/dirty bookkeeping.

const PATH := "user://shell.cfg"
const SECTION := "shell"

## Persistence is OFF during development: a remembered level/vehicle/density is confusing when
## the thing you are testing is the boot path itself. The logic below is intact — flip this back
## to true to re-enable. While false, nothing is read from or written to `user://`, so every
## visit boots from defaults (and a leftover shell.cfg is simply ignored).
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


## How much of the instrument cluster is on screen, as a Dashboard.Density SETTING (AUTO
## included — "let the rules decide" is a choice the player can go back to). Stored as
## Dashboard's own string key, and validated through it on the way out, so a stale or
## hand-edited cfg falls back to AUTO rather than to a blank dashboard.
static func dashboard_density() -> int:
	return Dashboard.setting_from_key(String(_config().get_value(SECTION, "dashboard", "auto")))


static func set_dashboard_density(setting: int) -> void:
	if not ENABLED:
		return
	var cfg := _config()
	cfg.set_value(SECTION, "dashboard", Dashboard.key_of(setting))
	cfg.save(PATH)


## The player's UI-size multiplier (SETTINGS ▸ UI SIZE), clamped to the range UiScale offers so a
## stale or hand-edited cfg cannot leave the UI unreadably small or off the screen.
static func ui_scale() -> float:
	var f := float(_config().get_value(SECTION, "ui_scale", UiScale.USER_DEFAULT))
	return clampf(f, UiScale.USER_STEPS[0], UiScale.USER_STEPS[UiScale.USER_STEPS.size() - 1])


static func set_ui_scale(factor: float) -> void:
	if not ENABLED:
		return
	var cfg := _config()
	cfg.set_value(SECTION, "ui_scale", factor)
	cfg.save(PATH)


## The parsed file, loaded once per run. A missing or corrupt file is simply an empty one:
## nothing here is worth failing a boot over.
static func _config() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		if ENABLED:
			_cfg.load(PATH)
	return _cfg

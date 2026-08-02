class_name BootParams
extends RefCounted
## What the shell was ASKED to boot into — the deep link, if there is one.
##
## The game now drives first in every mode (there is no level-select front door), so the one
## way an embedder can say "start in the city, in a semi" is a parameter. On web that is the
## page's query string (`?level=level_3&vehicle=semi`), which is what sloppyCAN sets; locally
## it is `--level=`/`--vehicle=` after a `--` on the command line, plus the CARLITO_LEVEL
## environment variable CI already uses for its baked-level smoke.
##
## Parsing and VALIDATION live together here, and both sides of the shell use them: a stale
## link (or a saved session naming a level that has since been renamed) must fall back to the
## default rather than boot into nothing. Unknown ids are dropped, not clamped — `{}` means
## "no opinion", which is exactly what the caller needs to know to consult its next authority.

## Empty result, i.e. no deep link. Both fields are always present so callers never guess.
const NONE := {"level": "", "vehicle": ""}


## Parse a query string ("?level=x&vehicle=y", leading '?' optional) into {level, vehicle},
## dropping ids that no longer exist.
static func parse_query(query: String) -> Dictionary:
	var out := NONE.duplicate()
	for pair in query.trim_prefix("?").split("&", false):
		var eq := pair.find("=")
		if eq <= 0:
			continue
		var key := pair.substr(0, eq).to_lower()
		var value := pair.substr(eq + 1).uri_decode()
		match key:
			"level":
				if is_level(value):
					out["level"] = value
			"vehicle":
				if is_vehicle(value):
					out["vehicle"] = value
	return out


## Whether `id` names a level in the registry. Dev fixtures count: level select hides them,
## but a deep link (and CARLITO_LEVEL) may name one deliberately.
static func is_level(id: String) -> bool:
	return LevelRegistry.scene_of(id) != ""


## Whether `variant` names a vehicle variant. This is the VARIANT axis (V), not the family the
## garage picks — a link says "semi", not "truck".
static func is_vehicle(variant: String) -> bool:
	return VehicleCatalog.VARIANTS.has(variant)


## The deep link for this run, or NONE. Web reads the page query string; everything else reads
## the command line and the environment.
static func resolve() -> Dictionary:
	if OS.has_feature("web"):
		var raw: Variant = JavaScriptBridge.eval("window.location.search", true)
		return parse_query(raw) if typeof(raw) == TYPE_STRING else NONE.duplicate()
	return parse_query(_local_query())


## The local stand-in for a query string. CARLITO_LEVEL comes first so an explicit
## `--level=` on the command line overrides it (later keys win in parse_query).
static func _local_query() -> String:
	var parts := PackedStringArray()
	var env := OS.get_environment("CARLITO_LEVEL")
	if env != "":
		parts.append("level=" + env)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level=") or arg.begins_with("--vehicle="):
			parts.append(arg.trim_prefix("--"))
	return "&".join(parts)

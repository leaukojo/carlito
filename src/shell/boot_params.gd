class_name BootParams
extends RefCounted
## Deep link boot params: web reads page query string; local reads --level/--vehicle or
## CARLITO_LEVEL env. Parsing and validation together; unknown ids dropped (not clamped) —
## {} means "no opinion" for the caller's next authority.

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

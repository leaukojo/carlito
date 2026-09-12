class_name BootParams
extends RefCounted
## Deep link boot params: web reads page query string; local reads --level/--vehicle or
## CARLITO_LEVEL env. Parsing and validation together; unknown ids dropped (not clamped) —
## {} means "no opinion" for the caller's next authority. Also the debug-only challenge-keys flag
## and challenge boot.

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


## Whether the keyboard may drive a challenge (InputRouter's dev override). Debug builds only —
## CI exports the web build as release, so it is never honoured there. The env var exists because
## an F6 run has no user args without editing project.godot.
static func challenge_keys() -> bool:
	return OS.is_debug_build() and wants_challenge_keys(OS.get_cmdline_user_args(),
			OS.get_environment("CARLITO_CHALLENGE_KEYS"))


static func wants_challenge_keys(args: PackedStringArray, env: String) -> bool:
	return env != "" or args.has("--challenge-keys")


## The challenge a debug build boots straight into, or "": `--challenge=<id>` or CARLITO_CHALLENGE,
## dev fixtures included, validated against the registry. Debug builds only, like the keys above.
static func challenge() -> String:
	if not OS.is_debug_build():
		return ""
	var id := parse_challenge(OS.get_cmdline_user_args(), OS.get_environment("CARLITO_CHALLENGE"))
	if id == "" or ChallengeRegistry.def_of(id, true) == null:
		return ""
	return id


## The id asked for, unvalidated. The command line overrides the environment, as `--level=` does.
static func parse_challenge(args: PackedStringArray, env: String) -> String:
	var id := env
	for arg in args:
		if arg.begins_with("--challenge="):
			id = arg.trim_prefix("--challenge=")
	return id


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

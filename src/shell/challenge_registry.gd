class_name ChallengeRegistry
extends Object
## The shell's challenge list, the LevelRegistry sibling: every ChallengeDef in the order the
## CHALLENGES screen lists them, grouped by the family its variant belongs to, families in the
## order their first challenge appears. A new challenge is a .tres plus a line here, and
## `problems()` is what the suite holds every entry to.

const ContractScript := preload("res://src/bridge/contract.gd")

## Ordered ChallengeDef paths, under `src/challenges/defs/`.
const DEFS: PackedStringArray = [
	"res://src/challenges/defs/car_start_up.tres",
	"res://src/challenges/defs/car_easy_turns.tres",
	"res://src/challenges/defs/car_box_stop.tres",
	"res://src/challenges/defs/car_box_blind.tres",
	"res://src/challenges/defs/car_turn_signals.tres",
	"res://src/challenges/defs/car_turn_blink.tres",
	"res://src/challenges/defs/car_speed_trap.tres",
	"res://src/challenges/defs/car_corner_budget.tres",
	"res://src/challenges/defs/car_blind_circle.tres",
	"res://src/challenges/defs/car_blind_slalom.tres",
]

## Dev fixtures: challenges to drive the runner on, reached only through a debug build's
## `--challenge=` (BootParams). Never listed, so neither the CHALLENGES screen nor ChallengeProgress
## sees them; the suite holds them to `problems()` like every listed def.
const DEV_DEFS: PackedStringArray = [
	"res://src/challenges/dev/dev_box_stop.tres",
	"res://src/challenges/dev/dev_box_stop_dark.tres",
	"res://src/challenges/dev/dev_box_stop_fog.tres",
]

## An id is a ConfigFile key in the progress store and will be a link parameter.
const ID_PATTERN := "^[a-z0-9_]+$"


## Every def, loaded on each call. Nothing is cached in a static var: objects held there outlive
## the engine's exit check and are reported as leaks, and the ResourceLoader cache already serves
## a def that anything still holds.
static func all() -> Array[ChallengeDef]:
	return _load_defs(DEFS)


## Every dev fixture, loaded the same way.
static func dev_all() -> Array[ChallengeDef]:
	return _load_defs(DEV_DEFS)


static func _load_defs(paths: PackedStringArray) -> Array[ChallengeDef]:
	var out: Array[ChallengeDef] = []
	for path in paths:
		var d := load(path) as ChallengeDef
		if d == null:
			push_error("ChallengeRegistry: '%s' is not a ChallengeDef" % path)
		else:
			out.append(d)
	return out


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for d in all():
		out.append(d.id)
	return out


## The def with `id`, or null. Dev fixtures only when asked for.
static func def_of(id: String, include_dev := false) -> ChallengeDef:
	for d in all():
		if d.id == id:
			return d
	if include_dev:
		for d in dev_all():
			if d.id == id:
				return d
	return null


## Families with at least one challenge, in first-listed order.
static func families() -> PackedStringArray:
	return PackedStringArray(group_by_family(all()).keys())


static func in_family(family: String) -> Array[ChallengeDef]:
	var out: Array[ChallengeDef] = []
	out.assign(group_by_family(all()).get(family, []))
	return out


## family -> Array of defs, both in the order `defs` lists them.
static func group_by_family(defs: Array[ChallengeDef]) -> Dictionary:
	var out := {}
	for d in defs:
		var family := d.family()
		if not out.has(family):
			out[family] = []
		(out[family] as Array).append(d)
	return out


## Ids appearing more than once in `defs`.
static func duplicate_ids(defs: Array[ChallengeDef]) -> PackedStringArray:
	var seen := {}
	var out := PackedStringArray()
	for d in defs:
		if seen.has(d.id) and not out.has(d.id):
			out.append(d.id)
		seen[d.id] = true
	return out


## The attachment catalog a family's E key walks; empty for a family with none.
static func attachment_catalog(family: String) -> PackedStringArray:
	match family:
		"truck":
			return TrailerCatalog.TRAILERS
		"tractor":
			return ImplementCatalog.IMPLEMENTS
	return PackedStringArray()


## The def's goals and constraints, empty slots skipped.
static func checks_of(d: ChallengeDef) -> Array[ChallengeCheck]:
	var out: Array[ChallengeCheck] = []
	for g in d.goals:
		if g != null:
			out.append(g)
	for c in d.constraints:
		if c != null:
			out.append(c)
	return out


## Everything wrong with `d`; empty means it can ship. The checks, in order:
## - The def's own fields, and its player-facing text.
## - The arena exists and lets the family spawn.
## - The course ships where the arena does, and loads with a spawn for the family and no preview
##   of another arena.
## - Every zone a check names exists and can contain something.
## - Every check's parameters are sane.
## - Every signal is a scalar "out" signal of the family, and every input field exists.
## - The attachment is in the family's catalog.
static func problems(d: ChallengeDef) -> PackedStringArray:
	var out := PackedStringArray()
	if RegEx.create_from_string(ID_PATTERN).search(d.id) == null:
		out.append("id '%s' must be lowercase letters, digits and underscores" % d.id)
	out.append_array(_text_problems(d))
	if d.goals.is_empty():
		out.append("no goals")
	if checks_of(d).size() < d.goals.size() + d.constraints.size():
		out.append("an empty goal or constraint slot")
	if d.par_s < 0.0:
		out.append("negative par time")
	if d.visibility == ChallengeDef.Visibility.FOG and d.fog_density <= 0.0:
		out.append("FOG with no fog density")
	var family := d.family()
	if family == "":
		out.append("unknown variant '%s'" % d.variant)
		return out
	out.append_array(_arena_problems(d))
	out.append_array(_placement_problems(d))
	out.append_array(_attachment_problems(d, family))
	out.append_array(_course_problems(d, family))
	out.append_array(_check_problems(d, family))
	return out


## The arena's LevelInfo read off its PackedScene state, so validation never instances a level. A
## root without one gets `LevelInfo.new()`, the same fallback `Level._ready` uses.
static func arena_info(scene_path: String) -> LevelInfo:
	var packed := load(scene_path) as PackedScene
	if packed != null:
		var state := packed.get_state()
		for i in state.get_node_property_count(0):
			if state.get_node_property_name(0, i) == &"info":
				var info := state.get_node_property_value(0, i) as LevelInfo
				if info != null:
					return info
	return LevelInfo.new()


## Title, briefing and hint are what the player reads: present, and plain ASCII (rule 10 — the
## web font has no emoji glyphs, so anything non-ASCII renders as tofu).
static func _text_problems(d: ChallengeDef) -> PackedStringArray:
	var out := PackedStringArray()
	for field in ["title", "briefing", "hint"]:
		var text := String(d.get(field))
		if text.strip_edges() == "":
			out.append("no %s" % field)
			continue
		for i in text.length():
			if text.unicode_at(i) >= 128:
				out.append("%s has a non-ASCII character" % field)
				break
	return out


static func _arena_problems(d: ChallengeDef) -> PackedStringArray:
	var scene_path := LevelRegistry.scene_of(d.arena)
	if scene_path == "":
		return PackedStringArray(["arena '%s' is not a registered level" % d.arena])
	if not arena_info(scene_path).allows(d.variant):
		return PackedStringArray(["the %s family may not spawn on '%s'" % [d.family(), d.arena]])
	return PackedStringArray()


## A packed level's own folder ships in its pack and no other island's does (LevelPacks), so a
## course on an island lives in that island's folder, and a course on a main-pack level lives
## outside every island.
static func _placement_problems(d: ChallengeDef) -> PackedStringArray:
	var scene_path := LevelRegistry.scene_of(d.arena)
	if scene_path == "":
		return PackedStringArray()
	if LevelPacks.is_packed(scene_path):
		var home := scene_path.get_base_dir() + "/"
		if not d.course.begins_with(home):
			return PackedStringArray(["course must live under %s to ship in '%s''s level pack"
					% [home, d.arena]])
	elif LevelPacks.is_packed(d.course):
		return PackedStringArray(["course sits in a level pack, but '%s' ships in the main pack"
				% d.arena])
	return PackedStringArray()


static func _attachment_problems(d: ChallengeDef, family: String) -> PackedStringArray:
	var out := PackedStringArray()
	var catalog := attachment_catalog(family)
	if catalog.is_empty():
		if d.attachment != AttachmentCatalog.NONE:
			out.append("the %s family has nothing to attach" % family)
		if d.allow_attach_key:
			out.append("allow_attach_key on a family with nothing to attach")
	elif not catalog.has(d.attachment):
		out.append("attachment '%s' is not in the %s catalog" % [d.attachment, family])
	return out


static func _course_problems(d: ChallengeDef, family: String) -> PackedStringArray:
	if d.course == "" or not ResourceLoader.exists(d.course):
		return PackedStringArray(["course '%s' does not exist" % d.course])
	var packed := load(d.course) as PackedScene
	var node: Node = packed.instantiate() if packed != null else null
	if not node is Node3D:
		if node != null:
			node.free()
		return PackedStringArray(["course '%s' is not a scene with a Node3D root" % d.course])
	var course := node as Node3D
	var out := PackedStringArray()
	var spawn_ok := false
	for n in course.find_children("*", "", true, false):
		if n is VehicleSpawn and (n as VehicleSpawn).accepts(family):
			spawn_ok = true
			break
	if not spawn_ok:
		out.append("course has no VehicleSpawn accepting the %s family" % family)
	for n in course.find_children("*", "ArenaPreview", true, false):
		var shown := (n as ArenaPreview).arena
		if shown != "" and shown != d.arena:
			out.append("course previews '%s', but the arena is '%s'" % [shown, d.arena])
	for dup in ChallengeZone.duplicate_names(course):
		out.append("zone name '%s' is used twice" % dup)
	var zones := ChallengeZone.zones_of(course)
	for zone_name in zones:
		var why := zones[zone_name].problem()
		if why != "":
			out.append("zone '%s': %s" % [zone_name, why])
	for check in checks_of(d):
		# Bound on a copy: the def's own resources stay free of state.
		out.append_array((check.duplicate() as ChallengeCheck).bind(zones))
	course.free()
	return out


## The contract is parsed from its file per call, not read off the Contract autoload, so this runs
## the same wherever it is called from.
static func _check_problems(d: ChallengeDef, family: String) -> PackedStringArray:
	var contract := ContractScript.ContractData.parse(
			FileAccess.get_file_as_string(ContractScript.CONTRACT_PATH))
	var outs := {}
	for sig in contract.signals_for_vehicle(family, "out"):
		outs[sig.name] = sig
	var inputs := ChallengeFrame.input_fields()
	var out := PackedStringArray()
	for check in checks_of(d):
		out.append_array(check.problems())
		for s in check.signal_refs():
			if not outs.has(s):
				out.append("'%s' is not an out signal of the %s family" % [s, family])
			elif (outs[s] as ContractScript.SignalDef).is_instanced():
				out.append("'%s' is an array signal, and a check reads one number" % s)
		for f in check.input_refs():
			if not inputs.has(f):
				out.append("'%s' is not a VehicleInput or LampInput field" % f)
	for c in d.constraints:
		if c != null and (c.from_goal < 0 or c.from_goal >= maxi(d.goals.size(), 1)):
			out.append("a constraint's from_goal %d names no goal" % c.from_goal)
	return out

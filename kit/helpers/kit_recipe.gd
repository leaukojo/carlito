class_name KitRecipe
extends RefCounted
## Recipe loading and the pure, unit-tested logic for the kit generators (tools/gen_kit_assets.gd,
## tools/gen_thumbs.gd).
## Families-driven: one ordered `families` list per kit/import/<kit>.json classifies
## every GLB. First matching family wins, so ordering resolves overlaps (put "barrier"
## before "road"). A family: { name, label, match:[regex...],
## pipeline: "palette"|"prefab"|"exclude", collision_mode?, reason?(exclude only),
## assets:{ <name>:{...overrides} } }


## The recipe files in `dir`, sorted, cut to the kits named in `only` (basenames; empty = every
## one). Null (push_error) when `dir` will not open.
static func recipe_paths(dir: String, only: PackedStringArray) -> Variant:
	var d := DirAccess.open(dir)
	if d == null:
		push_error("cannot open " + dir)
		return null
	var out: Array[String] = []
	for f in d.get_files():
		if f.ends_with(".json") and (only.is_empty() or only.has(f.get_basename())):
			out.append(dir.path_join(f))
	out.sort()
	return out


## One recipe parsed, validated (`validate_families`) and run against its source GLBs under the
## coverage gate: {recipe, kit, source, families, classified (`classify`), fam_by_name}, or
## {errors: [...]} (the kit name prefixed) on a bad file, a bad family, an unopenable source or an
## unaccounted GLB.
static func load_recipe(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null or not parsed is Dictionary:
		return {"errors": ["bad recipe json: " + path]}
	var recipe: Dictionary = parsed
	var kit := String(recipe.get("kit", path.get_file().get_basename()))
	var source := String(recipe.get("source", ""))
	var families: Array = recipe.get("families", [])
	var errors: Array[String] = []
	for e in validate_families(families):
		errors.append("%s: %s" % [kit, e])
	if not errors.is_empty():
		return {"errors": errors}
	var dir := DirAccess.open(source)
	if dir == null:
		return {"errors": ["%s: cannot open source '%s'" % [kit, source]]}
	var names: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".glb"):
			names.append(f.get_basename())
	names.sort()
	var c := classify(names, families)
	if not (c.unaccounted as Array).is_empty():
		return {"errors": ["%s: %d unaccounted GLB(s) — add to a family or an explicit exclude: %s" %
				[kit, c.unaccounted.size(), ", ".join(c.unaccounted)]]}
	var fam_by_name := {}
	for fam: Dictionary in families:
		fam_by_name[String(fam.get("name", ""))] = fam
	return {"recipe": recipe, "kit": kit, "source": source, "families": families,
			"classified": c, "fam_by_name": fam_by_name}


## Assign each name to the first family whose any `match` regex matches. Returns
## assignments, unaccounted (gate failure), and counts. Iterate a sorted list for stable counts.
static func classify(names: Array, families: Array) -> Dictionary:
	var compiled := _compile(families)
	var assignments := {}
	var unaccounted: Array[String] = []
	var counts := {}
	for fam: Dictionary in families:
		counts[String(fam.get("name", ""))] = 0
	for raw in names:
		var name := String(raw)
		var hit := ""
		for entry: Dictionary in compiled:
			for re: RegEx in entry.regexes:
				if re.search(name) != null:
					hit = entry.name
					break
			if hit != "":
				break
		if hit == "":
			unaccounted.append(name)
		else:
			assignments[name] = hit
			counts[hit] = int(counts[hit]) + 1
	return {"assignments": assignments, "unaccounted": unaccounted, "counts": counts}


## Recipe-shape validation: every family needs a name and a match pattern; exclude
## families need a non-empty reason; regex patterns must compile.
static func validate_families(families: Array) -> Array:
	var errors: Array[String] = []
	var seen := {}
	for fam: Dictionary in families:
		var name := String(fam.get("name", ""))
		if name.is_empty():
			errors.append("family with no name")
		elif seen.has(name):
			errors.append("duplicate family name '%s'" % name)
		else:
			seen[name] = true
		var matches: Array = fam.get("match", [])
		if matches.is_empty():
			errors.append("family '%s' has no match patterns" % name)
		for p in matches:
			if RegEx.create_from_string(String(p)) == null:
				errors.append("family '%s' has invalid regex '%s'" % [name, str(p)])
		if String(fam.get("pipeline", "")) == "exclude" and String(fam.get("reason", "")).strip_edges().is_empty():
			errors.append("exclude family '%s' needs a non-empty reason" % name)
	return errors


static func is_catch_all(family: Dictionary) -> bool:
	const PROBE := ["x", "road-straight", "tree_default", "zZ9_-Anything"]
	for p in family.get("match", []):
		var re := RegEx.create_from_string(String(p))
		if re == null:
			continue
		var hits_all := true
		for s in PROBE:
			if re.search(String(s)) == null:
				hits_all = false
				break
		if hits_all:
			return true
	return false


## Meshlib item-id assignment that preserves ids painted GridMaps reference.
static func assign_item_ids(existing: Dictionary, ordered: Array) -> Dictionary:
	var result := {}
	var next_id := 0
	for id in existing.values():
		next_id = maxi(next_id, int(id) + 1)
	for raw in ordered:
		var name := String(raw)
		if existing.has(name):
			result[name] = int(existing[name])
		else:
			result[name] = next_id
			next_id += 1
	return result


static func _compile(families: Array) -> Array:
	var out := []
	for fam: Dictionary in families:
		var regexes: Array[RegEx] = []
		for p in fam.get("match", []):
			var re := RegEx.create_from_string(String(p))
			if re != null:
				regexes.append(re)
		out.append({"name": String(fam.get("name", "")), "regexes": regexes})
	return out

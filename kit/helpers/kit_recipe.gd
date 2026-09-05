class_name KitRecipe
extends RefCounted
## Pure, unit-tested logic for the kit asset generator (tools/gen_kit_assets.gd).
## Families-driven: one ordered `families` list per kit/import/<kit>.json classifies
## every GLB. First matching family wins, so ordering resolves overlaps (put "barrier"
## before "road"). A family: { name, label, match:[regex...],
## pipeline: "palette"|"prefab"|"exclude", collision_mode?, reason?(exclude only),
## assets:{ <name>:{...overrides} } }


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

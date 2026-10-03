extends RefCounted
## Churn-free save shared by the vehicle generators (gen_kenney_vehicles.gd,
## gen_boat_variants.gd): a regen that changes nothing leaves the file byte-identical, and the
## UIDs the file already had survive.

static var _unique_id_re := RegEx.create_from_string(" unique_id=\\d+")
## Godot re-rolls the 5-character suffix of every generated sub-resource id on each save
## (`StandardMaterial3D_l7l2h` -> `StandardMaterial3D_lei3o`).
static var _subres_id_re := RegEx.create_from_string("\\b([A-Za-z0-9]+)_([a-z0-9]{5})\\b")
static var _ext_res_re := RegEx.create_from_string("\\[ext_resource [^\\]]*\\]")
static var _uid_attr_re := RegEx.create_from_string(" uid=\"uid://[^\"]*\"")
static var _path_attr_re := RegEx.create_from_string(" path=\"([^\"]*)\"")


## Save a spec or scene, keeping the UIDs the file already had (see `restore_uids`).
static func save(res: Resource, path: String) -> Error:
	var before := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var err := ResourceSaver.save(res, path)
	if err != OK or before.is_empty():
		return err
	var after := restore_uids(before, FileAccess.get_file_as_string(path))
	if churn_key(after) == churn_key(before):
		after = before   # unchanged: keep the on-disk line endings too
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(after)
	return OK


## A scene's content minus the three things a re-save churns for free: per-node `unique_id`,
## sub-resource ID suffixes, and line endings (git checks out CRLF, ResourceSaver writes LF, so
## a raw byte compare calls every file changed). Sub-resource IDs are renumbered by order of
## first appearance rather than blanked, so a genuine edit that repoints a node at a different
## sub-resource of the same type still reads as a change (a real insertion shifts every later
## number — errs toward reporting a difference, the safe direction).
static func churn_key(text: String) -> String:
	var flat := _unique_id_re.sub(text.replace("\r\n", "\n"), "", true)
	var seen := {}
	var out := ""
	var cursor := 0
	for m in _subres_id_re.search_all(flat):
		out += flat.substr(cursor, m.get_start() - cursor)
		cursor = m.get_end()
		var token := m.get_string()
		if not seen.has(token):
			seen[token] = "%s_ID%d" % [m.get_string(1), seen.size()]
		out += String(seen[token])
	return out + flat.substr(cursor)


## Re-inject the UIDs `after` lost relative to `before` (header + every `[ext_resource]`,
## matched by resource path). ResourceSaver only writes a `uid=` it can see, so a plain save
## silently strips one whenever the source resource carries none in memory — a broken reference
## the moment a path moves, and a no-op regen turned into a diff on every scene.
static func restore_uids(before: String, after: String) -> String:
	if before.is_empty():
		return after
	var out := after
	var head_uid := _header_uid(before)
	if not head_uid.is_empty() and _header_uid(out).is_empty():
		var head_end := out.find("]")
		if head_end >= 0:
			out = out.insert(head_end, head_uid)
	var want := _ext_resource_uids(before)
	if want.is_empty():
		return out
	var rebuilt := ""
	var cursor := 0
	for m in _ext_res_re.search_all(out):
		var line := m.get_string()
		rebuilt += out.substr(cursor, m.get_start() - cursor)
		cursor = m.get_end()
		if _uid_attr_re.search(line) == null:
			var pa := _path_attr_re.search(line)
			if pa != null and want.has(pa.get_string(1)):
				line = line.insert(pa.get_start(), String(want[pa.get_string(1)]))
		rebuilt += line
	return rebuilt + out.substr(cursor)


## The ` uid="uid://..."` attribute of a .tres/.tscn header line, "" if it carries none.
static func _header_uid(text: String) -> String:
	var head_end := text.find("]")
	var at := text.find(" uid=\"uid://")
	if head_end < 0 or at < 0 or at > head_end:
		return ""
	var close := text.find("\"", at + 6)
	if close < 0 or close > head_end:
		return ""
	return text.substr(at, close - at + 1)


## `res://…` -> ` uid="uid://…"` for every `[ext_resource]` line in `text` that carries both.
static func _ext_resource_uids(text: String) -> Dictionary:
	var out := {}
	for m in _ext_res_re.search_all(text):
		var line := m.get_string()
		var u := _uid_attr_re.search(line)
		var pa := _path_attr_re.search(line)
		if u != null and pa != null:
			out[pa.get_string(1)] = u.get_string()
	return out

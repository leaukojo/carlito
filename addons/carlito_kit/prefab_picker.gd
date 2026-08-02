@tool
extends EditorProperty
## Kit-prefab picker for ScatterItem.prefab: a kit dropdown plus a prefab dropdown built by
## scanning kit/prefabs/<kit>/*.tscn. Assigns `load(path)` — a plain PackedScene reference,
## exactly what the generic resource slot produced — so the level's stale-bake input hash
## still tracks the choice through ordinary scene dependencies.
##
## Why this exists: the generated kit prefabs carry no `uid://` (gen_kit_assets writes them
## headless, and ResourceSaver mints no id for a file that has none), and Godot's resource
## picker lists only uid-indexed resources. So the only pickable "tree-large" was the raw
## kit/raw/suburban/tree-large.glb — un-scaled, no KitPiece, no dev collision, and it bakes
## to nothing. Listing prefabs only makes that mistake unreachable.

const PREFAB_DIR := "res://kit/prefabs"
const THUMB_DIR := "res://kit/thumbs"
const THUMB_PX := 28

## Prefab-dropdown index -> res:// path. "" is the <none> row.
var _paths: Array[String] = []
var _kits: Array[String] = []
var _kit_pick: OptionButton
var _prefab_pick: OptionButton
var _thumb: TextureRect
## Set while the UI is being written from the edited value, so the resulting item_selected
## signals don't echo back as property writes.
var _syncing := false


func _init() -> void:
	_kit_pick = OptionButton.new()
	_kit_pick.size_flags_horizontal = SIZE_EXPAND_FILL
	_kit_pick.tooltip_text = "Kit folder under kit/prefabs/"
	_prefab_pick = OptionButton.new()
	_prefab_pick.size_flags_horizontal = SIZE_EXPAND_FILL
	_prefab_pick.size_flags_stretch_ratio = 2.0
	_prefab_pick.tooltip_text = "Prefab scene to scatter"

	# The kit thumbs (rendered windowed by tools/gen_thumbs.tscn, same PNGs the palette dock
	# shows) double as the picked prefab's preview — kept small so the item table stays a
	# table, and left blank rather than padded when a prefab has no thumb yet.
	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = Vector2(THUMB_PX, THUMB_PX)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var row := HBoxContainer.new()
	row.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_kit_pick)
	row.add_child(_prefab_pick)
	row.add_child(_thumb)
	add_child(row)
	add_focusable(_kit_pick)
	add_focusable(_prefab_pick)

	_kits = _scan_kits()
	for kit in _kits:
		_kit_pick.add_item(kit)
	_kit_pick.item_selected.connect(_on_kit_selected)
	_prefab_pick.item_selected.connect(_on_prefab_selected)


## Inspector -> UI. Follows the edited value's own kit so selecting a region's items walks
## the dropdowns to whatever each one already holds.
func _update_property() -> void:
	var path := _edited_path()
	_syncing = true
	var kit := _kit_of(path)
	if kit != "":
		_kit_pick.select(_kits.find(kit))
	elif _kit_pick.selected < 0 and not _kits.is_empty():
		_kit_pick.select(0)
	_fill_prefabs(_current_kit(), path)
	_syncing = false


## Browsing kits never touches the value — the prefab dropdown just shows <none> until a
## prefab in that kit is picked.
func _on_kit_selected(_index: int) -> void:
	if _syncing:
		return
	_syncing = true
	_fill_prefabs(_current_kit(), _edited_path())
	_syncing = false


func _on_prefab_selected(index: int) -> void:
	if _syncing or index < 0 or index >= _paths.size():
		return
	var path := _paths[index]
	_show_thumb(path)
	emit_changed(get_edited_property(), load(path) as PackedScene if path != "" else null)


func _fill_prefabs(kit: String, selected: String) -> void:
	_prefab_pick.clear()
	_paths.clear()
	_prefab_pick.add_item("<none>")
	_paths.append("")
	var chosen := 0
	if kit != "":
		var dir := DirAccess.open(PREFAB_DIR.path_join(kit))
		if dir != null:
			var files := []
			for f in dir.get_files():
				if f.ends_with(".tscn"):
					files.append(f)
			files.sort()
			for f: String in files:
				var path := PREFAB_DIR.path_join(kit).path_join(f)
				_prefab_pick.add_item(f.get_basename())
				_paths.append(path)
				if path == selected:
					chosen = _paths.size() - 1
	# A value assigned outside kit/prefabs (a raw .glb picked before this editor existed)
	# stays visible and selected rather than reading as empty — clearing it is the author's
	# call, not a side effect of opening the inspector.
	if chosen == 0 and selected != "" and not selected.begins_with(PREFAB_DIR + "/"):
		_prefab_pick.add_item("%s (outside kit/prefabs)" % selected.get_file())
		_paths.append(selected)
		chosen = _paths.size() - 1
	_prefab_pick.select(chosen)
	_show_thumb(_paths[chosen])


## Preview for a picked prefab, from kit/thumbs/<kit>/<name>.png (blank when absent, and for
## anything outside kit/prefabs — a raw .glb has no thumb of its own).
func _show_thumb(path: String) -> void:
	var kit := _kit_of(path)
	if kit == "":
		_thumb.texture = null
		return
	var thumb := "%s/%s/%s.png" % [THUMB_DIR, kit, path.get_file().get_basename()]
	_thumb.texture = load(thumb) as Texture2D if ResourceLoader.exists(thumb) else null


func _current_kit() -> String:
	var index := _kit_pick.selected
	return _kits[index] if index >= 0 and index < _kits.size() else ""


func _edited_path() -> String:
	var current := get_edited_object().get(get_edited_property()) as PackedScene
	return current.resource_path if current != null else ""


## "res://kit/prefabs/suburban/tree-large.tscn" -> "suburban" (empty for anything else).
func _kit_of(path: String) -> String:
	if not path.begins_with(PREFAB_DIR + "/"):
		return ""
	var kit := path.get_base_dir().get_file()
	return kit if _kits.has(kit) else ""


func _scan_kits() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(PREFAB_DIR)
	if dir == null:
		return out
	for d in dir.get_directories():
		out.append(d)
	out.sort()
	return out

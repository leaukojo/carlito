@tool
extends VBoxContainer
## Bottom-panel browser over the kit assets: kit tabs -> family sections -> thumbnail grid,
## plus a text search across every kit. Clicking a prefab arms the placement tool; clicking
## a palette tile routes to the GridMap workflow. UI only; viewport logic lives in
## placement_tool.gd.

const Recipe := preload("res://kit/helpers/kit_recipe.gd")
const RECIPE_DIR := "res://kit/import"
const PREFAB_DIR := "res://kit/prefabs"
const PALETTE_DIR := "res://kit/palettes"
const THUMB_DIR := "res://kit/thumbs"
const THUMB_PX := 96

signal prefab_armed(kit: String, name: String)
signal tile_selected(kit: String, name: String, meshlib: String)
signal settings_changed(random_yaw: bool, snap_enabled: bool, snap_step: float, yaw_deg: float)
signal autofloor_changed(on: bool)

# Per kit, ordered families: { kit -> [ { label, items:[ {kit,name,kind,thumb} ] } ] ].
var _catalog: Dictionary = {}
var _kits: Array[String] = []
var _kit_cells: Dictionary = {}  # kit -> palette cell size (world units); default 1.0

var _tabs: TabBar
var _search: LineEdit
var _random_yaw: CheckButton
var _yaw_field: SpinBox
var _snap: CheckButton
var _snap_step: SpinBox
var _autofloor_btn: CheckButton
var _content: VBoxContainer
var _button_group := ButtonGroup.new()


func _init() -> void:
	name = "Palette"
	custom_minimum_size = Vector2(0, 240)
	_build_catalog()
	_build_ui()
	_rebuild_content()


# ------------------------------------------------------------------ catalog

func _build_catalog() -> void:
	var dir := DirAccess.open(RECIPE_DIR)
	if dir == null:
		return
	var recipe_files := []
	for f in dir.get_files():
		if f.ends_with(".json"):
			recipe_files.append(f)
	recipe_files.sort()
	for f in recipe_files:
		_ingest_recipe(RECIPE_DIR.path_join(f))


func _ingest_recipe(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	var recipe: Dictionary = parsed
	var kit := String(recipe.get("kit", path.get_file().get_basename()))
	var families: Array = recipe.get("families", [])
	if families.is_empty():
		return

	var pal: Dictionary = recipe.get("palette", {})
	var cell: Array = pal.get("cell_size", [])
	if cell.size() >= 1:
		_kit_cells[kit] = float(cell[0])

	# A family may route to its own overlay meshlib; default is the kit meshlib.
	var default_meshlib := "%s/%s.meshlib" % [PALETTE_DIR, kit]
	var fam_meshlib := {}  # family name -> meshlib path
	var meshlibs := {}     # meshlib path -> true (distinct outputs to scan for tile names)
	for fam: Dictionary in families:
		if String(fam.get("pipeline", "")) == "palette":
			var out := String(fam.get("palette_output", default_meshlib))
			fam_meshlib[String(fam.get("name", ""))] = out
			meshlibs[out] = true

	var names: Array[String] = []
	var kinds := {}  # name -> "prefab" | "tile"
	for n in _prefab_names(kit):
		names.append(n)
		kinds[n] = "prefab"
	for meshlib_path in meshlibs:
		for n in _tile_names(meshlib_path):
			if not kinds.has(n):
				names.append(n)
				kinds[n] = "tile"
	if names.is_empty():
		return

	var assigned: Dictionary = Recipe.classify(names, families).assignments
	var by_family := {}
	for fam: Dictionary in families:
		if String(fam.get("pipeline", "")) == "exclude":
			continue
		by_family[String(fam.get("name", ""))] = []
	var sorted_names := names.duplicate()
	sorted_names.sort()
	for n in sorted_names:
		var fam_name := String(assigned.get(n, ""))
		if by_family.has(fam_name):
			by_family[fam_name].append({
				"kit": kit, "name": n, "kind": kinds[n], "thumb": _thumb_path(kit, n),
				"meshlib": String(fam_meshlib.get(fam_name, default_meshlib)),
			})

	var sections := []
	for fam: Dictionary in families:
		var fam_name := String(fam.get("name", ""))
		if not by_family.has(fam_name) or (by_family[fam_name] as Array).is_empty():
			continue
		sections.append({"label": String(fam.get("label", fam_name)), "items": by_family[fam_name]})
	if not sections.is_empty():
		_catalog[kit] = sections
		_kits.append(kit)


func _prefab_names(kit: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(PREFAB_DIR.path_join(kit))
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".tscn"):
			out.append(f.get_basename())
	return out


func _tile_names(path: String) -> Array[String]:
	var out: Array[String] = []
	if not ResourceLoader.exists(path):
		return out
	var ml := load(path) as MeshLibrary
	if ml == null:
		return out
	for id in ml.get_item_list():
		out.append(ml.get_item_name(id))
	return out


func _thumb_path(kit: String, name: String) -> String:
	var p := "%s/%s/%s.png" % [THUMB_DIR, kit, name]
	return p if ResourceLoader.exists(p) else ""


# ------------------------------------------------------------------ ui

func _build_ui() -> void:
	# Kit tabs + search on one row, placement options on the next; too many kits for one row.
	var tabs_row := HBoxContainer.new()
	add_child(tabs_row)

	_tabs = TabBar.new()
	_tabs.clip_tabs = true   # overflow scrolls with arrows instead of blocking the row
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for kit in _kits:
		_tabs.add_tab(kit.capitalize())
	_tabs.tab_changed.connect(func(_i):
		_apply_kit_snap()
		_rebuild_content())
	tabs_row.add_child(_tabs)

	tabs_row.add_child(VSeparator.new())

	_search = LineEdit.new()
	_search.placeholder_text = "Search all kits"
	_search.custom_minimum_size = Vector2(160, 0)
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _rebuild_content())
	tabs_row.add_child(_search)

	var toolbar := HBoxContainer.new()
	add_child(toolbar)

	_random_yaw = CheckButton.new()
	_random_yaw.text = "Random yaw"
	_random_yaw.button_pressed = true
	_random_yaw.toggled.connect(_on_random_toggled)
	toolbar.add_child(_random_yaw)

	var yaw_label := Label.new()
	yaw_label.text = "Yaw"
	toolbar.add_child(yaw_label)

	_yaw_field = SpinBox.new()
	_yaw_field.min_value = 0
	_yaw_field.max_value = 359
	_yaw_field.step = 15
	_yaw_field.suffix = "deg"
	_yaw_field.editable = false  # Random yaw is on by default -> field is not in control
	_yaw_field.tooltip_text = "Placement yaw. Active when Random yaw is off. In the viewport: " \
			+ "[ / ] or Shift+mouse-wheel rotate the ghost."
	_yaw_field.value_changed.connect(func(_v): _emit_settings())
	toolbar.add_child(_yaw_field)

	_snap = CheckButton.new()
	_snap.text = "Snap"
	_snap.toggled.connect(func(_v): _emit_settings())
	toolbar.add_child(_snap)

	_snap_step = SpinBox.new()
	_snap_step.min_value = 0.25
	_snap_step.max_value = 50.0
	_snap_step.step = 0.25
	_snap_step.value = 1.0
	_snap_step.tooltip_text = "Grid snap step (world units) — defaults to the kit's tile grid"
	_snap_step.value_changed.connect(func(_v): _emit_settings())
	toolbar.add_child(_snap_step)

	toolbar.add_child(VSeparator.new())

	_autofloor_btn = CheckButton.new()
	_autofloor_btn.text = "Auto-floor"
	_autofloor_btn.tooltip_text = "Paint the selected tile straight onto the terrain: each " \
			+ "click raycasts the ground and the cell floor follows the hit height, so " \
			+ "you don't set the GridMap floor by hand. [ / ] rotate; Ctrl-click erases."
	_autofloor_btn.toggled.connect(func(on: bool): autofloor_changed.emit(on))
	toolbar.add_child(_autofloor_btn)

	_apply_kit_snap()  # seed the step from the initial tab's grid

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)


func _emit_settings() -> void:
	settings_changed.emit(_random_yaw.button_pressed, _snap.button_pressed,
			_snap_step.value, _yaw_field.value)


func _on_random_toggled(on: bool) -> void:
	_yaw_field.editable = not on  # manual yaw only makes sense when random isn't reseeding it
	_emit_settings()


func set_yaw_display(degrees: float) -> void:
	_yaw_field.set_block_signals(true)
	_yaw_field.value = fposmod(roundf(degrees), 360.0)  # 360 -> 0, stays within max_value
	_yaw_field.set_block_signals(false)


## Reflects a tool-driven auto-floor exit (RMB/Escape) without re-emitting autofloor_changed.
func set_autofloor(on: bool) -> void:
	if _autofloor_btn.button_pressed != on:
		_autofloor_btn.set_pressed_no_signal(on)


## Snap step follows the active kit's tile grid (palette cell_size), or 1 m for prop-only kits.
func _apply_kit_snap() -> void:
	if _kits.is_empty():
		return
	var kit := _kits[_tabs.current_tab]
	_snap_step.value = float(_kit_cells.get(kit, 1.0))


# ------------------------------------------------------------------ content

func _rebuild_content() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()

	var query := _search.text.strip_edges().to_lower()
	if not query.is_empty():
		_build_search(query)
	elif not _kits.is_empty():
		_build_browse(_kits[_tabs.current_tab])


func _build_browse(kit: String) -> void:
	for section: Dictionary in _catalog.get(kit, []):
		_add_section(String(section.label), section.items)


func _build_search(query: String) -> void:
	var matches := []
	for kit in _kits:
		for section: Dictionary in _catalog[kit]:
			for item: Dictionary in section.items:
				if query in String(item.name).to_lower():
					matches.append(item)
	if matches.is_empty():
		var empty := Label.new()
		empty.text = "No matches for \"%s\"" % query
		_content.add_child(empty)
		return
	_add_section("Results (%d)" % matches.size(), matches, true)


func _add_section(title: String, items: Array, show_kit := false) -> void:
	var header := Label.new()
	header.text = "%s  (%d)" % [title, items.size()]
	header.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	_content.add_child(header)

	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(grid)
	for item: Dictionary in items:
		grid.add_child(_make_tile(item, show_kit))


func _make_tile(item: Dictionary, show_kit: bool) -> Button:
	var kit := String(item.kit)
	var name := String(item.name)
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = _button_group
	b.custom_minimum_size = Vector2(THUMB_PX + 10, THUMB_PX + 26)
	b.tooltip_text = "%s/%s  (%s)" % [kit, name, item.kind]
	b.pressed.connect(func():
		if item.kind == "prefab":
			prefab_armed.emit(kit, name)
		else:
			tile_selected.emit(kit, name, String(item.get("meshlib", "")))
	)

	# Children ignore the mouse so the button still receives the click.
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 4
	box.offset_top = 4
	box.offset_right = -4
	box.offset_bottom = -4
	box.add_theme_constant_override("separation", 2)
	b.add_child(box)

	var pic := TextureRect.new()
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if item.thumb != "":
		var tex := load(item.thumb) as Texture2D
		if tex != null:
			pic.texture = tex
	box.add_child(pic)

	var caption := Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.text = ("%s/%s" % [kit, name]) if show_kit else name
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.clip_text = true
	caption.add_theme_font_size_override("font_size", 11)
	if item.kind == "tile":
		caption.add_theme_color_override("font_color", Color(0.8, 0.9, 0.7))
	box.add_child(caption)

	return b

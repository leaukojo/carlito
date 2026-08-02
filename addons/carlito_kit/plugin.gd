@tool
extends EditorPlugin
## Kit editor surface: the export-time authoring stripper (always), the palette dock +
## click-to-place tool, and the terrain sculpt/paint brush. The dock browses the kit
## assets; viewport clicks are forwarded here to whichever tool is active — the brush when a
## HeightmapTerrain is selected with a mode picked, else the placement tool. All editor API
## stays in this addon (the editor/runtime split). One inspector override rides along:
## ScatterItem.prefab gets kit-prefab dropdowns (see prefab_picker.gd).

const StripExport := preload("res://addons/carlito_kit/strip_export.gd")
const PaletteDock := preload("res://addons/carlito_kit/palette_dock.gd")
const PlacementTool := preload("res://addons/carlito_kit/placement_tool.gd")
const TerrainBrush := preload("res://addons/carlito_kit/terrain_brush.gd")
const BrushPanel := preload("res://addons/carlito_kit/brush_panel.gd")
const ScatterGizmo := preload("res://addons/carlito_kit/scatter_gizmo.gd")
const ScatterBrush := preload("res://addons/carlito_kit/scatter_brush.gd")
const ScatterPanel := preload("res://addons/carlito_kit/scatter_panel.gd")
const RoadDrawTool := preload("res://addons/carlito_kit/road_draw_tool.gd")
const RoadPanel := preload("res://addons/carlito_kit/road_panel.gd")
const GridMapPaintTool := preload("res://addons/carlito_kit/gridmap_paint_tool.gd")
const TileConform := preload("res://addons/carlito_kit/tile_conform.gd")
const FlyingCheck := preload("res://addons/carlito_kit/flying_check.gd")
const PolishPanel := preload("res://addons/carlito_kit/polish_panel.gd")
const LevelShotTool := preload("res://addons/carlito_kit/level_shot_tool.gd")
const PrefabInspector := preload("res://addons/carlito_kit/prefab_inspector.gd")

## The Rail checkbox's "on" profile (its "off" is RoadPath.DEFAULT_PROFILE_PATH).
const RAIL_PROFILE_PATH := "res://kit/roads/rail_profile.tres"

var _strip: EditorExportPlugin
var _dock: Control
var _tool  # PlacementTool (RefCounted)
var _brush  # TerrainBrush (RefCounted)
var _panel: Control
var _scatter_gizmo: EditorNode3DGizmoPlugin
var _scatter_brush  # ScatterBrush (RefCounted)
var _scatter_panel: Control
var _road_tool  # RoadDrawTool (RefCounted)
var _road_panel: Control
var _polish_panel: Control
var _selected_road: RoadPath  # the Rail checkbox's target (draw tool keeps its own copy)
var _prev_profiles := {}  # road instance id -> the profile Rail-on replaced (session only)
var _gridmap_tool  # GridMapPaintTool (RefCounted)
var _prefab_inspector: EditorInspectorPlugin
var _autofloor := false
var _root: TabContainer  # one bottom panel: Palette / Terrain / Scatter / Roads / Polish


func _enter_tree() -> void:
	_strip = StripExport.new()
	add_export_plugin(_strip)

	_scatter_gizmo = ScatterGizmo.new()
	add_node_3d_gizmo_plugin(_scatter_gizmo)

	_prefab_inspector = PrefabInspector.new()
	add_inspector_plugin(_prefab_inspector)

	_tool = PlacementTool.new(get_undo_redo())
	_gridmap_tool = GridMapPaintTool.new(get_undo_redo())
	_gridmap_tool.deactivated.connect(func():
		_autofloor = false
		_dock.set_autofloor(false))
	_dock = PaletteDock.new()
	_dock.prefab_armed.connect(func(kit, name):
		_drop_road_draw()  # the placement ghost owns the viewport now
		_gridmap_tool.set_active(false)
		_tool.arm(kit, name))
	_dock.tile_selected.connect(_on_tile_selected)
	_dock.settings_changed.connect(_on_settings_changed)
	_dock.autofloor_changed.connect(_on_autofloor_changed)
	_polish_panel = PolishPanel.new()
	_polish_panel.conform_tiles_requested.connect(func(tile_lift: float, prefab_apron: float):
		TileConform.conform_all(EditorInterface.get_edited_scene_root(),
				tile_lift, prefab_apron))
	_polish_panel.paint_tiles_requested.connect(func():
		TileConform.paint_all(EditorInterface.get_edited_scene_root()))
	_polish_panel.tidy_authoring_requested.connect(func(): _tool.tidy_authoring())
	_polish_panel.flag_flying_requested.connect(func(tolerance: float):
		FlyingCheck.flag(EditorInterface.get_edited_scene_root(), tolerance))
	_polish_panel.clear_flying_requested.connect(func():
		FlyingCheck.clear(EditorInterface.get_edited_scene_root()))
	_polish_panel.drop_flying_requested.connect(func(tolerance: float):
		FlyingCheck.drop(EditorInterface.get_edited_scene_root(), get_undo_redo(),
				tolerance))
	_polish_panel.set_shot_view_requested.connect(func():
		LevelShotTool.save_view(EditorInterface.get_edited_scene_root()))
	_polish_panel.shoot_thumb_requested.connect(func():
		LevelShotTool.shoot(EditorInterface.get_edited_scene_root()))
	_tool.yaw_changed.connect(func(deg): _dock.set_yaw_display(deg))

	_brush = TerrainBrush.new(get_undo_redo())
	_panel = BrushPanel.new()
	_panel.mode_changed.connect(_on_brush_mode)
	_panel.channel_changed.connect(func(ch): _brush.channel = ch)
	_panel.params_changed.connect(func(r, s, f):
		_brush.radius = r
		_brush.strength = s
		_brush.falloff = f)
	_panel.flatten_changed.connect(func(fixed, height, step):
		_brush.flatten_fixed = fixed
		_brush.flatten_height = height
		_brush.snap_step = step)
	_panel.shape_changed.connect(func(square): _brush.square = square)
	_panel.grid_snap_changed.connect(func(on):
		_brush.grid_snap = on
		if on:
			_panel.set_snap_step(_brush.grid_cell_y()))
	_panel.pick_requested.connect(func(): _brush.arm_pick())
	_panel.fill_requested.connect(func(): _brush.fill_terrain())
	_brush.radius_display.connect(func(r): _panel.set_radius_display(r))
	_brush.height_picked.connect(func(y): _panel.set_picked_height(y))

	_scatter_brush = ScatterBrush.new(get_undo_redo())
	_scatter_panel = ScatterPanel.new()
	_scatter_panel.mode_changed.connect(_on_scatter_mode)
	_scatter_panel.radius_changed.connect(func(r): _scatter_brush.radius = r)
	_scatter_brush.radius_display.connect(func(r): _scatter_panel.set_radius_display(r))

	_road_tool = RoadDrawTool.new(get_undo_redo())
	_road_panel = RoadPanel.new()
	_road_panel.mode_changed.connect(_on_road_mode)
	_road_panel.close_requested.connect(func(): _road_tool.close_loop())
	_road_panel.smooth_corners_changed.connect(func(on): _road_tool.smooth_corners = on)
	_road_panel.snap_ports_changed.connect(func(on): _road_tool.snap_ports = on)
	_road_panel.snap_ends_requested.connect(func(): _road_tool.snap_ends())
	_road_panel.reverse_requested.connect(func(): _road_tool.reverse_road())
	_road_panel.draw_submode_changed.connect(func(m): _road_tool.set_submode(m))
	_road_panel.angle_snap_changed.connect(func(deg): _road_tool.angle_snap_deg = deg)
	_road_panel.rail_toggled.connect(_on_rail_toggled)
	_road_tool.draw_status.connect(func(msg): _road_panel.show_warning(msg))
	_road_tool.radius_display.connect(
			func(txt, warn): _road_panel.set_radius_display(txt, warn))
	_road_tool.deactivated.connect(func(): _road_panel.show_off())

	# One "Kit" bottom panel hosts the palette browser and the four tool panels as tabs,
	# so tile-city work (Palette tab -> roads kit) and spline work (Roads tab) are one
	# click apart instead of a switch-panel-and-reselect dance. add_control_to_dock is a
	# deprecated compatibility path in 4.6 whose EditorDock wrapper breaks 3D viewport
	# navigation (WASD freelook, F focus, wheel speed), so this rides the bottom panel.
	_root = TabContainer.new()
	_root.name = "Kit"
	_root.custom_minimum_size = Vector2(0, 260)
	_root.add_child(_dock)  # tab title = child node name: Palette / Terrain / Scatter / Roads / Polish
	for panel in [_panel, _scatter_panel, _road_panel, _polish_panel]:
		var scroll := ScrollContainer.new()
		scroll.name = panel.name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(panel)
		_root.add_child(scroll)
	add_control_to_bottom_panel(_root, "Kit")

	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	# Placement works regardless of selection, so we need every viewport event (docs:
	# "especially usable if your plugin will want to use raycast in the scene").
	set_input_event_forwarding_always_enabled()


func _exit_tree() -> void:
	remove_export_plugin(_strip)
	_strip = null

	remove_node_3d_gizmo_plugin(_scatter_gizmo)
	_scatter_gizmo = null

	remove_inspector_plugin(_prefab_inspector)
	_prefab_inspector = null

	EditorInterface.get_selection().selection_changed.disconnect(_on_selection_changed)

	if _tool != null:
		_tool.disarm()
	_tool = null
	_dock = null  # owned by _root, freed with it below

	if _brush != null:
		_brush.teardown()
	_brush = null
	_panel = null

	if _scatter_brush != null:
		_scatter_brush.teardown()
	_scatter_brush = null
	_scatter_panel = null

	if _road_tool != null:
		_road_tool.teardown()
	_road_tool = null
	_road_panel = null
	_polish_panel = null
	_selected_road = null
	_prev_profiles.clear()

	if _gridmap_tool != null:
		_gridmap_tool.teardown()
	_gridmap_tool = null

	if _root != null:
		remove_control_from_bottom_panel(_root)
		_root.free()  # frees the palette dock + the four tool panels with it
	_root = null


## Save hook: brush edits accumulate in memory and are written to the heightmap /
## splat PNGs only when the scene is saved — never reimported per stroke.
func _save_external_data() -> void:
	if _brush != null:
		_brush.flush_all()


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _brush != null and _brush.handle_input(camera, event):
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _scatter_brush != null and _scatter_brush.handle_input(camera, event):
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _road_tool != null and _road_tool.handle_input(camera, event):
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _gridmap_tool != null and _gridmap_tool.handle_input(camera, event):
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _tool != null and _tool.handle_input(camera, event):
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _on_brush_mode(mode: int) -> void:
	_brush.set_mode(mode)
	_panel.on_mode(mode)
	if mode != 0:  # a brush mode owns the viewport — drop any armed placement ghost
		_tool.disarm()
		_drop_road_draw()
		_drop_autofloor()


## Scatter brush mode picked: a non-Off mode owns the viewport, so drop the placement ghost
## (same rule as the terrain brush).
func _on_scatter_mode(mode: int) -> void:
	_scatter_brush.set_mode(mode)
	if mode != 0:
		_tool.disarm()
		_drop_road_draw()
		_drop_autofloor()


## Road Draw mode picked: same viewport-ownership rule as the brushes.
func _on_road_mode(mode: int) -> void:
	_road_tool.set_active(mode == 1)
	if mode != 0:
		_tool.disarm()
		_drop_autofloor()


## Palette tile picked: open the built-in GridMap workflow, and — when Auto-floor is on —
## also arm the terrain-aware paint tool on that GridMap (mode-exclusive: it owns the
## viewport, so drop the road draw). select_tile selects/creates the GridMap, so it is the
## tool's target.
func _on_tile_selected(kit: String, tile_name: String, meshlib: String) -> void:
	_tool.select_tile(kit, tile_name, meshlib)
	if not _autofloor:
		_gridmap_tool.set_active(false)
		return
	var grid: GridMap = null
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is GridMap:
			grid = node
			break
	if grid == null:
		return
	_drop_road_draw()
	_gridmap_tool.arm(grid, tile_name)
	_gridmap_tool.set_active(true)


func _on_autofloor_changed(on: bool) -> void:
	_autofloor = on
	if not on:
		_gridmap_tool.set_active(false)


func _drop_autofloor() -> void:
	_autofloor = false
	_gridmap_tool.set_active(false)
	_dock.set_autofloor(false)


func _drop_road_draw() -> void:
	_road_tool.set_active(false)
	_road_panel.show_off()


## Rail checkbox: swap the selected road's profile in ONE undoable action. Nothing else
## changes — a rail is a RoadPath with a different cross-section, so Draw/Drape/Smooth/
## Conform and the bake carry over.
##
## Ticking ON remembers the profile it replaced, so unticking puts a gravel or bridge road
## back rather than silently converting it to the city default — previewing a road as rail
## used to be a one-way trip for anything that wasn't already a city road. The memory is
## per editor session and per node (a road selected fresh after a reload falls back to the
## city default, i.e. the old behaviour); it deliberately does NOT live on the node, where
## it would serialize into the .tscn and land in the bake input hash.
func _on_rail_toggled(on: bool) -> void:
	if _selected_road == null:
		return
	var id := _selected_road.get_instance_id()
	var previous: RoadProfile = _prev_profiles.get(id)
	var next := load(RAIL_PROFILE_PATH) as RoadProfile if on else previous
	if next == null:
		next = load(RoadPath.DEFAULT_PROFILE_PATH) as RoadProfile
	if next == null:
		push_warning("Kit: cannot load the road profile presets from kit/roads/.")
		return
	if on:
		_prev_profiles[id] = _selected_road.profile
	else:
		_prev_profiles.erase(id)
	var undo := get_undo_redo()
	undo.create_action("%s road profile" % ("Rail" if on else "Road"),
			UndoRedo.MERGE_DISABLE, _selected_road)
	undo.add_do_property(_selected_road, "profile", next)
	undo.add_undo_property(_selected_road, "profile", _selected_road.profile)
	undo.commit_action()


func _on_selection_changed() -> void:
	var terrain: HeightmapTerrain = null
	var canvas: ScatterCanvas = null
	var road: RoadPath = null
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is HeightmapTerrain:
			terrain = node
		elif node is ScatterCanvas:
			canvas = node
		elif node is RoadPath:
			road = node
	_brush.set_target(terrain)
	var road_grid := _find_road_gridmap()
	_brush.set_grid(road_grid)
	_panel.set_has_terrain(terrain != null)
	if terrain != null:
		# Channel names and colors are the terrain's own data, so the picker is rebuilt per
		# selection rather than hard-coded in the panel.
		var colors := PackedColorArray()
		for i in 8:
			colors.append(terrain.channel_color(i))
		_panel.set_channels(terrain.channel_names, colors)
	_scatter_brush.set_target(canvas)
	_scatter_panel.set_has_canvas(canvas != null)
	_road_tool.set_target(road)
	_road_tool.set_grid(road_grid)
	_selected_road = road
	_road_panel.set_has_road(road != null)
	_road_panel.set_rail(road != null and road.profile != null
			and road.profile.has_method("is_carlito_rail_profile"))
	# Auto-floor paint follows its GridMap: selecting away from it drops the tool (mode
	# exclusivity — the same way the brushes release on deselect).
	if _gridmap_tool.is_active():
		var keeps := false
		for node in EditorInterface.get_selection().get_selected_nodes():
			if node is GridMap and _gridmap_tool.targets(node):
				keeps = true
				break
		if not keeps:
			_drop_autofloor()
	# Pop the dock and jump to the matching tool tab when exactly one tool node is picked.
	var tab := -1
	if terrain != null:
		tab = 1
	elif canvas != null:
		tab = 2
	elif road != null:
		tab = 3
	if tab != -1:
		_root.current_tab = tab
		make_bottom_panel_item_visible(_root)


## The road GridMap the brush snaps to (null if the level has none yet — the brush then falls
## back to a 12 m lattice at origin). Prefers the conventional "RoadsTiles" node; else the
## first GridMap found in the edited scene.
func _find_road_gridmap() -> GridMap:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	var found: GridMap = null
	for node in root.find_children("*", "GridMap", true, false):
		var gm := node as GridMap
		if gm.name == "RoadsTiles":
			return gm
		if found == null:
			found = gm
	return found


func _on_settings_changed(random_yaw: bool, snap_enabled: bool, snap_step: float,
		yaw_deg: float) -> void:
	if _tool == null:
		return
	_tool.random_yaw = random_yaw
	_tool.snap_enabled = snap_enabled
	_tool.snap_step = snap_step
	_tool.set_base_yaw(yaw_deg)

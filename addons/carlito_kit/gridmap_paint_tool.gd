@tool
extends RefCounted
## Terrain-aware GridMap painting ("auto-floor"). The built-in GridMap editor paints on a
## MANUAL floor plane and exposes no script hook to drive that floor, so this is a
## replacement paint tool: each viewport click raycasts the ground via the shared
## ground-snap chain (ground_snap.gd), lets the GridMap derive the cell Y from the hit
## height (local_to_map floors per axis), and commits ONE undoable set_cell_item with the
## palette's selected item + a Y-rotation from the [ / ] hotkeys.
##
## Inert (handle_input returns false) unless a GridMap is armed AND the panel toggle is on,
## so editor navigation/selection is untouched otherwise. Left-click paints (drag paints a
## streak, one cell per undo step); Ctrl+left-click erases; right-click / Escape exits.
## The ghost is an unowned wire box at the hovered cell (brush-cursor discipline: unshaded,
## no-depth-test, never serialized).

const GroundSnap := preload("res://addons/carlito_kit/ground_snap.gd")

const GHOST_COLOR := Color(0.4, 1.0, 0.5)

signal deactivated  # RMB/Escape exit -> the palette flips its toggle back off

var _undo: EditorUndoRedoManager
var _grid: GridMap = null
var _item := GridMap.INVALID_CELL_ITEM
var _yaw_step := 0  # 0..3 -> 0/90/180/270 deg about Y
var _active := false
var _no_excludes: Array[RID] = []
var _last_cell := Vector3i(2147483647, 0, 0)  # sentinel: nothing painted yet this drag
var _ghost: MeshInstance3D = null


func _init(undo: EditorUndoRedoManager) -> void:
	_undo = undo


## Arm from a palette pick: the target GridMap plus the item id resolved from its meshlib
## by name. A missing item leaves the tool inert.
func arm(grid: GridMap, tile_name: String) -> void:
	_grid = grid
	_item = _resolve_item(grid, tile_name)


func set_active(active: bool) -> void:
	_active = active
	if not active:
		_free_ghost()


func is_active() -> bool:
	return _active


func targets(grid: GridMap) -> bool:
	return _grid == grid


func teardown() -> void:
	_free_ghost()
	_grid = null


# ------------------------------------------------------------------ input

func handle_input(camera: Camera3D, event: InputEvent) -> bool:
	if not _active or not _valid():
		_hide_ghost()
		return false

	if event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				_exit()
				return true
			KEY_BRACKETLEFT:
				_yaw_step = (_yaw_step + 3) % 4
				return true
			KEY_BRACKETRIGHT:
				_yaw_step = (_yaw_step + 1) % 4
				return true

	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_exit()
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_paint(camera, mb.position, mb.ctrl_pressed)
			return true

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			return false  # editor freelook drag -> don't steal look motion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_paint(camera, mm.position, mm.ctrl_pressed)
		else:
			_last_cell = Vector3i(2147483647, 0, 0)  # released -> next click repaints its cell
			_update_ghost(camera, mm.position)
		return true

	return false


func _valid() -> bool:
	return _item != GridMap.INVALID_CELL_ITEM \
			and is_instance_valid(_grid) and _grid.is_inside_tree()


func _exit() -> void:
	set_active(false)
	deactivated.emit()


# ------------------------------------------------------------------ paint

func _paint(camera: Camera3D, mouse_pos: Vector2, erase: bool) -> void:
	var hit := GroundSnap.ground_point(camera, mouse_pos, _no_excludes)
	var cell := _grid.local_to_map(_grid.to_local(hit))  # auto-floor: Y from the hit height
	var orient := _grid.get_orthogonal_index_from_basis(
			Basis(Vector3.UP, _yaw_step * (PI / 2.0)))
	var item := GridMap.INVALID_CELL_ITEM if erase else _item
	if cell == _last_cell:
		return  # same cell within a drag -> no duplicate undo step
	var prev := _grid.get_cell_item(cell)
	var prev_orient := _grid.get_cell_item_orientation(cell)
	if prev == item and (item == GridMap.INVALID_CELL_ITEM or prev_orient == orient):
		_last_cell = cell
		return  # already painted -> nothing to do
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	_undo.create_action("Paint tile", UndoRedo.MERGE_DISABLE, scene_root)
	_undo.add_do_method(_grid, "set_cell_item", cell, item, orient)
	_undo.add_undo_method(_grid, "set_cell_item", cell, prev, prev_orient)
	_undo.commit_action()
	_last_cell = cell


func _resolve_item(grid: GridMap, tile_name: String) -> int:
	if grid == null or grid.mesh_library == null:
		return GridMap.INVALID_CELL_ITEM
	var ml := grid.mesh_library
	for id in ml.get_item_list():
		if ml.get_item_name(id) == tile_name:
			return id
	push_warning("Kit: tile '%s' not in the GridMap's meshlib." % tile_name)
	return GridMap.INVALID_CELL_ITEM


# ------------------------------------------------------------------ ghost

## Wire box at the hovered cell so the auto-derived floor is visible before the click.
func _update_ghost(camera: Camera3D, mouse_pos: Vector2) -> void:
	var hit := GroundSnap.ground_point(camera, mouse_pos, _no_excludes)
	var cell := _grid.local_to_map(_grid.to_local(hit))
	if not is_instance_valid(_ghost) or _ghost.get_parent() != _grid:
		_free_ghost()
		_ghost = MeshInstance3D.new()
		_ghost.name = "__GridMapPaintGhost"
		_ghost.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.vertex_color_use_as_albedo = true
		_ghost.material_override = mat
		_grid.add_child(_ghost)  # unowned on purpose -> never serialized
	var size := _grid.cell_size
	var lo := Vector3(cell) * size  # low corner, shifted per axis for centered cells
	if _grid.cell_center_x:
		lo.x -= size.x * 0.5
	if _grid.cell_center_y:
		lo.y -= size.y * 0.5
	if _grid.cell_center_z:
		lo.z -= size.z * 0.5
	var hi := lo + size
	var im := _ghost.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(GHOST_COLOR)
	_add_box(im, lo, hi)
	im.surface_end()
	_ghost.visible = true


static func _add_box(im: ImmediateMesh, lo: Vector3, hi: Vector3) -> void:
	var c := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z),
		Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	var edges := [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
	for e in edges:
		im.surface_add_vertex(c[e])


func _hide_ghost() -> void:
	if is_instance_valid(_ghost) and _ghost.visible:
		_ghost.visible = false


func _free_ghost() -> void:
	if is_instance_valid(_ghost):
		_ghost.free()
	_ghost = null

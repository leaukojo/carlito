@tool
extends RefCounted
## Draw-on-terrain road authoring: each viewport click ground-snaps and appends
## a curve point to the selected RoadPath (one undoable point per click).
## Shapes: Free (click-and-smooth), Straight (zero-handle chords, refuses
## corners tighter than the fold limit), Arc (3-click: start, tangent, end).
## A click near an open roads-GridMap tile edge snaps onto its port with the
## tangent locked outward, and arriving at one exits Draw mode. Snap Ends
## re-snaps endpoints dragged with the built-in gizmo (drags can't be
## intercepted directly).

const Groups := preload("res://src/levels/base/carlito_groups.gd")

const GroundSnap := preload("res://addons/carlito_kit/ground_snap.gd")
const RoadBuilderScript := preload("res://kit/helpers/road_builder.gd")
const RoadPortsScript := preload("res://kit/helpers/road_ports.gd")

const RECIPE_PATH := "res://kit/import/roads.json"
const SNAP_RADIUS := 3.0  # draw-click snap capture (XZ), ~1/4 cell
const SNAP_ENDS_RADIUS := 6.0  # Snap Ends button: forgiving post-drag fixup, 1/2 cell
const HANDLE_LEN := 4.0  # locked end tangent length, ~1/3 cell
const PORT_MARKER_RANGE := 30.0  # ghost draws port markers within this XZ range

const LINE_COLOR := Color(1.0, 0.75, 0.2)
const PORT_COLOR := Color(0.35, 0.75, 1.0)
const SNAP_COLOR := Color(0.4, 1.0, 0.5)
const WARN_COLOR := Color(1.0, 0.3, 0.25)

enum Submode { FREE, STRAIGHT, ARC }

const STUB_A := Vector3.ZERO  # the fresh-RoadPath stub curve; the first draw click replaces it
const STUB_B := Vector3(0, 0, 12)

signal deactivated  # RMB/Escape exit -> the panel flips its toggle back to Off
signal draw_status(msg: String)  # panel status line; "" after a successful commit
signal radius_display(text: String, warn: bool)  # live min-turn-radius readout

var smooth_corners := true  # Free mode: each click smooths the previous point (Catmull-Rom)
var snap_ports := true  # drawn end points capture onto GridMap ports
var draw_submode: Submode = Submode.FREE
var angle_snap_deg := 0.0  # snap candidate directions to this heading step, 0 = off

var _undo: EditorUndoRedoManager
var _road: Node3D = null
var _active := false
var _ghost: MeshInstance3D = null
var _no_excludes: Array[RID] = []
var _grid: GridMap = null
var _ports: Array[Dictionary] = []
var _table := {}
var _table_loaded := false
var _arc_dir := Vector3.ZERO  # pending world-space arc tangent (ZERO = not picked)


func _init(undo: EditorUndoRedoManager) -> void:
	_undo = undo


func set_target(road: Node3D) -> void:
	if road == _road:
		return
	_road = road
	_arc_dir = Vector3.ZERO
	if _road == null and _active:
		_exit()
	_free_ghost()


func set_active(active: bool) -> void:
	_active = active
	_arc_dir = Vector3.ZERO
	if _active:
		_refresh_ports()
		_prompt()
	else:
		_free_ghost()


func set_submode(mode: int) -> void:
	draw_submode = mode as Submode
	_arc_dir = Vector3.ZERO
	if _active:
		_prompt()


func set_grid(grid: GridMap) -> void:
	if grid == _grid:
		return
	_grid = grid
	if _active:
		_refresh_ports()


func teardown() -> void:
	_free_ghost()
	_road = null
	_grid = null
	_ports = []


# ------------------------------------------------------------------ input

## True when consumed (the plugin then returns AFTER_GUI_INPUT_STOP).
func handle_input(camera: Camera3D, event: InputEvent) -> bool:
	if not _active or not _target_valid():
		_hide_ghost()
		return false

	if event is InputEventKey and event.pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		_exit()
		return true

	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if draw_submode == Submode.ARC and _arc_dir != Vector3.ZERO:
				_arc_dir = Vector3.ZERO  # step back to the tangent pick, stay in Draw
				_prompt()
			else:
				_exit()
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			match draw_submode:
				Submode.ARC:
					_arc_click(_snap(camera, mb.position))
				_:
					_commit_point(_snap(camera, mb.position))
			return true

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			return false  # editor freelook drag -> don't steal look motion
		_update_ghost(camera, mm.position)
		return true

	return false


func _target_valid() -> bool:
	return is_instance_valid(_road) and _road.is_inside_tree()


func _exit() -> void:
	set_active(false)
	deactivated.emit()


func _snap(camera: Camera3D, mouse_pos: Vector2) -> Vector3:
	var clearance: float = _road.get("draw_clearance")
	return GroundSnap.ground_point(camera, mouse_pos, _no_excludes) \
			+ Vector3.UP * clearance


# ------------------------------------------------------------------ commit

## One undoable action per click. Straight zeroes the new point's handles and
## the previous out-handle for an exact miter. A click within SNAP_RADIUS of
## an open port lands on it flush with the deck and exits Draw mode. Fold
## guard: refuses a click that would turn the changed segments tighter than
## the ribbon half-width (would pinch the inside edge to a slit).
func _commit_point(world: Vector3) -> void:
	var straight := draw_submode == Submode.STRAIGHT
	var path := _road.get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null:
		push_warning("Kit: RoadPath '%s' has no Path child to draw into." % _road.name)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	var curve := path.curve
	var inv := path.global_transform.affine_inverse()
	var port := _snap_port(world)
	if straight and port.is_empty():
		var last: Variant = _last_point_world()
		if last != null:
			world = _apply_angle_snap(world, last)
	var port_handle := Vector3.ZERO
	if not port.is_empty():
		world = port["position"]
		port_handle = (inv.basis * (port["normal"] as Vector3)).normalized() * HANDLE_LEN
	var local := inv * world

	var stub := _is_default_stub(curve)
	var idx := curve.point_count   # index the new point will take (non-stub)
	var prev_handles := {}         # planned Catmull-Rom rewrite of the previous point
	var zero_prev_out := false     # straight mode: chord needs the previous out gone
	if not stub:
		if idx >= 1 and local.is_equal_approx(curve.get_point_position(idx - 1)):
			var msg := "Point refused: it lands on the previous point (a zero-length " \
					+ "segment) — click farther along."
			push_warning("Kit: " + msg)
			draw_status.emit(msg)
			return
		if straight:
			zero_prev_out = idx >= 1 and curve.get_point_out(idx - 1) != Vector3.ZERO
		elif smooth_corners and idx >= 2:
			prev_handles = RoadBuilderScript.smooth_handles(
					curve.get_point_position(idx - 2),
					curve.get_point_position(idx - 1), local)
		if not _fold_guard_ok(curve, idx, local, port_handle, prev_handles, straight):
			return

	_undo.create_action("Add road point", UndoRedo.MERGE_DISABLE, scene_root)
	if stub:
		_undo.add_do_method(curve, "remove_point", 1)
		_undo.add_do_method(curve, "remove_point", 0)
		_undo.add_do_method(curve, "add_point", local)
		if not port.is_empty():
			_undo.add_do_method(curve, "set_point_out", 0, port_handle)
		_undo.add_undo_method(curve, "remove_point", 0)
		_undo.add_undo_method(curve, "add_point", STUB_A)
		_undo.add_undo_method(curve, "add_point", STUB_B)
	else:
		_undo.add_do_method(curve, "add_point", local)
		if not port.is_empty():
			_undo.add_do_method(curve, "set_point_in", idx, port_handle)
		if zero_prev_out:
			_undo.add_do_method(curve, "set_point_out", idx - 1, Vector3.ZERO)
			_undo.add_undo_method(curve, "set_point_out", idx - 1, curve.get_point_out(idx - 1))
		if not prev_handles.is_empty():
			_undo.add_do_method(curve, "set_point_in", idx - 1, prev_handles["in"])
			_undo.add_do_method(curve, "set_point_out", idx - 1, prev_handles["out"])
			# undo methods run in registration order (verified on 4.6)
			_undo.add_undo_method(curve, "set_point_in", idx - 1, curve.get_point_in(idx - 1))
			_undo.add_undo_method(curve, "set_point_out", idx - 1, curve.get_point_out(idx - 1))
		_undo.add_undo_method(curve, "remove_point", idx)
	_undo.commit_action()
	draw_status.emit("")
	# a snapped first point leaves 1 point (keep drawing); a snapped arrival
	# leaves >= 2 and ends the road
	if not port.is_empty() and curve.point_count >= 2:
		_exit()


## True when the click may commit (checks RoadBuilder.min_turn_radius against
## the ribbon's full half-width).
func _fold_guard_ok(curve: Curve3D, idx: int, local: Vector3, port_handle: Vector3,
		prev_handles: Dictionary, straight := false) -> bool:
	var prof: RoadProfile = _road.get("profile")
	if prof == null:
		return true
	var limit := prof.full_half_width()
	var radius: float = RoadBuilderScript.min_turn_radius(
			_click_sim(curve, idx, local, port_handle, prev_handles, straight),
			_road.get("max_segment_length"), _road.get("max_segment_angle_deg"))
	if radius >= limit:
		return true
	var msg := "Point refused: turn radius %.1f m is under the road's %.1f m " % [
			radius, limit] \
			+ "half-width (the ribbon would pinch) — widen the turn or draw it as an Arc."
	push_warning("Kit: " + msg)
	draw_status.emit(msg)
	return false


## Path-local scratch curve of the segments a click at `local` creates or
## reshapes; shared by the fold guard and the ghost so they can never disagree.
func _click_sim(curve: Curve3D, idx: int, local: Vector3, port_handle: Vector3,
		prev_handles: Dictionary, zero_prev_out: bool) -> Curve3D:
	var sim := Curve3D.new()
	if not prev_handles.is_empty():
		sim.add_point(curve.get_point_position(idx - 2), Vector3.ZERO,
				curve.get_point_out(idx - 2))
		sim.add_point(curve.get_point_position(idx - 1),
				prev_handles["in"], prev_handles["out"])
	elif idx >= 2:
		sim.add_point(curve.get_point_position(idx - 2), Vector3.ZERO,
				curve.get_point_out(idx - 2))
		sim.add_point(curve.get_point_position(idx - 1), curve.get_point_in(idx - 1),
				Vector3.ZERO if zero_prev_out else curve.get_point_out(idx - 1))
	else:
		sim.add_point(curve.get_point_position(idx - 1), Vector3.ZERO,
				Vector3.ZERO if zero_prev_out else curve.get_point_out(idx - 1))
	sim.add_point(local, port_handle, Vector3.ZERO)
	return sim


# ------------------------------------------------------------------ arc mode


## Arc-mode click router (3-click pattern: start, tangent, end).
func _arc_click(world: Vector3) -> void:
	var last: Variant = _last_point_world()
	if last == null:
		_commit_point(world)
		_prompt()
		return
	var start_world: Vector3 = last
	if _arc_dir == Vector3.ZERO:
		var handle_dir := _last_out_world()
		if handle_dir == Vector3.ZERO:
			var dir := world - start_world
			if Vector2(dir.x, dir.z).length() < 0.1:
				return  # clicked on the start point: no direction to read
			_arc_dir = RoadBuilderScript.snap_direction(dir, angle_snap_deg)
			_prompt()
			return
		_arc_dir = handle_dir
	_commit_arc(world, start_world)


## Arc end click: fit via RoadBuilder.arc_points, refuse if the radius is
## under the ribbon's half-width. Ports are ignored — the end tangent is
## already fully determined.
func _commit_arc(world: Vector3, start_world: Vector3) -> void:
	var path := _road.get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null:
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	world = _apply_angle_snap(world, start_world)
	var curve := path.curve
	var inv := path.global_transform.affine_inverse()
	var start_idx := curve.point_count - 1
	var res: Dictionary = RoadBuilderScript.arc_points(
			curve.get_point_position(start_idx),
			(inv.basis * _arc_dir).normalized(), inv * world)
	var prof: RoadProfile = _road.get("profile")
	if prof != null and res.radius < prof.full_half_width():
		var msg := "Arc refused: radius %.1f m is under the road's %.1f m " % [
				res.radius, prof.full_half_width()] \
				+ "half-width (the ribbon would pinch) — aim wider."
		push_warning("Kit: " + msg)
		draw_status.emit(msg)
		return
	var pts: Array = res.points
	_undo.create_action("Add road arc", UndoRedo.MERGE_DISABLE, scene_root)
	_undo.add_do_method(curve, "set_point_out", start_idx, res.start_out)
	_undo.add_undo_method(curve, "set_point_out", start_idx, curve.get_point_out(start_idx))
	for i in pts.size():
		var p: Dictionary = pts[i]
		_undo.add_do_method(curve, "add_point", p["pos"])
		_undo.add_do_method(curve, "set_point_in", start_idx + 1 + i, p["in"])
		_undo.add_do_method(curve, "set_point_out", start_idx + 1 + i, p["out"])
		# same index each time: every undo removal shifts the next point down onto it
		_undo.add_undo_method(curve, "remove_point", start_idx + 1)
	_undo.commit_action()
	_arc_dir = Vector3.ZERO
	_prompt()


func _apply_angle_snap(world: Vector3, from: Vector3) -> Vector3:
	if angle_snap_deg <= 0.0:
		return world
	return from + RoadBuilderScript.snap_direction(world - from, angle_snap_deg)


func _last_out_world() -> Vector3:
	var path := _road.get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null or path.curve.point_count == 0:
		return Vector3.ZERO
	var out := path.curve.get_point_out(path.curve.point_count - 1)
	if out.length_squared() < 1e-8:
		return Vector3.ZERO
	return (path.global_transform.basis * out).normalized()


func _prompt() -> void:
	if draw_submode != Submode.ARC or not _target_valid():
		draw_status.emit("")
		return
	if _last_point_world() == null:
		draw_status.emit("Arc: click the start point.")
	elif _arc_dir == Vector3.ZERO and _last_out_world() == Vector3.ZERO:
		draw_status.emit("Arc: click the tangent direction.")
	else:
		draw_status.emit("Arc: click the end point (right-click re-picks the tangent).")


## Close the loop (panel button): append a point at the first point's
## position, C1-smoothed if smooth_corners is on. Exits Draw mode.
func close_loop() -> void:
	if not _target_valid():
		return
	var path := _road.get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null:
		return
	var curve := path.curve
	var n := curve.point_count
	if n < 3 or _is_default_stub(curve):
		push_warning("Kit: draw at least 3 points before closing the loop.")
		return
	var first := curve.get_point_position(0)
	var last := curve.get_point_position(n - 1)
	if last.is_equal_approx(first):
		push_warning("Kit: the road already ends on its first point.")
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	_undo.create_action("Close road loop", UndoRedo.MERGE_DISABLE, scene_root)
	_undo.add_do_method(curve, "add_point", first)
	if smooth_corners:
		var seam: Dictionary = RoadBuilderScript.smooth_handles(
				last, first, curve.get_point_position(1))
		var prev_h: Dictionary = RoadBuilderScript.smooth_handles(
				curve.get_point_position(n - 2), last, first)
		_undo.add_do_method(curve, "set_point_in", n, seam["in"])
		_undo.add_do_method(curve, "set_point_out", 0, seam["out"])
		_undo.add_do_method(curve, "set_point_in", n - 1, prev_h["in"])
		_undo.add_do_method(curve, "set_point_out", n - 1, prev_h["out"])
		# undo methods run in registration order (verified on 4.6)
		_undo.add_undo_method(curve, "set_point_out", n - 1, curve.get_point_out(n - 1))
		_undo.add_undo_method(curve, "set_point_in", n - 1, curve.get_point_in(n - 1))
		_undo.add_undo_method(curve, "set_point_out", 0, curve.get_point_out(0))
	_undo.add_undo_method(curve, "remove_point", n)
	_undo.commit_action()
	if _active:
		_exit()


## Panel button: snap the road's first/last curve points to their nearest
## open port and lock the end tangents. Ends that find no port are left alone.
func snap_ends() -> void:
	if not _target_valid():
		return
	var path := _road.get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null:
		return
	var curve := path.curve
	if curve.point_count < 2 or _is_default_stub(curve):
		push_warning("Kit: draw the road before snapping its ends.")
		return
	_refresh_ports()
	if _ports.is_empty():
		push_warning("Kit: no open ports found (is there a painted roads GridMap?).")
		return
	var inv := path.global_transform.affine_inverse()
	var last := curve.point_count - 1
	var ends := []  # [point index, port]
	for i in [0, last]:
		var port: Dictionary = RoadPortsScript.nearest_port(_ports,
				path.global_transform * curve.get_point_position(i), SNAP_ENDS_RADIUS)
		if not port.is_empty():
			ends.append([i, port])
	if ends.size() == 2 and ends[0][1]["position"] == ends[1][1]["position"]:
		ends.remove_at(1)  # both ends captured the same port: the first end wins
	if ends.is_empty():
		push_warning("Kit: no port within %.0f m of either road end." % SNAP_ENDS_RADIUS)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	_undo.create_action("Snap road ends to ports", UndoRedo.MERGE_DISABLE, scene_root)
	for e in ends:
		var i: int = e[0]
		var port: Dictionary = e[1]
		var handle: Vector3 = (inv.basis * (port["normal"] as Vector3)).normalized() \
				* HANDLE_LEN
		_undo.add_do_method(curve, "set_point_position", i, inv * (port["position"] as Vector3))
		_undo.add_undo_method(curve, "set_point_position", i, curve.get_point_position(i))
		if i == 0:
			_undo.add_do_method(curve, "set_point_out", 0, handle)
			_undo.add_undo_method(curve, "set_point_out", 0, curve.get_point_out(0))
		else:
			_undo.add_do_method(curve, "set_point_in", i, handle)
			_undo.add_undo_method(curve, "set_point_in", i, curve.get_point_in(i))
	_undo.commit_action()


func reverse_road() -> void:
	if not _target_valid():
		return
	_road.call(&"_reverse_curve")


# ------------------------------------------------------------------ ports

## Rebuilt on activation / grid change only, never per-frame.
func _refresh_ports() -> void:
	_ports = []
	if _grid != null and is_instance_valid(_grid) and _grid.is_inside_tree():
		_ports = RoadPortsScript.enumerate_ports(_grid, _load_table(), _grid.global_transform)
	_ports.append_array(_enumerate_road_ends())


## Other RoadPaths' first/last curve points, shaped as snap "ports" so a
## road-to-road join uses the same nearest_port + handle-lock path as a tile
## port. `cell` is a sentinel; road ends never reach the GridMap-repaint code.
func _enumerate_road_ends() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_instance_valid(_road):
		return out
	var root := _authoring_root(_road)
	if root == null:
		return out
	var roads: Array[Node] = []
	_collect_roads(root, roads)
	for r in roads:
		if r == _road:
			continue
		var path := r.get_node_or_null(^"Path") as Path3D
		if path == null or path.curve == null or path.curve.point_count < 2 \
				or _is_default_stub(path.curve):
			continue
		var curve := path.curve
		var xform := path.global_transform
		for at_last: bool in [false, true]:
			var t: Vector3 = RoadBuilderScript.end_tangent_out(curve, at_last)
			if t == Vector3.ZERO:
				continue
			var idx := (curve.point_count - 1) if at_last else 0
			out.append({
				"position": xform * curve.get_point_position(idx),
				"normal": (xform.basis * t).normalized(),
				"cell": Vector3i.ZERO,
			})
	return out


static func _authoring_root(node: Node) -> Node:
	return Groups.authoring_ancestor(node)


static func _collect_roads(node: Node, out: Array[Node]) -> void:
	if node.is_in_group(Groups.ROAD):
		out.append(node)
	for child in node.get_children():
		_collect_roads(child, out)


func _snap_port(world: Vector3) -> Dictionary:
	if not snap_ports or _ports.is_empty():
		return {}
	return RoadPortsScript.nearest_port(_ports, world, SNAP_RADIUS)


func _load_table() -> Dictionary:
	if _table_loaded:
		return _table
	_table_loaded = true
	var recipe: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECIPE_PATH))
	if recipe is Dictionary:
		for err in RoadPortsScript.validate(recipe):
			push_warning("Kit: roads ports table: %s" % err)
		_table = RoadPortsScript.parse_table(recipe)
	else:
		push_warning("Kit: cannot read %s for road port snapping." % RECIPE_PATH)
	return _table


static func _is_default_stub(curve: Curve3D) -> bool:
	return curve.point_count == 2 \
			and curve.get_point_position(0) == STUB_A \
			and curve.get_point_position(1) == STUB_B \
			and curve.get_point_in(1) == Vector3.ZERO \
			and curve.get_point_out(0) == Vector3.ZERO


# ------------------------------------------------------------------ ghost

## Ghost preview: the candidate segment as the tessellated ribbon edges, tinted
## red under the fold limit. Also feeds the panel's live min-radius readout.
func _update_ghost(camera: Camera3D, mouse_pos: Vector2) -> void:
	var world := _snap(camera, mouse_pos)
	var arc := draw_submode == Submode.ARC
	var target := {} if arc else _snap_port(world)
	if not is_instance_valid(_ghost) or _ghost.get_parent() != _road:
		_free_ghost()
		_ghost = MeshInstance3D.new()
		_ghost.name = "__RoadDrawGhost"
		_ghost.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = Color.WHITE
		_ghost.material_override = mat
		_road.add_child(_ghost)  # unowned on purpose -> never serialized

	var dest: Vector3 = world if target.is_empty() else target["position"]
	var last: Variant = _last_point_world()
	var prof: RoadProfile = _road.get("profile")
	var limit := prof.full_half_width() if prof != null else 0.0
	var scratch: Curve3D = null   # world-space candidate (null = no ribbon preview)
	var radius := INF
	var tangent_line := false     # arc tangent pick: plain direction line
	var start_world := Vector3.ZERO
	if last != null:
		# mirrors _commit_point's exact computation, so the preview IS the click's outcome
		start_world = last
		var path := _road.get_node_or_null(^"Path") as Path3D
		var curve := path.curve
		var inv := path.global_transform.affine_inverse()
		if arc:
			var dir := _arc_dir
			if dir == Vector3.ZERO:
				dir = _last_out_world()
			dest = _apply_angle_snap(world, start_world)
			if dir == Vector3.ZERO:
				tangent_line = true
			else:
				var res: Dictionary = RoadBuilderScript.arc_points(
						curve.get_point_position(curve.point_count - 1),
						(inv.basis * dir).normalized(), inv * dest)
				radius = res.radius
				scratch = Curve3D.new()
				scratch.add_point(curve.get_point_position(curve.point_count - 1),
						Vector3.ZERO, res.start_out)
				for p: Dictionary in res.points:
					scratch.add_point(p["pos"], p["in"], p["out"])
		else:
			var straight := draw_submode == Submode.STRAIGHT
			if straight and target.is_empty():
				dest = _apply_angle_snap(world, start_world)
			var port_handle := Vector3.ZERO
			if not target.is_empty():
				port_handle = (inv.basis * (target["normal"] as Vector3)).normalized() \
						* HANDLE_LEN
			var local := inv * dest
			var idx := curve.point_count
			var prev_handles := {}
			if not straight and smooth_corners and idx >= 2:
				prev_handles = RoadBuilderScript.smooth_handles(
						curve.get_point_position(idx - 2),
						curve.get_point_position(idx - 1), local)
			scratch = _click_sim(curve, idx, local, port_handle, prev_handles, straight)
			radius = RoadBuilderScript.min_turn_radius(scratch,
					_road.get("max_segment_length"), _road.get("max_segment_angle_deg"))
		if scratch != null:
			scratch = _to_world_curve(scratch, path.global_transform)
	var warn := prof != null and radius < limit

	var im := _ghost.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(WARN_COLOR if warn else LINE_COLOR)
	if scratch != null:
		_add_ribbon_edges(im, scratch, limit)
	elif tangent_line:
		im.surface_add_vertex(_ghost.to_local(start_world))
		im.surface_add_vertex(_ghost.to_local(dest))
	im.surface_add_vertex(_ghost.to_local(dest))
	im.surface_add_vertex(_ghost.to_local(dest + Vector3.UP * 2.0))
	if snap_ports and not arc:
		for port: Dictionary in _ports:
			var pos: Vector3 = port["position"]
			if port == target \
					or Vector2(pos.x - world.x, pos.z - world.z).length() > PORT_MARKER_RANGE:
				continue
			im.surface_set_color(PORT_COLOR)
			_add_marker(im, _ghost.to_local(pos), 0.9)
		if not target.is_empty():
			im.surface_set_color(SNAP_COLOR)
			_add_marker(im, _ghost.to_local(target["position"]), 1.6)
	im.surface_end()
	_ghost.visible = true

	if last == null or tangent_line:
		radius_display.emit("", false)
	elif radius == INF:
		radius_display.emit("straight", false)
	elif warn:
		radius_display.emit("radius %.1f m under the %.1f m half-width — would fold" % [
				radius, limit], true)
	else:
		radius_display.emit("min radius %.1f m" % radius, false)


static func _to_world_curve(curve: Curve3D, xform: Transform3D) -> Curve3D:
	var out := Curve3D.new()
	for i in curve.point_count:
		out.add_point(xform * curve.get_point_position(i),
				xform.basis * curve.get_point_in(i), xform.basis * curve.get_point_out(i))
	return out


## Left/right ribbon edge polylines at +-`half` lateral (centerline only when
## half is 0), framed like the extruder.
func _add_ribbon_edges(im: ImmediateMesh, curve: Curve3D, half: float) -> void:
	var offsets := RoadBuilderScript.adaptive_offsets(curve,
			_road.get("max_segment_length"), _road.get("max_segment_angle_deg"))
	if offsets.size() < 2:
		return
	var length := curve.get_baked_length()
	var prev_right := Vector3.RIGHT
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in offsets.size():
		var f: Transform3D = RoadBuilderScript.frame_at(curve, offsets[i], length, 0.0,
				prev_right)
		prev_right = f.basis.x
		var edge_l: Vector3 = f.origin - f.basis.x * half
		var edge_r: Vector3 = f.origin + f.basis.x * half
		if i > 0:
			im.surface_add_vertex(_ghost.to_local(prev_l))
			im.surface_add_vertex(_ghost.to_local(edge_l))
			if half > 0.0:
				im.surface_add_vertex(_ghost.to_local(prev_r))
				im.surface_add_vertex(_ghost.to_local(edge_r))
		prev_l = edge_l
		prev_r = edge_r


func _add_marker(im: ImmediateMesh, center: Vector3, size: float) -> void:
	var corners := [
		center + Vector3(0, 0, -size), center + Vector3(size, 0, 0),
		center + Vector3(0, 0, size), center + Vector3(-size, 0, 0),
	]
	for i in 4:
		im.surface_add_vertex(corners[i])
		im.surface_add_vertex(corners[(i + 1) % 4])
	im.surface_add_vertex(center)
	im.surface_add_vertex(center + Vector3.UP * 1.5)


func _last_point_world() -> Variant:
	var path := _road.get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null or path.curve.point_count == 0 \
			or _is_default_stub(path.curve):
		return null
	return path.global_transform \
			* path.curve.get_point_position(path.curve.point_count - 1)


func _hide_ghost() -> void:
	if is_instance_valid(_ghost) and _ghost.visible:
		_ghost.visible = false
		radius_display.emit("", false)  # no candidate under the cursor -> idle readout


func _free_ghost() -> void:
	if is_instance_valid(_ghost):
		_ghost.free()
	_ghost = null

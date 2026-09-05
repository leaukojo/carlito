@tool
extends RefCounted
## Reusable viewport brush chassis, shared by the terrain and scatter brushes: radius/
## strength/falloff params, the circular ground cursor, and the input loop (press -> stroke,
## motion -> spacing-throttled samples, release -> stroke end, [ ] adjust radius).
##
## Subclasses (terrain_brush.gd, scatter_brush.gd) override virtuals for the brush-specific
## work: _target_valid, _project, _cursor_parent, _cursor_points/_cursor_strips,
## _cursor_color, _stroke_begin/_stroke_apply/_stroke_end, _click_mode/_click.

signal radius_display(r: float)  # brackets change radius live -> the panel field tracks it

## Sample spacing as a fraction of radius: a stroke applies a new sample only after moving
## this far.
const SPACING_FRAC := 0.35
const CURSOR_SEGMENTS := 48

var radius := 8.0
var strength := 0.5
var falloff := 0.5

## Refreshed from every event that carries it, for subclasses that give Ctrl/Shift a
## meaning (terrain brush's invert and smooth).
var ctrl_pressed := false
var shift_pressed := false

var _cursor: MeshInstance3D = null
var _stroking := false
var _click_press := false  # a click-mode press was consumed; its release must be too
var _last_apply := Vector3.ZERO


## True when the event was consumed. Returns false whenever the subclass reports no valid
## target, so other editor tools and camera navigation are untouched until a brush is armed.
func handle_input(camera: Camera3D, event: InputEvent) -> bool:
	if not _target_valid():
		_hide_cursor()
		return false

	if event is InputEventWithModifiers:
		var mods := event as InputEventWithModifiers
		ctrl_pressed = mods.ctrl_pressed
		shift_pressed = mods.shift_pressed

	if event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_BRACKETLEFT:
				_set_radius(radius * 0.8)
				return true
			KEY_BRACKETRIGHT:
				_set_radius(radius * 1.25)
				return true

	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var p: Variant = _project(camera, (event as InputEventMouseButton).position)
			if p == null:
				return false
			# A click-mode brush gets the press as a discrete click, not the drag loop below.
			if _click_mode():
				_click_press = true
				_click(p)
				_update_cursor(p)
				return true
			_stroking = true
			_last_apply = p
			_stroke_begin(p)
			_stroke_apply(p)
			_update_cursor(p)
			return true
		if _stroking:
			_stroking = false
			_stroke_end()
			return true
		# Swallow the release matching a consumed click-mode press; a one-shot click can
		# disarm itself before release, so this can't re-test _click_mode() at that point.
		if _click_press:
			_click_press = false
			return true
		return false

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# Self-heal a stuck stroke: a mouse-up outside the viewport never sends a release
		# event, so trust the motion event's own live button_mask instead.
		if _stroking and not (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_stroking = false
			_stroke_end()
		var p: Variant = _project(camera, mm.position)
		if p == null:
			_hide_cursor()
			return _stroking
		_update_cursor(p)
		if _stroking and (p as Vector3).distance_to(_last_apply) >= maxf(radius * SPACING_FRAC, 0.01):
			_last_apply = p
			_stroke_apply(p)
		return _stroking

	return false


func _set_radius(value: float) -> void:
	radius = clampf(value, 0.5, 512.0)
	radius_display.emit(radius)


func _update_cursor(center: Vector3) -> void:
	var parent := _cursor_parent()
	if parent == null:
		return
	if not is_instance_valid(_cursor) or _cursor.get_parent() != parent:
		_free_cursor()
		_cursor = MeshInstance3D.new()
		_cursor.name = "__BrushCursor"
		_cursor.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true  # always visible, even under the terrain surface
		_cursor.material_override = mat
		parent.add_child(_cursor)  # unowned -> never serialized

	var im := _cursor.mesh as ImmediateMesh
	im.clear_surfaces()
	for strip in _cursor_strips(center):
		if (strip as PackedVector3Array).size() < 2:
			continue
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p in strip:
			im.surface_add_vertex(_cursor.to_local(p))
		im.surface_end()
	(_cursor.material_override as StandardMaterial3D).albedo_color = _cursor_color()
	_cursor.visible = true


func _hide_cursor() -> void:
	if is_instance_valid(_cursor):
		_cursor.visible = false


func _free_cursor() -> void:
	if is_instance_valid(_cursor):
		_cursor.free()
	_cursor = null


## Ray vs. the horizontal plane Y = plane_y. Null when the ray is parallel / points away.
static func _ray_plane(origin: Vector3, dir: Vector3, plane_y: float) -> Variant:
	if absf(dir.y) < 1e-6:
		return null
	var t := (plane_y - origin.y) / dir.y
	if t < 0.0:
		return null
	return origin + dir * t


func _target_valid() -> bool:
	return false


func _project(_camera: Camera3D, _mouse: Vector2) -> Variant:
	return null


func _cursor_parent() -> Node3D:
	return null


func _cursor_points(center: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in CURSOR_SEGMENTS + 1:
		var a := TAU * float(i) / float(CURSOR_SEGMENTS)
		pts.append(center + Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	return pts


## Every line strip the cursor draws, as separate surfaces (default: the single ring).
func _cursor_strips(center: Vector3) -> Array[PackedVector3Array]:
	return [_cursor_points(center)]


func _cursor_color() -> Color:
	return Color.WHITE


func _click_mode() -> bool:
	return false


func _click(_center: Vector3) -> void:
	pass


func _stroke_begin(_center: Vector3) -> void:
	pass


func _stroke_apply(_center: Vector3) -> void:
	pass


func _stroke_end() -> void:
	pass

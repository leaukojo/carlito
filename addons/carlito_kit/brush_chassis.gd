@tool
extends RefCounted
## Reusable viewport brush chassis (shared by the terrain and scatter brushes).
## Owns the pieces every brush needs: radius/strength/falloff params, the circular ground
## cursor, and the input loop (press -> stroke, motion -> spacing-throttled samples, release
## -> stroke end, [ ] adjust radius). The editor half of the editor/runtime split; the
## brush-specific work (where the ground is, what a stroke does) is delegated to virtuals a
## subclass overrides (terrain_brush.gd, scatter_brush.gd).
##
## Virtuals a subclass provides:
##   _target_valid() -> bool                         is there something to brush right now
##   _project(camera, mouse) -> Vector3 or null      ground point under the cursor
##   _cursor_parent() -> Node3D                       where the cursor node lives
##   _cursor_points(center) -> PackedVector3Array     ring geometry (world space)
##   _cursor_strips(center) -> Array[…]               all cursor line strips (defaults to the ring)
##   _cursor_color() -> Color                          ring tint (mode feedback)
##   _stroke_begin(center) / _stroke_apply(center) / _stroke_end()
##   _click_mode() -> bool / _click(center)          take a press as a discrete click, not a stroke

signal radius_display(r: float)  # brackets change radius live -> the panel field tracks it

## Sample spacing as a fraction of radius: a stroke applies a new sample only after moving
## this far, so slow drags don't over-stamp and big brushes stay responsive.
const SPACING_FRAC := 0.35
const CURSOR_SEGMENTS := 48

var radius := 8.0
var strength := 0.5
var falloff := 0.5

## Live modifier state, refreshed from every event that carries it (mouse buttons and motion
## both do), for subclasses that give Ctrl/Shift a meaning — the terrain brush's invert and
## smooth. Recorded unconditionally; a subclass that ignores them is unaffected.
var ctrl_pressed := false
var shift_pressed := false

var _cursor: MeshInstance3D = null
var _stroking := false
var _click_press := false  # a click-mode press was consumed; its release must be too
var _last_apply := Vector3.ZERO


# ------------------------------------------------------------------ input

## Returns true when the event was consumed (the plugin then returns AFTER_GUI_INPUT_STOP).
## Inert (returns false) whenever the subclass reports no valid target, so other editor tools
## and camera navigation are untouched until a brush is actually armed.
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
			# A click-mode brush (a two-point tool, a one-shot sampler) gets the press as a
			# discrete click and never enters the drag loop below.
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
		# Swallow the release matching a consumed click-mode press. Latched at the press
		# rather than re-testing _click_mode(), because a one-shot click (the eyedropper)
		# disarms itself and would leave the release to the editor — which selects on
		# release, changing the selection out from under the brush.
		if _click_press:
			_click_press = false
			return true
		return false

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# Self-heal a stuck stroke: if the mouse-up happened outside the viewport (over a
		# panel/dock), we never see the release event, and _stroking would stay true forever,
		# swallowing every future motion event -> blocks editor freelook. The live button_mask
		# on the motion event itself is authoritative.
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


# ------------------------------------------------------------------ cursor

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
		parent.add_child(_cursor)  # unowned on purpose -> never serialized

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
## Shared helper for subclass projection.
static func _ray_plane(origin: Vector3, dir: Vector3, plane_y: float) -> Variant:
	if absf(dir.y) < 1e-6:
		return null
	var t := (plane_y - origin.y) / dir.y
	if t < 0.0:
		return null
	return origin + dir * t


# ------------------------------------------------------------------ virtuals (defaults)

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


## Every line strip the cursor draws, as separate surfaces. Defaults to the single ring from
## _cursor_points; a brush with a second marker (the ramp's stored start point) returns more,
## which one strip could not express — a LINE_STRIP would join them with a stray chord.
func _cursor_strips(center: Vector3) -> Array[PackedVector3Array]:
	return [_cursor_points(center)]


func _cursor_color() -> Color:
	return Color.WHITE


## True while a press should read as a discrete click instead of opening a drag stroke.
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

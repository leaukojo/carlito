@tool
class_name ChallengeZone
extends Node3D
## One zone on a challenge course: a finish, a box, a gate, a checkpoint, a ring or a fail zone.
## Goals name a zone by its NODE NAME, which must be unique among the course's zones. A course is a
## runtime overlay and never arena content, so nothing here is a bake input. The node's scale is
## ignored: the exports below are the size. @tool only for the editor volume (unowned, never
## serializes), as VehicleSpawn does; at runtime a zone draws nothing, so a blind course's target
## is invisible by construction.

const _GIZMO_COLOR := Color(1.0, 0.8, 0.1, 0.3)
## A RING of unbounded height is drawn this tall.
const _GIZMO_UNBOUNDED_H := 3.0
const _RING_SEGMENTS := 48

@export var kind: ZoneShape.Kind = ZoneShape.Kind.BOX:
	set(value):
		kind = value
		_refresh_gizmo()
@export var size := Vector3(4.0, 2.0, 4.0):  ## BOX: full extents, m
	set(value):
		size = value
		_refresh_gizmo()
@export var inner_r := 0.0:                  ## RING: m, 0 = solid cylinder
	set(value):
		inner_r = value
		_refresh_gizmo()
@export var outer_r := 5.0:                  ## RING: m
	set(value):
		outer_r = value
		_refresh_gizmo()
@export var height := 0.0:                   ## RING: full vertical extent, m, 0 = unbounded
	set(value):
		height = value
		_refresh_gizmo()

var _gizmo: MeshInstance3D


func _ready() -> void:
	_refresh_gizmo()


## This zone's geometry in `xform`'s space.
func shape_at(xform: Transform3D) -> ZoneShape:
	if kind == ZoneShape.Kind.RING:
		return ZoneShape.ring(xform, inner_r, outer_r, height)
	return ZoneShape.box(xform, size)


## Every zone under `course` by name, in the space of `course`'s parent — world space once the
## course is instanced under the level root. Transforms are composed up the parent chain rather
## than read from `global_transform`, so this works on a course that never entered a tree (the
## registry's validation) as well as a live one. A duplicated name keeps the first zone found;
## `duplicate_names` reports it.
static func zones_of(course: Node3D) -> Dictionary[StringName, ZoneShape]:
	var out: Dictionary[StringName, ZoneShape] = {}
	for zone in _zones_under(course):
		if not out.has(zone.name):
			out[zone.name] = zone.shape_at(_course_space(zone, course))
	return out


## Zone names used more than once under `course`.
static func duplicate_names(course: Node3D) -> PackedStringArray:
	var seen := {}
	var out := PackedStringArray()
	for zone in _zones_under(course):
		if seen.has(zone.name) and not out.has(String(zone.name)):
			out.append(String(zone.name))
		seen[zone.name] = true
	return out


static func _zones_under(course: Node3D) -> Array[ChallengeZone]:
	var out: Array[ChallengeZone] = []
	for node in course.find_children("*", "", true, false):
		if node is ChallengeZone:
			out.append(node as ChallengeZone)
	return out


static func _course_space(node: Node3D, course: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		if n == course:
			break
		n = n.get_parent()
	return t


# --- the editor volume ---------------------------------------------------------------------------

func _refresh_gizmo() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _gizmo == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = _GIZMO_COLOR
		_gizmo = MeshInstance3D.new()
		_gizmo.material_override = mat
		add_child(_gizmo, false, Node.INTERNAL_MODE_BACK)
	_gizmo.mesh = _gizmo_mesh()


func _gizmo_mesh() -> Mesh:
	if kind == ZoneShape.Kind.BOX:
		var box := BoxMesh.new()
		box.size = size.max(Vector3.ONE * 0.01)
		return box
	var h := height if height > 0.0 else _GIZMO_UNBOUNDED_H
	var r_out := maxf(outer_r, 0.01)
	if inner_r <= 0.0:
		var cyl := CylinderMesh.new()
		cyl.top_radius = r_out
		cyl.bottom_radius = r_out
		cyl.height = h
		return cyl
	return _annulus(minf(inner_r, r_out), r_out, h)


## An annular prism about local Y: top, bottom, outer and inner walls. Drawn double-sided, so
## winding does not matter.
static func _annulus(r_in: float, r_out: float, h: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Vector3(0.0, h * 0.5, 0.0)
	for i in _RING_SEGMENTS:
		var a0 := TAU * float(i) / _RING_SEGMENTS
		var a1 := TAU * float(i + 1) / _RING_SEGMENTS
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		_quad(st, d0 * r_out + up, d1 * r_out + up, d1 * r_in + up, d0 * r_in + up)
		_quad(st, d0 * r_out - up, d1 * r_out - up, d1 * r_in - up, d0 * r_in - up)
		_quad(st, d0 * r_out - up, d1 * r_out - up, d1 * r_out + up, d0 * r_out + up)
		_quad(st, d0 * r_in - up, d1 * r_in - up, d1 * r_in + up, d0 * r_in + up)
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for p: Vector3 in [a, b, c, a, c, d]:
		st.add_vertex(p)

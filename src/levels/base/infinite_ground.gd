@tool
class_name InfiniteGround
extends StaticBody3D
## Endless flat ground with its top face at the node's Y: a square slab of collision plus a
## world-anchored grid mesh, re-centred on the active camera so the edge never arrives.
## A box, not a WorldBoundaryShape3D: Jolt caps that "infinite" plane at a project-setting
## size, so it would be finite anyway, just less visibly. The practical limit is float
## precision — tens of km out, physics and the grid start losing millimetres.
## Direct child of the level, never under `Authoring` (runtime collision, not bakeable).

const Layers := preload("res://src/physics/collision_layers.gd")
const SHADER := preload("res://src/levels/base/ground_grid.gdshader")
## Slab depth below the surface: thick enough that nothing tunnels through in one tick.
const THICKNESS := 20.0
## Re-centring step in metres. The grid is world-space, so this only keeps the body from
## moving every tick; any value well under half the extent works.
const FOLLOW_STEP := 50.0
## Quads per side, so nothing interpolated per vertex spans kilometres.
const MESH_SUBDIV := 64

## Side of the collision + visual square in metres. Fog and the camera's far plane hide the edge.
@export var extent := 4000.0:
	set(v):
		extent = v
		_rebuild()

var _mesh: MeshInstance3D
var _shape: CollisionShape3D


func _ready() -> void:
	collision_layer = Layers.TERRAIN
	collision_mask = Layers.DYNAMIC
	_rebuild()
	set_physics_process(not Engine.is_editor_hint())


func _physics_process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var xz := Vector2(cam.global_position.x, cam.global_position.z).snapped(
			Vector2(FOLLOW_STEP, FOLLOW_STEP))
	if not xz.is_equal_approx(Vector2(global_position.x, global_position.z)):
		global_position = Vector3(xz.x, global_position.y, xz.y)
		reset_physics_interpolation()


## Mesh + slab as internal children (never serialized), like WorldBounds and WaterSurface.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		_mesh.material_override = mat
		add_child(_mesh, false, Node.INTERNAL_MODE_BACK)
		_shape = CollisionShape3D.new()
		_shape.shape = BoxShape3D.new()
		add_child(_shape, false, Node.INTERNAL_MODE_BACK)
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent, extent)
	plane.subdivide_width = MESH_SUBDIV - 1
	plane.subdivide_depth = MESH_SUBDIV - 1
	_mesh.mesh = plane
	(_shape.shape as BoxShape3D).size = Vector3(extent, THICKNESS, extent)
	_shape.position = Vector3(0.0, -THICKNESS * 0.5, 0.0)

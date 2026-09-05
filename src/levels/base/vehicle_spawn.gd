@tool
class_name VehicleSpawn
extends Marker3D
## A place a vehicle can start; transform is the spawn pose, filter says which vehicle
## types belong here. @tool only for the editor gizmo (unowned, never serializes).

const _LAND_COLOR := Color(1.0, 0.55, 0.1, 0.35)
const _WATER_COLOR := Color(0.2, 0.7, 1.0, 0.35)
const _FOOTPRINT := Vector3(1.9, 1.0, 4.4)  ## roughly the car's footprint

## Vehicle type ids this spawn accepts (e.g. "car", "boat"); empty = any type.
@export var vehicle_types := PackedStringArray()
## Chosen for boats and as the safe respawn after a car falls in.
@export var is_water := false:
	set(value):
		is_water = value
		_apply_gizmo_color()

var _gizmo_material: StandardMaterial3D


## True when a vehicle of `type` may use this spawn.
func accepts(type: String) -> bool:
	return vehicle_types.is_empty() or vehicle_types.has(type)


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_gizmo_material = StandardMaterial3D.new()
	_gizmo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gizmo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = _FOOTPRINT
	body.mesh = body_mesh
	body.material_override = _gizmo_material
	body.position = Vector3(0, _FOOTPRINT.y * 0.5, 0)
	add_child(body, false, Node.INTERNAL_MODE_BACK)

	var arrow := MeshInstance3D.new()
	var arrow_mesh := PrismMesh.new()
	arrow_mesh.size = Vector3(1.2, 1.2, 0.4)
	arrow.mesh = arrow_mesh
	arrow.material_override = _gizmo_material
	arrow.rotation_degrees = Vector3(-90, 0, 0)  ## PrismMesh peaks +Y; pitch to -Z (forward)
	arrow.position = Vector3(0, 0.5, -_FOOTPRINT.z * 0.5 - 0.7)
	add_child(arrow, false, Node.INTERNAL_MODE_BACK)

	_apply_gizmo_color()


func _apply_gizmo_color() -> void:
	if _gizmo_material != null:
		_gizmo_material.albedo_color = _WATER_COLOR if is_water else _LAND_COLOR

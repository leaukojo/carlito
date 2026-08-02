@tool
class_name WaterSurface
extends Area3D
## One rectangular water region: the water HEIGHT API, the visual
## surface, and the non-boat kill/respawn volume in a single node a level drops in.
##
## - Height API: get_height() returns the node's global Y — FLAT at launch.
##   The visual waves live entirely in water.gdshader and never feed physics.
## - Buoyancy callers (BoatVehicle) find water via the "water" group + contains_xz().
## - Kill volume:
##   the Area's box spans the water body but its top sits kill_margin below the surface,
##   so a splash at the shoreline is survivable while a sunk vehicle respawns (the
##   existing BaseVehicle.respawn path, which already zeroes the accel history).
##
## The region is an axis-aligned rect around the node's origin; don't rotate the node.

const WATER_GROUP := "water"
const SHADER := preload("res://src/water/water.gdshader")
## Visual plane subdivisions (fixed: enough for the vertex waves, one draw call).
const MESH_SUBDIV := 32

@export var size := Vector2(24.0, 24.0):
	set(v):
		size = v
		_rebuild()
## Water body depth below the surface (kill box bottom; keep >= actual basin depth).
@export var depth := 2.0:
	set(v):
		depth = v
		_rebuild()
## The kill box top sits this far below the surface: grazing the surface is not death.
@export var kill_margin := 0.5:
	set(v):
		kill_margin = v
		_rebuild()
## Side length of an optional flat "sea to the horizon" plane around this region
## (0 = off). Visual only — one unsubdivided quad in the deep-water color, sitting
## slightly below the wavy surface so the two never z-fight; distance + fog blend it
## into the sky. No kill volume and no height API out there.
@export var far_sea_extent := 0.0:
	set(v):
		far_sea_extent = v
		_rebuild()
## Far-sea quad color. Match the PERCEIVED near-water look (translucent water over the
## seabed), not the shader's deep_color — the quad is opaque, so raw deep_color reads
## much darker than the real surface next to it.
@export var far_sea_color := Color(0.16, 0.36, 0.47):
	set(v):
		far_sea_color = v
		_rebuild()

## How far the far-sea quad sits below the surface (must clear the wave troughs).
const FAR_SEA_DROP := 0.25

## Invisible perimeter walls at the water's edge so boats can't sail off the map into
## the (visual-only) far sea. Four thin static boxes ring the `size` rect.
## Height above/below the surface and thickness in metres.
const WALL_HEIGHT := 20.0
const WALL_THICKNESS := 2.0

var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _far_mesh: MeshInstance3D
var _walls: StaticBody3D


func _ready() -> void:
	add_to_group(WATER_GROUP)
	_rebuild()
	if not Engine.is_editor_hint():
		monitoring = true
		body_entered.connect(_on_body_entered)


## Water surface height at `pos` — constant across the region at launch.
## Boats sample this; the shader waves are cosmetic and deliberately not reflected here.
func get_height(_pos: Vector3) -> float:
	return global_position.y


## Whether `pos` is over this water region (axis-aligned rect around the origin).
func contains_xz(pos: Vector3) -> bool:
	var d := pos - global_position
	return absf(d.x) <= size.x * 0.5 and absf(d.z) <= size.y * 0.5


## Build the visual plane + kill-volume shape as internal children (never serialized,
## same pattern as VehicleSpawn's gizmo) so levels only author the WaterSurface node.
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
	plane.size = size
	plane.subdivide_width = MESH_SUBDIV
	plane.subdivide_depth = MESH_SUBDIV
	_mesh.mesh = plane
	var box_height := maxf(depth - kill_margin, 0.05)
	(_shape.shape as BoxShape3D).size = Vector3(size.x, box_height, size.y)
	_shape.position = Vector3(0.0, -kill_margin - box_height * 0.5, 0.0)
	_rebuild_walls()
	_rebuild_far_sea()


## Ring the water region with four thin static walls at its outer edge. The vehicle
## sits on the near side of the wall, so the collision boxes hug the `size` rect from
## outside; the wall spans WALL_HEIGHT centred on the surface (blocks both floating and
## airborne vehicles). Rebuilt with size like everything else.
func _rebuild_walls() -> void:
	if _walls == null:
		_walls = StaticBody3D.new()
		add_child(_walls, false, Node.INTERNAL_MODE_BACK)
	for child in _walls.get_children():
		child.queue_free()
	var half := size * 0.5
	var t := WALL_THICKNESS
	# Each entry: (box size, centre offset). Long axis spans the full side plus corners.
	var walls := [
		[Vector3(size.x + t * 2.0, WALL_HEIGHT, t), Vector3(0.0, 0.0, half.y + t * 0.5)],
		[Vector3(size.x + t * 2.0, WALL_HEIGHT, t), Vector3(0.0, 0.0, -half.y - t * 0.5)],
		[Vector3(t, WALL_HEIGHT, size.y), Vector3(half.x + t * 0.5, 0.0, 0.0)],
		[Vector3(t, WALL_HEIGHT, size.y), Vector3(-half.x - t * 0.5, 0.0, 0.0)],
	]
	for w in walls:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w[0]
		cs.shape = box
		cs.position = w[1]
		_walls.add_child(cs)


func _rebuild_far_sea() -> void:
	if far_sea_extent <= 0.0:
		if _far_mesh != null:
			_far_mesh.queue_free()
			_far_mesh = null
		return
	if _far_mesh == null:
		_far_mesh = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.roughness = 0.12
		mat.metallic_specular = 0.6
		_far_mesh.material_override = mat
		_far_mesh.position = Vector3(0.0, -FAR_SEA_DROP, 0.0)
		add_child(_far_mesh, false, Node.INTERNAL_MODE_BACK)
	(_far_mesh.material_override as StandardMaterial3D).albedo_color = far_sea_color
	var plane := PlaneMesh.new()
	plane.size = Vector2(far_sea_extent, far_sea_extent)
	_far_mesh.mesh = plane


## Non-boat vehicle in the water body -> drown: reuse the respawn path.
## Deferred because Area3D signals fire during the physics flush, where transforms
## can't be written. Boats float; everything else that isn't a vehicle is ignored.
func _on_body_entered(body: Node3D) -> void:
	if body is BaseVehicle and not body is BoatVehicle:
		body.call_deferred("respawn")

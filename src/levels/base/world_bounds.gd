@tool
class_name WorldBounds
extends StaticBody3D
## The level's containment box: four invisible perimeter walls plus a ceiling. Belongs to
## the level, not the water. Axis-aligned around the node's origin (don't rotate); direct
## child of the level, never under `Authoring` (runtime collision, not bakeable geometry).

## Playable area in metres (XZ); match the level's water `size` so the sea wall and map wall are the same wall.
@export var extent := Vector2(2000.0, 2000.0):
	set(v):
		extent = v
		_rebuild()
## Ceiling height above the origin, in metres; default clears the contract's 0-500 m altitude scale.
@export var ceiling_height := 1500.0:
	set(v):
		ceiling_height = v
		_rebuild()
## How far below the origin the walls reach, in metres; must cover the deepest water/terrain.
@export var floor_depth := 100.0:
	set(v):
		floor_depth = v
		_rebuild()

## Wall/ceiling slab thickness, in metres; thick enough a plane can't tunnel through in one tick.
const Layers := preload("res://src/physics/collision_layers.gd")
const THICKNESS := 4.0


func _ready() -> void:
	# CONTAINMENT is its own layer so a sensor can exclude it with a bit, not a subtree walk.
	collision_layer = Layers.CONTAINMENT
	collision_mask = Layers.DYNAMIC
	_rebuild()


## Rebuilds the five slabs as internal children (never serialized). Frees only what it made
## (a blanket get_children(true) sweep would destroy author-parented children).
func _rebuild() -> void:
	if not is_inside_tree():
		return
	# Detach before freeing: queue_free() defers to end of frame, else old slabs stay collidable.
	var authored := get_children(false)
	for child in get_children(true):
		if authored.has(child):
			continue
		remove_child(child)
		child.queue_free()
	var half := extent * 0.5
	var t := THICKNESS
	# Walls span floor_depth below to ceiling_height above.
	var wall_h := ceiling_height + floor_depth
	var wall_y := (ceiling_height - floor_depth) * 0.5
	# Each entry: (box size, centre offset). Long sides overlap the corners (no gap at joins).
	var slabs := [
		[Vector3(extent.x + t * 2.0, wall_h, t), Vector3(0.0, wall_y, half.y + t * 0.5)],
		[Vector3(extent.x + t * 2.0, wall_h, t), Vector3(0.0, wall_y, -half.y - t * 0.5)],
		[Vector3(t, wall_h, extent.y), Vector3(half.x + t * 0.5, wall_y, 0.0)],
		[Vector3(t, wall_h, extent.y), Vector3(-half.x - t * 0.5, wall_y, 0.0)],
		# Ceiling spans the full rect including wall thickness.
		[
			Vector3(extent.x + t * 2.0, t, extent.y + t * 2.0),
			Vector3(0.0, ceiling_height + t * 0.5, 0.0),
		],
	]
	for s in slabs:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = s[0]
		cs.shape = box
		cs.position = s[1]
		add_child(cs, false, Node.INTERNAL_MODE_BACK)

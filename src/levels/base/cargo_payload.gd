class_name CargoPayload
extends RigidBody3D
## A crate the drone's cargo hook can pick up and drop. A direct child of the level, never
## under AuthoringRoot (which merges into static per-chunk geometry — standing rule 1).
## `mass` is written straight onto the drone's RigidBody3D when the hook latches (see
## drone_payload.gd). Carried, it stops colliding: a frozen kinematic body accepts no force
## back, so a clipped crate would otherwise shove a wall instead of passing through it.

## Freed at _ready: a static collider inside a rigid body is a body that cannot move.
const Groups := preload("res://src/levels/base/carlito_groups.gd")
const DEV_COLLISION := ^"Box/DevCollision"

## Set by the drone's hook; the crate itself never decides anything.
var carried := false
## Authored collision layers, restored on release (not re-typed as 1 — a payload's own layer must come back).
var _layer := 1
var _mask := 1


## Tagged for the drone's capture ray, which asks what it hit and must not depend on this class.
func _init() -> void:
	add_to_group(Groups.PAYLOAD)


func _ready() -> void:
	_layer = collision_layer
	_mask = collision_mask
	var dev := get_node_or_null(DEV_COLLISION)
	if dev != null:
		dev.queue_free()


## Rides the hook: frozen kinematic and out of the collision world (see header). Reparenting
## keeps one crate rather than hiding it and drawing a copy.
func attach_to(hook: Node3D, hang: Vector3) -> void:
	if carried:
		return
	carried = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	get_parent().remove_child(self)
	hook.add_child(self)
	transform = Transform3D(Basis.IDENTITY, hang)
	_set_colliding(false)


## Drops it back into the level at its carried pose, with the carrier's velocity so it keeps going.
func detach_to(level: Node, carrier_velocity: Vector3) -> void:
	if not carried:
		return
	carried = false
	var world := global_transform
	get_parent().remove_child(self)
	level.add_child(self)
	global_transform = world
	freeze = false
	_set_colliding(true)
	linear_velocity = carrier_velocity
	angular_velocity = Vector3.ZERO


func _set_colliding(on: bool) -> void:
	collision_layer = _layer if on else 0
	collision_mask = _mask if on else 0

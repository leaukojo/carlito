class_name FamilyContent
extends Node3D
## Level content that is there only while one of `families` is driven (Flatland's drone crates).
## On any other body its children leave the tree; on a matching spawn, and on that body's every
## respawn, they come back at their authored poses, a crate the drone left elsewhere in the level
## included: a respawn starts over, crates and all.
## Hooked to `Level.vehicle_changed`, which fires after a swap has handed a carried crate back, and
## to the body's `respawned`, which fires after the drone's own `respawn` has dropped one.

@export var families := PackedStringArray()

var _items: Array[Node3D] = []
var _poses: Array[Transform3D] = []
var _level: Level
var _present := false


## Runs before the level's own `_ready`, so the first spawn's `vehicle_changed` is heard.
func _ready() -> void:
	for child in get_children():
		if child is Node3D:
			_items.append(child as Node3D)
			_poses.append((child as Node3D).transform)
	var node := get_parent()
	while node != null and not node is Level:
		node = node.get_parent()
	_level = node as Level
	if _level != null:
		_level.vehicle_changed.connect(_on_vehicle_changed)


## The outgoing body is freed with its connection, so each matching spawn connects its own.
func _on_vehicle_changed(family: String) -> void:
	_present = families.has(family)
	_place()
	if _present and _level.vehicle != null and not _level.vehicle.respawned.is_connected(_place):
		_level.vehicle.respawned.connect(_place)


## Every item out of wherever it is, and back at its authored pose while a family is driven.
func _place() -> void:
	for i in _items.size():
		var item := _items[i]
		if not is_instance_valid(item):
			continue
		if item.get_parent() != null:
			item.get_parent().remove_child(item)
		if not _present:
			continue
		add_child(item)
		item.transform = _poses[i]
		if item is RigidBody3D:
			(item as RigidBody3D).linear_velocity = Vector3.ZERO
			(item as RigidBody3D).angular_velocity = Vector3.ZERO
		item.reset_physics_interpolation()


## Items out of the tree belong to nobody else: free them with this node.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for item in _items:
			if is_instance_valid(item) and item.get_parent() == null:
				item.free()

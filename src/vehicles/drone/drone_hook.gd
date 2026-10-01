class_name DroneHook
extends RefCounted
## The cargo hook: the marker it hangs from, the crate on it, and the latch. Ticked by DroneVehicle;
## DronePayload holds the law. This casts the capture ray and reparents the crate. The mass write
## stays on DroneVehicle: `tick` only reports that the latch changed.

const Layers := preload("res://src/physics/collision_layers.gd")
const Groups := preload("res://src/levels/base/carlito_groups.gd")

## How far each jaw swings out from shut, degrees. Drawn only: the latch is `latched`.
const JAW_OPEN_DEG := 40.0

## The scene's Hardpoint marker, or null on an airframe with none (the hook never catches).
var _marker: Node3D = null
## The optional jaws under the marker, and each one's shut pose as the scene authors it.
var _jaws: Array[Node3D] = []
var _jaw_rest: Array[Basis] = []
## The CargoPayload riding the hook, or null.
var _payload: Node = null
## The latch, published as contract `hardpoint_state`.
var latched := false
## Blocks a capture until `cmd` is seen low once. Set on `reset()`: InputRouter's hardpoint toggle
## survives a respawn (like `node_fail`'s) and the dropped crate lands under the hook, so without
## this the next tick recaptures it.
var _await_release := false


func _init(body: Node) -> void:
	_marker = body.get_node_or_null(^"Hardpoint") as Node3D
	for path: NodePath in [^"Hardpoint/JawL", ^"Hardpoint/JawR"]:
		var jaw := body.get_node_or_null(path) as Node3D
		if jaw != null:
			_jaws.append(jaw)
			_jaw_rest.append(jaw.transform.basis)
	_pose_jaws()


## One tick. Returns true if the latch changed (the vehicle's cue to re-derive the mass). The ray
## is cast only for a HOLD command with the latch open, so ordinary flight costs no raycast.
func tick(cmd: bool, space: PhysicsDirectSpaceState3D, body: RigidBody3D) -> bool:
	if _marker == null:
		return false
	if _payload != null and not is_instance_valid(_payload):
		# Freed out from under the hook (not through _drop/reset): forget it, never deref it.
		_payload = null
		latched = false
		_pose_jaws()
		return true
	if _await_release:
		if cmd:
			return false
		_await_release = false
	var found: Node = _find(space, body) if (cmd and not latched) else null
	var was := latched
	latched = DronePayload.latched(cmd, was, found != null)
	if latched == was:
		return false
	_pose_jaws()
	if latched and found != null:
		_payload = found
		# Hung by its top face: the crate's own height is the whole offset.
		found.call("attach_to", _marker, Vector3(0.0, -_height_of(found), 0.0))
	elif _payload != null:
		_drop(body, body.linear_velocity)
	return true


## The mass on the hook (kg), or 0 with nothing on it (or a payload freed out from under it).
func payload_mass() -> float:
	if _payload != null and not is_instance_valid(_payload):
		_payload = null
	return float(_payload.mass) if _payload != null else 0.0


## The hook in the body's frame: the point a payload's weight acts through. Body origin with no
## marker (no lever).
func hook_local() -> Vector3:
	return _marker.position if _marker != null else Vector3.ZERO


## Opens the hook and leaves the crate behind at its carried pose, at rest (a payload teleporting
## with the aircraft would be cargo delivered by respawning).
func reset(body: RigidBody3D) -> void:
	if _payload != null and not is_instance_valid(_payload):
		_payload = null
	if _payload != null:
		_drop(body, Vector3.ZERO)
	latched = false
	# A held HOLD command must be released before it can capture again (`_await_release`).
	_await_release = true
	_pose_jaws()


## Jaws shut on a closed latch, swung open otherwise, each about its own hinge (z). The right jaw is
## the left one turned half round, so one angle opens both outward.
func _pose_jaws() -> void:
	var swing := Basis(Vector3.BACK, 0.0 if latched else -deg_to_rad(JAW_OPEN_DEG))
	for i in _jaws.size():
		_jaws[i].transform.basis = _jaw_rest[i] * swing


## Hands the crate back to the level (the body's parent) with a velocity, and forgets it.
func _drop(body: RigidBody3D, velocity: Vector3) -> void:
	var dropped := _payload
	_payload = null
	dropped.call("detach_to", body.get_parent(), velocity)


## The payload under the hook, or null. Selected by group (root CLAUDE.md § Scene tags). The ray
## masks SOLID, not the payload alone, so the hook cannot reach a crate through a floor.
func _find(space: PhysicsDirectSpaceState3D, body: RigidBody3D) -> Node:
	if space == null or _marker == null:
		return null
	var from := _marker.global_position
	var query := PhysicsRayQueryParameters3D.create(
			from, from + Vector3.DOWN * DronePayload.CAPTURE_RANGE, Layers.SOLID, [body.get_rid()])
	var hit := space.intersect_ray(query)
	var collider: Variant = hit.get("collider")
	if collider is Node and (collider as Node).is_in_group(Groups.PAYLOAD):
		var found := collider as Node
		# A CAPTURE refusal, not a mass truncation: an over-MAX_PAYLOAD_KG crate on the hook would
		# make the felt mass disagree with what hangs there.
		if float(found.mass) > DronePayload.MAX_PAYLOAD_KG:
			return null
		return found
	return null


## A payload's height (m), measured off its collision shape (1.0 if it is not a box).
static func _height_of(payload: Node) -> float:
	var shape := payload.get_node_or_null(^"Shape") as CollisionShape3D
	if shape != null and shape.shape is BoxShape3D:
		return (shape.shape as BoxShape3D).size.y
	return 1.0

class_name DroneHook
extends RefCounted
## The cargo hook: the marker it hangs from, the crate on it, and the latch. Owned and ticked by
## DroneVehicle, while DronePayload holds the law. This binds the marker, casts the capture ray and
## reparents the crate. The mass write onto the aircraft stays on DroneVehicle, so `tick` only
## reports that the latch changed.

const Layers := preload("res://src/physics/collision_layers.gd")
const Groups := preload("res://src/levels/base/carlito_groups.gd")

## How far each jaw swings out from shut, degrees. Drawn only: the latch is `latched`.
const JAW_OPEN_DEG := 40.0

## The scene's Hardpoint marker, or null on an airframe with none — the hook simply never catches.
var _marker: Node3D = null
## The optional jaws under the marker, and each one's shut pose as the scene authors it.
var _jaws: Array[Node3D] = []
var _jaw_rest: Array[Basis] = []
## The CargoPayload riding the hook, or null.
var _payload: Node = null
## The latch, published as contract `hardpoint_state`.
var latched := false


func _init(body: Node) -> void:
	_marker = body.get_node_or_null(^"Hardpoint") as Node3D
	for path: NodePath in [^"Hardpoint/JawL", ^"Hardpoint/JawR"]:
		var jaw := body.get_node_or_null(path) as Node3D
		if jaw != null:
			_jaws.append(jaw)
			_jaw_rest.append(jaw.transform.basis)
	_pose_jaws()


## One tick. Returns true if the latch changed, which is the vehicle's cue to re-derive the mass.
## The ray is cast only when it could change anything, a HOLD command with the latch still open, so
## ordinary flight costs no extra raycast.
func tick(cmd: bool, space: PhysicsDirectSpaceState3D, body: RigidBody3D) -> bool:
	if _marker == null:
		return false
	var found: Node = _find(space, body) if (cmd and not latched) else null
	var was := latched
	latched = DronePayload.latched(cmd, was, found != null)
	if latched == was:
		return false
	_pose_jaws()
	if latched and found != null:
		_payload = found
		# Hung by its top face: the crate's own height is the whole offset, so a taller payload
		# hangs lower without anything here knowing its shape.
		found.call("attach_to", _marker, Vector3(0.0, -_height_of(found), 0.0))
	elif _payload != null:
		_drop(body, body.linear_velocity)
	return true


## The mass on the hook (kg), or 0 with nothing on it.
func payload_mass() -> float:
	return float(_payload.mass) if _payload != null else 0.0


## Where the hook is in the body's own frame, the point a payload's weight acts through. It falls
## back to the body origin with no marker, the same "no lever" the empty aircraft has.
func hook_local() -> Vector3:
	return _marker.position if _marker != null else Vector3.ZERO


## A respawn opens the hook and leaves the crate behind at its carried pose with no velocity: a
## payload teleporting with the aircraft would be cargo delivered by respawning.
func reset(body: RigidBody3D) -> void:
	if _payload != null:
		_drop(body, Vector3.ZERO)
	latched = false
	_pose_jaws()


## Jaws shut on a closed latch and swung open otherwise, each about its own hinge (z). The right jaw
## is the left one turned half round, so one angle opens both outward.
func _pose_jaws() -> void:
	var swing := Basis(Vector3.BACK, 0.0 if latched else -deg_to_rad(JAW_OPEN_DEG))
	for i in _jaws.size():
		_jaws[i].transform.basis = _jaw_rest[i] * swing


## Hand the crate back to the level (the body's own parent) with a velocity, and forget it.
func _drop(body: RigidBody3D, velocity: Vector3) -> void:
	var dropped := _payload
	_payload = null
	dropped.call("detach_to", body.get_parent(), velocity)


## The payload under the hook, or null. Selected by group rather than class, the kit rule: a
## headless run with a cold class_name cache would otherwise see a hook that never catches. The ray
## masks SOLID rather than the payload alone, taking the first hit and asking whether it was a
## crate, so ground stays in the mask and the hook cannot reach a crate through a floor.
func _find(space: PhysicsDirectSpaceState3D, body: RigidBody3D) -> Node:
	if space == null or _marker == null:
		return null
	var from := _marker.global_position
	var query := PhysicsRayQueryParameters3D.create(
			from, from + Vector3.DOWN * DronePayload.CAPTURE_RANGE, Layers.SOLID, [body.get_rid()])
	var hit := space.intersect_ray(query)
	var collider: Variant = hit.get("collider")
	if collider is Node and (collider as Node).is_in_group(Groups.PAYLOAD):
		return collider as Node
	return null


## A payload's own height (m), measured off its collision shape rather than declared, so the hang
## offset follows the crate instead of a constant a differently-sized payload would break.
static func _height_of(payload: Node) -> float:
	var shape := payload.get_node_or_null(^"Shape") as CollisionShape3D
	if shape != null and shape.shape is BoxShape3D:
		return (shape.shape as BoxShape3D).size.y
	return 1.0

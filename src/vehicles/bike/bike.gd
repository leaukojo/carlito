class_name BikeVehicle
extends BaseVehicle
## Motorcycle. Arcade lean via the narrow-track four-wheel trick: the spec gives it four
## invisible physics wheels in a narrow track, so it stays a plain BaseVehicle — every 60
## Hz RayWheel clamp is untouched and the FL/FR-steer + RL/RR-handbrake semantics keep
## working. A real two-wheel balance sim is explicitly out of scope.
##
## Everything visible about the "bike-ness" — the leaning body and the two spinning wheels
## — is pure visual work done in _tick_extras (never a _physics_process fork). The lean is
## an HONEST model: the SAME value we tilt the body by is what BikeTelemetry publishes as
## the contract 'lean' signal (physics body stays upright; only the Body node leans).

## Lean model constants (feel knobs — data-adjacent, tuned by driving in Phase 3).
const LEAN_MAX_DEG := 48.0          ## visual + telemetry clamp; matches the contract 'lean' warn
const LEAN_GRAVITY := 9.81          ## m/s^2 used to turn lateral g into a lean angle
const LEAN_STEER_GAIN := 15.0       ## extra deg of lean per unit steer at/above the speed ref
const LEAN_STEER_SPEED_REF := 12.0  ## m/s at which the steer term reaches full gain
const LEAN_SLEW_DEG := 160.0        ## deg/s the visual/telemetry lean slews toward its target
const WHEEL_VISUAL_RADIUS := 0.33   ## fallback if the wheel mesh isn't a CylinderMesh; real value read from the mesh in _ready

@export var body_path: NodePath = ^"Body"
@export var wheel_front_path: NodePath = ^"Body/WheelFront"
@export var wheel_rear_path: NodePath = ^"Body/WheelRear"
@export var collision_path: NodePath = ^"CollisionShape3D"

var _lean_deg := 0.0        ## current applied lean, + = right (published verbatim as 'lean')
var _front_spin := 0.0      ## accumulated front-wheel spin angle (rad)
var _rear_spin := 0.0       ## accumulated rear-wheel spin angle (rad)
var _body: Node3D
var _wheel_front: Node3D
var _wheel_rear: Node3D
var _collision: Node3D
var _collision_rest: Transform3D  ## authored collision transform; the lean is applied on top
var _body_rest: Basis       ## authored body basis; lean is applied relative to it
var _wf_rest_pos: Vector3   ## authored front-wheel position; only its Y is driven each tick
var _wr_rest_pos: Vector3   ## authored rear-wheel position; only its Y is driven each tick
var _wheel_visual_radius := WHEEL_VISUAL_RADIUS  ## read from the wheel CylinderMesh in _ready


func _make_telemetry() -> VehicleTelemetry:
	return BikeTelemetry.new()


func _ready() -> void:
	super._ready()
	_body = get_node_or_null(body_path) as Node3D
	_wheel_front = get_node_or_null(wheel_front_path) as Node3D
	_wheel_rear = get_node_or_null(wheel_rear_path) as Node3D
	_collision = get_node_or_null(collision_path) as Node3D
	if _body != null:
		_body_rest = _body.transform.basis
	if _collision != null:
		_collision_rest = _collision.transform
	if _wheel_front != null:
		_wf_rest_pos = _wheel_front.position
	if _wheel_rear != null:
		_wr_rest_pos = _wheel_rear.position
	# Sit the tyre on the road using the ACTUAL mesh radius so a mesh/variant change can't
	# silently make the wheels float or sink (prefer front, fall back to rear, then the const).
	var mesh_radius := _wheel_mesh_radius(_wheel_front)
	if mesh_radius <= 0.0:
		mesh_radius = _wheel_mesh_radius(_wheel_rear)
	if mesh_radius > 0.0:
		_wheel_visual_radius = mesh_radius


func _tick_extras(_input: InputRouter.VehicleInput, delta: float) -> void:
	var t := telemetry as BikeTelemetry
	# telemetry.acc_lat / .speed were refreshed by _update_telemetry earlier this tick. Lean
	# only while grounded — an airborne or spun-out bike returns upright so the leaned body
	# can't clip through the terrain (which reads as the bike "sinking into the road").
	var lean_goal := lean_target_deg(telemetry.acc_lat, telemetry.speed, _steer) if telemetry.ground else 0.0
	_lean_deg = move_toward(_lean_deg, lean_goal, LEAN_SLEW_DEG * delta)
	t.lean = _lean_deg

	# Visual body lean: rotate about local FORWARD (-Z) so a POSITIVE angle tips the top to the
	# right (+X). The rotation pivots about the tyre-contact LINE (ground level), not the
	# axle-height Body origin, so the whole bike — body, forks and wheels (its children) — tips
	# as one rigid unit and the contacts stay planted; pivoting about the origin instead swings
	# the wheels out from under the leaning body and reads as them detaching. Body is authored at
	# identity, so rotating about pivot p is basis*p folded into the origin. Physics body stays
	# upright — this touches the Body node only.
	var lean_basis := Basis(Vector3.FORWARD, deg_to_rad(_lean_deg))
	var pivot := Vector3(0.0, _ground_contact_y(), 0.0)
	var lean_xform := Transform3D(lean_basis, pivot - lean_basis * pivot)
	if _body != null:
		_body.transform = lean_xform * Transform3D(_body_rest, Vector3.ZERO)
	# Keep the chassis collision tipped with the visual so it doesn't read as detached.
	if _collision != null:
		_collision.transform = lean_xform * _collision_rest

	# Visual wheels: front yaws with the applied (speed-scaled) steer exactly like the physics
	# wheels, both spin from the RayWheel omega they ride (read from the sim, not derived), and
	# both are dropped onto the ground from the live suspension compression so they never float.
	# The wheels are children of the leaning Body and simply ride its contact-line lean, so no
	# per-wheel lean compensation is needed. Full transform is rebuilt each tick.
	_front_spin = wrapf(_front_spin + _axle_omega(false) * delta, 0.0, TAU)
	_rear_spin = wrapf(_rear_spin + _axle_omega(true) * delta, 0.0, TAU)
	if _wheel_front != null:
		_wheel_front.transform = Transform3D(
				Basis(Vector3.UP, _applied_steer) * Basis(Vector3.RIGHT, _front_spin),
				_wheel_contact(_wf_rest_pos, false) + Vector3.UP * _wheel_visual_radius)
	if _wheel_rear != null:
		_wheel_rear.transform = Transform3D(
				Basis(Vector3.RIGHT, _rear_spin),
				_wheel_contact(_wr_rest_pos, true) + Vector3.UP * _wheel_visual_radius)


## Mean wheel omega for one axle (rear = the two RL/RR wheels, front = FL/FR).
func _axle_omega(rear: bool) -> float:
	var sum := 0.0
	var count := 0
	for w in wheels:
		if w.is_rear == rear:
			sum += w.omega
			count += 1
	return sum / maxi(1, count)


## Mean live suspension compression for one axle (m).
func _axle_compression(rear: bool) -> float:
	var sum := 0.0
	var count := 0
	for w in wheels:
		if w.is_rear == rear:
			sum += w.compression
			count += 1
	return sum / maxi(1, count)


## Body-rest ground-contact point under a visual wheel: the physics contact (hub minus the
## compressed suspension travel), at the authored X/Z. The caller raises it by the visual
## radius to seat the tyre, so the wheel tracks suspension travel instead of floating.
func _wheel_contact(rest_pos: Vector3, rear: bool) -> Vector3:
	var anchor_y: float = spec.wheel_positions[2 if rear else 0].y
	var contact_y := anchor_y - (spec.rest_length + spec.wheel_radius - _axle_compression(rear))
	return Vector3(rest_pos.x, contact_y, rest_pos.z)


## Mean ground-contact height (body-local Y) of the two axles — the pivot line the body leans
## about so the tyres stay planted.
func _ground_contact_y() -> float:
	return (_wheel_contact(_wf_rest_pos, false).y + _wheel_contact(_wr_rest_pos, true).y) * 0.5


## Radius of a wheel node's CylinderMesh child (0.0 if the mesh isn't a CylinderMesh).
func _wheel_mesh_radius(wheel: Node3D) -> float:
	if wheel == null:
		return 0.0
	var mesh_node := wheel.get_node_or_null(^"Mesh") as MeshInstance3D
	if mesh_node == null:
		return 0.0
	var cylinder := mesh_node.mesh as CylinderMesh
	return cylinder.top_radius if cylinder != null else 0.0


## Arcade lean target in degrees (pure -> unit-tested): lateral g turned into a lean angle
## (the bike leans INTO the turn), plus a speed-scaled steer term so lean reads even before
## lateral g builds. + = leaning right. Clamped to +/- LEAN_MAX_DEG.
static func lean_target_deg(acc_lat: float, speed: float, steer: float) -> float:
	var from_accel := rad_to_deg(atan2(acc_lat, LEAN_GRAVITY))
	var speed_frac := clampf(absf(speed) / LEAN_STEER_SPEED_REF, 0.0, 1.0)
	var from_steer := steer * LEAN_STEER_GAIN * speed_frac
	return clampf(from_accel + from_steer, -LEAN_MAX_DEG, LEAN_MAX_DEG)


## Re-center the lean on respawn so a teleport doesn't leave the body cocked over.
func respawn() -> void:
	super.respawn()
	_lean_deg = 0.0
	if telemetry != null:
		(telemetry as BikeTelemetry).lean = 0.0
	if _body != null:
		_body.transform = Transform3D(_body_rest, Vector3.ZERO)
	if _collision != null:
		_collision.transform = _collision_rest

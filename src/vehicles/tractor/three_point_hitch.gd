class_name ThreePointHitch
extends Node3D
## Tractor anatomy: rear linkage (draft links, rockshaft, lift rods, top link) posed by
## HitchLinkage; PTO stub (6-spline, one painted); implement attach/detach. Solver works in
## planar Vector2(z, y); every pivot on local +Z. Pose: `rotation.x = -planar_angle`. Draft at
## chassis hitch point, not via colliders.

const Layers := preload("res://src/physics/collision_layers.gd")

## Top-link angle (degrees) while detached: parks instead of tracking a missing pin.
const DETACHED_TOP_ANGLE_DEG := 4.0

## Metres above a support point its ground ray starts: the most ground the drawn implement can
## float onto, about the balls' 0.57 m rise over the stroke.
const FLOAT_REACH := 0.6

## Natural frequencies (rad/s) of the critically damped follower the drawn float chases its ground
## contact with: the implement's mass on the soil's give. Without it the drawn implement copies
## every heightmap facet in a tick and lands on its bottom stop dead. UP while the support is under
## its contact (the ground pushes: stiff, so it sinks little), DOWN while above it (it settles
## under its weight: soft, so it lands gently). ESTIMATES, picked off a scratch probe over the
## rough-ground bump fields; ω·dt must stay under ~0.8 at 60 Hz (60 rings).
const FLOAT_OMEGA_UP := 40.0
const FLOAT_OMEGA_DOWN := 15.0

## Lower-link / rockshaft-arm pivot spacing (m), applied in _ready to both together.
@export var lower_link_x := 0.19

@onready var _lower_links: Array[Node3D] = [$LowerLinkL, $LowerLinkR]
@onready var _rock_arms: Array[Node3D] = [$RockArmL, $RockArmR]
@onready var _lift_rods: Array[Node3D] = [$LiftRodL, $LiftRodR]
@onready var _top_link: Node3D = $TopLink
@onready var _pto_stub: Node3D = $PtoStub
@onready var _mount: Node3D = $Mount

var implement: ImplementBase = null  ## null while detached

var _linkage := HitchLinkage.new()
## Fallback A-frame with nothing attached, captured before any implement overwrites it.
var _bare_mast_offset := _linkage.mast_offset
var _pto_on := false
var _pto_rpm := 0
var _pos01 := 1.0  ## last solved hitch position, for attach/detach re-pose
var _ball_y := 0.0          ## last solved ball height (body space), the physics pose's
## Mount's transform in the physics (commanded) pose; the node itself carries the drawn pose.
var _mount_physics := Transform3D.IDENTITY
var _ball_y_lowered := 0.0  ## ball height at pos01 = 0, ball_lift's datum
var _drawn := 1.0           ## drawn pose's pos01, at or above the commanded one
var _drawn_rate := 0.0      ## its rate (1/s), the follower's state


func _ready() -> void:
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_lower_links[i].position.x = side * lower_link_x
		_rock_arms[i].position.x = side * lower_link_x
	# Ball ends ride the lower links alone (the A-frame only enters the top-link solve), so this
	# datum is a constant of the tractor.
	_ball_y_lowered = (_linkage.solve(0.0)["ball"] as Vector2).y
	set_hitch(1.0)  # spawn raised (transport), matching TractorVehicle.SPAWN_HITCH
	# Mount is excluded: attach() merges whatever lands there against that implement's own skip list.
	StaticMeshMerge.merge_subtree(self, [_mount])


## Instance `scene` on the linkage, replacing whatever was attached; an unloadable scene leaves
## the hitch detached.
func attach(scene: PackedScene) -> void:
	detach()
	if scene == null:
		return
	var instanced := scene.instantiate()
	var node := instanced as ImplementBase
	if node == null:
		push_error("ThreePointHitch: '%s' is not an ImplementBase" % scene.resource_path)
		instanced.queue_free()  # nothing else references it
		return
	implement = node
	_linkage.mast_offset = node.mast_offset()
	_mount.add_child(node)
	# static_merge_skip() names the nodes StaticMeshMerge must leave individual.
	StaticMeshMerge.merge_subtree(node, node.static_merge_skip())
	set_hitch(_pos01)  # re-solve against the new A-frame before it is drawn


func detach() -> void:
	if implement != null:
		# Unparent before queue_free (end-of-frame), or an attach() right after would stack on it.
		_mount.remove_child(implement)
		implement.queue_free()
		implement = null
	_linkage.mast_offset = _bare_mast_offset
	set_hitch(_pos01)


## pos01 in [0, 1]: 1 = fully raised (transport), 0 = fully lowered (working). Poses every part.
## Two poses: the physics pose is the commanded solve, which ball_lift(), hitch_point() and
## implement_com() read; the drawn pose floats the implement onto its supports (_float_pos).
## `delta` > 0 (the physics tick) moves the drawn pose by the FLOAT_OMEGA_UP / _DOWN follower;
## 0 snaps it there.
func set_hitch(pos01: float, delta := 0.0) -> void:
	_pos01 = pos01
	var s := _linkage.solve(pos01)
	_ball_y = (s["ball"] as Vector2).y
	_mount_physics = _mount_pose(s)
	var target := _float_pos(pos01)
	if delta > 0.0:
		# Semi-implicit, critically damped on either side of the contact it chases.
		var w := FLOAT_OMEGA_UP if target > _drawn else FLOAT_OMEGA_DOWN
		_drawn_rate += (w * w * (target - _drawn) - 2.0 * w * _drawn_rate) * delta
		_drawn += _drawn_rate * delta
	else:
		_drawn = target
		_drawn_rate = 0.0
	# Never under the commanded pose (the linkage's stop), never past fully raised.
	if _drawn <= pos01:
		_drawn = pos01
		_drawn_rate = maxf(_drawn_rate, 0.0)
	elif _drawn >= 1.0:
		_drawn = 1.0
		_drawn_rate = minf(_drawn_rate, 0.0)
	_pose(s if _drawn == pos01 else _linkage.solve(_drawn))
	if implement != null:
		implement.set_hitch(_drawn)


## Mount rides the ball ends and carries the solved pitch; the implement is authored lowered, about
## the lower pin line (Mount's origin).
func _mount_pose(s: Dictionary) -> Transform3D:
	var ball: Vector2 = s["ball"]
	return Transform3D(Basis.from_euler(Vector3(-float(s["pitch"]), 0.0, 0.0)),
			Vector3(0.0, ball.y, ball.x))


## The drawn pose: a real linkage in float lets its support ride the ground. One ray per support
## point along the body's down axis, cast only while the commanded lift is inside the support's
## reach, so a raised implement never floats; no physics space or no hit floats nothing.
## COMPROMISE: physics reads the commanded pose on flat ground. Riding its support, an implement
## works at its drawn depth relative to the ground it rides, which is what that pose reports, so a
## float lift moves no weight and no draft depth. A dip under the support leaves the implement
## hanging at its stop. Undoing it means the mass fold-in and draft read the ground under the
## implement: these rays feed physics, and every hitch / plough figure is re-measured.
func _float_pos(pos01: float) -> float:
	if implement == null or not is_inside_tree() or ball_lift() > implement.support_lift():
		return pos01
	var points := implement.support_points()
	if points.is_empty():
		return pos01
	var space := get_world_3d().direct_space_state
	if space == null:
		return pos01
	var body := get_parent() as CollisionObject3D
	var exclude: Array[RID] = []
	if body != null:
		exclude.append(body.get_rid())
	var xf := global_transform
	var to_hitch := xf.affine_inverse()
	var posed := _mount_physics * implement.transform
	var supports := PackedVector3Array()   # implement frame
	var ground_y := PackedFloat32Array()   # this frame, under each support
	for p in points:
		var at := posed * p
		var query := PhysicsRayQueryParameters3D.create(
				xf * (at + Vector3.UP * FLOAT_REACH), xf * at, Layers.SOLID, exclude)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			supports.append(p)
			ground_y.append((to_hitch * (hit["position"] as Vector3)).y)
	if supports.is_empty():
		return pos01
	var clearance := func(sol: Dictionary) -> float:
		var drawn := _mount_pose(sol) * implement.transform
		var least := INF
		for i in supports.size():
			least = minf(least, (drawn * supports[i]).y - ground_y[i])
		return least
	return _linkage.float_pos(pos01, clearance)


## Pose every drawn part off solve `s`.
func _pose(s: Dictionary) -> void:
	var lower_rot := -float(s["lower_angle"])
	var rock_rot := -float(s["rock_angle"])
	var rod_rot := -((s["rod_attach"] as Vector2) - (s["rod_end"] as Vector2)).angle()
	var rod_end: Vector2 = s["rod_end"]
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_lower_links[i].rotation.x = lower_rot
		_rock_arms[i].rotation.x = rock_rot
		_lift_rods[i].position = Vector3(side * lower_link_x, rod_end.y, rod_end.x)
		_lift_rods[i].rotation.x = rod_rot

	# Detached: park the top link, no implement pin to follow.
	_top_link.rotation.x = -float(s["top_angle"]) if implement != null \
			else -deg_to_rad(DETACHED_TOP_ANGLE_DEG)

	var ball: Vector2 = s["ball"]
	_mount.position = Vector3(0.0, ball.y, ball.x)
	_mount.rotation.x = -float(s["pitch"])


## Metres the lower-link balls sit above their fully-lowered height: the implement's lift. Balls
## rise 0.57 m over the stroke while a plough share reaches 0.25 m, so shares clear the soil at
## ~43 % of the stroke.
func ball_lift() -> float:
	return _ball_y - _ball_y_lowered


## World-space ball line in the physics pose: where draft force is applied to the chassis (the
## implement subtree has no collision).
func hitch_point() -> Vector3:
	return global_transform * _mount_physics.origin


## The posed implement's centre of mass in the tractor's body space (this node's parent frame), or
## Vector3.INF with nothing attached. Composed off local transforms, so it is pose-independent.
func implement_com() -> Vector3:
	if implement == null:
		return Vector3.INF
	return transform * (_mount_physics * (implement.transform * implement.mass_centre()))


## Store PTO state; the stub shaft spins in _process at the real shaft rpm.
func set_pto(on: bool, rpm: int) -> void:
	_pto_on = on
	_pto_rpm = rpm
	if implement == null:
		return
	# Gated here, not per subclass: only an implement declaring Connection.PTO is driven.
	var driven := implement.uses(ImplementBase.Connection.PTO)
	implement.set_pto(on and driven, rpm if driven else 0)


## Hand the remote hydraulic flow (0..1) down the linkage. Gated like the PTO: no Connection.SCV
## reads a shut valve.
func set_scv(flow01: float) -> void:
	if implement == null:
		return
	var plumbed := implement.uses(ImplementBase.Connection.SCV)
	implement.set_scv(flow01 if plumbed else 0.0)


func _process(delta: float) -> void:
	# The stub points straight back along the tractor's local Z.
	if _pto_on and _pto_stub != null:
		_pto_stub.rotate_z(float(_pto_rpm) / 60.0 * TAU * delta)

class_name ThreePointHitch
extends Node3D
## Tractor anatomy: rear linkage (draft links, rockshaft, lift rods, top link) posed by
## HitchLinkage; PTO stub (6-spline, one painted); implement attach/detach. Solver works in
## planar Vector2(z, y); every pivot on local +Z. Pose: `rotation.x = -planar_angle`. Draft at
## chassis hitch point, not via colliders.

## Top-link angle (degrees) while detached: parks instead of tracking a missing pin; lower
## links/rockshaft articulate.
const DETACHED_TOP_ANGLE_DEG := 4.0

## Lower-link / rockshaft-arm pivot spacing (m), applied in _ready so widening it moves the whole
## linkage rather than pulling the lift rods off their arms.
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
var _ball_y := 0.0          ## last solved ball height (body space)
var _ball_y_lowered := 0.0  ## ball height at pos01 = 0, ball_lift's datum


func _ready() -> void:
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_lower_links[i].position.x = side * lower_link_x
		_rock_arms[i].position.x = side * lower_link_x
	# Ball ends ride the lower links alone (A-frame only enters the top-link solve), so this datum
	# is a constant of the tractor, solved once.
	_ball_y_lowered = (_linkage.solve(0.0)["ball"] as Vector2).y
	set_hitch(1.0)  # spawn raised (transport), matching TractorVehicle.SPAWN_HITCH


## Instance `scene` on the linkage. Replaces whatever was attached; an unloadable scene leaves the
## hitch detached rather than half-attached.
func attach(scene: PackedScene) -> void:
	detach()
	if scene == null:
		return
	var instanced := scene.instantiate()
	var node := instanced as ImplementBase
	if node == null:
		push_error("ThreePointHitch: '%s' is not an ImplementBase" % scene.resource_path)
		instanced.queue_free()  # nothing else references it — don't leak the orphan
		return
	implement = node
	_linkage.mast_offset = node.mast_offset()
	_mount.add_child(node)
	set_hitch(_pos01)  # re-solve against the new A-frame before it is drawn


func detach() -> void:
	if implement != null:
		# Unparent before queue_free (lands end-of-frame): an attach() right after detach() would
		# otherwise stack the new implement on the outgoing one.
		_mount.remove_child(implement)
		implement.queue_free()
		implement = null
	_linkage.mast_offset = _bare_mast_offset
	set_hitch(_pos01)


## pos01 in [0, 1]: 1 = fully raised (transport), 0 = fully lowered (working). Solves the
## whole linkage and poses every part from it.
func set_hitch(pos01: float) -> void:
	_pos01 = pos01
	var s := _linkage.solve(pos01)
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

	# Mount rides the ball ends and carries the solved pitch; the implement is authored in its
	# lowered pose about the lower pin line, exactly this node's origin.
	var ball: Vector2 = s["ball"]
	_ball_y = ball.y
	_mount.position = Vector3(0.0, ball.y, ball.x)
	_mount.rotation.x = -float(s["pitch"])

	if implement != null:
		implement.set_hitch(pos01)


## Metres the lower-link balls sit above their fully-lowered height — the implement's lift, i.e.
## how deep its tools still are. Balls rise 0.57 m over the stroke while a plough share reaches
## only 55 mm below ground, so shares clear the soil after the first tenth of the stroke.
func ball_lift() -> float:
	return _ball_y - _ball_y_lowered


## World-space ball line: where the implement hangs and where draft force is applied to the
## chassis (never on the implement — that subtree has no collision).
func hitch_point() -> Vector3:
	return _mount.global_position


## Store PTO state; the stub shaft spins in _process at the tractor's real shaft rpm.
func set_pto(on: bool, rpm: int) -> void:
	_pto_on = on
	_pto_rpm = rpm
	if implement == null:
		return
	# Only an implement that declares a PTO connection is actually driven; gating here (not
	# trusting each subclass) is what makes Connection.PTO real.
	var driven := implement.uses(ImplementBase.Connection.PTO)
	implement.set_pto(on and driven, rpm if driven else 0)


## Hand the tractor's remote hydraulic flow (0..1) down the linkage. Gated like the PTO: an
## implement without Connection.SCV reads a shut valve regardless of spool position.
func set_scv(flow01: float) -> void:
	if implement == null:
		return
	var plumbed := implement.uses(ImplementBase.Connection.SCV)
	implement.set_scv(flow01 if plumbed else 0.0)


func _process(delta: float) -> void:
	# The stub's axis is the tractor's local Z (it points straight back), so this is rotate_z.
	if _pto_on and _pto_stub != null:
		_pto_stub.rotate_z(float(_pto_rpm) / 60.0 * TAU * delta)

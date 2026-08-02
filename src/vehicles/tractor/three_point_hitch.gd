class_name ThreePointHitch
extends Node3D
## The tractor's rear three-point linkage and PTO stub shaft — tractor ANATOMY, so it lives
## on the tractor, not on the implement, and it stays whole when nothing is attached.
##
## It owns three things:
##   1. the articulating linkage — two lower draft links, the rockshaft arms above them, the
##      rigid lift rods between the two, and the top link. Every angle comes out of
##      HitchLinkage's four-bar solve, so the parts stay pinned to each other and the
##      implement's pitch is a CONSEQUENCE of the geometry rather than a second animation;
##   2. the PTO stub shaft under its guard, spun at the shaft speed the tractor reports. It
##      is modelled as a real 6-spline 540 shaft rather than a smooth cylinder, and ONE
##      spline is painted — a plain round shaft is rotationally symmetric, so from the chase
##      camera it reads as standing still no matter how fast it turns;
##   3. the attach/detach point. Attaching is a logical ISOBUS address claim — the implement
##      scene is instanced under Mount and that is the whole connection. No hoses, no cables,
##      no joint, NO COLLISION: the subtree is visual, and the draft force is applied
##      at the hitch point on the chassis instead.
##
## Angle convention (see HitchLinkage): the solver works in planar Vector2(z, y) angles, and
## every pivot node here is authored with its geometry running along local +Z, so posing a
## joint is `rotation.x = -planar_angle` — a positive rotation about X tips +Z toward -Y.

## Top-link angle (planar degrees) while DETACHED. With no implement there is no A-frame to
## close the four-bar on, so the top link parks instead of tracking a pin that is not there —
## the lower links and rockshaft still articulate, because the rockshaft really does raise
## them whether or not anything is hanging off the ends.
const DETACHED_TOP_ANGLE_DEG := 4.0

## |x| of the lower-link / rockshaft-arm pivots (the ball ends splay wider). It is applied to
## the authored pivot nodes in _ready, so widening it really does widen the whole linkage
## instead of pulling the lift rods off the arms they hang from.
@export var lower_link_x := 0.19

@onready var _lower_links: Array[Node3D] = [$LowerLinkL, $LowerLinkR]
@onready var _rock_arms: Array[Node3D] = [$RockArmL, $RockArmR]
@onready var _lift_rods: Array[Node3D] = [$LiftRodL, $LiftRodR]
@onready var _top_link: Node3D = $TopLink
@onready var _pto_stub: Node3D = $PtoStub
@onready var _mount: Node3D = $Mount

var implement: ImplementBase = null  ## null while detached

var _linkage := HitchLinkage.new()
## The A-frame the linkage falls back to with nothing attached — captured before any
## implement overwrites it, so detaching restores it without instancing a throwaway node.
var _bare_mast_offset := _linkage.mast_offset
var _pto_on := false
var _pto_rpm := 0
var _pos01 := 1.0  ## last solved hitch position, so attach/detach can re-pose without it
var _ball_y := 0.0          ## last solved ball height (body space), for ball_lift
var _ball_y_lowered := 0.0  ## ball height at pos01 = 0 — the working datum ball_lift measures from


func _ready() -> void:
	# The pivot rows are authored at the default lower_link_x; re-stating them from the export
	# keeps every part of the linkage on the same pair of planes if it is ever changed.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_lower_links[i].position.x = side * lower_link_x
		_rock_arms[i].position.x = side * lower_link_x
	# The ball ends ride the lower links alone (the A-frame only enters the TOP-link solve), so
	# the fully-lowered datum is a constant of the tractor and is solved once, not per tick.
	_ball_y_lowered = (_linkage.solve(0.0)["ball"] as Vector2).y
	set_hitch(1.0)  # spawn raised (transport), matching TractorVehicle.SPAWN_HITCH


## Instance `scene` on the linkage. The implement's own A-frame feeds the four-bar solve, so
## a different frame really does change how it pitches on the way up. Replaces whatever was
## attached; passing an unloadable scene leaves the hitch detached rather than half-attached.
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
	set_hitch(_pos01)  # the new A-frame re-solves the four-bar: pose it before it is drawn


func detach() -> void:
	if implement != null:
		# Unparent BEFORE queueing the free: queue_free lands at the end of the frame, so an
		# attach() immediately after a detach() (which is exactly what one V press does)
		# would otherwise stack the new implement on top of the outgoing one.
		_mount.remove_child(implement)
		implement.queue_free()
		implement = null
	_linkage.mast_offset = _bare_mast_offset
	set_hitch(_pos01)  # back to the bare solve (and the parked top link) straight away


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

	# Detached: park the top link; there is no implement pin for it to follow.
	_top_link.rotation.x = -float(s["top_angle"]) if implement != null \
			else -deg_to_rad(DETACHED_TOP_ANGLE_DEG)

	# Mount rides the ball ends and carries the solved pitch — the implement is authored in
	# its lowered pose about the lower pin line, which is exactly this node's origin.
	var ball: Vector2 = s["ball"]
	_ball_y = ball.y
	_mount.position = Vector3(0.0, ball.y, ball.x)
	_mount.rotation.x = -float(s["pitch"])

	if implement != null:
		implement.set_hitch(pos01)


## Metres the lower-link balls sit above their fully-lowered (working) height — the implement's
## LIFT, which is how deep its tools still are. Read by the tractor's draft model: the balls rise
## 0.57 m over the stroke while a plough share only reaches 55 mm below the ground line, so the
## shares are clear of the soil after the first tenth of it. The height comes out of the same
## four-bar solve that poses the linkage, so the number and the picture cannot disagree.
func ball_lift() -> float:
	return _ball_y - _ball_y_lowered


## World-space ball line: where the implement hangs off the linkage, and where the draft force is
## applied to the chassis (never on the implement — that subtree has no collision at all).
func hitch_point() -> Vector3:
	return _mount.global_position


## Store the PTO state; the stub shaft spins in _process. `rpm` is the real shaft speed the
## tractor read out of the drivetrain, so the visible spin rate is honest.
func set_pto(on: bool, rpm: int) -> void:
	_pto_on = on
	_pto_rpm = rpm
	if implement == null:
		return
	# The stub shaft turns whatever is (or is not) hanging on the linkage, but only an implement
	# that DECLARES a PTO connection is on the far end of it. Gating here rather than trusting
	# each subclass to ignore a drive it never plugged in is what makes Connection.PTO real.
	var driven := implement.uses(ImplementBase.Connection.PTO)
	implement.set_pto(on and driven, rpm if driven else 0)


## Hand the tractor's hydraulic remote flow (0..1) down the linkage. Gated exactly like the
## PTO: only an implement that DECLARES Connection.SCV has hoses on the remote, so anything
## else reads a shut valve however far the tractor's spool is opened. Nothing visual happens on
## the tractor end — the SCV is non-visual plumbing (no hoses are modelled).
func set_scv(flow01: float) -> void:
	if implement == null:
		return
	var plumbed := implement.uses(ImplementBase.Connection.SCV)
	implement.set_scv(flow01 if plumbed else 0.0)


func _process(delta: float) -> void:
	# The stub's axis is the tractor's local Z (it points straight back), so this is rotate_z.
	if _pto_on and _pto_stub != null:
		_pto_stub.rotate_z(float(_pto_rpm) / 60.0 * TAU * delta)

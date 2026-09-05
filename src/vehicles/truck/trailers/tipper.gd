extends TowedBody
## Dump semi-trailer. It consumes PTO, which turns the pump, and HYDRAULIC, the proportional
## valve; losing PTO mid-lift freezes the body where it stands, like RefuseBody's arm. The raise
## interlock lives in `TowedBody.body_raise_allowed` and is gated by SemiTractor before flow
## reaches this class, never policed here.
##
## The load shift is a consequence, not a term: `set_load_offset_z` moves the real centre of mass
## rearward as the body tips, so trailer_axle_load and the tractor's axle_load move on their own.

## Full tip angle, degrees about the rear hinge. 42 deg puts the raised rig ~5.2 m tall, which is
## why the interlock demands a genuine standstill.
const TIP_MAX_DEG := 42.0

## Seconds down to fully up. Slow on purpose: the interlock must be something you can drive into.
const TIP_TRAVEL_S := 6.0

## Metres the payload's centre of mass slides rearward at full tip (measured off the 6.20 m floor
## at 42 deg).
const TIP_COM_SHIFT_Z := 0.90

## Top-hinged: swings open under the load's own weight once the body has lifted enough.
const TAILGATE_OPEN_DEG := 62.0
const TAILGATE_START := 0.12  ## tip fraction at which the gate starts to swing

## Collision swap thresholds. Two values rather than one, so a spool parked on the boundary
## cannot dither the compound rebuild between the two authored poses.
const RAISED_ON := 0.55
const RAISED_OFF := 0.45

## Metres of rod that stay inside the barrel at full extension, so it never reads as two
## separated cylinders.
const ROD_OVERLAP := 0.20

var _tip := 0.0  ## 0..1 body position; the rams and the tailgate are posed from it

var _tip_body: Node3D = null
var _tailgate: Node3D = null
var _col_down: CollisionShape3D = null  ## lowered-pose box, the one enabled at rest
var _col_up: CollisionShape3D = null    ## same box swept to full tip; enabled only above the swap
var _rams: Array[Node3D] = []          ## the two ram pivots, L then R
var _ram_anchors: Array[Vector3] = []  ## frame-end eye of each ram, in trailer space
var _ram_heads: Array[Node3D] = []     ## body-end eye markers, children of the tipping body
var _barrel_len := 0.0                 ## read off the barrel mesh, never restated
var _rod_len := 1.0                    ## the rod mesh's own height; scale.y is a multiple of it


func _ready() -> void:
	super._ready()
	_tip_body = get_node_or_null(^"TipBody")
	if _tip_body == null:
		push_error("%s: no TipBody — the tipping body cannot be posed" % name)
		return
	_tailgate = _tip_body.get_node_or_null(^"Tailgate")
	_col_down = get_node_or_null(^"CollisionTipBody") as CollisionShape3D
	_col_up = get_node_or_null(^"CollisionTipBodyRaised") as CollisionShape3D
	if _col_down == null or _col_up == null:
		push_error("%s: the tipping body needs both authored collision poses" % name)
	# Geometry is measured off the .tscn, the ram eyes being markers and the barrel length the
	# mesh's own height, so re-authoring the ram moves the pose with it.
	var sides := PackedStringArray(["L", "R"])
	for side in sides:
		var pivot := get_node_or_null(NodePath("Ram" + side)) as Node3D
		var anchor := get_node_or_null(NodePath("RamAnchor" + side)) as Node3D
		var head := _tip_body.get_node_or_null(NodePath("RamHead" + side)) as Node3D
		if pivot == null or anchor == null or head == null:
			push_error("%s: ram %s is missing its pivot, anchor or head" % [name, side])
			return
		_rams.append(pivot)
		_ram_anchors.append(anchor.position)
		_ram_heads.append(head)
	var barrel := _rams[0].get_node_or_null(^"Barrel") as MeshInstance3D
	var rod := _rams[0].get_node_or_null(^"Rod") as MeshInstance3D
	if barrel != null:
		_barrel_len = (barrel.mesh as CylinderMesh).height
	if rod != null:
		_rod_len = (rod.mesh as CylinderMesh).height
	_pose_body()


func consumers() -> int:
	return Consumer.PTO | Consumer.HYDRAULIC


func tick_body(delta: float) -> void:
	# No pump, no movement: losing PTO freezes the body where it is, not a retraction.
	if pto_on:
		_tip = move_toward(_tip, clampf(valve_flow, 0.0, 1.0), delta / TIP_TRAVEL_S)
	# The load walks with the body; this is the only physics effect of the tip.
	set_load_offset_z(_tip * TIP_COM_SHIFT_Z)
	_pose_body()


func reset_body() -> void:
	_tip = 0.0
	_pose_body()


## Body position, 0..1. SemiTractor reads it to clamp the raise interlock, holding a body already
## up rather than commanding it down into traffic.
func body_pos01() -> float:
	return _tip


## Pose the body, tailgate and both rams from `_tip`.
func _pose_body() -> void:
	if _tip_body == null:
		return
	_tip_body.rotation.x = deg_to_rad(TIP_MAX_DEG) * _tip
	if _tailgate != null:
		# Top-hinged, so the bottom edge swings rearward once the load can reach it.
		var gate01 := clampf((_tip - TAILGATE_START) / (1.0 - TAILGATE_START), 0.0, 1.0)
		_tailgate.rotation.x = -deg_to_rad(TAILGATE_OPEN_DEG) * gate01
	for i in _rams.size():
		_pose_ram(_rams[i], _ram_anchors[i], _tip_body.transform * _ram_heads[i].position)
	_swap_collision()


## Enables whichever authored collision pose is nearer, only touching the compound when the
## answer changes.
func _swap_collision() -> void:
	if _col_down == null or _col_up == null:
		return
	var is_up := not _col_up.disabled
	var want_up := _tip > (RAISED_OFF if is_up else RAISED_ON)
	if want_up == is_up:
		return
	_col_up.disabled = not want_up
	_col_down.disabled = want_up


## Lays one telescopic ram between its two eyes, in trailer space. The pivot's +Y aims at the
## head along the cylinder's axis; the barrel stays at the frame end and the rod extends out.
func _pose_ram(pivot: Node3D, anchor: Vector3, head: Vector3) -> void:
	var axis := head - anchor
	var span := axis.length()
	if span < 0.01:
		return
	pivot.position = anchor
	pivot.basis = _aim_y(axis / span)
	var rod := pivot.get_node_or_null(^"Rod") as Node3D
	if rod == null:
		return
	# Exposed rod is what the barrel doesn't cover, plus the overlap kept inside it.
	var out := maxf(span - _barrel_len + ROD_OVERLAP, ROD_OVERLAP)
	rod.scale.y = out / _rod_len
	rod.position.y = span - out * 0.5


## Orthonormal basis with +Y along the unit vector `dir`. Roll about that axis is arbitrary for a
## cylinder, and the fallback goes from RIGHT to FORWARD if `dir` is nearly parallel to RIGHT.
static func _aim_y(dir: Vector3) -> Basis:
	var side := Vector3.RIGHT
	if absf(dir.dot(side)) > 0.99:
		side = Vector3.FORWARD
	var fwd := side.cross(dir).normalized()
	return Basis(dir.cross(fwd).normalized(), dir, fwd)

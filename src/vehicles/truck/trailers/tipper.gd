extends TowedBody
## Tipper / dump semi-trailer — the trailer with a FUNCTION, and the only one in the catalog that
## plugs anything into the towing unit.
##
## It consumes two things, declared in `consumers()` and gated at the coupling by SemiTractor:
##
##   - THE CHASSIS PTO, which turns the tipping pump. No pump, no movement — and losing the PTO
##     part way up FREEZES the body where it stands rather than driving it home, which is what
##     really happens and is the same choice RefuseBody's interlock makes for the refuse arm.
##   - A PROPORTIONAL HYDRAULIC VALVE, non-visual plumbing exactly like the tractor's SCV: no hoses
##     are modelled, the spool position is logical state, and the only visible thing on this end is
##     the pair of rams it feeds.
##
## NAMING REFERENCE, DECLARED AND NOT IMPLEMENTED: ISO 25200 is where tipping-body command and
## status naming lives, and CiA 408 is the CANopen device profile for proportional fluid-power
## valves — which is what this valve would be, on a rig that ran one. NEITHER IS BUILT HERE. There
## is no CiA 408 profile, no object dictionary, no tipper message and, above all, no new signal:
## this phase adds nothing to the ISO 11992 bus, because ISO 11992 carries nothing about the body.
## The reference is here so the model can be recognised for what it is a sketch of.
##
## THE INTERLOCK IS REAL AND IT IS NOT HERE. `TowedBody.body_raise_allowed` takes TOWING-UNIT state
## (parking brake, road speed) and SemiTractor is what evaluates it and clamps the spool before the
## flow ever reaches this class. That is deliberate: a trailer that policed its own interlock could
## be replaced by one that did not, and the whole point of gating at the coupling is that it cannot.
##
## THE LOAD SHIFT IS A CONSEQUENCE, NEVER A TERM. Tipping slides the payload down the body toward
## the tailgate, so `set_load_offset_z` walks this body's real centre of mass rearward: at full tip
## the fifth wheel's share falls from ~21 % to ~5 %, which the bogie's springs pick up. So
## trailer_axle_load climbs, the tractor's axle_load drops, and neither signal has a tipper term in
## it. Watch axle_load rather than engine_load for it — the same asymmetry the refuse hopper has
## (see the hopper_load note in src/vehicles/CLAUDE.md).

## Full tip angle, degrees about the rear hinge. 42 deg is a real dump angle (a bulk tipper runs
## 45-50); it puts the front of the 6.2 m body 4.1 m above the hinge, so the raised rig is about
## 5.2 m tall — which is why the interlock demands a genuine standstill.
const TIP_MAX_DEG := 42.0

## Seconds from down to fully up. Slow, like the refuse arm and for the same reason: the interlock
## has to be something you can drive INTO, and a body that snapped up would make the whole gate
## invisible.
const TIP_TRAVEL_S := 6.0

## Metres the payload's centre of mass slides REARWARD at full tip. Measured off the body rather
## than picked: the floor is 6.20 m long and tilts 42 deg, so a load that ends up heaped against
## the tailgate has moved roughly a seventh of the body's length back along the trailer.
const TIP_COM_SHIFT_Z := 0.90

## The tailgate is TOP-HINGED, so it swings open under the load's own weight once the body has
## lifted far enough for the load to press on it — it is not a separately commanded door.
const TAILGATE_OPEN_DEG := 62.0
const TAILGATE_START := 0.12  ## tip fraction at which the gate starts to swing

## Metres of rod that stay inside the barrel at full extension. Enough that the ram never reads as
## two separated cylinders, which is the one way a telescopic ram can look broken.
const ROD_OVERLAP := 0.20

var _tip := 0.0  ## 0..1 body position; the rams and the tailgate are posed from it

var _tip_body: Node3D = null
var _tailgate: Node3D = null
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
	# Geometry lives in the .tscn and is MEASURED off it (the implements' rule): the ram eyes are
	# markers, and the barrel's length is the mesh's own height, so re-authoring the ram moves the
	# pose with it instead of leaving a constant behind.
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
	# NO PUMP, NO MOVEMENT. This is the freeze, not a retraction: the flow stops where it is, so a
	# body half way up when the PTO drops stays half way up. Driving it back down on a lost drive
	# would be inventing an accumulator nothing here models.
	if pto_on:
		_tip = move_toward(_tip, clampf(valve_flow, 0.0, 1.0), delta / TIP_TRAVEL_S)
	# The load walks with the body, and this is the ONLY thing the tip does to the physics.
	set_load_offset_z(_tip * TIP_COM_SHIFT_Z)
	_pose_body()


func reset_body() -> void:
	_tip = 0.0
	_pose_body()


## 0..1 body position. SemiTractor reads this to clamp the raise interlock: refusing the raise on a
## body that is already up must hold it there rather than commanding it down into traffic.
func body_pos01() -> float:
	return _tip


## Pose the body, the tailgate and both rams from `_tip`. Everything visible is driven from the one
## number, so the picture and the load shift cannot disagree.
func _pose_body() -> void:
	if _tip_body == null:
		return
	_tip_body.rotation.x = deg_to_rad(TIP_MAX_DEG) * _tip
	if _tailgate != null:
		# Top-hinged: the bottom edge swings REARWARD, which is a negative rotation about the local
		# X in this frame. It only starts once the body is up far enough for the load to reach it.
		var gate01 := clampf((_tip - TAILGATE_START) / (1.0 - TAILGATE_START), 0.0, 1.0)
		_tailgate.rotation.x = -deg_to_rad(TAILGATE_OPEN_DEG) * gate01
	for i in _rams.size():
		_pose_ram(_rams[i], _ram_anchors[i], _tip_body.transform * _ram_heads[i].position)


## Lay one telescopic ram between its two eyes, both in TRAILER space. The pivot aims its own +Y at
## the head (a cylinder's axis is +Y), the barrel is fixed at the frame end, and the rod slides out
## of it — so the ram lengthens by extending rather than by stretching, which is the difference
## between a hydraulic ram and a rubber band.
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
	# The exposed rod is whatever the barrel does not cover, plus the overlap that stays inside it.
	var out := maxf(span - _barrel_len + ROD_OVERLAP, ROD_OVERLAP)
	rod.scale.y = out / _rod_len
	rod.position.y = span - out * 0.5


## An orthonormal basis whose +Y points along `dir` (already unit). The roll about that axis is
## arbitrary for a cylinder, so any stable perpendicular will do — RIGHT, unless the ram happens to
## be pointing along it, which no tipping ram does but a guard costs one branch.
static func _aim_y(dir: Vector3) -> Basis:
	var side := Vector3.RIGHT
	if absf(dir.dot(side)) > 0.99:
		side = Vector3.FORWARD
	var fwd := side.cross(dir).normalized()
	return Basis(dir.cross(fwd).normalized(), dir, fwd)

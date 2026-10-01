class_name FarmTipper
extends TowedBody
## Drawbar tipping trailer: the tractor's towed body, making `Connection.DRAWBAR` real. A TowedBody
## (a RigidBody3D on a joint with its own RayWheels), not an ImplementBase.
##
## It declares in two vocabularies, `consumers()` for what Drawbar gates flow on and
## `connections()` for what TractorVehicle publishes, pinned against each other by
## test_drawbar_trailer. It claims no bus address (no ECU) and no PTO (the tractor's SCV feeds the
## ram). Tipping shifts the payload COM.

## Full tip angle, degrees about the rear hinge; steeper than the road tipper's 42 (it empties grain).
const TIP_MAX_DEG := 45.0

## Seconds from down to fully up.
const TIP_TRAVEL_S := 5.0

## Metres the payload COM slides rearward at full tip.
##
## Sized by what must stay on the pin, not by floor fraction: a drawbar carries a 12 % nose weight
## (a fifth wheel 27 %), so the road tipper's fractional walk would zero the pin load. Check with
## `live_kingpin_share`.
const TIP_COM_SHIFT_Z := 0.33

## Top-hinged tailgate: swings open once the body has lifted enough. Not commanded; no signal.
const TAILGATE_OPEN_DEG := 58.0
const TAILGATE_START := 0.15  ## tip fraction at which the gate starts to swing

## Tip fractions where collision swaps between the two authored poses. Two thresholds, so a spool
## parked on the boundary cannot dither.
const RAISED_ON := 0.55
const RAISED_OFF := 0.45

## Metres of rod that stay inside the barrel at full extension.
const ROD_OVERLAP := 0.20

var _tip := 0.0  ## 0..1 body position

var _tip_body: Node3D = null
var _tailgate: Node3D = null
var _col_down: CollisionShape3D = null  ## lowered-pose box, the one enabled at rest
var _col_up: CollisionShape3D = null    ## same box swept to full tip; enabled only above the swap
var _ram: Node3D = null                 ## the ram pivot; ONE, under the body's centreline
var _ram_anchor := Vector3.ZERO         ## frame-end eye, in trailer space
var _ram_head: Node3D = null            ## body-end eye marker, a child of the tipping body
var _barrel_len := 0.0                  ## read off the barrel mesh, never restated
var _rod_len := 1.0                     ## the rod mesh's own height; scale.y is a multiple of it


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
	# Ram geometry is measured off the scene.
	_ram = get_node_or_null(^"Ram") as Node3D
	var anchor := get_node_or_null(^"RamAnchor") as Node3D
	_ram_head = _tip_body.get_node_or_null(^"RamHead") as Node3D
	if _ram == null or anchor == null or _ram_head == null:
		push_error("%s: the ram is missing its pivot, anchor or head" % name)
		return
	_ram_anchor = anchor.position
	var barrel := _ram.get_node_or_null(^"Barrel") as MeshInstance3D
	var rod := _ram.get_node_or_null(^"Rod") as MeshInstance3D
	if barrel == null or rod == null:
		push_error("%s: the ram needs both a Barrel and a Rod to be measured from" % name)
		return
	_barrel_len = (barrel.mesh as CylinderMesh).height
	_rod_len = (rod.mesh as CylinderMesh).height
	_pose_body()

	# Skipped from the merge: the ram's Rod (moved every tick by _pose_ram), the lamp lenses LampSet
	# bound (each needs its own node), and the Wheels visuals (re-based per side at spawn).
	var skip: Array[Node] = _lamps.bound_meshes()
	skip.append(rod)
	var wheels_root := get_node_or_null(wheel_root)
	if wheels_root != null:
		skip.append(wheels_root)
	StaticMeshMerge.merge_subtree(self, skip)


## What it plugs into on the towing unit: HYDRAULIC only (the pump is the tractor's).
func consumers() -> int:
	return Consumer.HYDRAULIC


## DRAWBAR (towed from the pin) | SCV (ram fed from a spool valve). No ISOBUS_DATA; see the header.
func connections() -> int:
	return ImplementBase.Connection.DRAWBAR | ImplementBase.Connection.SCV


## No device class, declared explicitly.
func device_class() -> int:
	return ImplementBase.CLASS_NONE


## Rolls on its own wheels, nothing in the soil.
func draft_relevant() -> bool:
	return false


func tick_body(delta: float) -> void:
	# No PTO gate: the SCV flow already passed TractorVehicle's running/raise gates.
	_tip = move_toward(_tip, clampf(valve_flow, 0.0, 1.0), delta / TIP_TRAVEL_S)
	set_load_offset(_tip * TIP_COM_SHIFT_Z)
	_pose_body()


func reset_body() -> void:
	_tip = 0.0
	_pose_body()


## 0..1 body position. TractorVehicle reads this to hold the raise interlock on an already-up body.
func body_pos01() -> float:
	return _tip


## Pose the body, tailgate and ram from `_tip`, so the picture and the load shift agree.
func _pose_body() -> void:
	if _tip_body == null:
		return
	_tip_body.rotation.x = deg_to_rad(TIP_MAX_DEG) * _tip
	if _tailgate != null:
		# Top-hinged: the bottom edge swings rearward (negative local X) once the load can reach it.
		var gate01 := clampf((_tip - TAILGATE_START) / (1.0 - TAILGATE_START), 0.0, 1.0)
		_tailgate.rotation.x = -deg_to_rad(TAILGATE_OPEN_DEG) * gate01
	if _ram != null and _ram_head != null:
		_pose_ram(_tip_body.transform * _ram_head.position)
	_swap_collision()


## Enable whichever authored collision pose the body is nearer, only when the answer changes:
## re-transforming a shape per tick rebuilds the compound and re-derives the inertia tensor at
## 60 Hz, and the jointed rig buzzes.
func _swap_collision() -> void:
	if _col_down == null or _col_up == null:
		return
	var is_up := not _col_up.disabled
	var want_up := _tip > (RAISED_OFF if is_up else RAISED_ON)
	if want_up == is_up:
		return
	_col_up.disabled = not want_up
	_col_down.disabled = want_up


## Lay the telescopic ram between its two eyes (trailer space): the pivot aims +Y (a cylinder's
## axis) at the head, the barrel is fixed at the frame end, the rod extends out of it.
func _pose_ram(head: Vector3) -> void:
	var axis := head - _ram_anchor
	var span := axis.length()
	if span < 0.01:
		return
	_ram.position = _ram_anchor
	_ram.basis = _aim_y(axis / span)
	var rod := _ram.get_node_or_null(^"Rod") as Node3D
	if rod == null:
		return
	var out := maxf(span - _barrel_len + ROD_OVERLAP, ROD_OVERLAP)
	rod.scale.y = out / _rod_len
	rod.position.y = span - out * 0.5


## Orthonormal basis with +Y along `dir` (unit); roll is arbitrary for a cylinder. Duplicated from
## tipper.gd (different ram counts and eyes).
static func _aim_y(dir: Vector3) -> Basis:
	var side := Vector3.RIGHT
	if absf(dir.dot(side)) > 0.99:
		side = Vector3.FORWARD
	var fwd := side.cross(dir).normalized()
	return Basis(dir.cross(fwd).normalized(), dir, fwd)

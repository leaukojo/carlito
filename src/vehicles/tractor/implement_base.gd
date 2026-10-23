class_name ImplementBase
extends Node3D
## Visual attachment for the three-point hitch (no collision, joint, or RigidBody); its weight
## reaches the chassis as live mass and COM (TractorVehicle._apply_implement_mass). Subclasses
## declare connections/device_class/draft/tool_depth/mast_offset/mass in code, not
## exported data, so a scene edit cannot claim a connection the machine lacks.

## The five connections between a tractor and an implement. The first three are mechanical; SCV
## and ISOBUS_DATA are logical state only (no hoses or cables are modelled).
## NOT TowedBody.Consumer, whose bits differ (PTO is 4 here, 1 there) and which has no data-bus
## member. The one fact in both is the hose (SCV here, Consumer.HYDRAULIC there), on FarmTipper,
## pinned by test_drawbar_trailer. Never mask one enum's value against the other's uses().
enum Connection {
	THREE_POINT = 1,   ## carried on the two lower links + top link
	DRAWBAR = 2,       ## towed from the swinging drawbar
	PTO = 4,           ## driven off the power take-off stub shaft
	SCV = 8,           ## selective control valve — a hydraulic remote
	ISOBUS_DATA = 16,  ## claims an address on the implement bus
}

## ISO 11783-1 device classes: the raw 'implement_type' values. The contract's enum table is the
## source of truth for the LABELS.
const CLASS_NONE := 0        ## nothing attached
const CLASS_TILLAGE := 2
const CLASS_SECONDARY_TILLAGE := 3  ## powered tillage — a harrow, not a plough
const CLASS_FERTILIZER := 5
const CLASS_FORAGE := 9

## Metres of lift over which a ground-supported implement's weight passes from the ground to the
## linkage when it carries no deeper tool: an ESTIMATE of a gauge tyre's or packer roller's sink
## into worked soil, a few cm.
const SUPPORT_BAND := 0.05

## PTO drive as last handed down (see set_pto); false / 0 for an implement with no PTO.
var pto_on := false
var pto_rpm := 0

## Hydraulic remote flow, 0..1 (see set_scv). An implement with no SCV reads a shut valve.
var scv_flow := 0.0


## Which connections this implement uses (bitwise OR of Connection, subclass override). The tractor
## gates real drive/bus behaviour on it, so claiming an absent connection is repeated by the signals.
func connections() -> int:
	return 0


## ISO device class reported as 'implement_type' while attached (subclass override).
func device_class() -> int:
	return CLASS_NONE


## True when this implement works IN the soil, so lowering it pulls back on the tractor (subclass
## override). A machine that never touches soil publishes no draft.
func draft_relevant() -> bool:
	return false


## How far below the ground line this implement's tools reach at full lower, in metres: the span
## draft ramps across (subclass override). Measured off the implement's own geometry (harrow tines
## 0.10 m, plough shares 0.25 m).
##
## 0 by default: right for anything above ground, and "no depth, no draft" rather than a divide
## by zero in TractorTelemetry.draft_depth01. `test_implement_catalog` pins draft-relevant implies
## a positive depth.
func tool_depth() -> float:
	return 0.0


## Its pull in newtons at full depth, full soil and `TractorTelemetry.DRAFT_S_REF_KMH` (subclass
## override), sourced for the class of its drawn size. 0 for a machine that publishes no draft.
func draft_rating() -> float:
	return 0.0


## How its draft follows speed: ASABE D497's `A + B S + C S²` (S in km/h; any common units, only
## the ratio to the reference speed is used) in x, y, z, and in w the top of its speed range, above
## which the curve is held (subclass override). Speed-independent by default.
func draft_shape() -> Vector4:
	return Vector4(1.0, 0.0, 0.0, 0.0)


## Power (kW) its PTO shaft takes at `ground_kmh` with the balls `ball_lift` m over the bottom stop
## and `soil01` of ploughable soil under the hitch (subclass override): each machine reads its own
## geometry. 0 by default, as for a machine the PTO does not drive. The tractor puts it on the crank
## (`VehicleTelemetry.pto_crank_torque`) only while its PTO turns this machine.
func pto_power_kw(_ground_kmh: float, _ball_lift: float, _soil01: float) -> float:
	return 0.0


## The machine's mass in kg (subclass override), sourced for the class of its DRAWN size.
func mass_kg() -> float:
	return 0.0


## Its centre of mass in its own frame: origin on the lower pin line, +z rearward, y up, ground at
## y = -0.21 lowered (subclass override). Measured off the scene.
func mass_centre() -> Vector3:
	return Vector3.ZERO


## Share of its weight the ground carries at the linkage's bottom stop, 0..1 (subclass override):
## a gauge wheel, roller or skids. 0 for a machine held clear of the ground.
func ground_share() -> float:
	return 0.0


## Where it rests on the ground, in its own frame at the lowered pose (on the ground line, y =
## -0.21), measured off the scene (subclass override): the points the drawn linkage floats on. Empty
## for a machine held clear of the ground; test_implement_catalog pins it to `ground_share() > 0`.
func support_points() -> PackedVector3Array:
	return PackedVector3Array()


## Lift over which the ground hands this implement's weight to the linkage: its tools' reach, or the
## support's sink where that is more, so the weight leaves the ground where the tools leave the soil.
func support_lift() -> float:
	return maxf(tool_depth(), SUPPORT_BAND)


## Share of the implement's weight the linkage carries, 0..1, at `ball_lift` metres above the
## bottom stop: `1 - share` (its ground share) there, all of it from `lift_span` (its support lift)
## up, linear between so the chassis' mass write stays continuous over a few ticks of travel.
static func carried01(ball_lift: float, lift_span: float, share: float) -> float:
	var g := clampf(share, 0.0, 1.0)
	if lift_span <= 0.0:
		return 1.0 if ball_lift > 0.0 else 1.0 - g
	return 1.0 - g * (1.0 - clampf(ball_lift / lift_span, 0.0, 1.0))


## The implement's A-frame: top pin relative to lower pins, Vector2(z, y) in its own frame.
## HitchLinkage solves the top link against this. Override only for a deliberately odd frame.
func mast_offset() -> Vector2:
	return HitchLinkage.DEFAULT_MAST_OFFSET


## Nodes ThreePointHitch.attach() hands to StaticMeshMerge as a skip list: anything THIS implement
## moves, scales or re-materials individually every tick (Spreader's Gate/RamRod). Empty by default:
## rotating a whole pivot (Rotor, DepthWheel) carries the merged children along.
func static_merge_skip() -> Array[Node]:
	return []


func uses(conn: Connection) -> bool:
	return (connections() & int(conn)) != 0


## Hitch seam: pos01 in [0, 1], 0 = fully lowered, 1 = fully raised. The hitch already
## positioned this node; override for parts that react to depth (a gate, a depth wheel).
func set_hitch(_pos01: float) -> void:
	pass


## PTO seam: `on` is engaged state, `rpm` the shaft speed; the hitch gates it off without
## Connection.PTO. Override to react; state is kept for spin_from_pto.
func set_pto(on: bool, rpm: int) -> void:
	pto_on = on
	pto_rpm = rpm


## SCV seam: `flow01` is the hydraulic remote opening, 0..1, gated like PTO.
func set_scv(flow01: float) -> void:
	scv_flow = flow01


## Turn `node` about `axis` at the last reported shaft speed, geared by `ratio`. `ratio` is well
## under 1: 540 rpm is nine turns/sec, which aliases at 60 fps; pto_rpm stays honest.
func spin_from_pto(node: Node3D, delta: float, ratio: float, axis := Vector3.UP) -> void:
	if node != null and pto_on:
		node.rotate(axis, float(pto_rpm) / 60.0 * TAU * ratio * delta)

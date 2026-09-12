class_name ImplementBase
extends Node3D
## Visual attachment for the three-point hitch (no collision, joint, or RigidBody). Subclasses
## declare connections/device_class/draft_relevant/tool_depth/mast_offset as code, not exported
## data, to guard against scene edits that claim a connection the machine lacks. Absent signals
## read 0/false, never a gap.

## The five real connections between a tractor and an implement. The first three are
## mechanical; SCV (hydraulic remote) and ISOBUS_DATA (the implement bus) are logical state
## only — no hoses or cables are modelled.
## NOT TowedBody.Consumer, whose bits deliberately differ (PTO is 4 here, 1 there) and which has no
## data-bus member. The only fact stated in both is the hose (SCV here <-> Consumer.HYDRAULIC
## there), on FarmTipper alone, pinned by test_drawbar_trailer. Never mask one enum's value against
## the other's uses().
enum Connection {
	THREE_POINT = 1,   ## carried on the two lower links + top link
	DRAWBAR = 2,       ## towed from the swinging drawbar
	PTO = 4,           ## driven off the power take-off stub shaft
	SCV = 8,           ## selective control valve — a hydraulic remote
	ISOBUS_DATA = 16,  ## claims an address on the implement bus
}

## ISO 11783-1 device classes — the raw values the 'implement_type' signal carries. Kept in
## sync with the contract's enum table, which is the source of truth for the LABELS.
const CLASS_NONE := 0        ## nothing attached
const CLASS_TILLAGE := 2
const CLASS_SECONDARY_TILLAGE := 3  ## powered tillage — a harrow, not a plough
const CLASS_FERTILIZER := 5
const CLASS_FORAGE := 9

## PTO drive as the tractor last handed it down (see set_pto). An implement with no PTO is
## gated off by the hitch and simply reads false / 0 here.
var pto_on := false
var pto_rpm := 0

## Hydraulic remote flow, 0..1 (see set_scv). An implement with no SCV reads a shut valve.
var scv_flow := 0.0


## Which connections this implement uses (bitwise OR of Connection, subclass override).
## Load-bearing: the tractor gates real drive/bus behaviour on it, so claiming a connection
## not actually present is a lie the signals will repeat.
func connections() -> int:
	return 0


## ISO device class reported as 'implement_type' while attached (subclass override).
func device_class() -> int:
	return CLASS_NONE


## True when this implement works IN the soil, so lowering it pulls back on the tractor
## (subclass override). A machine that never touches soil must publish no draft, not a small
## polite number.
func draft_relevant() -> bool:
	return false


## How far below the ground line this implement's tools reach at full lower, in metres —
## the span draft ramps across (subclass override). Measured off the implement's own authored
## geometry, since a shared constant would have the harrow (0.02 m tines) reporting draft with
## its tines visibly in the air against the plough's 0.055 m shares.
##
## 0 by default: right for anything above ground, and safe for a draft-relevant machine that
## forgets a depth (TractorTelemetry.draft_depth01 divides by it — "no depth, no draft" rather
## than by zero). `test_implement_catalog` pins draft-relevant implies a positive depth.
func tool_depth() -> float:
	return 0.0


## The implement's A-frame: top pin relative to lower pins, Vector2(z, y) in its own frame.
## HitchLinkage solves the top link against this. Override only for a deliberately odd frame.
func mast_offset() -> Vector2:
	return HitchLinkage.DEFAULT_MAST_OFFSET


## Nodes ThreePointHitch.attach() must hand to StaticMeshMerge as a skip list — anything THIS
## implement moves, scales or re-materials individually every tick (Spreader's Gate/RamRod).
## Empty by default: most implements only rotate whole pivots (Rotor, DepthWheel), which
## StaticMeshMerge folds freely since the pivot itself still carries the merged children along.
func static_merge_skip() -> Array[Node]:
	return []


## True when this implement uses `conn` (readability helper over the bitmask).
func uses(conn: Connection) -> bool:
	return (connections() & int(conn)) != 0


## Hitch seam: pos01 in [0, 1], 0 = fully lowered, 1 = fully raised. The hitch already
## positioned/pitched this node; override for parts that react to depth (a gate, a depth wheel).
func set_hitch(_pos01: float) -> void:
	pass


## PTO seam: `on` is engaged state, `rpm` the shaft speed. Gated off by the hitch for an
## implement not declaring Connection.PTO. Override to react; state is kept here for
## spin_from_pto below.
func set_pto(on: bool, rpm: int) -> void:
	pto_on = on
	pto_rpm = rpm


## SCV seam: `flow01` is the hydraulic remote opening, 0..1. Gated by the hitch the same way
## as PTO.
func set_scv(flow01: float) -> void:
	scv_flow = flow01


## Turn `node` about `axis` at the shaft speed the tractor last reported, geared by `ratio`.
## `ratio` is deliberately well under 1: 540 rpm is nine turns/sec, which at 60 fps aliases
## into a slow backwards crawl — only the rendering is geared down, pto_rpm stays honest.
func spin_from_pto(node: Node3D, delta: float, ratio: float, axis := Vector3.UP) -> void:
	if node != null and pto_on:
		node.rotate(axis, float(pto_rpm) / 60.0 * TAU * ratio * delta)

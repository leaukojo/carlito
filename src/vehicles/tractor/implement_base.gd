class_name ImplementBase
extends Node3D
## Base class for everything the tractor can carry on its three-point hitch.
##
## An implement is PURELY VISUAL: no CollisionShape, no joint, no RigidBody. It is a child of
## the tractor chassis body, so it rides along for free, and ThreePointHitch poses it from the
## solved linkage each tick. The draft force is applied at the hitch point on the
## tractor, never by scraping colliders on the implement.
##
## A subclass declares five things about itself, as CODE (not exported data — a scene edit
## must not be able to claim a connection the implement does not actually have):
##   connections()    — which of the five real tractor <-> implement connections it uses;
##   device_class()   — the ISO 11783-1 device class published as the 'implement_type' signal;
##   draft_relevant() — whether it works IN the soil, so pulling it costs the tractor;
##   tool_depth()     — how far its tools reach below the ground line when fully lowered;
##   mast_offset()    — its A-frame, which the linkage's four-bar solve closes on.
## and consumes the three seams the tractor drives it through, set_hitch / set_pto / set_scv.
##
## Signals for functions an implement does not have read 0 / false — the dashboard stays
## stable across implement swaps (plan decision 7), so a plough must report no PTO rather
## than the cluster losing a bar.

## The five real connections between a tractor and an implement. The first three are
## mechanical; SCV (hydraulic remote) and ISOBUS_DATA (the implement bus) are non-visual —
## no hoses or cables are modelled, they are logical state only (plan decision 6).
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

## PTO drive as the tractor last handed it down (see set_pto). Held on the base because both
## driven implements need it and neither should be trusted to remember it differently: an
## implement that declares no PTO is gated off by the hitch and simply reads false / 0 here,
## which is what "signals for absent functions read 0 / false" means at this end of the link.
var pto_on := false
var pto_rpm := 0

## Hydraulic remote flow as the tractor last handed it down, 0..1 (see set_scv). Held here for
## the same reason as the PTO state: an implement with no SCV is gated off by the hitch and
## reads a shut valve, rather than being trusted to ignore the flow it was sent.
var scv_flow := 0.0


## Which connections this implement uses — a bitwise OR of Connection (subclass override).
## LOAD-BEARING, not documentation: the tractor gates real behaviour on it. ISOBUS_DATA decides
## whether 'implement_connected' / 'implement_type' report a claim at all, and PTO decides
## whether the stub shaft's drive reaches this implement. Claiming a connection you do not
## have is therefore a lie the signals will repeat.
func connections() -> int:
	return 0


## ISO device class reported as 'implement_type' while attached (subclass override).
func device_class() -> int:
	return CLASS_NONE


## True when this implement does its work IN the soil, so lowering it really does pull back on
## the tractor (subclass override). The plough and the power harrow answer true: a mower deck
## and a spreader disc ride above the ground, and a machine that never touches soil must publish
## NO draft, not a small polite number. The 'draft_force' signal reads this — declaring it here
## keeps the honest-zero case a property of the machine rather than a branch in the tractor.
func draft_relevant() -> bool:
	return false


## How far below the ground line this implement's tools reach at full lower, in METRES — its
## working depth, and the whole span the draft force ramps across (subclass override).
##
## It belongs to the MACHINE, not to the draft model: it is measured off this implement's own
## authored geometry, so the depth the force is sized from and the steel the player watches
## enter the ground are the same number. A shared constant cannot do that — the plough's shares
## reach 0.055 m under the ground line and the harrow's tines only 0.02 m, so one figure for
## both would have had the harrow reporting draft with its tines visibly in the air.
##
## 0 by default, which is the right answer for anything working above the ground and a safe one
## for a draft-relevant machine that forgets to declare a depth: TractorTelemetry.draft_depth01
## divides by it and answers "no depth, no draft" rather than dividing by zero.
## `test_implement_catalog` pins the pairing — draft-relevant implies a positive depth.
func tool_depth() -> float:
	return 0.0


## The implement's A-frame: its top pin relative to its lower pins, as Vector2(z, y) in the
## implement's own frame. HitchLinkage solves the top link against this, so a taller frame
## really does change how the implement pitches on the way up. The default is the standard
## frame the hitch geometry was tuned around; override only for a deliberately odd frame.
func mast_offset() -> Vector2:
	return HitchLinkage.DEFAULT_MAST_OFFSET


## True when this implement uses `conn` (readability helper over the bitmask).
func uses(conn: Connection) -> bool:
	return (connections() & int(conn)) != 0


## Hitch seam: pos01 in [0, 1], 0 = fully lowered (working), 1 = fully raised (transport).
## The hitch already positioned and pitched this node — this is for an implement whose OWN
## parts react to depth (a plough's depth wheel, a spreader's gate).
func set_hitch(_pos01: float) -> void:
	pass


## PTO seam: `on` is the engaged state, `rpm` the shaft speed. An implement that does not
## declare Connection.PTO never sees drive here — the hitch gates it off, so a plough reads a
## dead shaft rather than being trusted to ignore one. Override only to react to the change;
## the state itself is kept here for spin_from_pto below.
func set_pto(on: bool, rpm: int) -> void:
	pto_on = on
	pto_rpm = rpm


## SCV seam: `flow01` is the tractor's hydraulic remote opening, 0..1. Gated by the hitch the
## same way the PTO is — an implement that does not declare Connection.SCV never sees flow
## here, so the only machine that reacts is the one with a ram actually modelled on it.
## Override only to react; the state itself is kept here.
func set_scv(flow01: float) -> void:
	scv_flow = flow01


## Turn `node` about `axis` at the shaft speed the tractor last reported, geared by `ratio`.
## The axis is a real difference between the machines, not a detail: a mower deck and a
## spreader disc turn about the VERTICAL, a power harrow's tine rotor about the machine's
## transverse horizontal axis. Default is vertical because two of the three do that.
##
## `ratio` is COSMETIC and deliberately well under 1. A real rotor turns at roughly shaft
## speed, and 540 rev/min is nine turns a second — which at 60 fps aliases into a slow
## backwards crawl, the one thing a part whose entire job is to make 'pto_rpm' legible must
## never do. The published pto_rpm stays the honest number the drivetrain produced; only the
## rendering is geared down.
func spin_from_pto(node: Node3D, delta: float, ratio: float, axis := Vector3.UP) -> void:
	if node != null and pto_on:
		node.rotate(axis, float(pto_rpm) / 60.0 * TAU * ratio * delta)

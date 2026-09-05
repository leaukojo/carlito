class_name DronePayload
extends RefCounted
## The cargo hook's law: the latch rule and the mass it puts on the airframe. Pure static logic,
## no node state, no scene. The mass really changes, since `carried_mass` and `carried_com` are
## written onto the RigidBody3D and the hover collective is recomputed from them, or a crate would
## fly exactly like an empty aircraft. The latch is one bit: closing needs a payload in reach,
## opening needs nothing at all.

## How far below the hook a payload may sit and still be caught (m). A hover is never exactly
## still, so this is a hand's width of slack along the hook's own downward ray. The gesture is
## hover over, not land on: a ray does not report a shape it starts inside, so a craft settled
## with its hook buried in the crate catches nothing however long HOLD is commanded.
const CAPTURE_RANGE := 1.2

## The heaviest payload the hook will take (kg). Not a strength model, but the point past which
## the airframe cannot hold a hover: the shipped quad is 5 kg with 150 N of thrust, so it sits at
## 0.33 collective empty and 0.62 at this limit, still flyable and unmistakably heavy.
const MAX_PAYLOAD_KG := 4.0


## Is the latch closed this tick? It closes only on a HOLD command with something in reach and
## stays closed while the command holds, `prev` being what lets a captured payload stay captured
## once it is off the ray. It opens the instant the command drops, with no condition and no timer.
static func latched(cmd: bool, prev: bool, capture_ok: bool) -> bool:
	if not cmd:
		return false
	return prev or capture_ok


## The body mass with the payload on it (kg). A named function so the flight path, the published
## `payload_weight` and the test all read the same line.
static func carried_mass(base_mass: float, payload_kg: float) -> float:
	return maxf(base_mass, 0.0) + clampf(payload_kg, 0.0, MAX_PAYLOAD_KG)


## The composed centre of mass, in the body's own local frame: the mass-weighted mean of the
## airframe's own CoM and the hook position the payload hangs from. The hook is below the CoM, so
## this pulls the CoM down, which is genuinely more stable in roll and pitch rather than a
## compensation.
static func carried_com(base_com: Vector3, hook_local: Vector3, base_mass: float,
		payload_kg: float) -> Vector3:
	var m := maxf(base_mass, 0.0)
	var p := clampf(payload_kg, 0.0, MAX_PAYLOAD_KG)
	var total := m + p
	if total <= 0.0:
		return base_com
	return (base_com * m + hook_local * p) / total


## What the hook reports it is holding, in newtons: uavcan.equipment.hardpoint.Status's
## payload_weight is a force, not a mass. Zero for an open hook.
static func payload_weight_n(payload_kg: float, gravity: float) -> float:
	return clampf(payload_kg, 0.0, MAX_PAYLOAD_KG) * maxf(gravity, 0.0)

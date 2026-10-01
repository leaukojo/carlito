class_name DronePayload
extends RefCounted
## The cargo hook's law: the latch rule and the mass it puts on the airframe. Pure static logic.
## The latch is one bit: closing needs a payload in reach, opening needs nothing.

## How far below the hook a payload may sit and still be caught (m), along the hook's downward ray.
## Hover over, do not land on: a ray does not report a shape it starts inside, so a hook buried in
## the crate catches nothing however long HOLD is commanded.
const CAPTURE_RANGE := 1.2

## The heaviest payload the hook will take (kg): the shipped 5 kg quad with 150 N of thrust hovers
## at 0.33 collective empty and 0.59 at this limit, still flyable and unmistakably heavy.
const MAX_PAYLOAD_KG := 4.0


## Is the latch closed this tick? Closes only on a HOLD command with something in reach and stays
## closed while it holds (`prev` keeps a payload that is off the ray). Opens the instant the
## command drops.
static func latched(cmd: bool, prev: bool, capture_ok: bool) -> bool:
	if not cmd:
		return false
	return prev or capture_ok


## The body mass with the payload on it (kg). The real refusal is at CAPTURE (`DroneHook._find`
## never returns a crate over `MAX_PAYLOAD_KG`); the clamp is a degenerate-input guard, not the gate.
static func carried_mass(base_mass: float, payload_kg: float) -> float:
	return maxf(base_mass, 0.0) + clampf(payload_kg, 0.0, MAX_PAYLOAD_KG)


## The composed centre of mass in the body's frame: the mass-weighted mean of the airframe's CoM
## and the hook position. The hook is below the CoM, so this pulls it down (more stable in roll
## and pitch, not a compensation).
static func carried_com(base_com: Vector3, hook_local: Vector3, base_mass: float,
		payload_kg: float) -> Vector3:
	var m := maxf(base_mass, 0.0)
	var p := clampf(payload_kg, 0.0, MAX_PAYLOAD_KG)
	var total := m + p
	if total <= 0.0:
		return base_com
	return (base_com * m + hook_local * p) / total


## What the hook reports it holds, in newtons (uavcan.equipment.hardpoint.Status `payload_weight`
## is a force, not a mass). Zero for an open hook.
static func payload_weight_n(payload_kg: float, gravity: float) -> float:
	return clampf(payload_kg, 0.0, MAX_PAYLOAD_KG) * maxf(gravity, 0.0)

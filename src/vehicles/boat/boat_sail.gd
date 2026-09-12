class_name BoatSail
extends RefCounted
## The sailboat's rig (contract 'sheet' -> 'sail_angle') — pure static logic, no node state, the
## BoatAutopilot shape. BoatVehicle holds nothing per tick for it: the boom follows the sheet and
## the apparent wind, both of which are read fresh every tick, so there is no rig state to keep.
## Tested in tests/test_boat_sail.gd.
##
## THE SIGN CONVENTION, stated once: the boom angle is measured in the SAME ROTATIONAL SENSE as
## `awa`, which is the whole reason `aoa = awa - boom` is true. A boom is an AFT-pointing spar, so
## a positive angle in that sense lays its far end to PORT — and because the wind always pushes it
## to leeward, the boom angle always SHARES `awa`'s sign. Read the number as how far out the boom
## is and the sign as which side the wind is on; do not read it as "+ is to starboard".
##
## It is a THIRD body-frame air term on this hull, beside the windage pair, and like them it must
## NOT route through VehicleMath.air_damper (whose `axis` masks WORLD space, which cannot express
## a body-frame split on a hull that yaws). Nor through damped_force: a sail force is an EXTERNAL
## force like `thrust_force`, not a damper, so it takes no one-tick clamp. It is bounded by
## `aws^2` and terminated by the hull's own `drag_long`; a clamp here would be a fiction that
## slowed the boat in exactly the gusts the rig exists to show.
##
## THE NO-GO ZONE IS NOT CLAMPED IN — IT EMERGES, which is the only reason it is honest (rule 3).
## Close to the wind the lateral coefficient runs several times the drive coefficient, and against
## the hull's `drag_lat` that is a leeway angle wide enough that the course made good stays ~50 deg
## off the wind however high the bow points. Leeway is part of `linear_velocity`, so
## BoatTelemetry.apparent_wind sees it and the loop closes on itself. If a hull points
## unrealistically high, its `drag_lat` is the lever — do not add a cutoff.

## Sea-level air, shared with the aero drag every other family uses.
const RHO_AIR := VehicleMath.AIR_DENSITY

## THE POLAR IS A LABELLED HONEST MODEL, and it is the FLAT-PLATE pair, not a measured sail polar.
## A soft sail is a thin cambered plate rather than an airfoil, so `sin(2a)` / `1 - cos(2a)` is the
## right shape and needs no piecewise stall branch: it is correct at the three points that matter
## (0 deg no lift, 45 deg peak lift, 90 deg pure drag) and continuous everywhere between. Past
## 90 deg the lift term goes negative on its own, which is what a plate blown backwards does.
const CL_MAX := 1.5     ## peak lift coefficient, at 45 deg of attack
const CD_MIN := 0.08    ## edge-on drag, at 0 and 180 deg
const CD_STALL := 1.2   ## drag added by 90 deg of attack (the plate broadside to the flow)

## LUFFING, the one place this model imposes rather than emerges — and what makes irons a real
## state. A soft sail cannot hold camber at a small angle of attack: it flaps and makes NO lift,
## where a rigid foil would still make some. Below LUFF_DEG the lift term is zero, ramping in over
## LUFF_BAND_DEG so a sail fills rather than switching on. Drag carries no luff factor: a flapping
## sail still has CD_MIN, which is all it has here anyway.
const LUFF_DEG := 12.0
const LUFF_BAND_DEG := 4.0


# --- the boom ------------------------------------------------------------------

## Where the boom actually sits, in degrees off the centreline, given the sheet 0..1 and the
## apparent wind angle. Signed like `awa` — see the sign convention in the header.
##
## THE SHEET IS A LIMIT, NOT A POSITION. A boom is a free-swinging spar: the wind pushes it to
## leeward until either the sheet stops it or it lines up with the airflow and stops pulling. So
## the travel is `min(sheet * max_deg, |awa|)` and the SIDE is the wind's, which is why hauling in
## and easing out are not symmetric — easing past the wind angle luffs the sail rather than
## easing it further. A dead calm (`awa` 0, the undefined case apparent_wind reports) leaves it
## on the centreline.
static func boom_angle(sheet: float, awa_deg: float, max_deg: float) -> float:
	var travel := minf(clampf(sheet, 0.0, 1.0) * maxf(max_deg, 0.0), absf(awa_deg))
	return signf(awa_deg) * travel


## Angle of attack: what the sail sees, the apparent wind less the boom. Both are measured from the
## bow with + to starboard, so this shares their sign and `boom_angle`'s clamp keeps |aoa| <= |awa|.
static func attack_angle(awa_deg: float, boom_deg: float) -> float:
	return awa_deg - boom_deg


# --- the polar -----------------------------------------------------------------

## Lift coefficient at `aoa_deg`. Unsigned with respect to the SIDE the wind is on — `force` below
## carries that — but it does go negative past 90 deg, which is the flat plate reversing, not a
## bug. Zero inside the luff band, see LUFF_DEG.
static func lift_coeff(aoa_deg: float) -> float:
	var a := absf(aoa_deg)
	var fill := clampf((a - LUFF_DEG) / LUFF_BAND_DEG, 0.0, 1.0)
	return CL_MAX * sin(deg_to_rad(2.0 * a)) * fill


## Drag coefficient at `aoa_deg`: edge-on at 0 and 180, broadside at 90.
static func drag_coeff(aoa_deg: float) -> float:
	var a := absf(aoa_deg)
	return CD_MIN + CD_STALL * (1.0 - cos(deg_to_rad(2.0 * a))) * 0.5


# --- the force -----------------------------------------------------------------

## The rig's force in WORLD space, built in the water plane out of the hull's own `bow` / `stbd`
## axes so the sign convention is stated exactly once, here.
##
## `aw` is BoatTelemetry.apparent_wind verbatim — (speed m/s, angle deg from the bow, + to
## starboard) — and it is already flattened to the water plane, so a heeling hull reads the same
## wind and this force does not shrink with heel.
##
## `awa` names where the air comes FROM, so the flow GOES the other way; lift is perpendicular to
## the flow, on the side that has a forward component. Worked on a starboard beam reach
## (`awa` +90): flow is `-stbd` (the air blows the hull to port) and lift is `+bow` (the rig pulls
## it forward) — which is the case tests/test_boat_sail.gd pins.
##
## Zero for a hull with no rig (`area` 0) and in a dead calm, so the two powerboats pay one
## comparison a tick and nothing else.
static func force(aw: Vector2, boom_deg: float, area: float,
		bow: Vector3, stbd: Vector3) -> Vector3:
	if area <= 0.0 or aw.x <= 0.0:
		return Vector3.ZERO
	var aoa := attack_angle(aw.y, boom_deg)
	var r := deg_to_rad(aw.y)
	var flow := -(cos(r) * bow + sin(r) * stbd)
	var lift := signf(aw.y) * _turn_to_starboard(flow, bow, stbd)
	var q := 0.5 * RHO_AIR * aw.x * aw.x * area
	return q * (drag_coeff(aoa) * flow + lift_coeff(aoa) * lift)


## `v` turned 90 degrees toward starboard within the water plane: bow -> stbd, stbd -> -bow. Taken
## through the two axes rather than through a world rotation, because the plane this turns in is
## the hull's, and `bow`/`stbd` are already flattened by the caller.
static func _turn_to_starboard(v: Vector3, bow: Vector3, stbd: Vector3) -> Vector3:
	return v.dot(bow) * stbd - v.dot(stbd) * bow

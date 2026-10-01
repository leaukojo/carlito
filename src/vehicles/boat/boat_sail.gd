class_name BoatSail
extends RefCounted
## The sailboat's rig (contract 'sheet' -> 'sail_angle'): pure static logic, no node state, the
## BoatAutopilot shape. The boom follows the sheet and the apparent wind, so there is no rig state.
## Tested in tests/test_boat_sail.gd.
##
## THE SIGN CONVENTION: the boom angle is in the SAME ROTATIONAL SENSE as `awa`, which is why
## `aoa = awa - boom` holds. The wind pushes the boom to leeward, so its angle always SHARES
## `awa`'s sign: read the number as how far out the boom is and the sign as which side the wind
## is on, not as "+ is to starboard".
##
## It is a third body-frame air term beside the windage pair and, like them, must NOT route
## through VehicleMath.air_damper (its `axis` masks WORLD space). Nor through damped_force: a sail
## force is EXTERNAL like `thrust_force`, so it takes no one-tick clamp (it is bounded by `aws^2`
## and the hull's `drag_long`; a clamp would slow the boat in exactly the gusts the rig shows).
##
## THE NO-GO ZONE IS NOT CLAMPED IN, IT EMERGES (rule 3). Close to the wind the lateral coefficient
## runs several times the drive coefficient, and against the hull's `drag_lat` that is a wide
## leeway angle. Leeway is part of `linear_velocity`, so BoatTelemetry.apparent_wind sees it. If a
## hull points unrealistically high, its `drag_lat` is the lever; add no cutoff.

## Sea-level air, shared with the aero drag every other family uses.
const RHO_AIR := VehicleMath.AIR_DENSITY

## THE POLAR IS A LABELLED HONEST MODEL: the FLAT-PLATE pair, not a measured sail polar. `sin(2a)` /
## `1 - cos(2a)` is right at the three points that matter (0 deg no lift, 45 deg peak lift, 90 deg
## pure drag) and continuous between, so there is no stall branch. Past 90 deg the lift term goes
## negative on its own (a plate blown backwards).
const CL_MAX := 1.5     ## peak lift coefficient, at 45 deg of attack
const CD_MIN := 0.08    ## edge-on drag, at 0 and 180 deg
const CD_STALL := 1.2   ## drag added by 90 deg of attack (the plate broadside to the flow)

## LUFFING, the one place this model imposes rather than emerges: a soft sail flaps and makes NO
## lift at a small angle of attack. Below LUFF_DEG the lift term is zero, ramping in over
## LUFF_BAND_DEG so a sail fills rather than switching on. Drag carries no luff factor.
const LUFF_DEG := 12.0
const LUFF_BAND_DEG := 4.0


# --- the boom ------------------------------------------------------------------

## Where the boom sits, in degrees off the centreline, given the sheet 0..1 and the apparent wind
## angle. Signed like `awa`.
##
## THE SHEET IS A LIMIT, NOT A POSITION: the wind pushes the boom to leeward until the sheet stops
## it or it lines up with the airflow. So the travel is `min(sheet * max_deg, |awa|)` and the SIDE
## is the wind's; easing past the wind angle luffs the sail rather than easing it further. A dead
## calm (`awa` 0, the undefined case apparent_wind reports) leaves it on the centreline.
static func boom_angle(sheet: float, awa_deg: float, max_deg: float) -> float:
	var travel := minf(clampf(sheet, 0.0, 1.0) * maxf(max_deg, 0.0), absf(awa_deg))
	return signf(awa_deg) * travel


## Angle of attack: the apparent wind less the boom. Both are from the bow, + to starboard, and
## `boom_angle`'s clamp keeps |aoa| <= |awa|.
static func attack_angle(awa_deg: float, boom_deg: float) -> float:
	return awa_deg - boom_deg


# --- the polar -----------------------------------------------------------------

## Lift coefficient at `aoa_deg`. Unsigned for the side the wind is on (`force` carries that), but
## negative past 90 deg: the flat plate reversing, not a bug. Zero inside the luff band.
static func lift_coeff(aoa_deg: float) -> float:
	var a := absf(aoa_deg)
	var fill := clampf((a - LUFF_DEG) / LUFF_BAND_DEG, 0.0, 1.0)
	return CL_MAX * sin(deg_to_rad(2.0 * a)) * fill


## Drag coefficient at `aoa_deg`: edge-on at 0 and 180, broadside at 90.
static func drag_coeff(aoa_deg: float) -> float:
	var a := absf(aoa_deg)
	return CD_MIN + CD_STALL * (1.0 - cos(deg_to_rad(2.0 * a))) * 0.5


# --- the force -----------------------------------------------------------------

## The rig's force in WORLD space, built in the water plane from the hull's own `bow` / `stbd`
## axes.
##
## `aw` is BoatTelemetry.apparent_wind verbatim (speed m/s, angle deg from the bow, + to starboard),
## already flattened to the water plane, so this force does not shrink with heel.
##
## `awa` names where the air comes FROM, so the flow GOES the other way; lift is perpendicular to
## the flow, on the side with a forward component. On a starboard beam reach (`awa` +90) the flow
## is `-stbd` and the lift is `+bow`, the case tests/test_boat_sail.gd pins.
##
## Zero for a hull with no rig (`area` 0) and in a dead calm.
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


## `v` turned 90 degrees toward starboard within the water plane: bow -> stbd, stbd -> -bow.
static func _turn_to_starboard(v: Vector3, bow: Vector3, stbd: Vector3) -> Vector3:
	return v.dot(bow) * stbd - v.dot(stbd) * bow


## The hull's `fwd`/`right` flattened onto the water plane and normalized, for `force`'s `bow` /
## `stbd`: `aw` is already flattened there, so raw body axes on a heeled hull would add a vertical
## component and shrink the horizontal drive by cos(heel). With the bow straight up or down (as in
## apparent_wind) the raw axes pass through unchanged.
static func flatten_hull_axes(fwd: Vector3, right: Vector3) -> Array[Vector3]:
	var flat_fwd := Vector3(fwd.x, 0.0, fwd.z)
	if flat_fwd.length_squared() <= 1e-12:
		return [fwd, right]
	flat_fwd = flat_fwd.normalized()
	return [flat_fwd, Vector3(-flat_fwd.z, 0.0, flat_fwd.x)]

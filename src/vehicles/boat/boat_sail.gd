class_name BoatSail
extends RefCounted
## The sailboat's rig (contract 'sheet' -> 'sail_angle'): pure static logic, no node state, the
## BoatAutopilot shape. Tour: docs/vehicles.md § Sailing.
##
## The boom angle shares `awa`'s sign (which side the wind is on), so `aoa = awa - boom`.
## Not through VehicleMath.air_damper (its `axis` masks WORLD space) nor damped_force: a sail force
## is external like `thrust_force`, so it takes no clamp. The no-go zone emerges from `drag_lat`
## leeway (rule 3): a hull pointing too high is fixed there, never by a cutoff.

## Sea-level air, shared with the aero drag every other family uses.
const RHO_AIR := VehicleMath.AIR_DENSITY

## Labelled honest model: the flat-plate polar, not a measured one; right at 0/45/90 deg and
## continuous between, so no stall branch.
const CL_MAX := 1.5     ## peak lift coefficient, at 45 deg of attack
const CD_MIN := 0.08    ## edge-on drag, at 0 and 180 deg
const CD_STALL := 1.2   ## drag added by 90 deg of attack (the plate broadside to the flow)

## Luffing, the one imposed term: no lift below LUFF_DEG, filling in over LUFF_BAND_DEG.
const LUFF_DEG := 12.0
const LUFF_BAND_DEG := 4.0


# --- the boom ------------------------------------------------------------------

## Boom angle off the centreline (deg, signed like `awa`). The sheet is a limit, not a position:
## easing past the wind angle luffs the sail. A dead calm leaves it on the centreline.
static func boom_angle(sheet: float, awa_deg: float, max_deg: float) -> float:
	var travel := minf(clampf(sheet, 0.0, 1.0) * maxf(max_deg, 0.0), absf(awa_deg))
	return signf(awa_deg) * travel


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

## The rig's force in WORLD space. `aw` is BoatTelemetry.apparent_wind verbatim (m/s, deg from
## the bow, + to starboard). `awa` is where the air comes FROM; lift is perpendicular to the flow
## on the forward side (starboard beam reach: flow `-stbd`, lift `+bow`).
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


## The hull's `fwd`/`right` flattened onto the water plane for `force`: raw axes on a heeled hull
## would shrink the drive by cos(heel). A vertical bow passes the raw axes through.
static func flatten_hull_axes(fwd: Vector3, right: Vector3) -> Array[Vector3]:
	var flat_fwd := Vector3(fwd.x, 0.0, fwd.z)
	if flat_fwd.length_squared() <= 1e-12:
		return [fwd, right]
	flat_fwd = flat_fwd.normalized()
	return [flat_fwd, Vector3(-flat_fwd.z, 0.0, flat_fwd.x)]

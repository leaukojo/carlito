class_name HitchLinkage
extends RefCounted
## Three-point hitch kinematics — pure math, no nodes, no tree (rule 8: testable logic).
##
## A real three-point hitch is a four-bar linkage seen from the side. Only ONE thing is
## free: how far the rockshaft has swung the lower links. Everything else follows from the
## parts being rigid:
##   - the lower links swing about their pivots, carrying the ball ends;
##   - the implement's A-frame top pin must stay `top_len` from the mast pivot AND
##     |mast_offset| from the ball ends, so the implement's PITCH is *solved*, not authored
##     — which is why implements visibly tip back as they lift;
##   - the lift rods are rigid too, so the rockshaft arm angle is solved the same way.
## Both solves are the same circle-circle intersection.
##
## All geometry is in the tractor's side plane as Vector2(z, y) in BODY space, measured
## against the Kenney tractor body (rear body face z ~ +0.99 at the centreline, ground at
## y ~ 0, rear tyre inner faces at |x| = 0.253). Angles are PLANAR — atan2(y, z), so 0
## points straight back. A Node3D rotating about local X needs the NEGATED planar angle
## (a positive rotation.x tips +Z toward -Y); ThreePointHitch does that conversion.
##
## The defaults below ARE the shipped tractor geometry, so tests exercise the real numbers
## (test_hitch_linkage asserts the whole sweep stays reachable).

# --- lower links (the rockshaft-driven draft arms) ---
var lower_pivot := Vector2(0.92, 0.42)   ## forward pivot, under the rear axle housing
var lower_len := 0.827                   ## pivot -> ball end
var lower_angle_lo_deg := -14.7          ## fully lowered (working): ball at y ~ 0.21
var lower_angle_hi_deg := 25.8           ## fully raised (transport): ball at y ~ 0.78

# --- top link ---
var top_pivot := Vector2(1.00, 0.78)     ## mast pin, 0.36 above the lower pivots
var top_len := 0.661                     ## = |(ball_lowered + mast_offset) - top_pivot|,
                                         ## i.e. chosen so pitch reads 0 at fully lowered

## The standard A-frame the hitch geometry was tuned around. ImplementBase returns this as its
## default mast_offset, so the frame lives in ONE place — a second copy would let the detached
## solve and an implement's own frame drift apart silently.
const DEFAULT_MAST_OFFSET := Vector2(-0.06, 0.533)

## Attached implement's A-frame: top pin relative to the lower pins, in the implement's own
## frame. Set from ImplementBase.mast_offset() on attach; the default is the standard frame
## (also used while DETACHED so the solve stays well-conditioned).
var mast_offset := DEFAULT_MAST_OFFSET

# --- rockshaft + lift rods ---
var rock_pivot := Vector2(1.02, 0.95)    ## rockshaft axis, just aft of the rear deck
var rock_arm_len := 0.24                 ## rockshaft axis -> upper rod pin
var lift_rod_len := 0.50                 ## rigid rod, upper pin -> lower pin
var rod_attach_frac := 0.42              ## lower rod pin, as a fraction along the lower link


## Solve the whole linkage at `pos01` (0 = fully lowered/working, 1 = fully raised/transport).
## Returns planar angles + the joint positions the hitch scene needs:
##   lower_angle, top_angle, rock_angle : float, planar radians
##   ball, top_pin, rod_attach, rod_end : Vector2(z, y) in body space
##   pitch                              : float, implement rotation from its authored rest pose
##   reachable                          : false if the geometry could not close (see below)
## `reachable` false means a geometry edit broke the linkage — the returned pose is clamped
## so nothing explodes, but the test suite fails loudly instead of shipping a broken hitch.
func solve(pos01: float) -> Dictionary:
	var t := clampf(pos01, 0.0, 1.0)
	var lower_angle := deg_to_rad(lerpf(lower_angle_lo_deg, lower_angle_hi_deg, t))
	var along := Vector2(cos(lower_angle), sin(lower_angle))
	var ball := lower_pivot + along * lower_len

	# Top link: the pin is on the implement's A-frame circle around the ball AND on the top
	# link's circle around the mast pin. Prefer the upper root — the lower one folds the
	# implement under the tractor.
	var top := circle_intersect(ball, mast_offset.length(), top_pivot, top_len, Vector2(0.0, 1.0))
	var top_pin: Vector2 = top["point"]

	# Lift rods: same solve one link down. Prefer the rearward root (the forward one points
	# the rockshaft arm into the transmission).
	var rod_attach := lower_pivot + along * (lower_len * rod_attach_frac)
	var rock := circle_intersect(rock_pivot, rock_arm_len, rod_attach, lift_rod_len, Vector2(1.0, 0.0))
	var rod_end: Vector2 = rock["point"]

	return {
		"lower_angle": lower_angle,
		"ball": ball,
		"top_pin": top_pin,
		"top_angle": (top_pin - top_pivot).angle(),
		"pitch": wrapf((top_pin - ball).angle() - mast_offset.angle(), -PI, PI),
		"rock_angle": (rod_end - rock_pivot).angle(),
		"rod_attach": rod_attach,
		"rod_end": rod_end,
		"reachable": bool(top["reachable"]) and bool(rock["reachable"]),
	}


## Intersection of circle (c1, r1) with circle (c2, r2), picking the root furthest along
## `prefer` (measured from c1) — the branch choice has to be stable across the whole sweep,
## and a fixed perpendicular sign is NOT: which side is "up" flips as c1 -> c2 rotates.
## Returns { point: Vector2, reachable: bool }. When the circles miss, the point is clamped
## onto circle 1 pointing at c2 (nearest reachable pose) and reachable is false.
static func circle_intersect(c1: Vector2, r1: float, c2: Vector2, r2: float,
		prefer: Vector2) -> Dictionary:
	var span := c2 - c1
	var d := span.length()
	if d < 1e-6 or d > r1 + r2 or d < absf(r1 - r2):
		var dir := span / d if d > 1e-6 else prefer.normalized()
		return {"point": c1 + dir * r1, "reachable": false}
	var a := (d * d + r1 * r1 - r2 * r2) / (2.0 * d)
	var h := sqrt(maxf(0.0, r1 * r1 - a * a))
	var u := span / d
	var mid := c1 + u * a
	var perp := Vector2(-u.y, u.x) * h
	var p1 := mid + perp
	var p2 := mid - perp
	var point := p1 if (p1 - c1).dot(prefer) >= (p2 - c1).dot(prefer) else p2
	return {"point": point, "reachable": true}

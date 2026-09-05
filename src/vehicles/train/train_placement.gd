class_name TrainPlacement
extends RefCounted
## Pure car-pose geometry: a rail car sits on two bogies, so its pose is fixed by two points
## on the centreline at s +/- bogie_half_spacing. Position is their midpoint, orientation is
## the chord between them, up = world Y. No physics, no node access.
## Samples come from the level's rail Curve3D via `rail_to_world()` (baked RailTrack or
## unbaked RoadPath, same duck API); on a closed loop the two s values wrap. `lift` raises
## the pose along world up so modelled wheels rest on the rail ribs rather than the deck.

## World pose for a car centred at arc position `s`. `curve` is in the space `rail_to_world`
## maps from; `half_spacing` is the bogie half-spacing (m); `closed`/`length` wrap the samples.
static func car_pose(curve: Curve3D, rail_to_world: Transform3D, s: float,
		half_spacing: float, closed: bool, length: float, lift := 0.0) -> Transform3D:
	var front_s := _wrap(s + half_spacing, closed, length)
	var back_s := _wrap(s - half_spacing, closed, length)
	var front := rail_to_world * curve.sample_baked(front_s)
	var back := rail_to_world * curve.sample_baked(back_s)
	return pose_from_bogies(front, back, lift)


## Pose from two world-space bogie points: origin at the midpoint (+ optional vertical lift),
## body forward (-Z) along the chord front<-back, up = world Y. Right-handed via up x forward.
## Degenerate (coincident) points fall back to +Z-forward so a bad sample never NaNs a basis.
static func pose_from_bogies(front: Vector3, back: Vector3, lift := 0.0) -> Transform3D:
	var mid := (front + back) * 0.5 + Vector3.UP * lift
	var forward := front - back
	if forward.length_squared() < 1e-9:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	# Right-handed orthonormal basis, -Z = forward, Y ~ world up. Wrong cross order yields a
	# det = -1 (mirrored) basis: mesh renders inside-out and the hood camera's look_at flips.
	var zc := -forward
	var xc := Vector3.UP.cross(zc)
	if xc.length_squared() < 1e-9:
		# Track pointing straight up/down (never happens on a rail): pick any stable right.
		xc = Vector3.RIGHT
	xc = xc.normalized()
	var yc := zc.cross(xc).normalized()
	return Transform3D(Basis(xc, yc, zc), mid)


static func _wrap(arc: float, closed: bool, length: float) -> float:
	if closed and length > 0.0:
		return fposmod(arc, length)
	return arc

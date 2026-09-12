class_name ZoneShape
extends RefCounted
## Pure geometry of one course zone: an oriented BOX, or a vertical RING (an annulus about the
## zone's local Y; `inner_r` 0 makes it a solid cylinder, which is what a waypoint is). Every
## boundary is INCLUSIVE, so a wheel contact exactly on a box edge is inside. Built from a
## ChallengeZone node by `ChallengeZone.zones_of`, or directly by the tests.

enum Kind { BOX, RING }

## Boundary slack: absorbs float noise from composing transforms, far below anything a wire
## signal resolves (the finest, lat/lon, is about 1 cm).
const EPS := 1e-6
## Sample spacing when a path is tested against a RING. Rings are metres across, so 10 cm
## cannot step over one.
const RING_STEP := 0.1

var kind := Kind.BOX
## Orthonormal: the dimensions below are the size, never a node scale.
var xform := Transform3D.IDENTITY
var size := Vector3.ONE   ## BOX: full extents along the zone's local axes
var inner_r := 0.0        ## RING: m, 0 = solid cylinder
var outer_r := 1.0        ## RING: m
var height := 0.0         ## RING: full vertical extent about the centre, 0 = unbounded


static func box(p_xform: Transform3D, p_size: Vector3) -> ZoneShape:
	var z := ZoneShape.new()
	z.kind = Kind.BOX
	z.xform = p_xform.orthonormalized()
	z.size = p_size
	return z


static func ring(p_xform: Transform3D, p_inner: float, p_outer: float, p_height := 0.0) -> ZoneShape:
	var z := ZoneShape.new()
	z.kind = Kind.RING
	z.xform = p_xform.orthonormalized()
	z.inner_r = p_inner
	z.outer_r = p_outer
	z.height = p_height
	return z


func contains(p: Vector3) -> bool:
	var local := xform.affine_inverse() * p
	if kind == Kind.BOX:
		var half := size * 0.5
		return absf(local.x) <= half.x + EPS and absf(local.y) <= half.y + EPS \
				and absf(local.z) <= half.z + EPS
	if height > 0.0 and absf(local.y) > height * 0.5 + EPS:
		return false
	var r := Vector2(local.x, local.z).length()
	return r >= inner_r - EPS and r <= outer_r + EPS


## Whether the straight path a -> b passes through the zone. This is the tick-to-tick test that
## stops a gate thinner than one tick of travel (0.46 m at 100 km/h) from being skipped between
## two samples. Exact for a box (slab clipping in the zone's frame); sampled for a ring.
func crosses(a: Vector3, b: Vector3) -> bool:
	if kind == Kind.RING:
		var steps := clampi(ceili(a.distance_to(b) / RING_STEP), 1, 256)
		for i in steps + 1:
			if contains(a.lerp(b, float(i) / steps)):
				return true
		return false
	var inv := xform.affine_inverse()
	var la := inv * a
	var d := inv * b - la
	var half := size * 0.5
	var t0 := 0.0
	var t1 := 1.0
	for axis in 3:
		var h := half[axis] + EPS
		if absf(d[axis]) < 1e-12:
			if absf(la[axis]) > h:
				return false
			continue
		var ta := (-h - la[axis]) / d[axis]
		var tb := (h - la[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	return true


## Angle of `p` about the zone's vertical axis, radians. Only differences between two readings
## mean anything (a lap sums them), so the zero direction is arbitrary.
func angle_of(p: Vector3) -> float:
	var local := xform.affine_inverse() * p
	return atan2(local.z, local.x)


## Why this zone can never contain anything, or "" when it can.
func problem() -> String:
	if kind == Kind.BOX:
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			return "a box side is not positive"
		return ""
	if inner_r < 0.0 or outer_r <= inner_r:
		return "a ring needs 0 <= inner_r < outer_r"
	if height < 0.0:
		return "a ring height is negative"
	return ""

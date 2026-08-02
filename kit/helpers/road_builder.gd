class_name RoadBuilder
extends RefCounted
## Pure road-geometry math for RoadPath: curvature-adaptive
## curve sampling, ribbon extrusion from a RoadProfile cross-section, and the destructive
## conform-terrain flatten mask. Everything is static, deterministic, and editor-free so
## the baker (a game-mode tool, never the editor) can call it on an untreed level, and it
## all gets the Drivetrain test discipline (tests/test_road.gd).
##
## Bake-hash note (the ScatterBase precedent): extrusion runs BY the baker at bake time, so
## this file is bake-adjacent CODE. No resource dependency edge reaches it (Godot reports
## resource deps, not script->script edges), so it is named in LevelBaker.BAKE_CODE_INPUTS
## and hashed explicitly — editing it re-stales every level by itself. Still bump
## BAKER_VERSION for semantic changes, so the intent is recorded and old manifests are
## rejected on version alone.
##
## Frames: the road frame is built from the tangent + world UP (right vector always
## horizontal, pitch follows slope, roll ONLY from explicit curve tilt) — deliberately
## NOT Curve3D.sample_baked_with_rotation, whose parallel-transported up vector
## accumulates roll on climbing turns. Because the right vector flips WITH the tangent,
## reversing a curve's direction preserves the winding (still up-facing).
##
## Closed loops (first control position == last): the two end rings share an origin, so
## extrude gives BOTH the bisector of the two end tangents — a smooth seam loses its
## residual crease, an angled seam gets a proper miter — and the duplicated ring welds
## at bake (1 mm snap).

## Subdivision floor (m): a segment this short is never bisected, so a hard kink in the
## curve terminates the recursion instead of recursing forever.
const MIN_SEG := 0.5
## Finite-difference half-step (m) for tangents.
const TANGENT_H := 0.1
## Inside-edge fold clamp: between two rings, a cross-section point at |x| beyond the
## local turn radius (ds / tangent swing) sweeps BACKWARDS and the ribbon self-overlaps.
## Extrude clamps the inside lateral to this fraction of the local radius, so any curve
## — hairpins, zero-handle corners — renders fold-free (the inner edge pinches instead).
const FOLD_MARGIN := 0.95
## Largest angle (degrees) an endpoint handle may deviate from the curve's own end tangent
## before extrude falls back to the finite difference. The handle is the better end frame
## for a port-snapped road (see extrude), but it is authored freely — the built-in Path3D
## gizmo will happily leave an out-handle near-perpendicular to the first chord. An end
## ring yawed that far makes the first segment's tangent swing enormous, the fold clamp
## then pinches ring 0 to nothing, and the road starts as a bowtie instead of a ring.
## Past this the handle is no longer describing the road's direction.
const END_TANGENT_MAX_DEV_DEG := 60.0


# ------------------------------------------------------------ adaptive sampling

## Baked-length offsets along the curve: strictly increasing, first 0.0, last ==
## get_baked_length(). Every interior control point's arc offset is an anchor, then
## each anchor span is cut into uniform segments of at most max_seg_len and each is
## recursively bisected while tangents across it disagree by more than max_angle_deg
## — checked end-to-end AND against the midpoint tangent, so an S-inflection whose
## end tangents happen to be parallel still subdivides.
##
## The control-point anchors are the corner miter: a zero-handle kink gets a ring
## exactly AT the corner, whose central-difference tangent is the angle bisector —
## without it the nearest rings sit up to MIN_SEG away on either side and the edge
## notches/overlaps even at small angles. (When the local turn radius drops below the
## ribbon half-width, extrude's FOLD_MARGIN clamp pinches the inside edge instead of
## letting it self-overlap.)
## Empty for a null / <2-point / ~zero-length curve.
static func adaptive_offsets(curve: Curve3D, max_seg_len: float,
		max_angle_deg: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if curve == null or curve.point_count < 2:
		return out
	var length := curve.get_baked_length()
	if length < 0.001:
		return out
	var max_angle := deg_to_rad(maxf(max_angle_deg, 0.1))
	var anchors := PackedFloat32Array([0.0])
	for i in range(1, curve.point_count - 1):
		var o := curve.get_closest_offset(curve.get_point_position(i))
		# Strictly ascending with breathing room, so a self-near curve's bogus
		# closest-offset match degrades to the plain split instead of misordering.
		if o - anchors[anchors.size() - 1] > MIN_SEG * 0.5 and length - o > MIN_SEG * 0.5:
			anchors.append(o)
	anchors.append(length)
	out.append(0.0)
	for ai in anchors.size() - 1:
		var seg_a := anchors[ai]
		var seg_b := anchors[ai + 1]
		var coarse := maxi(1, int(ceil((seg_b - seg_a) / maxf(max_seg_len, MIN_SEG))))
		for i in coarse:
			_subdivide(curve, seg_a + (seg_b - seg_a) * float(i) / float(coarse),
					seg_a + (seg_b - seg_a) * float(i + 1) / float(coarse),
					max_angle, length, out)
	return out


## Catmull-Rom-style auto-handles for a curve point from its two neighbours: both
## handles share the neighbour-chord direction; each is a third of the distance to
## its own neighbour, so closely spaced points stay tight and long spans arc wide.
## The draw tool applies this to the previous point per click and RoadPath's Smooth
## button to every interior point — hand-clicked polylines become C1 curves. (C1 does
## NOT guarantee a minimum turn radius; extrude's fold clamp covers what remains.)
## Coincident neighbours degenerate to zero handles.
static func smooth_handles(prev: Vector3, point: Vector3, next: Vector3) -> Dictionary:
	var chord := next - prev
	if chord.length_squared() < 1e-12:
		return {"in": Vector3.ZERO, "out": Vector3.ZERO}
	var dir := chord.normalized()
	return {"in": -dir * (point.distance_to(prev) / 3.0),
			"out": dir * (point.distance_to(next) / 3.0)}


# ------------------------------------------------------------ draw-mode primitives
# Pure helpers for the addon's Straight/Arc draw sub-modes. Additive only — nothing
# below feeds extrusion or conform, so bake output is untouched (no BAKER_VERSION bump).


## Snap `dir`'s XZ heading to the nearest multiple of step_deg, preserving XZ length
## and Y (the draw tool's angle-snap toggle). step_deg <= 0 or a ~vertical dir returns
## dir unchanged.
static func snap_direction(dir: Vector3, step_deg: float) -> Vector3:
	if step_deg <= 0.0:
		return dir
	var len_xz := Vector2(dir.x, dir.z).length()
	if len_xz < 1e-6:
		return dir
	var step := deg_to_rad(step_deg)
	var heading := roundf(atan2(dir.z, dir.x) / step) * step
	return Vector3(cos(heading) * len_xz, dir.y, sin(heading) * len_xz)


## First curve point index that coincides with its predecessor (a zero-length segment),
## or -1 when the curve is clean. Coincident control points make Curve3D's bake spam
## "Zero length interval." / "The target vector can't be zero." (verified), so the draw
## tool refuses clicks that would create one and RoadPath warns when the gizmo already did.
## Pure — additive, no bake output.
static func first_coincident_index(curve: Curve3D) -> int:
	if curve == null:
		return -1
	for i in range(1, curve.point_count):
		if curve.get_point_position(i).is_equal_approx(curve.get_point_position(i - 1)):
			return i
	return -1


## Distance between a curve's first and last control positions — the gap a "closed" loop
## fails to close. INF for a curve too short to be a loop. Single owner of the closed-loop
## question: extrude's seam handling asks is_closed_loop, and RoadPath warns when this is
## small but nonzero (a loop closed by eye rather than by snapping).
static func endpoint_gap(curve: Curve3D) -> float:
	if curve == null or curve.point_count < 3:
		return INF
	return curve.get_point_position(0).distance_to(
			curve.get_point_position(curve.point_count - 1))


## Whether the two end control points coincide, so extrude gives both end rings the
## bisector of the end tangents and the duplicated ring welds at bake.
static func is_closed_loop(curve: Curve3D) -> bool:
	if curve == null or curve.point_count < 3:
		return false
	return curve.get_point_position(0).is_equal_approx(
			curve.get_point_position(curve.point_count - 1))


## Outward end tangent of an open curve at one end (curve-local, unit): the direction a
## road CONTINUES past that end — used by the draw tool's road-to-road snapping to lock a
## joined road's handle collinear with this one (a seamless deck join). Reads the endpoint
## handle (get_point_in at the last point / get_point_out at the first, negated to point
## AWAY from the road), falling back to the chord toward the adjacent point when the handle
## is zero (polyline / Straight ends). Vector3.ZERO for a < 2-point curve. Additive — no
## bake output, no BAKER_VERSION bump.
static func end_tangent_out(curve: Curve3D, at_last: bool) -> Vector3:
	if curve == null or curve.point_count < 2:
		return Vector3.ZERO
	var n := curve.point_count
	if at_last:
		var h := curve.get_point_in(n - 1)
		if h.length_squared() > 1e-12:
			return (-h).normalized()
		var chord := curve.get_point_position(n - 1) - curve.get_point_position(n - 2)
		return chord.normalized() if chord.length_squared() > 1e-12 else Vector3.ZERO
	var h0 := curve.get_point_out(0)
	if h0.length_squared() > 1e-12:
		return (-h0).normalized()
	var chord0 := curve.get_point_position(0) - curve.get_point_position(1)
	return chord0.normalized() if chord0.length_squared() > 1e-12 else Vector3.ZERO


## 3-click circular arc (start point, tangent direction, end point — the
## Cities: Skylines pattern) as Curve3D point data:
## {start_out: Vector3, points: [{pos, in, out}, ...], radius: float}.
## The circle is solved in XZ from the start tangent + chord; the sweep (reflex
## supported) is split into equal sub-arcs of <= 90 deg, each emitted as one cubic via
## the standard approximation (handle length 4/3 * tan(sub/4) * r), so `points` holds
## the interior split points plus the end. Height lerps linearly along arc length and
## the slope rides in every handle, keeping 3D tangent continuity at the joins
## (in == -out by construction). A ~collinear end or degenerate input falls back to a
## straight zero-handle segment with radius INF.
static func arc_points(start: Vector3, start_dir: Vector3, end: Vector3) -> Dictionary:
	var straight := {"start_out": Vector3.ZERO,
			"points": [{"pos": end, "in": Vector3.ZERO, "out": Vector3.ZERO}],
			"radius": INF}
	var t2 := Vector2(start_dir.x, start_dir.z)
	var d2 := Vector2(end.x - start.x, end.z - start.z)
	if t2.length_squared() < 1e-12 or d2.length_squared() < 1e-8:
		return straight
	t2 = t2.normalized()
	var side := t2.x * d2.y - t2.y * d2.x
	# chord nearly along the tangent: the radius explodes — a straight reads the same
	if absf(side) < d2.length() * 0.001:
		return straight
	var r_signed := d2.length_squared() / (2.0 * side)
	var center := Vector2(start.x, start.z) + Vector2(-t2.y, t2.x) * r_signed
	var radius := absf(r_signed)
	var turn := signf(r_signed)   # rotation direction in XZ math coords
	var u0 := Vector2(start.x, start.z) - center
	var u1 := Vector2(end.x, end.z) - center
	var sweep := fposmod(turn * (u1.angle() - u0.angle()), TAU)
	if sweep < 1e-4:
		return straight
	# tolerance so an exact 90/180/270-degree sweep doesn't ceil into an extra segment
	# (Vector2.angle() is float32 — the sweep carries ~1e-7 noise against float64 PI)
	var segs := maxi(1, int(ceil(sweep / (PI * 0.5) - 1e-5)))
	var sub := sweep / float(segs)
	var k := 4.0 / 3.0 * tan(sub * 0.25) * radius
	var slope := (end.y - start.y) / (radius * sweep)   # dy per arc meter
	var start_out := Vector3.ZERO
	var pts := []
	for i in segs + 1:
		var u := u0.rotated(turn * sub * float(i))
		var tan2 := (Vector2(-u.y, u.x) * turn).normalized()   # unit tangent at u
		var handle := Vector3(tan2.x * k, slope * k, tan2.y * k)
		if i == 0:
			start_out = handle
			continue
		var pos := Vector3(center.x + u.x,
				lerpf(start.y, end.y, float(i) / float(segs)), center.y + u.y)
		pts.append({"pos": pos, "in": -handle, "out": handle})
	return {"start_out": start_out, "points": pts, "radius": radius}


## Append the offsets of (a, b] to out, bisecting while curvature demands it.
static func _subdivide(curve: Curve3D, a: float, b: float, max_angle: float,
		length: float, out: PackedFloat32Array) -> void:
	if b - a > MIN_SEG:
		var m := (a + b) * 0.5
		var ta := tangent_at(curve, a, length)
		var tm := tangent_at(curve, m, length)
		var tb := tangent_at(curve, b, length)
		if ta.angle_to(tm) > max_angle or tm.angle_to(tb) > max_angle \
				or ta.angle_to(tb) > max_angle:
			_subdivide(curve, a, m, max_angle, length, out)
			_subdivide(curve, m, b, max_angle, length, out)
			return
	out.append(b)


## Central-difference tangent at a baked offset, clamped at the curve ends.
static func tangent_at(curve: Curve3D, offset: float, length: float) -> Vector3:
	var a := curve.sample_baked(maxf(offset - TANGENT_H, 0.0))
	var b := curve.sample_baked(minf(offset + TANGENT_H, length))
	var d := b - a
	return d.normalized() if d.length_squared() > 1e-12 else Vector3.FORWARD


## Smallest local turn radius extrude's fold clamp will see over the curve: per
## adjacent ring pair, ds / tangent swing — skipping pure pitch kinks (crest/dip, no
## lateral component), exactly like the clamp. INF for straights/degenerate curves.
## The draw tool refuses clicks that would drop this below the ribbon half-width: below
## that floor the inside edge pinches to the fold point and the corner reads as a slit
## — geometric, not fixable by frames (adding this helper changes no bake output).
static func min_turn_radius(curve: Curve3D, max_seg_len: float,
		max_angle_deg: float) -> float:
	var offsets := adaptive_offsets(curve, max_seg_len, max_angle_deg)
	if offsets.size() < 2:
		return INF
	var length := curve.get_baked_length()
	var best := INF
	for i in offsets.size() - 1:
		var t_a := tangent_at(curve, offsets[i], length)
		var t_b := tangent_at(curve, offsets[i + 1], length)
		var swing := t_a.angle_to(t_b)
		if swing < 1e-4:
			continue
		if absf(t_a.cross(t_b).dot(Vector3.UP)) < 1e-8:
			continue   # pure pitch kink: no lateral fold
		best = minf(best, (offsets[i + 1] - offsets[i]) / swing)
	return best


## Road frame at a baked offset: basis.x = right (horizontal unless tilted), basis.y =
## up, origin = the curve point. A near-vertical tangent (authoring pathology — roads
## are never vertical) degenerates T x UP, so the caller threads the previous ring's
## right vector through as the fallback (Vector3.RIGHT for the first ring).
static func frame_at(curve: Curve3D, offset: float, length: float, tilt: float,
		prev_right: Vector3) -> Transform3D:
	return frame_from_tangent(tangent_at(curve, offset, length),
			curve.sample_baked(offset), tilt, prev_right)


## frame_at with an explicit tangent — extrude overrides the two end tangents of a
## closed loop with their bisector so the seam rings coincide exactly.
static func frame_from_tangent(t: Vector3, origin: Vector3, tilt: float,
		prev_right: Vector3) -> Transform3D:
	var r := t.cross(Vector3.UP)
	if r.length_squared() < 1e-8:
		r = prev_right
	r = r.normalized()
	var u := r.cross(t).normalized()
	if absf(tilt) > 1e-6:
		r = r.rotated(t, tilt)
		u = u.rotated(t, tilt)
	return Transform3D(Basis(r, u, r.cross(u)), origin)


# ------------------------------------------------------------------ banking LUT

## Tilt lookup from the baked point/tilt parallel arrays: [cumulative chord lengths,
## tilts]. Chord length tracks baked length closely (baked points are dense). Built
## only when banking is on.
static func tilt_lut(curve: Curve3D) -> Array:
	var pts := curve.get_baked_points()
	var tilts := curve.get_baked_tilts()
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	for i in range(1, pts.size()):
		cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
	return [cum, tilts]


## Lerped tilt at a baked offset (binary search over the cumulative lengths).
static func tilt_at(lut: Array, offset: float) -> float:
	var cum: PackedFloat32Array = lut[0]
	var tilts: PackedFloat32Array = lut[1]
	if tilts.is_empty():
		return 0.0
	if tilts.size() == 1 or offset <= 0.0:
		return tilts[0]
	if offset >= cum[cum.size() - 1]:
		return tilts[tilts.size() - 1]
	var i := cum.bsearch(offset)   # first index with cum[i] >= offset; i >= 1 here
	var span := cum[i] - cum[i - 1]
	var t := 0.0 if span <= 0.0 else (offset - cum[i - 1]) / span
	return lerpf(tilts[i - 1], tilts[i], t)


# ---------------------------------------------------------------------- extrusion

## Extrude the cross-section along the curve, in curve-local space. Returns
## {material slot (int): Mesh.ARRAY_MAX-sized arrays} — one indexed triangle surface
## per slot that has strips. Strips do NOT share verts across breakpoints (crisp
## low-poly hard edges at material changes and the drop crease). Per vertex:
##   position = origin + R * x' + U * p.y, x' = p.x fold-clamped (see FOLD_MARGIN)
##   normal   = R * n2.x + U * n2.y, n2 = perp of the 2D strip edge (flat strip -> +U)
##   uv       = (lateral meters, arc-length meters)
## Winding per quad is clockwise seen from above (Godot's front-face order, same as
## heightmap_terrain._build_chunk) and stays up-facing when the curve is reversed,
## because R flips with T.
static func extrude(curve: Curve3D, points: PackedVector2Array, mats: PackedInt32Array,
		offsets: PackedFloat32Array, banked: bool) -> Dictionary:
	var result := {}
	if curve == null or points.size() < 2 or mats.size() != points.size() - 1 \
			or offsets.size() < 2:
		return result
	var length := curve.get_baked_length()
	var lut: Array = tilt_lut(curve) if banked else []

	# Closed loop: the two end rings share an origin, so both get the bisector of the
	# two end tangents — one shared frame instead of a crease/wedge at the seam.
	var seam_tangent := Vector3.ZERO
	if is_closed_loop(curve):
		var bis := tangent_at(curve, 0.0, length) + tangent_at(curve, length, length)
		if bis.length_squared() > 1e-12:
			seam_tangent = bis.normalized()

	# Open ends use the EXACT endpoint tangent — the handle direction — instead of the
	# finite difference, which bends with any immediate curvature and yaws the end ring
	# (a port-snapped end then buries one edge in the tile and gaps the other). Zero
	# handles (polyline) keep the finite-difference fallback: the first chord is the
	# exact tangent there anyway, and so does a handle that has been dragged more than
	# END_TANGENT_MAX_DEV_DEG off the curve's own end direction (see the const).
	var start_tangent := Vector3.ZERO
	var end_tangent := Vector3.ZERO
	if seam_tangent == Vector3.ZERO and curve.point_count >= 2:
		var max_dev := deg_to_rad(END_TANGENT_MAX_DEV_DEG)
		var h0 := curve.get_point_out(0)
		if h0.length_squared() > 1e-12:
			var cand0 := h0.normalized()
			if cand0.angle_to(tangent_at(curve, 0.0, length)) <= max_dev:
				start_tangent = cand0
		var h1 := curve.get_point_in(curve.point_count - 1)
		if h1.length_squared() > 1e-12:
			var cand1 := -h1.normalized()
			if cand1.angle_to(tangent_at(curve, length, length)) <= max_dev:
				end_tangent = cand1

	var frames: Array[Transform3D] = []
	var prev_right := Vector3.RIGHT
	for i in offsets.size():
		var o := offsets[i]
		var tilt := tilt_at(lut, o) if banked else 0.0
		var t := tangent_at(curve, o, length)
		if seam_tangent != Vector3.ZERO and (i == 0 or i == offsets.size() - 1):
			t = seam_tangent
		elif i == 0 and start_tangent != Vector3.ZERO:
			t = start_tangent
		elif i == offsets.size() - 1 and end_tangent != Vector3.ZERO:
			t = end_tangent
		var f := frame_from_tangent(t, curve.sample_baked(o), tilt, prev_right)
		prev_right = f.basis.x
		frames.append(f)

	# Inside-edge fold clamp, once per ring (strips share frames): per adjacent ring
	# pair the local turn radius is ds / tangent swing, and the INSIDE of the turn is
	# the side the tangent rotates toward — (t_a x t_b).UP > 0 turns toward the
	# negative-lateral side (r = t x UP). A ring's clamp is the min over its adjacent
	# pairs of FOLD_MARGIN * radius; straights and the outside stay INF (unclamped),
	# a zero-handle corner's miter ring clamps to ~0 (the inside edge meets AT the
	# corner and fans — the clean angled connection).
	var clamp_neg := PackedFloat32Array()   # lateral p.x < 0 side
	var clamp_pos := PackedFloat32Array()   # lateral p.x > 0 side
	clamp_neg.resize(frames.size())
	clamp_neg.fill(INF)
	clamp_pos.resize(frames.size())
	clamp_pos.fill(INF)
	for i in frames.size() - 1:
		var t_a := -frames[i].basis.z
		var t_b := -frames[i + 1].basis.z
		var swing := t_a.angle_to(t_b)
		if swing < 1e-4:
			continue
		var turn := t_a.cross(t_b).dot(Vector3.UP)
		if absf(turn) < 1e-8:
			continue   # pure pitch kink (crest/dip): no lateral turn, no lateral fold
		var limit := FOLD_MARGIN * (offsets[i + 1] - offsets[i]) / swing
		if turn > 0.0:
			clamp_neg[i] = minf(clamp_neg[i], limit)
			clamp_neg[i + 1] = minf(clamp_neg[i + 1], limit)
		else:
			clamp_pos[i] = minf(clamp_pos[i], limit)
			clamp_pos[i + 1] = minf(clamp_pos[i + 1], limit)

	# A cross-section whose polyline CLOSES (last point == first) encloses a solid volume —
	# exactly what RoadProfile emits when base_depth > 0. Sweeping it alone produced an
	# open tube: you looked straight down a bridge's open end into its hollow interior,
	# and because the box's walls and floor are welded into the drivable body, a vehicle
	# that entered through an open end sat inside it and dropped out through the back
	# faces of the floor. Cap both ends with the section's own triangulation.
	var closed_section := points.size() >= 4 \
			and points[0].is_equal_approx(points[points.size() - 1])
	var cap_slot: int = mats[mats.size() - 1] if closed_section else -1

	# insertion-ordered slot list (deterministic: strip order)
	var slots: Array[int] = []
	for m in mats:
		if not slots.has(m):
			slots.append(m)

	for slot in slots:
		var pos := PackedVector3Array()
		var nrm := PackedVector3Array()
		var uv := PackedVector2Array()
		var idx := PackedInt32Array()
		for si in mats.size():
			if mats[si] != slot:
				continue
			var p0 := points[si]
			var p1 := points[si + 1]
			var n2 := Vector2(-(p1.y - p0.y), p1.x - p0.x).normalized()
			var base := pos.size()
			for ri in frames.size():
				var f := frames[ri]
				var r := f.basis.x
				var u := f.basis.y
				# fold clamp collapses the inside lateral toward the fold point; the UV
				# keeps the profile p.x so material mapping is untouched, y unchanged
				var x0 := _clamp_lateral(p0.x, clamp_neg[ri], clamp_pos[ri])
				var x1 := _clamp_lateral(p1.x, clamp_neg[ri], clamp_pos[ri])
				pos.append(f.origin + r * x0 + u * p0.y)
				pos.append(f.origin + r * x1 + u * p1.y)
				var n := (r * n2.x + u * n2.y).normalized()
				nrm.append(n)
				nrm.append(n)
				uv.append(Vector2(p0.x, offsets[ri]))
				uv.append(Vector2(p1.x, offsets[ri]))
			for ri in frames.size() - 1:
				var q := base + ri * 2
				idx.append_array(PackedInt32Array([q, q + 2, q + 1, q + 1, q + 2, q + 3]))
		if slot == cap_slot:
			_append_end_caps(pos, nrm, uv, idx, frames, points, offsets,
					clamp_neg, clamp_pos)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = idx
		result[slot] = arrays
	return result


## Triangulate the closed cross-section at the first and last ring and append both caps,
## using each ring's OWN fold-clamped laterals so a cap always meets the strips it closes.
##
## Facing: a cap vertex is origin + R*x + U*y, and R x U == -T, so a triangle whose 2D
## signed area is positive has its Godot front face along +T. The last ring's cap must
## face +T (forward, out of the road) and the first ring's -T, so each triangle is emitted
## in whichever order gives its side the sign it needs. Degenerate rings (a fold clamp
## tight enough to collapse the section) simply get no cap rather than a fan of slivers.
static func _append_end_caps(pos: PackedVector3Array, nrm: PackedVector3Array,
		uv: PackedVector2Array, idx: PackedInt32Array, frames: Array[Transform3D],
		points: PackedVector2Array, offsets: PackedFloat32Array,
		clamp_neg: PackedFloat32Array, clamp_pos: PackedFloat32Array) -> void:
	var n := points.size() - 1   # drop the duplicated closing point
	for which in 2:
		var ri := 0 if which == 0 else frames.size() - 1
		var f := frames[ri]
		var poly := PackedVector2Array()
		for i in n:
			poly.append(Vector2(
					_clamp_lateral(points[i].x, clamp_neg[ri], clamp_pos[ri]), points[i].y))
		var tris := Geometry2D.triangulate_polygon(poly)
		if tris.is_empty():
			continue
		var tangent := -f.basis.z
		var normal := tangent if which == 1 else -tangent
		var base := pos.size()
		for i in n:
			pos.append(f.origin + f.basis.x * poly[i].x + f.basis.y * poly[i].y)
			nrm.append(normal)
			uv.append(Vector2(points[i].x, offsets[ri]))
		var want_positive := which == 1
		for ti in range(0, tris.size() - 2, 3):
			var a := tris[ti]
			var b := tris[ti + 1]
			var c := tris[ti + 2]
			var signed_area := (poly[b].x - poly[a].x) * (poly[c].y - poly[a].y) \
					- (poly[b].y - poly[a].y) * (poly[c].x - poly[a].x)
			if (signed_area > 0.0) == want_positive:
				idx.append_array(PackedInt32Array([base + a, base + b, base + c]))
			else:
				idx.append_array(PackedInt32Array([base + a, base + c, base + b]))


## Signed lateral clamped to its side's fold limit (INF = untouched).
static func _clamp_lateral(x: float, c_neg: float, c_pos: float) -> float:
	if x < 0.0:
		return -minf(-x, c_neg)
	return minf(x, c_pos)


## Flatten extruded surfaces into an unindexed triangle soup (same verts, same winding,
## so render and collision coincide) — the weld-pool / dev-trimesh input. Slots are
## visited sorted so the soup is deterministic.
static func faces_from_surfaces(surfaces: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var keys := surfaces.keys()
	keys.sort()
	for k in keys:
		var arrays: Array = surfaces[k]
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in idx:
			out.append(pos[i])
	return out


## Transform surface arrays: positions by the full transform, normals by the
## inverse-transpose basis re-normalized (for a non-identity Path3D child transform), and
## triangles reversed when the transform mirrors — a Path3D child scaled negatively on one
## axis would otherwise hand the baker a ribbon wound inside-out (same trap as
## LevelBaker.SurfaceAccumulator.append).
static func transform_surface_arrays(arrays: Array, xform: Transform3D) -> Array:
	var out := arrays.duplicate()
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var npos := PackedVector3Array()
	npos.resize(pos.size())
	for i in pos.size():
		npos[i] = xform * pos[i]
	out[Mesh.ARRAY_VERTEX] = npos
	var src_n: Variant = arrays[Mesh.ARRAY_NORMAL]
	if src_n is PackedVector3Array:
		var nb := xform.basis.inverse().transposed()
		var nn := PackedVector3Array()
		nn.resize((src_n as PackedVector3Array).size())
		for i in nn.size():
			nn[i] = (nb * (src_n as PackedVector3Array)[i]).normalized()
		out[Mesh.ARRAY_NORMAL] = nn
	var src_idx: Variant = arrays[Mesh.ARRAY_INDEX]
	if xform.basis.determinant() < 0.0 and src_idx is PackedInt32Array:
		var si := src_idx as PackedInt32Array
		var flipped := si.duplicate()
		for i in range(0, si.size() - 2, 3):
			flipped[i + 1] = si[i + 2]
			flipped[i + 2] = si[i + 1]
		out[Mesh.ARRAY_INDEX] = flipped
	return out


# ------------------------------------------------------------------ conform math

## Flatten blend weight for a centerline distance: 1 inside half_width, smoothstep down
## to 0 at half_width + falloff.
static func flatten_weight(dist: float, half_width: float, falloff: float) -> float:
	if dist <= half_width:
		return 1.0
	var edge := half_width + maxf(falloff, 0.0)
	if dist >= edge:
		return 0.0
	var t := (dist - half_width) / maxf(falloff, 0.001)
	return 1.0 - t * t * (3.0 - 2.0 * t)


## Flatten the greyscale height image under a road. `samples` are
## (local_x, local_z, target_norm) triples — terrain-LOCAL, node-origin-relative XZ
## (the height_at convention) packed as Vector3(x, z, target); target_norm is the
## normalized [0,1] road height. Callers sample AT the extrusion's adaptive_offsets
## rings: the lerp between consecutive samples then IS the ribbon's chordal surface,
## so the flatten can never target the analytic curve where it rides above the
## chords over a crest. `deck` (optional, same packing per vertex, 3 verts per
## triangle) is the actual full-width deck strip extruded on the ribbon's frames;
## where a pixel lands inside a deck triangle its plane height replaces the
## centerline projection (see the raster pass below — the projection is wrong at the
## edges of steep yawing segments). Pixel mapping mirrors HeightmapTerrain.height_at
## exactly: px = (lx + span_x*0.5) / span_x * (iw-1), separate x/z pixel scales (the
## brush_ops anisotropy convention). Per pixel the strictly-nearest centerline SEGMENT
## wins (first segment wins ties — deterministic) and the target is LERPED at the
## pixel's projection onto it — never the nearest point sample: a point target is off
## by up to half the sample spacing x the grade, which at ε = 0.05 pokes terrain
## through the ribbon on any grade over ~20%. One apply
## pass then blends toward the target:
##   new = lerp(old, quantize(target), flatten_weight(dist, half_width, falloff))
## half_width is the flatten plateau — callers pass the FULL ribbon half-width
## (skirt included) so terrain under the drop skirt sits at a predictable road - ε
## and always crosses the skirt on its slope. quantize is floor(t*255)/255 — FLOOR,
## not round, so the 8-bit PNG can never store terrain ABOVE the analytic road height
## (the z-fight guard; any epsilon > 0 suffices, but the skirt must absorb
## epsilon + one height step). Returns the tight dirty Rect2i in pixels (empty if
## unchanged). Same inputs -> identical bytes.
static func conform_heights(img: Image, samples: PackedVector3Array, half_width: float,
		falloff: float, span_x: float, span_z: float,
		deck := PackedVector3Array()) -> Rect2i:
	var iw := img.get_width()
	var ih := img.get_height()
	if samples.is_empty() or iw < 2 or ih < 2:
		return Rect2i()
	if samples.size() == 1:
		samples.append(samples[0])   # local CoW copy: one degenerate segment
	var sx := float(iw - 1) / maxf(span_x, 0.001)   # pixels per meter
	var sz := float(ih - 1) / maxf(span_z, 0.001)
	var reach := half_width + maxf(falloff, 0.0)
	var rx := reach * sx
	var rz := reach * sz

	# padded bounding pixel rect over all samples
	var min_px := iw
	var max_px := -1
	var min_pz := ih
	var max_pz := -1
	for s in samples:
		var px_f := (s.x + span_x * 0.5) * sx
		var pz_f := (s.y + span_z * 0.5) * sz
		min_px = mini(min_px, int(floor(px_f - rx)) - 1)
		max_px = maxi(max_px, int(ceil(px_f + rx)) + 1)
		min_pz = mini(min_pz, int(floor(pz_f - rz)) - 1)
		max_pz = maxi(max_pz, int(ceil(pz_f + rz)) + 1)
	min_px = clampi(min_px, 0, iw - 1)
	max_px = clampi(max_px, 0, iw - 1)
	min_pz = clampi(min_pz, 0, ih - 1)
	max_pz = clampi(max_pz, 0, ih - 1)
	if max_px < min_px or max_pz < min_pz:
		return Rect2i()
	var rw := max_px - min_px + 1
	var rh := max_pz - min_pz + 1

	# nearest-segment pass: per pixel, keep the smallest squared distance to any
	# centerline segment + the target lerped at the projection onto it
	var dist2 := PackedFloat32Array()
	dist2.resize(rw * rh)
	dist2.fill(INF)
	var target := PackedFloat32Array()
	target.resize(rw * rh)
	for si in samples.size() - 1:
		var a := samples[si]
		var b := samples[si + 1]
		var ax := (a.x + span_x * 0.5) * sx
		var az := (a.y + span_z * 0.5) * sz
		var bx := (b.x + span_x * 0.5) * sx
		var bz := (b.y + span_z * 0.5) * sz
		var x0 := clampi(int(floor(minf(ax, bx) - rx)), min_px, max_px)
		var x1 := clampi(int(ceil(maxf(ax, bx) + rx)), min_px, max_px)
		var z0 := clampi(int(floor(minf(az, bz) - rz)), min_pz, max_pz)
		var z1 := clampi(int(ceil(maxf(az, bz) + rz)), min_pz, max_pz)
		var abx := b.x - a.x   # meters
		var abz := b.y - a.y
		var ab2 := abx * abx + abz * abz
		for pz in range(z0, z1 + 1):
			var pmz := float(pz) / sz - span_z * 0.5
			for px in range(x0, x1 + 1):
				var pmx := float(px) / sx - span_x * 0.5
				var t := 0.0
				if ab2 > 1e-12:
					t = clampf(((pmx - a.x) * abx + (pmz - a.y) * abz) / ab2, 0.0, 1.0)
				var dxm := pmx - (a.x + abx * t)
				var dzm := pmz - (a.y + abz * t)
				var d2 := dxm * dxm + dzm * dzm
				var bi := (pz - min_pz) * rw + (px - min_px)
				if d2 < dist2[bi]:
					dist2[bi] = d2
					target[bi] = lerpf(a.z, b.z, t)

	# Deck raster pass: where the pixel center lies inside an actual ribbon-deck
	# triangle (`deck`: terrain-local (x, z, target_norm) verts, 3 per triangle —
	# the caller extrudes a flat full-width strip on the SAME frames as the ribbon),
	# override the projected target with the triangle's plane height and pin the
	# distance to 0 (plateau). The centerline projection above assumes the deck's
	# lateral axis is perpendicular to the chord; on a segment that is both steep
	# and yawing, the real ruled surface between rings shifts along-slope by up to
	# half_width * sin(swing/2) * grade — tens of centimetres at authoring extremes,
	# way past conform_epsilon, poking terrain through the ribbon edges of steep
	# bends. Only the rasterized triangles are trustworthy where the ribbon actually
	# is; the projection remains for the falloff ring beyond the deck (where the
	# blend back to original terrain makes its error invisible). Raster order is the
	# triangle order (deterministic); shared edges agree by plane continuity.
	for ti in range(0, deck.size() - 2, 3):
		var ta := deck[ti]
		var tb := deck[ti + 1]
		var tc := deck[ti + 2]
		var abx := tb.x - ta.x
		var abz := tb.y - ta.y
		var acx := tc.x - ta.x
		var acz := tc.y - ta.y
		var den := abx * acz - abz * acx
		if absf(den) < 1e-9:
			continue
		var x0 := clampi(int(floor((minf(ta.x, minf(tb.x, tc.x)) + span_x * 0.5) * sx)),
				min_px, max_px)
		var x1 := clampi(int(ceil((maxf(ta.x, maxf(tb.x, tc.x)) + span_x * 0.5) * sx)),
				min_px, max_px)
		var z0 := clampi(int(floor((minf(ta.y, minf(tb.y, tc.y)) + span_z * 0.5) * sz)),
				min_pz, max_pz)
		var z1 := clampi(int(ceil((maxf(ta.y, maxf(tb.y, tc.y)) + span_z * 0.5) * sz)),
				min_pz, max_pz)
		for pz in range(z0, z1 + 1):
			var pmz := float(pz) / sz - span_z * 0.5
			for px in range(x0, x1 + 1):
				var pmx := float(px) / sx - span_x * 0.5
				var apx := pmx - ta.x
				var apz := pmz - ta.y
				var w1 := (apx * acz - apz * acx) / den
				var w2 := (abx * apz - abz * apx) / den
				if w1 < -1e-6 or w2 < -1e-6 or w1 + w2 > 1.0 + 1e-6:
					continue
				var bi := (pz - min_pz) * rw + (px - min_px)
				dist2[bi] = 0.0
				target[bi] = ta.z + w1 * (tb.z - ta.z) + w2 * (tc.z - ta.z)

	return _apply_targets(img, dist2, target, min_px, min_pz, max_px, max_pz, rw,
			half_width, falloff, false)


## Flatten under a set of axis-aligned XZ rects (GridMap tile footprints), each with
## its own normalized [0,1] target height. Same terrain-local conventions and pixel
## mapping as conform_heights; the plateau is the rect interior (distance 0 — callers
## pass the tile's actual XZ footprint), the strictly-nearest rect wins per pixel
## (first wins ties — pass rects in sorted-cell order, deterministic) and
## flatten_weight smoothsteps out over `falloff` beyond the union. Targets are
## ROUND-quantized, not floor: tiles sit ON the terrain, so the closest 8-bit height
## either side of the cell base is the best meet — the deck (surface_y above the
## base) hides the residual, unlike a road ribbon where storing above the surface
## would poke through. Returns the tight dirty Rect2i in pixels (empty if unchanged).
## Same inputs -> identical bytes.
static func conform_rects(img: Image, rects: Array[Rect2], targets: PackedFloat32Array,
		falloff: float, span_x: float, span_z: float) -> Rect2i:
	var iw := img.get_width()
	var ih := img.get_height()
	if rects.is_empty() or rects.size() != targets.size() or iw < 2 or ih < 2:
		return Rect2i()
	var sx := float(iw - 1) / maxf(span_x, 0.001)   # pixels per meter
	var sz := float(ih - 1) / maxf(span_z, 0.001)
	var reach := maxf(falloff, 0.0)

	# padded bounding pixel rect over all rects
	var min_px := iw
	var max_px := -1
	var min_pz := ih
	var max_pz := -1
	for r in rects:
		min_px = mini(min_px, int(floor((r.position.x - reach + span_x * 0.5) * sx)) - 1)
		max_px = maxi(max_px, int(ceil((r.end.x + reach + span_x * 0.5) * sx)) + 1)
		min_pz = mini(min_pz, int(floor((r.position.y - reach + span_z * 0.5) * sz)) - 1)
		max_pz = maxi(max_pz, int(ceil((r.end.y + reach + span_z * 0.5) * sz)) + 1)
	min_px = clampi(min_px, 0, iw - 1)
	max_px = clampi(max_px, 0, iw - 1)
	min_pz = clampi(min_pz, 0, ih - 1)
	max_pz = clampi(max_pz, 0, ih - 1)
	if max_px < min_px or max_pz < min_pz:
		return Rect2i()
	var rw := max_px - min_px + 1
	var rh := max_pz - min_pz + 1

	# nearest-rect pass: per pixel, keep the smallest squared distance to any rect
	# (0 inside it) + that rect's target
	var dist2 := PackedFloat32Array()
	dist2.resize(rw * rh)
	dist2.fill(INF)
	var target := PackedFloat32Array()
	target.resize(rw * rh)
	for ri in rects.size():
		var r := rects[ri]
		var x0 := clampi(int(floor((r.position.x - reach + span_x * 0.5) * sx)), min_px, max_px)
		var x1 := clampi(int(ceil((r.end.x + reach + span_x * 0.5) * sx)), min_px, max_px)
		var z0 := clampi(int(floor((r.position.y - reach + span_z * 0.5) * sz)), min_pz, max_pz)
		var z1 := clampi(int(ceil((r.end.y + reach + span_z * 0.5) * sz)), min_pz, max_pz)
		for pz in range(z0, z1 + 1):
			var pmz := float(pz) / sz - span_z * 0.5
			var dzm := maxf(maxf(r.position.y - pmz, pmz - r.end.y), 0.0)
			for px in range(x0, x1 + 1):
				var pmx := float(px) / sx - span_x * 0.5
				var dxm := maxf(maxf(r.position.x - pmx, pmx - r.end.x), 0.0)
				var d2 := dxm * dxm + dzm * dzm
				var bi := (pz - min_pz) * rw + (px - min_px)
				if d2 < dist2[bi]:
					dist2[bi] = d2
					target[bi] = targets[ri]

	return _apply_targets(img, dist2, target, min_px, min_pz, max_px, max_pz, rw,
			0.0, falloff, true)


## Shared apply pass for conform_heights / conform_rects: blend each pixel toward its
## quantized target by flatten_weight(nearest distance), tracking the dirty rect.
## round_quantize: floor for road ribbons (never store above the surface), round for
## tile bases (closest meet either side; the deck hides the residual).
static func _apply_targets(img: Image, dist2: PackedFloat32Array,
		target: PackedFloat32Array, min_px: int, min_pz: int, max_px: int,
		max_pz: int, rw: int, half_width: float, falloff: float,
		round_quantize: bool) -> Rect2i:
	var reach := half_width + maxf(falloff, 0.0)
	var reach2 := reach * reach
	var dminx := img.get_width()
	var dminz := img.get_height()
	var dmaxx := -1
	var dmaxz := -1
	for pz in range(min_pz, max_pz + 1):
		for px in range(min_px, max_px + 1):
			var bi := (pz - min_pz) * rw + (px - min_px)
			var d2 := dist2[bi]
			if d2 > reach2:   # strict: at reach the weight is 0 anyway, and a
				continue      # zero-falloff rect plateau (d2 == reach2 == 0) must apply
			var w := flatten_weight(sqrt(d2), half_width, falloff)
			if w <= 0.0:
				continue
			var old := img.get_pixel(px, pz).r
			var t := clampf(target[bi], 0.0, 1.0) * 255.0
			var q := (roundf(t) if round_quantize else floorf(t)) / 255.0
			var nv := lerpf(old, q, w)
			if clampi(roundi(nv * 255.0), 0, 255) == roundi(old * 255.0):
				continue
			img.set_pixel(px, pz, Color(nv, nv, nv))
			dminx = mini(dminx, px)
			dmaxx = maxi(dmaxx, px)
			dminz = mini(dminz, pz)
			dmaxz = maxi(dmaxz, pz)
	if dmaxx < 0:
		return Rect2i()
	return Rect2i(dminx, dminz, dmaxx - dminx + 1, dmaxz - dminz + 1)

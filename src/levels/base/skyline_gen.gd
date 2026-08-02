class_name SkylineGen
extends RefCounted
## Pure, unit-tested mesh math for SkylineRing's distant horizon ridge
## (tests/test_skyline_gen.gd). Static fns only, deterministic from their arguments —
## same seed, same ridge, forever — the same discipline as TerrainGen.
##
## The ridge is a closed ring of three concentric vertex rings: an inner base and an
## outer base, both on the sea plane (local y = 0), with a noise-driven crest between
## them. That gives a lit inward slope and a shadowed outer slope, so the silhouette
## reads as land rather than a flat black curtain — for a couple hundred triangles.

## Crest noise is sampled 2-D ON THE CIRCLE of this radius (noise units, not metres).
## Sampling a 1-D angle would tear at theta = 0; walking a circle in 2-D noise closes
## seamlessly by construction. The circumference (2*PI*RING_NOISE_RADIUS) is roughly
## the peak count, since one simplex feature spans ~1 noise unit at frequency 1.
const RING_NOISE_RADIUS := 3.2
const NOISE_OCTAVES := 3
## Crest height range as a fraction of `height`. The floor is well above 0 so the ridge
## never dips back to sea level and opens a gap in the silhouette.
const CREST_MIN := 0.35


## Per-segment crest heights around the ring, in metres, index 0 at theta = 0 going
## counter-clockwise. `segments` entries — the ring wraps, so there is no duplicate
## closing entry (segment i spans theta_i .. theta_i+1, with the last wrapping to 0).
static func crest_heights(segments: int, seed_value: int, height: float) -> PackedFloat32Array:
	var count := maxi(segments, 3)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = NOISE_OCTAVES
	noise.seed = seed_value
	noise.frequency = 1.0
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var theta := TAU * float(i) / float(count)
		var n := noise.get_noise_2d(
				cos(theta) * RING_NOISE_RADIUS, sin(theta) * RING_NOISE_RADIUS)
		# remap01 is TerrainGen's noise [-1,1] -> [0,1]; reused so both generators
		# share one remap (and its clamp).
		var t := TerrainGen.remap01(n)
		out[i] = height * (CREST_MIN + (1.0 - CREST_MIN) * t)
	return out


## The three vertex rings, outermost radius first is NOT the order — returns
## [inner_base, crest, outer_base], each `segments` points long, in the ring's local
## frame (base rings on y = 0, crest at the heights above). Split out from build_mesh so
## the ring geometry is checkable on its own.
static func ring_points(radius: float, band_depth: float,
		heights: PackedFloat32Array) -> Array[PackedVector3Array]:
	var count := heights.size()
	var half := maxf(band_depth, 0.0) * 0.5
	var inner := PackedVector3Array()
	var crest := PackedVector3Array()
	var outer := PackedVector3Array()
	inner.resize(count)
	crest.resize(count)
	outer.resize(count)
	for i in count:
		var theta := TAU * float(i) / float(count)
		var dir := Vector3(cos(theta), 0.0, sin(theta))
		inner[i] = dir * maxf(radius - half, 0.0)
		crest[i] = dir * radius + Vector3(0.0, heights[i], 0.0)
		outer[i] = dir * (radius + half)
	var out: Array[PackedVector3Array] = [inner, crest, outer]
	return out


## The ridge mesh: two closed quad strips (inner base -> crest -> outer base), flat
## shaded. Every triangle carries its own three vertices and one face normal — hard-edged
## low-poly facets, and no shared-normal smoothing to soften the silhouette.
## Winding puts the inner slope's faces toward the ring centre (where the player is) and
## the outer slope's away, so the ridge is solid from both sides without two-sided culling.
static func build_mesh(radius: float, height: float, band_depth: float,
		seed_value: int, segments: int) -> ArrayMesh:
	var heights := crest_heights(segments, seed_value, height)
	var count := heights.size()
	var rings := ring_points(radius, band_depth, heights)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for strip in 2:
		var lo: PackedVector3Array = rings[strip]
		var hi: PackedVector3Array = rings[strip + 1]
		for i in count:
			var j := (i + 1) % count
			# One winding for both strips: the inner strip climbs lo->hi going OUTWARD
			# and the outer strip descends going outward, so the same vertex order lands
			# their normals on opposite radial sides (inner faces the centre, outer faces
			# away) and both tilt upward. Verified against the theta = 0 quad by hand.
			_add_tri(verts, normals, lo[i], hi[j], hi[i])
			_add_tri(verts, normals, lo[i], lo[j], hi[j])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## One flat-shaded triangle: three vertices plus the face normal repeated. A degenerate
## triangle (zero-area, e.g. band_depth 0) falls back to UP so the normal stays unit
## length and the mesh never carries NaNs.
static func _add_tri(verts: PackedVector3Array, normals: PackedVector3Array,
		a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	n = n.normalized() if n.length_squared() > 0.0 else Vector3.UP
	verts.append(a)
	verts.append(b)
	verts.append(c)
	normals.append(n)
	normals.append(n)
	normals.append(n)

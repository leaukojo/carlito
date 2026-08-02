extends GdUnitTestSuite
## SkylineGen pure fns: crest heights, ring points, ridge mesh.
## The ring is a closed loop, so the seam at theta = 0 is the interesting case; the rest
## is bounds, counts, and determinism (same seed, same ridge — same discipline as
## TerrainGen). Crest heights come back as float32, so bounds carry a small epsilon.

const Gen := preload("res://src/levels/base/skyline_gen.gd")

const EPS := 0.001


# --- crest heights ---


func test_crest_heights_length_matches_segments() -> void:
	assert_int(Gen.crest_heights(64, 1, 80.0).size()).is_equal(64)


func test_crest_heights_clamps_tiny_segment_counts() -> void:
	# A ring needs at least a triangle's worth of points.
	assert_int(Gen.crest_heights(0, 1, 80.0).size()).is_equal(3)
	assert_int(Gen.crest_heights(2, 1, 80.0).size()).is_equal(3)


func test_crest_heights_stay_in_band() -> void:
	# Never dips to sea level (that would open a gap in the silhouette) and never
	# overshoots the authored peak.
	for v in Gen.crest_heights(128, 7, 80.0):
		assert_float(v).is_greater_equal(80.0 * Gen.CREST_MIN - EPS)
		assert_float(v).is_less_equal(80.0 + EPS)


func test_crest_heights_are_deterministic_from_seed() -> void:
	var a := Gen.crest_heights(128, 7, 80.0)
	var b := Gen.crest_heights(128, 7, 80.0)
	var c := Gen.crest_heights(128, 8, 80.0)
	assert_bool(a == b).is_true()
	assert_bool(a == c).is_false()


func test_crest_heights_scale_linearly_with_height() -> void:
	var a := Gen.crest_heights(64, 3, 50.0)
	var b := Gen.crest_heights(64, 3, 100.0)
	for i in a.size():
		assert_float(b[i]).is_equal_approx(a[i] * 2.0, EPS)


func test_crest_heights_vary_around_the_ring() -> void:
	# A flat ring would read as a wall, not a ridge.
	var h := Gen.crest_heights(128, 7, 80.0)
	var lo := h[0]
	var hi := h[0]
	for v in h:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	assert_float(hi - lo).is_greater(80.0 * 0.1)


func test_crest_seam_is_continuous() -> void:
	# Noise sampled 2-D on the circle closes by construction: the step across the wrap
	# (last -> first) must be no worse than the worst step elsewhere. A 1-D angle
	# parametrization would tear right here.
	var h := Gen.crest_heights(128, 7, 80.0)
	var worst_interior := 0.0
	for i in range(h.size() - 1):
		worst_interior = maxf(worst_interior, absf(h[i + 1] - h[i]))
	assert_float(absf(h[0] - h[h.size() - 1])).is_less_equal(worst_interior)


# --- ring points ---


func test_ring_points_radii_and_base_plane() -> void:
	var h := Gen.crest_heights(32, 5, 60.0)
	var rings := Gen.ring_points(600.0, 220.0, h)
	assert_int(rings.size()).is_equal(3)
	for i in h.size():
		var inner: Vector3 = rings[0][i]
		var crest: Vector3 = rings[1][i]
		var outer: Vector3 = rings[2][i]
		assert_float(Vector2(inner.x, inner.z).length()).is_equal_approx(490.0, 0.01)
		assert_float(Vector2(crest.x, crest.z).length()).is_equal_approx(600.0, 0.01)
		assert_float(Vector2(outer.x, outer.z).length()).is_equal_approx(710.0, 0.01)
		# Both bases sit on the sea plane; only the crest rises.
		assert_float(inner.y).is_equal(0.0)
		assert_float(outer.y).is_equal(0.0)
		assert_float(crest.y).is_equal_approx(h[i], EPS)


func test_ring_points_are_radially_aligned() -> void:
	# Crest sits directly outboard of its inner base — the band never skews. Vector2
	# component math is float32, hence the 1e-5 tolerance rather than something tighter.
	var h := Gen.crest_heights(16, 5, 60.0)
	var rings := Gen.ring_points(600.0, 220.0, h)
	for i in h.size():
		var inner: Vector3 = rings[0][i]
		var crest: Vector3 = rings[1][i]
		var angle := Vector2(inner.x, inner.z).angle_to(Vector2(crest.x, crest.z))
		assert_float(angle).is_equal_approx(0.0, 1e-5)


func test_ring_points_clamp_inner_radius_at_origin() -> void:
	# band_depth wider than the ring must not fold the inner base to a negative radius.
	var h := Gen.crest_heights(8, 5, 60.0)
	var rings := Gen.ring_points(50.0, 400.0, h)
	for p: Vector3 in rings[0]:
		assert_float(Vector2(p.x, p.z).length()).is_equal_approx(0.0, EPS)


# --- mesh ---


func test_mesh_triangle_count() -> void:
	# Two quad strips of `segments` quads: 4 triangles per segment, 3 unshared verts
	# each (flat shading duplicates them).
	var mesh := Gen.build_mesh(600.0, 80.0, 220.0, 7, 64)
	assert_int(mesh.get_surface_count()).is_equal(1)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_int(verts.size()).is_equal(64 * 4 * 3)
	assert_int(normals.size()).is_equal(verts.size())


func test_mesh_normals_are_unit_length() -> void:
	var normals: PackedVector3Array = Gen.build_mesh(
			600.0, 80.0, 220.0, 7, 64).surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	for n in normals:
		assert_float(n.length()).is_equal_approx(1.0, EPS)


func test_mesh_normals_are_flat_per_face() -> void:
	# Hard-edged low-poly facets: the three verts of a triangle share one normal.
	var normals: PackedVector3Array = Gen.build_mesh(
			600.0, 80.0, 220.0, 7, 32).surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	for base in range(0, normals.size(), 3):
		assert_bool(normals[base].is_equal_approx(normals[base + 1])).is_true()
		assert_bool(normals[base].is_equal_approx(normals[base + 2])).is_true()


func test_mesh_slopes_face_away_from_the_crest() -> void:
	# Inner slope faces the ring centre (where the player is), outer slope faces away,
	# and both tilt upward — a flipped winding would cull the ridge away from inside.
	var arrays := Gen.build_mesh(600.0, 80.0, 220.0, 7, 64).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for base in range(0, verts.size(), 3):
		var centroid := (verts[base] + verts[base + 1] + verts[base + 2]) / 3.0
		var n := normals[base]
		assert_float(n.y).is_greater(0.0)
		var radial := Vector2(centroid.x, centroid.z)
		var outward := Vector2(n.x, n.z).dot(radial.normalized())
		if radial.length() < 600.0:
			assert_float(outward).is_less(0.0)      # inner slope looks inward
		else:
			assert_float(outward).is_greater(0.0)   # outer slope looks away


func test_mesh_extent_matches_radius_and_band() -> void:
	var aabb := Gen.build_mesh(600.0, 80.0, 220.0, 7, 128).get_aabb()
	assert_float(aabb.position.y).is_equal(0.0)
	assert_float(aabb.end.y).is_less_equal(80.0 + EPS)
	# Widest ring is the outer base at radius + band_depth / 2; a 128-gon's chord sag
	# is well under the 1 m tolerance.
	assert_float(aabb.end.x).is_equal_approx(710.0, 1.0)
	assert_float(aabb.position.x).is_equal_approx(-710.0, 1.0)


func test_mesh_is_deterministic_from_seed() -> void:
	var a: PackedVector3Array = Gen.build_mesh(
			600.0, 80.0, 220.0, 7, 64).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var b: PackedVector3Array = Gen.build_mesh(
			600.0, 80.0, 220.0, 7, 64).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var c: PackedVector3Array = Gen.build_mesh(
			600.0, 80.0, 220.0, 8, 64).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_bool(a == b).is_true()
	assert_bool(a == c).is_false()


func test_mesh_survives_a_zero_width_band() -> void:
	# Degenerate triangles must not produce NaN normals.
	var normals: PackedVector3Array = Gen.build_mesh(
			600.0, 80.0, 0.0, 7, 16).surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	for n in normals:
		assert_float(n.length()).is_equal_approx(1.0, EPS)

# GdUnit generated TestSuite
extends GdUnitTestSuite
## Unit tests for the scatter core: deterministic seeded
## placement (same seed = identical forest, forever), min-spacing guarantees,
## footprint containment, weighted item picks, the stored stride-5 layout, the
## stale-guard ground hash, and the shared item-mesh/shape harvesting.

const Scatter := preload("res://kit/helpers/scatter_region.gd")
const Canvas := preload("res://kit/helpers/scatter_canvas.gd")


func _square(half: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-half, -half), Vector2(half, -half),
			Vector2(half, half), Vector2(-half, half)])


func _params(overrides := {}) -> Dictionary:
	var p := {
		"polygon": _square(10.0),
		"density": 0.1,
		"min_spacing": 1.0,
		"seed": 1234,
		"weights": PackedFloat32Array([1.0]),
		"yaw_jitter_deg": 360.0,
		"scale_min": 0.9,
		"scale_max": 1.1,
	}
	for k in overrides:
		p[k] = overrides[k]
	return p


func _all_points(placements: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for flat: PackedFloat32Array in placements:
		@warning_ignore("integer_division")
		for j in flat.size() / 4:
			out.append(Vector2(flat[j * 4], flat[j * 4 + 1]))
	return out


# ------------------------------------------------------------------ determinism

func test_same_seed_identical_output() -> void:
	var a := Scatter.generate_placements(_params())
	var b := Scatter.generate_placements(_params())
	assert_that(a).is_equal(b)
	assert_bool(_all_points(a).size() > 0).is_true()


func test_different_seed_differs() -> void:
	var a := Scatter.generate_placements(_params())
	var b := Scatter.generate_placements(_params({"seed": 4321}))
	assert_that(a).is_not_equal(b)


# ---------------------------------------------------------------------- spacing

func test_min_spacing_respected_across_items() -> void:
	var placements := Scatter.generate_placements(_params({
		"weights": PackedFloat32Array([1.0, 1.0]),
		"density": 0.5,
		"min_spacing": 2.0,
	}))
	var pts := _all_points(placements)
	assert_bool(pts.size() > 5).is_true()
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			assert_bool(pts[i].distance_to(pts[j]) >= 2.0 - 0.0001).is_true()


func test_zero_spacing_reaches_density_target() -> void:
	# area 400 x density 0.05 = 20; nothing rejects, so the target is hit exactly.
	var placements := Scatter.generate_placements(_params({
		"density": 0.05, "min_spacing": 0.0}))
	assert_int(_all_points(placements).size()).is_equal(20)


func test_tight_spacing_caps_below_target() -> void:
	# 10 instances/m2 with 2 m spacing is unsatisfiable — the attempt budget must
	# terminate with a partial (but spacing-clean) fill, not loop forever.
	var placements := Scatter.generate_placements(_params({
		"density": 10.0, "min_spacing": 2.0}))
	var n := _all_points(placements).size()
	assert_bool(n > 0).is_true()
	assert_bool(n < 4000).is_true()


# ------------------------------------------------------------------ containment

func test_points_inside_box_polygon() -> void:
	var poly := _square(10.0)
	for p in _all_points(Scatter.generate_placements(_params())):
		assert_bool(Geometry2D.is_point_in_polygon(p, poly)).is_true()


func test_points_inside_concave_polygon() -> void:
	# L-shape: the notch (x>0, y>0 quadrant) must stay empty.
	var poly := PackedVector2Array([Vector2(-10, -10), Vector2(10, -10), Vector2(10, 0),
			Vector2(0, 0), Vector2(0, 10), Vector2(-10, 10)])
	var pts := _all_points(Scatter.generate_placements(_params({
		"polygon": poly, "density": 0.2})))
	assert_bool(pts.size() > 10).is_true()
	for p in pts:
		assert_bool(Geometry2D.is_point_in_polygon(p, poly)).is_true()
		assert_bool(p.x > 0.0 and p.y > 0.0).is_false()


# ---------------------------------------------------------------- items/weights

func test_weights_bias_item_pick() -> void:
	var placements := Scatter.generate_placements(_params({
		"weights": PackedFloat32Array([1.0, 9.0]),
		"density": 0.5,
		"min_spacing": 0.5,
	}))
	@warning_ignore("integer_division")
	var light := placements[0].size() / 4
	@warning_ignore("integer_division")
	var heavy := placements[1].size() / 4
	assert_bool(heavy > light * 2).is_true()


func test_jitter_ranges_respected() -> void:
	var placements := Scatter.generate_placements(_params({
		"yaw_jitter_deg": 90.0, "scale_min": 0.5, "scale_max": 0.6}))
	var flat := placements[0]
	@warning_ignore("integer_division")
	for j in flat.size() / 4:
		assert_bool(absf(flat[j * 4 + 2]) <= deg_to_rad(45.0) + 0.0001).is_true()
		var s := flat[j * 4 + 3]
		assert_bool(s >= 0.5 - 0.0001 and s <= 0.6 + 0.0001).is_true()


# ------------------------------------------------------------------- degenerate

func test_degenerate_inputs_yield_empty_per_item_arrays() -> void:
	assert_array(Scatter.generate_placements(_params({
		"weights": PackedFloat32Array()}))).is_empty()
	for placements in [
		Scatter.generate_placements(_params({"polygon": PackedVector2Array()})),
		Scatter.generate_placements(_params({"density": 0.0})),
		Scatter.generate_placements(_params({"weights": PackedFloat32Array([0.0])})),
	]:
		assert_int((placements as Array).size()).is_equal(1)
		assert_int(((placements as Array)[0] as PackedFloat32Array).size()).is_equal(0)


# ----------------------------------------------------------------- polygon area

func test_polygon_area() -> void:
	assert_float(Scatter.polygon_area(_square(10.0))).is_equal_approx(400.0, 0.001)
	var tri := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(0, 3)])
	assert_float(Scatter.polygon_area(tri)).is_equal_approx(6.0, 0.001)
	tri.reverse()   # winding-agnostic
	assert_float(Scatter.polygon_area(tri)).is_equal_approx(6.0, 0.001)
	assert_float(Scatter.polygon_area(PackedVector2Array([Vector2.ZERO, Vector2.ONE]))) \
			.is_equal_approx(0.0, 0.001)


# ----------------------------------------------------------- stored transforms

func test_stored_transform_decodes_stride5() -> void:
	var flat := PackedFloat32Array([0, 0, 0, 0, 1, 1.0, 2.0, 3.0, PI / 2.0, 2.0])
	assert_int(Scatter.stored_count(flat)).is_equal(2)
	var t := Scatter.stored_transform(flat, 1)
	assert_that(t.origin).is_equal(Vector3(1, 2, 3))
	assert_float(t.basis.get_scale().x).is_equal_approx(2.0, 0.001)
	# yaw PI/2 turns local +X toward -Z (right-handed Y rotation), scaled by 2
	assert_float((t.basis * Vector3.RIGHT).z).is_equal_approx(-2.0, 0.001)


# ------------------------------------------------------------------ ground hash

func _terrain(img: Image, terrain_name: String) -> Node3D:
	var t := StaticBody3D.new()
	t.name = terrain_name
	t.set_script(load("res://src/levels/base/heightmap_terrain.gd"))
	t.set("heightmap", ImageTexture.create_from_image(img))
	return t


func _flat_img(shade := 0.5) -> Image:
	var img := Image.create(8, 8, false, Image.FORMAT_L8)
	img.fill(Color(shade, shade, shade))
	return img


func test_ground_hash_empty_without_terrain() -> void:
	var root: Node3D = auto_free(Node3D.new())
	assert_str(Scatter.ground_hash(root)).is_empty()


func test_ground_hash_stable_and_sensitive() -> void:
	var a: Node3D = auto_free(Node3D.new())
	a.add_child(_terrain(_flat_img(), "T"))
	var b: Node3D = auto_free(Node3D.new())
	b.add_child(_terrain(_flat_img(), "T"))
	assert_str(Scatter.ground_hash(a)).is_equal(Scatter.ground_hash(b))

	var img := _flat_img()
	img.set_pixel(3, 3, Color(0.9, 0.9, 0.9))   # one sculpted pixel
	var c: Node3D = auto_free(Node3D.new())
	c.add_child(_terrain(img, "T"))
	assert_str(Scatter.ground_hash(c)).is_not_equal(Scatter.ground_hash(a))


func test_ground_hash_tracks_amplitude() -> void:
	var a: Node3D = auto_free(Node3D.new())
	a.add_child(_terrain(_flat_img(), "T"))
	var b: Node3D = auto_free(Node3D.new())
	var t := _terrain(_flat_img(), "T")
	t.set("height", 99.0)   # same pixels, different world amplitude = different ground
	b.add_child(t)
	assert_str(Scatter.ground_hash(a)).is_not_equal(Scatter.ground_hash(b))


# --------------------------------------------------- item mesh / shape harvest

func _template() -> Node3D:
	var root := Node3D.new()
	var a := MeshInstance3D.new()
	a.mesh = BoxMesh.new()
	root.add_child(a)
	var b := MeshInstance3D.new()
	b.mesh = BoxMesh.new()
	b.position = Vector3(5, 0, 0)
	root.add_child(b)
	var body := StaticBody3D.new()
	body.position = Vector3(0, 1, 0)
	root.add_child(body)
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	cs.position = Vector3(0, 0.5, 0)
	body.add_child(cs)
	return root


func test_build_item_mesh_merges_in_prefab_space() -> void:
	var template: Node3D = auto_free(_template())
	var mesh := Scatter.build_item_mesh(template)
	assert_int(mesh.get_surface_count()).is_equal(1)   # same (null) material merges
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var box_verts := (BoxMesh.new().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			as PackedVector3Array).size()
	assert_int(verts.size()).is_equal(box_verts * 2)
	var max_x := 0.0
	for v in verts:
		max_x = maxf(max_x, v.x)
	assert_float(max_x).is_equal_approx(5.5, 0.001)   # second box carried its offset


func test_shape_entries_accumulate_local_transforms() -> void:
	var template: Node3D = auto_free(_template())
	var entries := Scatter.shape_entries(template)
	assert_int(entries.size()).is_equal(1)
	assert_that((entries[0][1] as Transform3D).origin).is_equal(Vector3(0, 1.5, 0))


# --------------------------------------------------------------------- canvas

## The shared statics live on ScatterBase; the two front-ends must resolve them identically
## (GDScript inherits statics), so the baker can duck-call them on a region or a canvas.
func test_canvas_inherits_shared_statics() -> void:
	var flat := PackedFloat32Array([1.0, 2.0, 3.0, 0.0, 1.0])
	assert_int(Canvas.stored_count(flat)).is_equal(1)
	assert_that(Canvas.stored_transform(flat, 0).origin).is_equal(Vector3(1, 2, 3))
	var root: Node3D = auto_free(Node3D.new())
	assert_str(Canvas.ground_hash(root)).is_empty()


## Erase drops exactly the instances whose world XZ falls inside the brush disc; Y is ignored
## (it is a top-down radius), and the canvas transform is applied (stored data is region-local).
func test_canvas_erase_within_radius() -> void:
	# Three instances at region-local x = 0, 5, 20 (z = 0). Canvas is offset +100 in world X.
	var flat := PackedFloat32Array([
		0.0, 9.0, 0.0, 0.0, 1.0,     # world x = 100 (Y ignored)
		5.0, 0.0, 0.0, 0.0, 1.0,     # world x = 105
		20.0, 0.0, 0.0, 0.0, 1.0])   # world x = 120
	var base := Transform3D(Basis.IDENTITY, Vector3(100, 0, 0))
	# Radius 6 around world (104, *, 0): catches x=100 and x=105, spares x=120.
	var out := Canvas.erase_within([flat], base, Vector3(104, 0, 0), 6.0)
	assert_int(Canvas.stored_count(out[0])).is_equal(1)
	assert_that(Canvas.stored_transform(out[0], 0).origin).is_equal(Vector3(20, 0, 0))


func test_canvas_erase_empty_when_all_inside() -> void:
	var flat := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 1.0])
	var out := Canvas.erase_within([flat], Transform3D.IDENTITY, Vector3.ZERO, 100.0)
	assert_int(Canvas.stored_count(out[0])).is_equal(0)


# ------------------------------------------------------- grid pattern (lattice fill)

func _rect(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0),
			Vector2(x1, z1), Vector2(x0, z1)])


func _grid_params(overrides := {}) -> Dictionary:
	var p := {
		"polygon": _rect(0.0, 0.0, 10.0, 10.0),
		"step": Vector2(1.0, 1.0),
		"seed": 7,
		"weights": PackedFloat32Array([1.0]),
		"yaw_jitter_deg": 0.0,
		"scale_min": 1.0,
		"scale_max": 1.0,
	}
	for k in overrides:
		p[k] = overrides[k]
	return p


func test_grid_fills_every_cell_centre() -> void:
	# 10x10 m at 1 m step -> cell centres at 0.5 .. 9.5 on each axis = 100 points.
	var pts := _all_points(Scatter.generate_grid_placements(_grid_params()))
	assert_int(pts.size()).is_equal(100)
	for p in pts:
		assert_bool(is_equal_approx(fposmod(p.x, 1.0), 0.5)).is_true()
		assert_bool(is_equal_approx(fposmod(p.y, 1.0), 0.5)).is_true()


func test_grid_step_controls_count() -> void:
	var pts := _all_points(Scatter.generate_grid_placements(
			_grid_params({"step": Vector2(2.0, 5.0)})))
	assert_int(pts.size()).is_equal(5 * 2)


func test_grid_is_world_anchored_across_abutting_fills() -> void:
	# Two rectangles meeting at x = 5 must tile ONE lattice: no duplicate, no gap.
	var a := _all_points(Scatter.generate_grid_placements(
			_grid_params({"polygon": _rect(0.0, 0.0, 5.0, 10.0)})))
	var b := _all_points(Scatter.generate_grid_placements(
			_grid_params({"polygon": _rect(5.0, 0.0, 10.0, 10.0)})))
	assert_int(a.size() + b.size()).is_equal(100)
	for p in a:
		assert_bool(b.has(p)).is_false()


func test_grid_deterministic() -> void:
	var a := Scatter.generate_grid_placements(_grid_params())
	var b := Scatter.generate_grid_placements(_grid_params())
	assert_that(a).is_equal(b)


func test_grid_zero_jitter_is_exactly_uniform() -> void:
	for flat: PackedFloat32Array in Scatter.generate_grid_placements(_grid_params()):
		@warning_ignore("integer_division")
		for j in flat.size() / 4:
			assert_float(flat[j * 4 + 2]).is_equal(0.0)   # yaw
			assert_float(flat[j * 4 + 3]).is_equal(1.0)   # scale


func test_grid_offset_rect_stays_on_the_same_lattice() -> void:
	# A rectangle not aligned to the step still snaps to the world lattice.
	var pts := _all_points(Scatter.generate_grid_placements(
			_grid_params({"polygon": _rect(-3.3, -3.3, 1.2, 1.2)})))
	assert_bool(pts.size() > 0).is_true()
	for p in pts:
		assert_bool(is_equal_approx(fposmod(p.x, 1.0), 0.5)).is_true()


func test_grid_rejects_bad_step() -> void:
	var out := Scatter.generate_grid_placements(_grid_params({"step": Vector2.ZERO}))
	assert_int(_all_points(out).size()).is_equal(0)

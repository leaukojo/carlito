extends GdUnitTestSuite
## StaticMeshMerge: candidate selection, per-material surface grouping, world-space vertex and
## winding fidelity through a rotated/scaled/mirrored child transform, skip lists (leaf and whole
## subtree), hidden-not-freed originals, and idempotency. Its vertex math is a copy of the
## baker's SurfaceAccumulator, so test_bake.gd does not cover it — this suite does.

const Merge := preload("res://src/vehicles/base/static_mesh_merge.gd")


## One unit quad (two indexed triangles), normal up, on `material` if given.
func _quad_mesh(material: Material = null) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null:
		mesh.surface_set_material(0, material)
	return mesh


func _mesh_child(name_: String, material: Material = null, xform := Transform3D.IDENTITY) -> MeshInstance3D:
	var mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	mi.name = name_
	mi.mesh = _quad_mesh(material)
	mi.transform = xform
	return mi


## The one merged child StaticMeshMerge added directly under `parent`, or null if none.
func _merged_of(parent: Node) -> MeshInstance3D:
	for child in parent.get_children():
		if Merge.is_merged(child):
			return child as MeshInstance3D
	return null


# --- candidate selection ---------------------------------------------------------------------

func test_a_lone_mesh_child_is_left_alone() -> void:
	var parent: Node3D = auto_free(Node3D.new())
	parent.add_child(_mesh_child("Only"))
	Merge.merge_subtree(parent)
	assert_object(_merged_of(parent)).is_null()
	assert_bool((parent.get_node("Only") as MeshInstance3D).visible).is_true()


func test_two_or_more_siblings_fold_into_one_merged_child() -> void:
	var parent: Node3D = auto_free(Node3D.new())
	parent.add_child(_mesh_child("A"))
	parent.add_child(_mesh_child("B"))
	parent.add_child(_mesh_child("C"))
	Merge.merge_subtree(parent)
	var merged := _merged_of(parent)
	assert_object(merged).is_not_null()
	assert_str(merged.name).is_equal("MergedMesh")


func test_never_merges_across_a_pivot() -> void:
	# Two children directly on the parent, two more one level down under a pivot Node3D — the
	# pivot's own children must fold into THEIR OWN merged node, never the parent's.
	var parent: Node3D = auto_free(Node3D.new())
	parent.add_child(_mesh_child("A"))
	parent.add_child(_mesh_child("B"))
	var pivot: Node3D = auto_free(Node3D.new())
	pivot.name = "Pivot"
	parent.add_child(pivot)
	pivot.add_child(_mesh_child("PA"))
	pivot.add_child(_mesh_child("PB"))
	Merge.merge_subtree(parent)
	assert_object(_merged_of(parent)).is_not_null()
	assert_object(_merged_of(pivot)).is_not_null()
	# The parent's own merged mesh carries only its two direct quads, not the pivot's.
	assert_int(_merged_of(parent).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()).is_equal(8)


# --- per-material surface grouping ---------------------------------------------------------------

func test_surface_count_is_distinct_material_count() -> void:
	var mat_a := StandardMaterial3D.new()
	var mat_b := StandardMaterial3D.new()
	var parent: Node3D = auto_free(Node3D.new())
	parent.add_child(_mesh_child("A1", mat_a))
	parent.add_child(_mesh_child("A2", mat_a))
	parent.add_child(_mesh_child("B1", mat_b))
	Merge.merge_subtree(parent)
	var merged := _merged_of(parent)
	assert_int(merged.mesh.get_surface_count()).is_equal(2)
	# Vertex count is preserved across the merge regardless of the surface split.
	var total := 0
	for s in merged.mesh.get_surface_count():
		total += (merged.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_int(total).is_equal(12)  # 3 quads * 4 verts


func test_a_surface_carries_the_material_its_group_shared() -> void:
	var mat_a := StandardMaterial3D.new()
	var mat_b := StandardMaterial3D.new()
	var parent: Node3D = auto_free(Node3D.new())
	parent.add_child(_mesh_child("A", mat_a))
	parent.add_child(_mesh_child("B", mat_b))
	Merge.merge_subtree(parent)
	var merged := _merged_of(parent)
	var mats: Array[Material] = []
	for s in merged.mesh.get_surface_count():
		mats.append(merged.mesh.surface_get_material(s))
	assert_bool(mats.has(mat_a)).override_failure_message("mat_a's surface went missing").is_true()
	assert_bool(mats.has(mat_b)).override_failure_message("mat_b's surface went missing").is_true()


# --- world-space fidelity through the child transform ---------------------------------------

func test_positions_and_normals_survive_a_rotated_scaled_mirrored_child() -> void:
	var mat := StandardMaterial3D.new()
	var parent: Node3D = auto_free(Node3D.new())
	# Straight copy, identity.
	parent.add_child(_mesh_child("Plain", mat))
	# Rotated 90 deg about Y and pushed off-origin.
	var rot := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(5, 0, 0))
	parent.add_child(_mesh_child("Rotated", mat, rot))
	# Non-uniform scale.
	var scaled := Transform3D(Basis.IDENTITY.scaled(Vector3(2, 1, 3)), Vector3(0, 5, 0))
	parent.add_child(_mesh_child("Scaled", mat, scaled))
	# Mirrored (negative determinant): winding must flip, normals must stay outward.
	var mirrored := Transform3D(Basis.IDENTITY.scaled(Vector3(-1, 1, 1)), Vector3(0, 0, 5))
	parent.add_child(_mesh_child("Mirrored", mat, mirrored))

	var expected_positions: Array[Vector3] = []
	for child in parent.get_children():
		var mi := child as MeshInstance3D
		var src: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v in src:
			expected_positions.append(mi.transform * v)

	Merge.merge_subtree(parent)
	var merged := _merged_of(parent)
	var out_pos: PackedVector3Array = merged.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var out_norm: PackedVector3Array = merged.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	assert_int(out_pos.size()).is_equal(expected_positions.size())
	for i in out_pos.size():
		assert_vector(out_pos[i]) \
			.override_failure_message("vertex %d drifted from its child transform" % i) \
			.is_equal_approx(expected_positions[i], Vector3.ONE * 0.0001)
		assert_float(out_norm[i].length()).is_equal_approx(1.0, 0.0001)
	# The source quad's triangles face against their normal (cross(b - a, c - a) . n < 0). The
	# merge must keep that orientation — the mirrored child only does if its winding is flipped.
	var idx: PackedInt32Array = merged.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	for t in range(0, idx.size(), 3):
		var a := out_pos[idx[t]]
		var face := (out_pos[idx[t + 1]] - a).cross(out_pos[idx[t + 2]] - a)
		assert_float(face.dot(out_norm[idx[t]])) \
			.override_failure_message("triangle at index %d is wound inside-out" % t) \
			.is_less(0.0)


# --- hidden, not freed -------------------------------------------------------------------------

func test_originals_are_hidden_not_freed() -> void:
	var parent: Node3D = auto_free(Node3D.new())
	parent.add_child(_mesh_child("A"))
	parent.add_child(_mesh_child("B"))
	Merge.merge_subtree(parent)
	for name_ in ["A", "B"]:
		var n := parent.get_node(NodePath(name_)) as MeshInstance3D
		assert_object(n).override_failure_message("%s was freed, not hidden" % name_).is_not_null()
		assert_bool(n.visible).override_failure_message("%s stayed visible" % name_).is_false()
	assert_bool(_merged_of(parent).visible).is_true()


# --- skip lists ----------------------------------------------------------------------------------

func test_a_skipped_leaf_never_joins_the_group() -> void:
	var parent: Node3D = auto_free(Node3D.new())
	parent.add_child(_mesh_child("A"))
	parent.add_child(_mesh_child("B"))
	var moved := _mesh_child("Moved")
	parent.add_child(moved)
	Merge.merge_subtree(parent, [moved])
	assert_bool(moved.visible).override_failure_message("a skipped leaf was hidden").is_true()
	var merged := _merged_of(parent)
	var verts: PackedVector3Array = merged.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_int(verts.size()).override_failure_message("the skipped leaf's quad leaked into the merge") \
		.is_equal(8)  # A + B only


func test_a_skipped_subtree_is_never_descended_into() -> void:
	var parent: Node3D = auto_free(Node3D.new())
	parent.add_child(_mesh_child("A"))
	parent.add_child(_mesh_child("B"))
	var wheels: Node3D = auto_free(Node3D.new())
	wheels.name = "Wheels"
	parent.add_child(wheels)
	wheels.add_child(_mesh_child("WA"))
	wheels.add_child(_mesh_child("WB"))
	Merge.merge_subtree(parent, [wheels])
	assert_object(_merged_of(wheels)) \
		.override_failure_message("a skipped subtree was still walked and merged").is_null()
	for name_ in ["WA", "WB"]:
		assert_bool((wheels.get_node(NodePath(name_)) as MeshInstance3D).visible).is_true()


# --- idempotency -----------------------------------------------------------------------------

func test_merging_twice_does_not_re_merge_or_merge_the_merged_node() -> void:
	var parent: Node3D = auto_free(Node3D.new())
	parent.add_child(_mesh_child("A"))
	parent.add_child(_mesh_child("B"))
	Merge.merge_subtree(parent)
	var first_child_count := parent.get_child_count()
	var first_verts: PackedVector3Array = _merged_of(parent).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

	Merge.merge_subtree(parent)
	assert_int(parent.get_child_count()) \
		.override_failure_message("a second merge added another MergedMesh").is_equal(first_child_count)
	var second_verts: PackedVector3Array = _merged_of(parent).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_int(second_verts.size()).is_equal(first_verts.size())

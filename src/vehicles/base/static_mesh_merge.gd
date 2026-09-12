class_name StaticMeshMerge
extends RefCounted
## Folds a Node3D subtree's static MeshInstance3D children into one merged mesh per PIVOT GROUP:
## every Node3D with >= 2 direct MeshInstance3D children (after skips) gets one new "MergedMesh"
## child, one surface per distinct get_active_material(surface). Never merges across a pivot — a
## mesh only joins its own direct parent's group — so an articulating part (a rockshaft arm, the
## farm tipper's TipBody) keeps posing the merged node exactly like it posed the originals.
##
## Originals are HIDDEN, never freed: farm_tipper.gd reads the Ram/Rod CylinderMesh height off its
## own scene, and the geometry sweeps in tests/test_three_point_hitch.gd walk MeshInstance3D AABBs
## expecting the ORIGINAL per-part boxes, not one conservative union — a hidden mesh costs no draw
## call either way. Merging is idempotent: a node tagged MERGED_META is never folded again, and a
## hidden original is never picked up as a candidate on a second pass.
##
## The per-vertex math (positions by the full transform, normals by the inverse-transpose basis
## re-normalized, triangle winding reversed when the transform mirrors) is a LOCAL COPY of
## kit/bake/level_baker.gd's SurfaceAccumulator rather than a preload of it: the baker is
## level-authoring tooling (BAKE_CODE_INPUTS, headless-bake concerns) and src/vehicles/ has no
## business depending on kit/. UVs and vertex colours carry only when every merged surface has
## them, the same rule SurfaceAccumulator uses; tangents are dropped (the kit is flat-colour, like
## the baker's own copy). Unlike the baker, surfaces here are NOT quantized
## (ARRAY_FLAG_COMPRESS_ATTRIBUTES): these are small, close-to-camera parts, not level chunks,
## and full-precision normals matter more on a thin rod than the vertex-buffer bytes are worth.

## Meta key marking a node as StaticMeshMerge's own output — never a merge candidate, and never
## re-merged into a group of its own.
const MERGED_META := &"static_mesh_merge"


## True for a node StaticMeshMerge produced. Geometry sweeps (tyre clearance, the PTO envelope,
## `_lowest_y`) must skip these: a merged node's AABB is the union of everything folded into it,
## which reads as a false clearance failure where the original per-part boxes did not — read the
## hidden originals instead, which the same find_children sweep still returns.
static func is_merged(node: Node) -> bool:
	return node is Node and node.has_meta(MERGED_META)


## Recursively fold every eligible Node3D in `root`'s subtree (root included).
##
## `skip` excludes specific nodes: a MeshInstance3D in it is never folded into its parent's group
## (an implement's Gate/RamRod, the farm tipper's Ram/Rod, a lamp lens LampSet binds by NodePath —
## see LampSet.bound_meshes); any OTHER node in it (Wheels) is not merged and not descended into
## at all, since a wheel-scene instance's own children are re-based per side by the spawn code and
## must never be touched.
static func merge_subtree(root: Node, skip: Array[Node] = []) -> void:
	_walk(root, skip)


static func _walk(node: Node, skip: Array[Node]) -> void:
	if skip.has(node):
		return
	if node is Node3D:
		_merge_direct_children(node as Node3D, skip)
	for child in node.get_children():
		_walk(child, skip)


## Merge `parent`'s own DIRECT MeshInstance3D children only — a grandchild belongs to its own
## parent's group. Skips a child in `skip`, an already-merged node, and anything already hidden by
## an earlier merge, so a second call on the same subtree is a no-op.
static func _merge_direct_children(parent: Node3D, skip: Array[Node]) -> void:
	var candidates: Array[MeshInstance3D] = []
	for child in parent.get_children():
		var mi := child as MeshInstance3D
		if mi == null or skip.has(mi) or is_merged(mi) or not mi.visible or mi.mesh == null:
			continue
		candidates.append(mi)
	if candidates.size() < 2:
		return

	var order: Array[Material] = []
	var accum_by_material: Dictionary = {}  # Material (or null) -> _Accumulator
	for mi in candidates:
		var mesh := mi.mesh
		for s in mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if not accum_by_material.has(mat):
				accum_by_material[mat] = _Accumulator.new()
				order.append(mat)
			(accum_by_material[mat] as _Accumulator).append(mesh.surface_get_arrays(s), mi.transform)
	if order.is_empty():
		return

	var merged := MeshInstance3D.new()
	merged.name = "MergedMesh"
	var out_mesh := ArrayMesh.new()
	for mat in order:
		(accum_by_material[mat] as _Accumulator).commit(out_mesh, mat)
	merged.mesh = out_mesh
	merged.cast_shadow = candidates[0].cast_shadow
	merged.set_meta(MERGED_META, true)
	parent.add_child(merged)

	for mi in candidates:
		mi.visible = false


## Per-material vertex accumulator. A local copy of kit/bake/level_baker.gd's SurfaceAccumulator —
## see this file's header for why it is copied rather than shared.
class _Accumulator:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var has_uv := false
	var has_color := false

	func append(arrays: Array, xform: Transform3D) -> void:
		var src_pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base := positions.size()
		for v in src_pos:
			positions.push_back(xform * v)

		var nbasis := xform.basis.inverse().transposed()
		var src_n: Variant = arrays[Mesh.ARRAY_NORMAL]
		if src_n is PackedVector3Array and (src_n as PackedVector3Array).size() == src_pos.size():
			for n: Vector3 in src_n:
				normals.push_back((nbasis * n).normalized())
		else:
			for i in src_pos.size():
				normals.push_back(Vector3.UP)

		var src_uv: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var uv_ok: bool = src_uv is PackedVector2Array \
				and (src_uv as PackedVector2Array).size() == src_pos.size()
		if uv_ok and not has_uv:
			has_uv = true
			uvs.resize(base)  # zero-fill earlier vertices
		if has_uv:
			if uv_ok:
				uvs.append_array(src_uv)
			else:
				uvs.resize(uvs.size() + src_pos.size())

		var src_col: Variant = arrays[Mesh.ARRAY_COLOR]
		var col_ok: bool = src_col is PackedColorArray \
				and (src_col as PackedColorArray).size() == src_pos.size()
		if col_ok and not has_color:
			has_color = true
			for i in base:
				colors.push_back(Color.WHITE)
		if has_color:
			if col_ok:
				colors.append_array(src_col)
			else:
				for i in src_pos.size():
					colors.push_back(Color.WHITE)

		# A mirroring transform (negative determinant) flips triangle handedness; copying the
		# index order verbatim would render the merged part inside-out under cull_back.
		var flip := xform.basis.determinant() < 0.0
		var src_idx: Variant = arrays[Mesh.ARRAY_INDEX]
		var src: PackedInt32Array
		if src_idx is PackedInt32Array and (src_idx as PackedInt32Array).size() > 0:
			src = src_idx
		else:
			src = PackedInt32Array()
			src.resize(src_pos.size())
			for i in src_pos.size():
				src[i] = i
		if flip:
			for i in range(0, src.size() - 2, 3):
				indices.push_back(base + src[i])
				indices.push_back(base + src[i + 2])
				indices.push_back(base + src[i + 1])
		else:
			for ix: int in src:
				indices.push_back(base + ix)

	func commit(mesh: ArrayMesh, material: Material) -> void:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		if has_uv:
			arrays[Mesh.ARRAY_TEX_UV] = uvs
		if has_color:
			arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var si := mesh.get_surface_count() - 1
		if material != null:
			mesh.surface_set_material(si, material)

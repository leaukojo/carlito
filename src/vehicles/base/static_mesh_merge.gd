class_name StaticMeshMerge
extends RefCounted
## Folds a Node3D subtree's static MeshInstance3D children into one "MergedMesh" per PIVOT GROUP
## (a Node3D's direct mesh children), one surface per material, so articulating parts still pose.
## Originals are HIDDEN, never freed (farm_tipper.gd and the hitch sweeps read per-part meshes).
##
## The vertex math is a LOCAL COPY of `SurfaceAccumulator` in kit/bake/level_baker.gd: src/vehicles/
## must not depend on hash-stamped kit/ code. Unlike the baker it does not quantize: full-precision
## normals matter more on a thin rod near the camera than the bytes saved.

## Meta key marking a node as StaticMeshMerge's own output.
const MERGED_META := &"static_mesh_merge"


## True for a node StaticMeshMerge produced. Geometry sweeps (tyre clearance, the PTO envelope)
## must skip these: a merged node's AABB is the union of everything folded into it, which reads as
## a false clearance failure. Read the hidden originals instead.
static func is_merged(node: Node) -> bool:
	return node is Node and node.has_meta(MERGED_META)


## Recursively fold every eligible Node3D in `root`'s subtree (root included).
##
## `skip` excludes specific nodes: a MeshInstance3D in it is never folded into its parent's group
## (an implement's Gate/RamRod, the farm tipper's Ram/Rod, a lamp lens: `LampSet.bound_meshes`);
## any OTHER node in it (Wheels) is not descended into at all, since the spawn code re-bases a
## wheel instance's children per side.
static func merge_subtree(root: Node, skip: Array[Node] = []) -> void:
	_walk(root, skip)


static func _walk(node: Node, skip: Array[Node]) -> void:
	if skip.has(node):
		return
	if node is Node3D:
		_merge_direct_children(node as Node3D, skip)
	for child in node.get_children():
		_walk(child, skip)


## Merge `parent`'s own DIRECT MeshInstance3D children only. Skips a child in `skip`, a merged
## node, and anything hidden, so a second call on the same subtree is a no-op.
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


## Per-material vertex accumulator (copy of `SurfaceAccumulator`; see the header).
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

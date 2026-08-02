extends SceneTree
## Dev utility: print the merged mesh AABB of imported kit GLBs so per-kit
## root_scale / cell_size / alignment can be derived (kit/import/*.json recipes).
## Run after an import pass:
##   godot --headless --path . --script res://tools/measure_kit.gd -- kit/raw/roads [name-filter]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- <folder under res://> [substring filter]")
		quit(1)
		return
	var folder := "res://" + String(args[0]).trim_prefix("res://")
	var filter := String(args[1]) if args.size() > 1 else ""
	var dir := DirAccess.open(folder)
	if dir == null:
		print("cannot open ", folder)
		quit(1)
		return
	var names := []
	for f in dir.get_files():
		if f.ends_with(".glb") and (filter.is_empty() or f.contains(filter)):
			names.append(f)
	names.sort()
	for f in names:
		var scene := load(folder.path_join(f)) as PackedScene
		if scene == null:
			print(f, "  LOAD FAILED")
			continue
		var inst := scene.instantiate()
		var aabb := _merged_aabb(inst, Transform3D.IDENTITY)
		inst.free()
		print("%-42s size=(%.3f, %.3f, %.3f)  min=(%.3f, %.3f, %.3f)  max=(%.3f, %.3f, %.3f)" % [
			f, aabb.size.x, aabb.size.y, aabb.size.z,
			aabb.position.x, aabb.position.y, aabb.position.z,
			aabb.end.x, aabb.end.y, aabb.end.z])
	quit(0)


func _merged_aabb(node: Node, xform: Transform3D) -> AABB:
	var aabb := AABB()
	var first := true
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		aabb = xform * (node as MeshInstance3D).mesh.get_aabb()
		first = false
	for child in node.get_children():
		var cx := xform
		if child is Node3D:
			cx = xform * (child as Node3D).transform
		var ca := _merged_aabb(child, cx)
		if ca.size != Vector3.ZERO or ca.position != Vector3.ZERO:
			aabb = ca if first else aabb.merge(ca)
			first = false
	return aabb

extends RefCounted
## Shared walk: the worst forward-swing radius about the kingpin, over every BoxMesh corner ahead
## of it. Shared by test_trailer.gd (checks it against each trailer's own clearance) and
## test_truck.gd (checks it against each tractor unit's kingpin-to-cab-structure gap), so both
## check the same physical swing figure rather than duplicating the walk.


## Worst swing radius about the kingpin over every BoxMesh corner ahead of it, walked recursively
## with the transforms accumulated by hand (an instantiated scene is not in a tree). Corners rather
## than a half-width-plus-overhang formula, because the tipper's body lives under a rotating pivot.
## Returns [radius, name].
static func worst_forward_swing(node: Node, xf: Transform3D, worst: Array) -> void:
	for child in node.get_children():
		var n3 := child as Node3D
		if n3 == null:
			continue
		var here := xf * n3.transform
		var mesh_node := n3 as MeshInstance3D
		if mesh_node != null and mesh_node.mesh is BoxMesh:
			var half: Vector3 = (mesh_node.mesh as BoxMesh).size * 0.5
			var signs: Array[float] = [-1.0, 1.0]
			for sx in signs:
				for sy in signs:
					for sz in signs:
						var p: Vector3 = here * Vector3(sx * half.x, sy * half.y, sz * half.z)
						# Behind the kingpin it swings away from the cab; only what is ahead can reach it.
						if p.z >= 0.0:
							continue
						var r := Vector2(p.x, p.z).length()
						if r > float(worst[0]):
							worst[0] = r
							worst[1] = String(n3.name)
		worst_forward_swing(n3, here, worst)

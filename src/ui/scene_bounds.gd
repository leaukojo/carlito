extends RefCounted
## World-space AABB of a subtree's visible geometry. Shared by VehicleShot (the live
## turntable + vehicle card thumbnails), gen_thumbs.gd (kit prefab thumbnails) and
## gen_level_thumbs.gd (level card overview framing). Runtime-safe (no editor APIs) so it
## stays reachable from src/ui at runtime as well as from tools/ generators.


## World-space bounds spanning every root's visible geometry.
static func world_aabb(roots: Array[Node3D]) -> AABB:
	var out := AABB()
	var first := true
	for root in roots:
		if root == null or not is_instance_valid(root):
			continue
		for vi in visuals(root):
			var local := vi.get_aabb()
			var g := vi.global_transform
			for i in 8:
				var corner := local.position + Vector3(
						local.size.x if (i & 1) else 0.0,
						local.size.y if (i & 2) else 0.0,
						local.size.z if (i & 4) else 0.0)
				var w := g * corner
				if first:
					out = AABB(w, Vector3.ZERO)
					first = false
				else:
					out = out.expand(w)
	return out


static func visuals(node: Node) -> Array[VisualInstance3D]:
	var found: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(visuals(child))
	return found

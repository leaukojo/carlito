@tool
extends RefCounted
## Shared editor ground resolution — the ground-snap fallback chain, extracted from
## placement_tool.gd so the road draw tool reuses it verbatim: physics raycast
## first, then each HeightmapTerrain's height sample, then the Y=0 plane. A click
## never dead-drops; every branch yields a point. Editor-only (addons never ship).

const RAY_LEN := 100000.0


## Fallback chain: physics hit -> HeightmapTerrain sample -> Y=0 plane.
## `excludes` keeps caller-owned collision (the placement ghost) out of the ray.
static func ground_point(camera: Camera3D, mouse_pos: Vector2,
		excludes: Array[RID]) -> Vector3:
	var origin := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	var scene_root := EditorInterface.get_edited_scene_root()

	if scene_root is Node3D:
		var space := (scene_root as Node3D).get_world_3d().direct_space_state
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(
					origin, origin + dir * RAY_LEN, 0xFFFFFFFF, excludes)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				return hit.position

	# Physics missed (editor space not always populated). Try each terrain by sampling
	# its height at where the ray crosses the terrain's base plane.
	if scene_root != null:
		for terrain in scene_root.find_children("*", "HeightmapTerrain", true, false):
			var xz := ray_plane(origin, dir, terrain.global_position.y)
			if xz != null and terrain.contains_xz(xz):
				return Vector3(xz.x, terrain.height_at(xz), xz.z)

	var flat := ray_plane(origin, dir, 0.0)
	return flat if flat != null else origin + dir * 10.0


## Ray vs. the horizontal plane Y=plane_y. Null when the ray is parallel / points away.
static func ray_plane(origin: Vector3, dir: Vector3, plane_y: float) -> Variant:
	if absf(dir.y) < 1e-6:
		return null
	var t := (plane_y - origin.y) / dir.y
	if t < 0.0:
		return null
	return origin + dir * t

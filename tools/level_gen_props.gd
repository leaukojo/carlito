## Authoring-node helpers shared by the level generators that dress a level with kit pieces
## (`gen_farm_playground.gd`, `gen_skyport.gd`). Every piece is positioned from its measured
## merged mesh AABB, never a guessed origin convention. Failures print under the caller's `tag`.


## The merged AABB of every MeshInstance3D under `node`, in the frame `xform` maps `node` into.
static func merged_aabb(node: Node, xform: Transform3D) -> AABB:
	var aabb := AABB()
	var first := true
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		aabb = xform * (node as MeshInstance3D).mesh.get_aabb()
		first = false
	for child in node.get_children():
		var cx := xform
		if child is Node3D:
			cx = xform * (child as Node3D).transform
		var ca := merged_aabb(child, cx)
		if ca.size != Vector3.ZERO or ca.position != Vector3.ZERO:
			aabb = ca if first else aabb.merge(ca)
			first = false
	return aabb


## An apron of `cells` palette tiles as a real GridMap, named "RoadsTiles". Cell indices come from
## asking the GridMap where `centre` (world XZ, at ground `y`) lands (local_to_map); the world
## rect is measured back off the item mesh and palette transform, never a hand-guessed offset.
## Returns {grid, rect (world XZ), deck_y}, or {} on failure.
static func apron_gridmap(meshlib_path: String, tile: String, centre: Vector2, y: float,
		cells: Vector2i, tag: String) -> Dictionary:
	var ml := load(meshlib_path) as MeshLibrary
	if ml == null:
		printerr("[%s] cannot load %s" % [tag, meshlib_path])
		return {}
	var item := ml.find_item_by_name(tile)
	if item < 0:
		printerr("[%s] roads palette has no '%s' tile" % [tag, tile])
		return {}
	var mesh := ml.get_item_mesh(item)
	if mesh == null:
		printerr("[%s] roads palette tile '%s' has no mesh" % [tag, tile])
		return {}

	var grid := GridMap.new()
	grid.name = "RoadsTiles"
	grid.mesh_library = ml
	grid.cell_size = Vector3(12, 3, 12)
	grid.cell_center_y = false
	# Level 3's tile city uses the same offset: the tile deck is 0.24 m thick and sits on the
	# cell base, so dropping the map 0.22 m lands the driving surface 0.02 m above the ground
	# instead of behind a 24 cm lip.
	grid.position = Vector3(0, -0.22, 0)

	var y_cell := int(round(y / grid.cell_size.y))
	var origin := grid.local_to_map(Vector3(centre.x, y, centre.y))
	var i0 := origin.x - int((cells.x - 1) / 2.0)
	var j0 := origin.z - int((cells.y - 1) / 2.0)
	var mesh_xform := ml.get_item_mesh_transform(item)
	var bounds := AABB()
	var first := true
	for di in cells.x:
		for dj in cells.y:
			var cell := Vector3i(i0 + di, y_cell, j0 + dj)
			grid.set_cell_item(cell, item)
			var placed := Transform3D(Basis.IDENTITY, grid.map_to_local(cell))
			var world: AABB = grid.transform * placed * mesh_xform * mesh.get_aabb()
			bounds = world if first else bounds.merge(world)
			first = false
	return {
		"grid": grid,
		"rect": Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z),
		"deck_y": bounds.end.y,
	}


## Instance the prefab at `path`, yaw it, and sit it on the ground at `at`: its measured merged
## AABB's rotated centre on the target XZ, its base on the target Y. Measuring after rotation
## matters, since a prefab whose origin isn't its centre would walk sideways when yawed. Added
## under `parent` and owned by `root`, so PackedScene.pack serializes it. Returns the rotated
## AABB (its size is the piece's footprint), or AABB() when the prefab does not load.
static func place(parent: Node, root: Node, path: String, node_name: String, at: Vector3,
		yaw: float, tag: String) -> AABB:
	var scene := load(path) as PackedScene
	if scene == null:
		printerr("[%s] cannot load %s" % [tag, path])
		return AABB()
	var piece := scene.instantiate() as Node3D
	var turn := Basis(Vector3.UP, yaw)
	var aabb: AABB = Transform3D(turn, Vector3.ZERO) * merged_aabb(piece, Transform3D.IDENTITY)
	piece.name = node_name
	piece.transform = Transform3D(turn,
			at - Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z))
	parent.add_child(piece)
	piece.owner = root
	return aabb

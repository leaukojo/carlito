extends RefCounted
## The smallest bakeable level, shared by the baker's suites: a root "L", a
## VehicleSpawn "Spawn" and an empty AuthoringRoot "Authoring" (`authoring_of`). It never enters
## the tree, so nothing runs `_ready`: the baker's own operating mode.


static func bakeable_level() -> Node3D:
	var root := Node3D.new()
	root.name = "L"
	var spawn := Marker3D.new()
	spawn.name = "Spawn"
	spawn.set_script(load("res://src/levels/base/vehicle_spawn.gd"))
	root.add_child(spawn)
	var authoring := Node3D.new()
	authoring.name = "Authoring"
	authoring.set_script(preload("res://kit/helpers/authoring_root.gd"))
	root.add_child(authoring)
	return root


static func authoring_of(level: Node3D) -> Node3D:
	return level.get_node("Authoring") as Node3D

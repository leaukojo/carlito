class_name RailTrack
extends Node3D
## Runtime form of a rail: a Curve3D the train's consist sim rides, emitted into the baked
## scene by LevelBaker (the authored RoadPath is freed/stripped at load, so the baker
## duplicates its curve here). In unbaked dev play the RoadPath itself answers the same
## duck-typed API. No @tool, no editor classes anywhere, not even as type annotations.

## Rail centreline, in the space rail_local_xform() maps from. Duplicated at bake.
@export var curve: Curve3D
## Distance between the rail centrelines (m), copied off the authoring profile.
@export var gauge := 1.44
## Whether the curve's endpoints coincide (a train can lap it forever); cached from RoadBuilder.is_closed_loop at bake time.
@export var closed := false


## Duck-typing marker: this node is a baked rail track.
func is_carlito_rail_track() -> bool:
	return true


# ---------------------------------------------------------------- rail node API
# Shared verbatim with RoadPath. Discovery is has_method("get_rail_curve") and
# get_rail_curve() != null, not a marker method (a city-profile RoadPath must answer "no").


func get_rail_curve() -> Curve3D:
	return curve


## Curve space -> this node's local space; identity here (RoadPath returns its Path child's transform).
func rail_local_xform() -> Transform3D:
	return Transform3D.IDENTITY


## Curve space -> world: `rail_to_world() * curve.sample_baked(s)`.
func rail_to_world() -> Transform3D:
	return global_transform * rail_local_xform()


func rail_gauge() -> float:
	return gauge


func is_rail_closed() -> bool:
	return closed


## First closed rail loop under `root`, duck-typed; null if none. Shared by Level and TrainVehicle so the two never disagree.
static func find_closed_rail(root: Node) -> Node:
	if root.has_method("get_rail_curve") and root.call("get_rail_curve") != null \
			and bool(root.call("is_rail_closed")):
		return root
	for child in root.get_children():
		var found := find_closed_rail(child)
		if found != null:
			return found
	return null

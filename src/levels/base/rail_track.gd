class_name RailTrack
extends Node3D
## The runtime form of a rail: a Curve3D the train's consist sim rides, emitted into the
## baked scene by LevelBaker.
##
## Why this node exists at all: rails are authored as a RoadPath under the level's
## AuthoringRoot, which a baked level FREES at load (level.gd._setup_baked) and the export
## plugin strips from shipped builds entirely. The ribbon geometry survives — it welds into
## the level-wide Drivable body — but the curve does not, and the curve is the whole point
## of a rail. So the baker duplicates it into one of these.
##
## In unbaked dev play there is no baked scene and no RailTrack: the RoadPath itself
## answers the same duck-typed API. Exactly one of the two is ever present.
##
## Runtime-safe by construction: no @tool, no editor classes anywhere (not even as type
## annotations — that is what silently breaks a script in an exported build).

## The rail centreline, in the space rail_local_xform() maps from. Duplicated at bake, so
## editing the authored curve afterwards cannot mutate a shipped one.
@export var curve: Curve3D
## Distance between the rail centrelines (m), copied off the authoring profile.
@export var gauge := 1.44
## Whether the curve's endpoints coincide, i.e. a train can lap it forever.
## RoadBuilder.is_closed_loop is the single owner of that question at bake time; this is
## its cached answer, so runtime never re-derives it with a second predicate.
@export var closed := false


## Duck-typing marker: "this node IS a baked rail track".
func is_carlito_rail_track() -> bool:
	return true


# ---------------------------------------------------------------- rail node API
# Shared verbatim with RoadPath (kit/helpers/road_path.gd) so discovery works the same in
# baked and unbaked play. Discovery is `has_method("get_rail_curve") and
# get_rail_curve() != null` — not a marker method — because has_method() is static and a
# RoadPath carrying a city profile must be able to answer "not a rail right now".


func get_rail_curve() -> Curve3D:
	return curve


## Curve space -> THIS node's local space. Identity here (the baker bakes the authoring
## transform into the node's own transform); RoadPath returns its Path child's transform.
## Exists so the baker, which works on an untreed instance where global_transform is
## unavailable, can compose the same value it would at runtime.
func rail_local_xform() -> Transform3D:
	return Transform3D.IDENTITY


## Curve space -> world. What consumers sample through: `rail_to_world() * curve.sample_baked(s)`.
func rail_to_world() -> Transform3D:
	return global_transform * rail_local_xform()


func rail_gauge() -> float:
	return gauge


func is_rail_closed() -> bool:
	return closed


## The first CLOSED rail loop under `root`, discovered duck-typed (a baked RailTrack or an
## unbaked authoring RoadPath — same get_rail_curve()/is_rail_closed() API), or null. Shared
## by Level (spawn gating) and TrainVehicle (self-placement) so the two never disagree on what
## the train may run on: both require a closed loop, never an open rail.
static func find_closed_rail(root: Node) -> Node:
	if root.has_method("get_rail_curve") and root.call("get_rail_curve") != null \
			and bool(root.call("is_rail_closed")):
		return root
	for child in root.get_children():
		var found := find_closed_rail(child)
		if found != null:
			return found
	return null

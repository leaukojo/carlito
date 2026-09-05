class_name DroneSensorSuite
extends RefCounted
## The two raycast sensors: sky pattern, visibility mask, cursor, last rangefinder reading,
## shared query object, and the roster indices publication gates through. Owned and ticked
## by `DroneVehicle`; `DroneSensors` stays the law, this class carries state across ticks.
##
## GNSS offline -> published sky is EMPTY (0), so `sats`/`fix_type`/`hdop` fall out as
## no-fix. RANGE offline -> `agl` publishes RANGE_INVALID (-1), never 0 — zero is exactly
## what a landing detector would act on.

## The fixed sky pattern, built once and only swept afterwards.
var _sky := PackedVector3Array()
## Bit i = sky ray i reached the sky on its LAST cast. Starts EMPTY — no fix until the
## round-robin has gone round once (a respawn triggers the same acquisition).
var _visible := 0
## Next ray in the round-robin sweep.
var _cursor := 0
## The craft's OWN rangefinder reading, ungated by the bus.
var _agl := DroneSensors.RANGE_INVALID
## Query object, built once and refilled per cast (avoids 5 throwaway RefCounteds/tick).
## Excludes this airframe; mask is SOLID — must omit Containment, or WorldBounds' walls eat
## satellites over open water.
var _query: PhysicsRayQueryParameters3D
## Resolved once from the roster (`DroneBus.NODES`), not hardcoded — a reordered roster
## must not silently gate the wrong sensor.
var _gnss_node := -1
var _range_node := -1


func _init(body: RigidBody3D) -> void:
	_query = DroneSensors.make_query([body.get_rid()])
	_sky = DroneSensors.sky_pattern(DroneSensors.SKY_RAYS, DroneSensors.SKY_MASK_DEG)
	_gnss_node = DroneBus.index_of("GNSS")
	_range_node = DroneBus.index_of("RANGE")


## Measure before anything decides anything. Both raycasts hit real level collision, never a
## scripted volume. Five rays/tick between the two (see DroneSensors.SKY_RAYS_PER_TICK).
func measure(space: PhysicsDirectSpaceState3D, pos: Vector3) -> void:
	_visible = DroneSensors.sweep_sky(space, pos, _sky, _visible, _cursor,
			DroneSensors.SKY_RAYS_PER_TICK, _query)
	_cursor = (_cursor + DroneSensors.SKY_RAYS_PER_TICK) % maxi(_sky.size(), 1)
	_agl = DroneSensors.measure_agl(space, pos, _query)


## The four published readings, both node gates applied (opposite directions, see header).
func publish(t: DroneTelemetry, node_fail: int) -> void:
	var sky := _visible if DroneBus.is_online(node_fail, _gnss_node) else 0
	t.sats = DroneSensors.sats(sky, _sky.size())
	t.fix_type = DroneSensors.fix_type(t.sats)
	t.hdop = DroneSensors.hdop(_sky, sky)
	t.agl = _agl if DroneBus.is_online(node_fail, _range_node) else DroneSensors.RANGE_INVALID


## The craft's own AGL — what the landed predicate reads, ungated by the bus.
func agl() -> float:
	return _agl


## A teleport invalidates every measurement (the accel-history rule). Clearing the sky mask
## makes the receiver reacquire over the next few ticks instead of keeping a fix earned
## somewhere else.
func reset() -> void:
	_visible = 0
	_cursor = 0
	_agl = DroneSensors.RANGE_INVALID

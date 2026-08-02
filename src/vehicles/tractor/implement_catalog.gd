class_name ImplementCatalog
extends RefCounted
## Static registry of the implements the tractor can carry, and the order E cycles them in.
##
## Deliberately shaped like VehicleCatalog: pure static data + helpers, unit-tested, no
## runtime state. It exists so the tractor family can cycle its IMPLEMENT rather than its
## body — there is only one tractor body, and the implement is the interesting axis.
##
## DETACHED is a real entry in the cycle, not a special case wrapped around it: a bare
## tractor with the linkage empty is a legitimate state (implement_connected reads false,
## implement_type reads 0) and it must be as reachable as any implement.

const DETACHED := ""  ## no implement on the hitch

## Cycle order. The spreader leads because it is the fullest machine on the linkage — three
## point, PTO and the hydraulic remote all at once — so the tractor spawns with every
## attachment signal doing something. Behind it the rest run plough (three-point only),
## harrow (the same tillage job, now driven), mower (rotor on the vertical axis) — then
## DETACHED, so E from the last implement returns to a bare tractor.
const IMPLEMENTS: PackedStringArray = [
	"res://src/vehicles/tractor/implements/spreader.tscn",
	"res://src/vehicles/tractor/implements/plough.tscn",
	"res://src/vehicles/tractor/implements/harrow.tscn",
	"res://src/vehicles/tractor/implements/mower.tscn",
	DETACHED,
]


## The implement the tractor spawns with (attached, so the hitch/PTO signals do something
## the moment you drive it).
static func first() -> String:
	return IMPLEMENTS[0]


## Next entry in the cycle, wrapping. An unknown id restarts the cycle rather than sticking.
static func next(current: String) -> String:
	var i := IMPLEMENTS.find(current)
	return IMPLEMENTS[(i + 1) % IMPLEMENTS.size()] if i >= 0 else IMPLEMENTS[0]


## True when `id` names an actual implement (as opposed to the detached state).
static func is_attached(id: String) -> bool:
	return id != DETACHED

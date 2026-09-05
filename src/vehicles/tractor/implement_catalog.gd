class_name ImplementCatalog
extends RefCounted
## Static registry of implements the tractor cycles (E key). DETACHED is a real entry. The
## last is a drawbar trailer (RigidBody3D joint, not visual). TOWED routes ids to the right
## coupler; test_drawbar_trailer checks it against each machine's declared Connection.

const DETACHED := AttachmentCatalog.NONE  ## nothing on the hitch and nothing on the drawbar

## Cycle order. The spreader leads because it uses every connection (three-point, PTO, hydraulic
## remote) so the tractor spawns with every attachment signal doing something; then plough
## (three-point only), harrow (driven tillage), mower (vertical rotor), the drawbar trailer, then
## DETACHED. The trailer must stay off first(): the tractor spawns on it and measure_vehicles
## reports force against `spec.mass` (4000 kg) — a towed first() would measure a 14 t combination
## against that number, the same trap `-- semi` sets on the truck side.
const IMPLEMENTS: PackedStringArray = [
	"res://src/vehicles/tractor/implements/spreader.tscn",
	"res://src/vehicles/tractor/implements/plough.tscn",
	"res://src/vehicles/tractor/implements/harrow.tscn",
	"res://src/vehicles/tractor/implements/mower.tscn",
	"res://src/vehicles/tractor/trailers/farm_tipper.tscn",
	DETACHED,
]

## The entries in IMPLEMENTS that are TOWED BODIES rather than three-point implements: a
## RigidBody3D coupled to the drawbar on a joint, standing on its own wheels, with collision of
## its own. Everything not on this list is an ImplementBase — visual only, no collision, no
## joint, posed by the linkage's four-bar solve.
const TOWED: PackedStringArray = [
	"res://src/vehicles/tractor/trailers/farm_tipper.tscn",
]


## The implement the tractor spawns with (attached, so the hitch/PTO signals do something
## the moment you drive it).
static func first() -> String:
	return AttachmentCatalog.first(IMPLEMENTS)


## Next entry in the cycle, wrapping. An unknown id restarts the cycle rather than sticking.
static func next(current: String) -> String:
	return AttachmentCatalog.next(IMPLEMENTS, current)


## True when `id` names an actual machine (as opposed to the detached state).
static func is_attached(id: String) -> bool:
	return AttachmentCatalog.is_attached(id)


## True when `id` is TOWED from the drawbar rather than carried on the three-point linkage — the
## one question TractorVehicle asks before it decides which coupler an id belongs to.
static func is_towed(id: String) -> bool:
	return TOWED.has(id)

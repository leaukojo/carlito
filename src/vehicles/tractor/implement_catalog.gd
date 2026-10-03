class_name ImplementCatalog
extends RefCounted
## Static registry of implements the tractor cycles (E key). DETACHED is a real entry. TOWED routes
## ids to the right coupler; test_drawbar_trailer checks it against each machine's Connection.

const DETACHED := AttachmentCatalog.NONE  ## nothing on the hitch and nothing on the drawbar

## Cycle order. The spreader leads because it uses every connection, so the tractor spawns with
## every attachment signal doing something.
const IMPLEMENTS: PackedStringArray = [
	"res://src/vehicles/tractor/implements/spreader.tscn",
	"res://src/vehicles/tractor/implements/plough.tscn",
	"res://src/vehicles/tractor/implements/harrow.tscn",
	"res://src/vehicles/tractor/implements/mower.tscn",
	"res://src/vehicles/tractor/trailers/farm_tipper.tscn",
	DETACHED,
]

## The entries in IMPLEMENTS that are TOWED BODIES: a RigidBody3D on the drawbar joint, with
## collision of its own. Everything else is a visual-only ImplementBase.
const TOWED: PackedStringArray = [
	"res://src/vehicles/tractor/trailers/farm_tipper.tscn",
]


## The implement the tractor spawns with (attached, so the hitch/PTO signals do something).
static func first() -> String:
	return AttachmentCatalog.first(IMPLEMENTS)


## Next entry in the cycle, wrapping. An unknown id restarts the cycle rather than sticking.
static func next(current: String) -> String:
	return AttachmentCatalog.next(IMPLEMENTS, current)


## True when `id` names an actual machine (as opposed to the detached state).
static func is_attached(id: String) -> bool:
	return AttachmentCatalog.is_attached(id)


## True when `id` is TOWED from the drawbar rather than carried on the three-point linkage.
static func is_towed(id: String) -> bool:
	return TOWED.has(id)

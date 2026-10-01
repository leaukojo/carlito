class_name TrailerCatalog
extends RefCounted
## Static registry of the semi-trailers the tractor unit can pull, and the order E cycles them,
## shaped by AttachmentCatalog. BOBTAIL is a real entry: trailer signals read zeros there.
## No trailer adds a signal and there is no `trailer_type` (ISO 11992 carries nothing about the
## body). They differ by mass (14-24 t), what they plug into, and which tractor signals they move.

const BOBTAIL := AttachmentCatalog.NONE  ## nothing on the fifth wheel

## Cycle order: box (heaviest, nothing else) -> tipper (PTO + valve + raise interlock) -> tanker
## (shifting centre of mass) -> flatbed (lightest) -> BOBTAIL. Box is FIRST so the semi spawns on
## the 3:1 mass ratio; BOBTAIL is LAST so one E press drops the trailer and the next re-couples a box.
const TRAILERS: PackedStringArray = [
	"res://src/vehicles/truck/trailers/box.tscn",
	"res://src/vehicles/truck/trailers/tipper.tscn",
	"res://src/vehicles/truck/trailers/tanker.tscn",
	"res://src/vehicles/truck/trailers/flatbed.tscn",
	BOBTAIL,
]


## What the tractor unit spawns coupled to.
static func first() -> String:
	return AttachmentCatalog.first(TRAILERS)


## Next entry in the cycle, wrapping; an unknown id restarts it.
static func next(current: String) -> String:
	return AttachmentCatalog.next(TRAILERS, current)


## True when `id` names an actual trailer (as opposed to running bobtail).
static func is_coupled(id: String) -> bool:
	return AttachmentCatalog.is_attached(id)

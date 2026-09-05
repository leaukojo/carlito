class_name TrailerCatalog
extends RefCounted
## Static registry of the semi-trailers the tractor unit can pull, and the order E cycles them.
## Shaped by AttachmentCatalog: pure static data + helpers, unit-tested, no runtime state.
## BOBTAIL is a real entry, not a special case: a solo tractor is a legitimate state, and trailer
## signals read honest zeros there.
## None of the four trailers adds a signal — ISO 11992 carries nothing about the body, and there
## is deliberately no `trailer_type`. They differ by mass (14-24 t), what they plug into the
## towing unit, and which tractor-side signals they move.

const BOBTAIL := AttachmentCatalog.NONE  ## nothing on the fifth wheel

## Cycle order: box (heaviest, nothing else) -> tipper (PTO + valve + raise interlock) -> tanker
## (shifting centre of mass) -> flatbed (lightest) -> BOBTAIL.
## Box is FIRST so the semi spawns on the 3:1 mass ratio; bobtail is LAST so one E press drops the
## trailer and the next picks a box back up.
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


## Next entry in the cycle, wrapping. An unknown id restarts the cycle rather than sticking.
static func next(current: String) -> String:
	return AttachmentCatalog.next(TRAILERS, current)


## True when `id` names an actual trailer (as opposed to running bobtail).
static func is_coupled(id: String) -> bool:
	return AttachmentCatalog.is_attached(id)

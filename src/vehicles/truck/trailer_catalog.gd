class_name TrailerCatalog
extends RefCounted
## Static registry of the semi-trailers the tractor unit can pull, and the order E cycles them
## in. Deliberately shaped like ImplementCatalog: pure static data + helpers, unit-tested, no
## runtime state — the tractor family cycles its IMPLEMENT rather than its body for the same
## reason, and this is the truck family's version of that idea.
##
## BOBTAIL is a REAL ENTRY IN THE CYCLE, not a special case wrapped around it: a solo tractor
## unit is a legitimate (and very common) state of the machine, and it must be as reachable as
## any trailer. Phase 5's trailer signals then read honest zeros there, exactly as a detached
## tractor's implement signals do.
##
## FOUR TRAILERS AND NOT ONE OF THEM ADDS A SIGNAL. That is the content of the set rather than a
## limitation of it: ISO 11992 is the application layer for brakes and running gear, so it carries
## nothing about the body, and there is deliberately no `trailer_type`. What tells these four apart
## is MASS (14 t to 24 t), what they plug into the towing unit, and which TRACTOR-side signals they
## move. Adding one is a line here plus a scene; adding a signal for one is the mistake this
## catalog exists to make visible.

const BOBTAIL := ""  ## nothing on the fifth wheel

## Cycle order, chosen so each press changes something you can name — the ImplementCatalog rule:
##
##   box      the heaviest, and NOTHING else. On the trailer bus it is the flatbed.
##   tipper   the only trailer with a function: chassis PTO + a proportional valve, a real raise
##            interlock, and a tip that walks the load rearward off the fifth wheel.
##   tanker   a labelled model of a shifting centre of mass, moving under every stop.
##   flatbed  the lightest, and now something to compare the other three against.
##   BOBTAIL  a solo tractor unit — A REAL ENTRY, not a special case wrapped around the cycle.
##
## The box is FIRST, so the semi spawns coupled to the heaviest trailer in the catalog (the
## tractor's spawn-attached precedent) and the 3 : 1 mass ratio Phase 4 verified is the ratio the
## game opens on rather than a corner of it. Bobtail stays LAST, so one press of E drops the
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
	return TRAILERS[0]


## Next entry in the cycle, wrapping. An unknown id restarts the cycle rather than sticking.
static func next(current: String) -> String:
	var i := TRAILERS.find(current)
	return TRAILERS[(i + 1) % TRAILERS.size()] if i >= 0 else TRAILERS[0]


## True when `id` names an actual trailer (as opposed to running bobtail).
static func is_coupled(id: String) -> bool:
	return id != BOBTAIL

extends TowedBody
## Box / curtainside semi-trailer: THE HEAVIEST TRAILER IN THE CATALOG AND NOTHING ELSE.
##
## No PTO, no valve, no interlock, no load model, no override but this one. That is not an
## unfinished trailer — it is the point of the whole trailer-variety phase, stated as plainly as a
## class can state it:
##
##   ON THE ISO 11992 TRAILER BUS A BOX IS INDISTINGUISHABLE FROM A FLATBED. Part 2 of the standard
##   is the application layer for brakes and running gear, so the entire boundary is a coupling
##   claim, the brake demand out, the ABS state back and an axle load. A box van and a flat deck
##   couple identically, brake identically and report identically. There is no body-type message to
##   tell them apart, and inventing one (`trailer_type`) would undercut exactly the lesson the thin
##   boundary is here to teach — see the trailer-bus note in src/vehicles/CLAUDE.md.
##
##   ON THE TRACTOR'S OWN SIGNALS IT IS A COMPLETELY DIFFERENT VEHICLE. 24 t against the flatbed's
##   14 t is 10 t more on the springs: trailer_axle_load reads ~19 400 kg against ~11 200, axle_load
##   picks up its share of the plate load, engine_load answers on every grade and under every
##   pull-away, and the rig accelerates and stops like the different machine it is.
##
## So `consumers()` returning 0 is a DECLARATION, not an omission — the box really does plug nothing
## into the towing unit beyond the pneumatic lines and the ISO 7638 connector every trailer shares.
## It is written out here rather than inherited so that the claim is visible in the file, and
## test_trailer asserts it against the flatbed's: the two must agree, or the lesson is not true.
##
## Geometry (box.tscn) is a curtainsider: the body is the same steel either way, and curtains are
## what a European general-freight trailer actually carries.


func consumers() -> int:
	return 0

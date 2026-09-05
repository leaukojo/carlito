extends TowedBody
## Box / curtainside semi-trailer: the heaviest trailer in the catalog, nothing else. No PTO,
## valve, interlock or load model.
## On ISO 11992 it is indistinguishable from a flatbed (Part 2 only carries brakes/running gear,
## no body-type message) — don't add a `trailer_type` to tell them apart, see
## src/vehicles/CLAUDE.md. On the tractor's own signals (mass, axle_load, engine_load) it reads
## as a completely different vehicle: 24 t against the flatbed's 14 t.
## `consumers()` returning 0 is a declaration, checked against the flatbed's by test_trailer.


func consumers() -> int:
	return 0

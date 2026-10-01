extends TowedBody
## Box / curtainside semi-trailer: the heaviest trailer in the catalog, nothing else (no PTO, valve,
## interlock or load model). On ISO 11992 it is indistinguishable from a flatbed (no body-type
## message), so there is no `trailer_type` (see docs/heavy_vehicles.md); on the tractor's mass,
## axle_load and engine_load it reads as a different vehicle (24 t against 14 t). `consumers()`
## returning 0 is a declaration, checked against the flatbed's by test_trailer.


func consumers() -> int:
	return 0

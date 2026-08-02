class_name BikeTelemetry
extends VehicleTelemetry
## Bike telemetry. Adds the one bike-flavored "out" field (lean) on top of the
## ground-vehicle VehicleTelemetry. The field name is EXACTLY the contract name so the
## Bridge's name-keyed marshaling and the dashboard's t.get(name) reads work unchanged.
##
## lean is an honest model (same latitude as fuel/coolant/engine_load): it is the SAME
## value BikeVehicle tilts the visual body by, computed from the arcade lean model — not a
## real two-wheel balance sim. + = leaning right (contract 'lean').

var lean := 0.0   ## deg, contract 'lean'


func to_bridge_dict() -> Dictionary:
	var d := super()
	d["lean"] = lean
	return d

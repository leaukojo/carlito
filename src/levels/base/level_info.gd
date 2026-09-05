class_name LevelInfo
extends Resource
## Per-level metadata the shell needs without reading the scene tree (spawn markers stay in the scene as VehicleSpawn nodes).

@export var display_name := "Untitled Level"
## Vehicle type ids allowed here (contract 'vehicles' tags); empty = allow all.
@export var allowed_vehicles := PackedStringArray(["car"])
## Spawned on first load; must be in allowed_vehicles.
@export var default_vehicle := "car"


## allowed_vehicles lists families, so `variant` is checked by its family.
func allows(variant: String) -> bool:
	return allowed_vehicles.is_empty() or allowed_vehicles.has(VehicleCatalog.family_of(variant))

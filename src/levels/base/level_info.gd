class_name LevelInfo
extends Resource
## Per-level metadata: what the shell needs to load and populate a level
## without reading its scene tree. Spawn markers live in the scene as VehicleSpawn
## nodes; everything else that is data (name, allowed/default vehicle) lives here.

@export var display_name := "Untitled Level"
## Vehicle type ids allowed here (match contract 'vehicles' tags, e.g. "car").
## Empty = allow all. The vehicle selector reads this to decide what it will spawn here — and
## what it shows refused, with the reason, rather than hiding.
@export var allowed_vehicles := PackedStringArray(["car"])
## Vehicle type spawned when the level first loads. Must be in allowed_vehicles.
@export var default_vehicle := "car"


## True when `variant` may drive here. allowed_vehicles lists FAMILIES, so a variant is
## checked by its family (empty allow-list = everything allowed).
func allows(variant: String) -> bool:
	return allowed_vehicles.is_empty() or allowed_vehicles.has(VehicleCatalog.family_of(variant))

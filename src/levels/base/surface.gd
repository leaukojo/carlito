class_name Surface
## The ground a tyre stands on: one shared table; a terrain names each paint channel's surface
## (`HeightmapTerrain.channel_surface`), never its own figures. Per surface, `ref_grip` (the
## reference all-season tyre's peak over its dry-asphalt peak, [0, 1]) and `drag` (rolling
## resistance added over the tyre's own hard-road figure). A tyre class scales `ref_grip` per
## surface (`TyreClass`); `drag` is tyre-blind (a COMPROMISE: a big tyre pays the car's soil
## figure). Each figure's source, derivation and grade: `docs/sources.md` § Sourced figures,
## *Surfaces*. How a terrain blends them: `docs/systems.md` § Level framework. Ids are stored in
## level scenes: append a surface, never reorder.

enum {
	ASPHALT, WET, PAD, GRAVEL, DIRT, GRASS, SAND, ROCK, MUD, FIELD, SNOW, ICE,
	COUNT,
}

## Ceiling on a surface's added rolling resistance (loose sand is ~0.3).
const MAX_DRAG := 0.5

const NAMES: Array[String] = [
	"Asphalt", "Wet", "Pad", "Gravel", "Dirt", "Grass", "Sand", "Rock", "Mud", "Field", "Snow", "Ice",
]
const REF_GRIP: Array[float] = [1.0, 0.55, 0.95, 0.71, 0.8, 0.5, 0.6, 0.7, 0.45, 0.5, 0.45, 0.12]
const DRAG: Array[float] = [0.0, 0.0, 0.0, 0.01, 0.04, 0.06, 0.05, 0.01, 0.1, 0.06, 0.02, 0.0]


static func is_valid(id: int) -> bool:
	return id >= 0 and id < COUNT


## Peak grip over dry asphalt's, [0, 1]; an unknown id reads ASPHALT.
static func ref_grip(id: int) -> float:
	return clampf(REF_GRIP[id if is_valid(id) else ASPHALT], 0.0, 1.0)


## A tyre's grip on `id` out of its per-surface `response` (`RayWheel.tyre_grip`); an empty or
## short one reads `ref_grip`, the reference tyre.
static func grip_in(response: PackedFloat32Array, id: int) -> float:
	return response[id] if id >= 0 and id < response.size() else ref_grip(id)


## Added rolling resistance, [0, MAX_DRAG]; an unknown id reads ASPHALT.
static func drag(id: int) -> float:
	return clampf(DRAG[id if is_valid(id) else ASPHALT], 0.0, MAX_DRAG)


static func display_name(id: int) -> String:
	return NAMES[id] if is_valid(id) else "?%d" % id


## The id whose name matches `key` (any case), or -1.
static func from_key(key: String) -> int:
	for i in COUNT:
		if NAMES[i].to_lower() == key.to_lower():
			return i
	return -1

class_name VehicleCatalog
extends RefCounted
## Static registry of vehicle variants and their families. A variant is a concrete body scene;
## a family is the contract type (car/truck/tractor/boat/drone/plane) for bridge/dashboard/spawn.
## Hand-built vehicles are listed first per family. The rest are Kenney and Watercraft packs
## (CC0), generated with individual feel. Every variant maps to a pre-declared contract family.

const KENNEY := "res://src/vehicles/kenney/"
const WATERCRAFT := "res://src/vehicles/watercraft/"

## variant id -> { scene: String, family: String }. Insertion order is the cycle order.
const VARIANTS := {
	# -- hand-built bodies, first in their family. The car / truck / boat / tractor families
	# have no hand-built body: they default to their first kit / watercraft variant below
	# (sedan-sports / garbage-truck / boat-speed-a / tractor-kenney). --
	# The modelled airframe, first so it is the drone family's default; same flight numbers as "drone".
	"drone-mk2": {"scene": "res://src/vehicles/drone/drone_mk2.tscn", "family": "drone"},
	"drone": {"scene": "res://src/vehicles/drone/drone.tscn", "family": "drone"},
	"plane": {"scene": "res://src/vehicles/plane/plane.tscn", "family": "plane"},
	"bullet": {"scene": "res://src/vehicles/train/train.tscn", "family": "train"},
	# -- Watercraft pack: boat family --
	"boat-speed-a": {"scene": WATERCRAFT + "boat-speed-a.tscn", "family": "boat"},
	"boat-speed-j": {"scene": WATERCRAFT + "boat-speed-j.tscn", "family": "boat"},
	"boat-sail-a": {"scene": WATERCRAFT + "boat-sail-a.tscn", "family": "boat"},
	# -- Kenney car kit: car family (sedan-sports first = the default car) --
	"sedan-sports": {"scene": KENNEY + "sedan-sports.tscn", "family": "car"},
	"sedan": {"scene": KENNEY + "sedan.tscn", "family": "car"},
	"hatchback-sports": {"scene": KENNEY + "hatchback-sports.tscn", "family": "car"},
	"suv": {"scene": KENNEY + "suv.tscn", "family": "car"},
	"suv-luxury": {"scene": KENNEY + "suv-luxury.tscn", "family": "car"},
	"taxi": {"scene": KENNEY + "taxi.tscn", "family": "car"},
	"police": {"scene": KENNEY + "police.tscn", "family": "car"},
	"race": {"scene": KENNEY + "race.tscn", "family": "car"},
	"race-future": {"scene": KENNEY + "race-future.tscn", "family": "car"},
	"van": {"scene": KENNEY + "van.tscn", "family": "car"},
	"pickup": {"scene": KENNEY + "pickup.tscn", "family": "car"},
	"pickup-flat": {"scene": KENNEY + "pickup-flat.tscn", "family": "car"},
	# Heavy vans: `car` family — family is the chassis class, not the job. Proprietary CAN, not
	# J1939 (standards home: CiA 447 special-purpose car profile). Keep the truck chassis feel:
	# see
	# gen_kenney_vehicles.gd's VAN_BASE.
	"delivery": {"scene": KENNEY + "delivery.tscn", "family": "car"},
	"delivery-flat": {"scene": KENNEY + "delivery-flat.tscn", "family": "car"},
	"ambulance": {"scene": KENNEY + "ambulance.tscn", "family": "car"},
	# -- Kenney car kit: truck family (J1939) — garbage-truck first = the default truck --
	"garbage-truck": {"scene": KENNEY + "garbage-truck.tscn", "family": "truck"},
	"firetruck": {"scene": KENNEY + "firetruck.tscn", "family": "truck"},
	# Hand-built cab-over tractor unit (the kit ships no semi), so it is a plain scene path rather
	# than a KENNEY one. Ordinary truck-family variant: V walks it like any other body, and what it
	# tows is E's business — this file knows nothing about that (see boot.gd's _cycle_attachment).
	"semi": {"scene": "res://src/vehicles/truck/semi.tscn", "family": "truck"},
	# The North American conventional: a BODY variant of the one above, not a different trailer, so
	# it belongs here and E's trailer cycle is untouched. It tows the same trailers through the same
	# pneumatic lines and carries no ISO 11992 data pair, which is the whole reason it ships — see
	# conventional_spec.tres and the contract's 'j2497' note.
	"semi-conventional": {"scene": "res://src/vehicles/truck/conventional.tscn", "family": "truck"},
	# -- Kenney car kit: tractor family (ISOBUS) --
	"tractor-kenney": {"scene": KENNEY + "tractor-kenney.tscn", "family": "tractor"},
}


## The contract family a variant belongs to; "" if the variant is unknown.
static func family_of(variant: String) -> String:
	return String(VARIANTS[variant]["family"]) if VARIANTS.has(variant) else ""


## Scene path for a variant; "" if unknown.
static func scene_of(variant: String) -> String:
	return String(VARIANTS[variant]["scene"]) if VARIANTS.has(variant) else ""


## Variants in `family`, in cycle (insertion) order.
static func variants_in_family(family: String) -> PackedStringArray:
	var out := PackedStringArray()
	for v in VARIANTS:
		if String(VARIANTS[v]["family"]) == family:
			out.append(v)
	return out


## The family's legacy/first variant (what the garage spawns for that family); "" if none.
static func first_in_family(family: String) -> String:
	var vs := variants_in_family(family)
	return vs[0] if not vs.is_empty() else ""


## Next variant within the same family, wrapping around. Returns `variant` unchanged when
## it is unknown or the only one in its family.
static func next_in_family(variant: String) -> String:
	var vs := variants_in_family(family_of(variant))
	if vs.size() < 2:
		return variant
	var i := vs.find(variant)
	return vs[(i + 1) % vs.size()] if i >= 0 else vs[0]

extends ImplementBase
## Mounted rotary mower: the rotor turns at the shaft speed the tractor reports, so PTO, revs and
## 540/1000 are visible. Not draft-relevant: the deck rides on its tail wheel above the ground.

## Rotor turns per PTO shaft turn, cosmetic legibility gearing (see spin_from_pto).
const ROTOR_RATIO := 0.3

## Mass (kg) of the class drawn: a 7 ft (2.14 m sweep) Cat 2 single-spindle rotary cutter, the
## Land Pride RCR2684 at 1370 lb with a single tail wheel (sourced: its manual); Woods' BB84.40
## lists 1041-1132 lb (secondary). Citations: docs/sources.md.
const MASS_KG := 620.0

## Centre of mass in this frame: the area-weighted centroid of the scene's meshes.
const MASS_CENTRE := Vector3(0.0, -0.02, 1.21)

## Tail wheel axle behind the lower pin line (m), measured off mower.tscn.
const TAIL_WHEEL_Z := 2.8

## Weight the ground carries at the bottom stop: with the top link floating (an ESTIMATE of the
## setup), the lower pins and the tail wheel carry the deck between them, so the wheel's share is
## the centre's lever over the wheel's.
const GROUND_SHARE := MASS_CENTRE.z / TAIL_WHEEL_Z

@onready var _rotor: Node3D = $Rotor


func connections() -> int:
	return Connection.THREE_POINT | Connection.PTO | Connection.ISOBUS_DATA


func device_class() -> int:
	return CLASS_FORAGE


func mass_kg() -> float:
	return MASS_KG


func mass_centre() -> Vector3:
	return MASS_CENTRE


func ground_share() -> float:
	return GROUND_SHARE


## The tail wheel's bottom (TailWheel, radius 0.2, axle 0.01 under the pin line).
func support_points() -> PackedVector3Array:
	return PackedVector3Array([Vector3(0.0, -0.21, TAIL_WHEEL_Z)])


func _process(delta: float) -> void:
	# Vertical axis: blades sweep parallel to the ground.
	spin_from_pto(_rotor, delta, ROTOR_RATIO)

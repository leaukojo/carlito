extends ImplementBase
## Mounted power harrow: powered secondary tillage, the only implement whose rotor turns about a
## horizontal axis. The plough is dragged through soil and this one is driven through it, hence ISO
## device class 3 against the plough's 2. The tines work in the soil, so draft_relevant() is true.

## Rotor turns per PTO shaft turn, cosmetic legibility gearing (see spin_from_pto).
const ROTOR_RATIO := 0.35

## Working depth (m below ground at full lower), measured off harrow.tscn (tines at y=-0.31,
## ground at y=-0.21), inside the trials' 6-15 cm. Its own number: the plough's 0.25 would report
## draft with the tines 15 cm in the air.
const TINE_DEPTH_M := 0.1

## Mass (kg) of the class drawn: a 3.0 m Cat 2 power harrow with a packer roller. Kverneland's M
## 3.0 at 1550 kg (sourced; its summary table says 927), the Amazone KE 3002 at 1530 with its
## roller (secondary) and Kuhn's HR 3030 at 1679 (sourced). Citations: docs/sources.md.
const MASS_KG := 1550.0

## Centre of mass in this frame: the area-weighted centroid of the scene's meshes.
const MASS_CENTRE := Vector3(0.0, 0.04, 0.59)

## Weight the ground carries at the bottom stop: the packer roller carries the machine and sets its
## depth. An ESTIMATE.
const GROUND_SHARE := 0.8

## The packer roller's bottom, measured off harrow.tscn (Roller, radius 0.2, 2.92 m long): its two
## ends and its middle, so a rigid 3 m roller rests on the highest of a slope or a ridge.
const SUPPORT := Vector3(0.0, -0.21, 1.12)
const ROLLER_HALF := 1.46

## Drawbar draught in D497's form, N per m width with S in km/h: A 1183, B 239, C 0, the line through
## a 3 m power harrow's 5.7 kN at 3 km/h and 10.0 kN at 9 km/h (Balsari et al., Biosystems
## Engineering 202, 2021: trials at 6-15 cm, two rotor speeds, a 1000 rpm PTO; the abstract read, the
## pair only from a summary of it: secondary, unverified against its tables). D497 rates no power
## harrow's draft (its load is mostly PTO). Held above 9 km/h, the top of the pair. Citations:
## docs/sources.md.
const DRAFT_SHAPE := Vector4(1183.0, 239.0, 0.0, 9.0)

## Pull at 7 km/h, full depth, full soil: that line at 7 km/h (2.856 kN/m) over the drawn 3.0 m,
## the trials' own width, 8.57 kN. The pair is the trials' speed trend, not one depth's, so it is
## an estimate at any one.
const RATED_DRAFT_N := 8570.0

@onready var _rotor: Node3D = $Rotor


func connections() -> int:
	return Connection.THREE_POINT | Connection.PTO | Connection.ISOBUS_DATA


func device_class() -> int:
	return CLASS_SECONDARY_TILLAGE


func draft_relevant() -> bool:
	return true


func tool_depth() -> float:
	return TINE_DEPTH_M


func draft_rating() -> float:
	return RATED_DRAFT_N


func draft_shape() -> Vector4:
	return DRAFT_SHAPE


func mass_kg() -> float:
	return MASS_KG


func mass_centre() -> Vector3:
	return MASS_CENTRE


func ground_share() -> float:
	return GROUND_SHARE


func support_points() -> PackedVector3Array:
	var side := Vector3(ROLLER_HALF, 0.0, 0.0)
	return PackedVector3Array([SUPPORT - side, SUPPORT, SUPPORT + side])


func _process(delta: float) -> void:
	# Transverse axis (local X): the tine shaft runs across the machine.
	spin_from_pto(_rotor, delta, ROTOR_RATIO, Vector3.RIGHT)

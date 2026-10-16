extends ImplementBase
## Four-furrow mounted mouldboard plough: the implement that uses the three-point linkage alone
## (no Connection.PTO; it is pulled, not driven). Draft-relevant: the shares are in the ground.
## Lowered, the shares reach 0.25 m below the ground line (balls 0.21 m up); raised, the front
## share is ~0.4 m clear.

## Degrees the gauge wheel's arm swings down as the plough is lifted (it hangs on its stop in the air).
const GAUGE_ARM_DROP_DEG := -11.0

## Working depth (m below ground at full lower), measured off plough.tscn (share bottom at
## y=-0.46, ground at y=-0.21). Draft ramps across this; re-measure if legs/shares move.
const SHARE_DEPTH_M := 0.25

## Mass (kg) of the class drawn: four 14" bodies (0.356 m across a 1.42 m cut, 0.85 m interbody
## clearance) on a Cat 2 headstock, the Kverneland AD Variomat 85's 4-furrow at 80-100 hp:
## sourced. Citations: docs/vehicles.md § Sourced figures.
const MASS_KG := 900.0

## Centre of mass in this frame: the area-weighted centroid of the scene's meshes (sheet and tube
## steel of one gauge). Left of centre because the beam steps the bodies out to the left.
const MASS_CENTRE := Vector3(-0.53, -0.05, 1.91)

## Weight the ground carries at the bottom stop: the depth wheel, ~7 of a 4-furrow plough's
## 21.4 kN with the top link free, in work (Oberhaus et al. 2005, read off its Fig. 2: sourced).
## The landside heel's share is unmeasured and left out.
const GROUND_SHARE := 0.35

## The depth wheel's tyre bottom, measured off plough.tscn (DepthWheel + Tyre, radius 0.3).
const SUPPORT := Vector3(-1.488, -0.21, 3.42)

## ASABE D497.7's mouldboard row, N per m width per cm depth with S in km/h: A 652, B 0, C 5.1
## (EcoTIM, arXiv 2604.17991, quoting D497.7: secondary). Its field speed range is 5-10 km/h,
## typical 7 (U. Arizona's machinery-management Table 3: sourced); held above 10. Citations:
## docs/vehicles.md § Sourced figures.
const DRAFT_SHAPE := Vector4(652.0, 0.0, 5.1, 10.0)

## Pull at 7 km/h, full depth, full soil: D497 for the drawn 1.42 m cut at its drawn 25 cm (a 14"
## body's 35.6 cm furrow over a width-to-depth ratio of ~1.4, inside a design slide's 1.1-1.5:
## estimate) in medium soil (texture factor 0.70; fine 1.0, coarse 0.45):
## 0.70 × 901.9 × 1.42 × 25 = 22.41 kN.
const RATED_DRAFT_N := 22410.0

@onready var _depth_wheel: Node3D = $DepthWheel


func connections() -> int:
	return Connection.THREE_POINT | Connection.ISOBUS_DATA


func device_class() -> int:
	return CLASS_TILLAGE


func draft_relevant() -> bool:
	return true


func tool_depth() -> float:
	return SHARE_DEPTH_M


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
	return PackedVector3Array([SUPPORT])


func set_hitch(pos01: float) -> void:
	if _depth_wheel != null:
		_depth_wheel.rotation.x = deg_to_rad(GAUGE_ARM_DROP_DEG) * clampf(pos01, 0.0, 1.0)

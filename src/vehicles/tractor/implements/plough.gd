extends ImplementBase
## Three-furrow mounted mouldboard plough — the implement that teaches the three-point linkage
## on its own. The only one of the four with nothing on the PTO (connections() omits
## Connection.PTO): a plough is pulled, not driven. Draft-relevant, like the power harrow — the
## shares are in the ground, so draft is real here and a clean zero for the mower/spreader.
## Lowered, shares straddle the ground line (balls at 0.21 m up fully lowered, shares 0.055 m
## below that); raised, the machine is half a metre clear.

## Degrees the gauge wheel's arm swings down as the plough is lifted. Trails on a hinged arm:
## held up by the soil on the ground, hanging on its stop in the air.
const GAUGE_ARM_DROP_DEG := -11.0

## Working depth (m below ground at full lower), measured off plough.tscn (share at y=-0.22,
## 0.1 m extent, ground at y=-0.21). Draft ramps across this; re-measure if legs/shares move.
const SHARE_DEPTH_M := 0.055

@onready var _depth_wheel: Node3D = $DepthWheel


func connections() -> int:
	return Connection.THREE_POINT | Connection.ISOBUS_DATA


func device_class() -> int:
	return CLASS_TILLAGE


func draft_relevant() -> bool:
	return true


func tool_depth() -> float:
	return SHARE_DEPTH_M


func set_hitch(pos01: float) -> void:
	if _depth_wheel != null:
		_depth_wheel.rotation.x = deg_to_rad(GAUGE_ARM_DROP_DEG) * clampf(pos01, 0.0, 1.0)

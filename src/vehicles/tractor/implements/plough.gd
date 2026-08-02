extends ImplementBase
## Three-furrow mounted mouldboard plough — the implement that teaches the three-point
## linkage on its own.
##
## It is the only one of the four with NOTHING on the power take-off: a plough is pulled
## through the soil, it is not driven. That is a declaration, not a comment — connections()
## omits Connection.PTO, so ThreePointHitch never passes it drive and 'pto_rpm' reaching the
## shaft behind it changes nothing here. It is draft-relevant, along with the power harrow that
## works the same soil under power: these shares are in the ground, so the draft force is real
## for this machine and a clean zero for the mower and the spreader.
##
## Its whole visual job is 'hitch_pos_actual': lowered, the shares straddle the ground line
## (measured — the lower-link balls sit 0.21 m up when fully lowered, and the shares reach
## 0.055 m below that); raised, the machine is half a metre clear.

## Degrees the gauge wheel's arm swings down as the plough is lifted. The wheel trails on a
## hinged arm, so on the ground it is held up by the soil and in the air it hangs on its stop
## — a small, real motion, and the reason ImplementBase has a set_hitch seam at all.
const GAUGE_ARM_DROP_DEG := -11.0

## Working depth (m below the ground line at full lower) — MEASURED off plough.tscn: each share
## sits at y = -0.22 with a 0.1 m vertical extent, so its point reaches y = -0.27 against a
## ground line of y = -0.21. This is what the draft force ramps across, so it must be re-measured
## if the legs or the shares ever move.
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

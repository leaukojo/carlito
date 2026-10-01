extends ImplementBase
## Mounted rotary mower: the rotor turns at the shaft speed the tractor reports, so PTO, revs and
## 540/1000 are visible. Not draft-relevant: the deck rides on skids above the ground.

## Rotor turns per PTO shaft turn, cosmetic legibility gearing (see spin_from_pto).
const ROTOR_RATIO := 0.3

@onready var _rotor: Node3D = $Rotor


func connections() -> int:
	return Connection.THREE_POINT | Connection.PTO | Connection.ISOBUS_DATA


func device_class() -> int:
	return CLASS_FORAGE


func _process(delta: float) -> void:
	# Vertical axis: blades sweep parallel to the ground.
	spin_from_pto(_rotor, delta, ROTOR_RATIO)

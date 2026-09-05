extends ImplementBase
## Mounted rotary mower (rotary cutter) — makes the PTO visible: the rotor turns at the shaft
## speed the tractor reports, so engaging the PTO, revving the engine and switching 540/1000 are
## all visible rather than read off the cluster. Not draft-relevant: the deck rides on skids
## above the ground, so draft_relevant() stays false and draft reads a clean zero.

## Rotor turns per PTO shaft turn — cosmetic legibility gearing, see spin_from_pto.
const ROTOR_RATIO := 0.3

@onready var _rotor: Node3D = $Rotor


func connections() -> int:
	return Connection.THREE_POINT | Connection.PTO | Connection.ISOBUS_DATA


func device_class() -> int:
	return CLASS_FORAGE


func _process(delta: float) -> void:
	# Vertical axis: blades sweep parallel to the ground (rotate_y, not the PTO stub's rotate_z).
	spin_from_pto(_rotor, delta, ROTOR_RATIO)

extends ImplementBase
## Mounted rotary mower (rotary cutter) — the implement that makes the POWER TAKE-OFF visible.
##
## It hangs on the same three links as the plough, but everything interesting about it is on
## the other connection: the rotor turns at the shaft speed the tractor reports, so engaging
## the PTO, revving the engine and switching 540/1000 are all things you can
## SEE rather than read off the cluster.
##
## It is not draft-relevant: the deck rides on its skids above the ground, so pulling it costs
## the tractor nothing that a plough's shares would — draft_relevant() stays false and the
## draft signal must read a clean zero with this on the hitch.

## Rotor turns per PTO shaft turn — cosmetic legibility gearing, see spin_from_pto.
const ROTOR_RATIO := 0.3

@onready var _rotor: Node3D = $Rotor


func connections() -> int:
	return Connection.THREE_POINT | Connection.PTO | Connection.ISOBUS_DATA


func device_class() -> int:
	return CLASS_FORAGE


func _process(delta: float) -> void:
	# Vertical axis: a rotary cutter's blades sweep parallel to the ground, so this is the
	# base's rotate_y helper, not the tractor stub's rotate_z.
	spin_from_pto(_rotor, delta, ROTOR_RATIO)

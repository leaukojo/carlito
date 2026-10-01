extends ImplementBase
## Mounted power harrow: powered secondary tillage, the only implement whose rotor turns about a
## horizontal axis. The plough is dragged through soil and this one is driven through it, hence ISO
## device class 3 against the plough's 2. The tines work in the soil, so draft_relevant() is true.

## Rotor turns per PTO shaft turn, cosmetic legibility gearing (see spin_from_pto).
const ROTOR_RATIO := 0.35

## Working depth (m below ground at full lower), measured off harrow.tscn (tines at y=-0.23,
## ground at y=-0.21). Its own number: the plough's 0.055 would report draft with the tines 35 mm
## in the air.
const TINE_DEPTH_M := 0.02

@onready var _rotor: Node3D = $Rotor


func connections() -> int:
	return Connection.THREE_POINT | Connection.PTO | Connection.ISOBUS_DATA


func device_class() -> int:
	return CLASS_SECONDARY_TILLAGE


func draft_relevant() -> bool:
	return true


func tool_depth() -> float:
	return TINE_DEPTH_M


func _process(delta: float) -> void:
	# Transverse axis (local X): the tine shaft runs across the machine.
	spin_from_pto(_rotor, delta, ROTOR_RATIO, Vector3.RIGHT)

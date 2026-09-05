extends ImplementBase
## Mounted power harrow — powered secondary tillage, the only implement whose rotor turns about
## a horizontal axis. Counterpart to the plough on the same connection: the plough is dragged
## through soil, this one is driven through it, hence a different ISO device class (3 vs. the
## plough's 2). The tine rotor works in the soil, so draft_relevant() is true, like the plough.
## The telescoping driveshaft (PTO stub to input gearbox) is not modelled, like every implement;
## the gearbox and input shaft are.

## Rotor turns per PTO shaft turn, cosmetic legibility gearing (see spin_from_pto). Power harrows
## gear down hard from the PTO, so this stays honest about direction as well as readable.
const ROTOR_RATIO := 0.35

## Working depth (m below ground at full lower), measured off harrow.tscn (tines at y=-0.23,
## ground at y=-0.21). Shallower than the plough by design; own number, not shared with it, since
## a shared depth would report draft with the tines 35 mm in the air.
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
	# Transverse axis (local X): the tine shaft runs across the machine, unlike the mower/spreader's
	# vertical discs.
	spin_from_pto(_rotor, delta, ROTOR_RATIO, Vector3.RIGHT)

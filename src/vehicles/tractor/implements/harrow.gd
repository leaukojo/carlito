extends ImplementBase
## Mounted power harrow — powered SECONDARY tillage, and the only machine here whose rotor
## turns about a horizontal axis.
##
## It is the counterpart to the plough on the same connection: both are tillage, but the
## plough is dragged through the soil and this one is DRIVEN through it. That is why it
## reports a different ISO device class (3, secondary tillage, against the plough's 2) — the
## bus has to be able to tell "something is breaking up what I just ploughed" from "something
## is ploughing".
##
## The tine rotor works IN the soil, so unlike the mower and the spreader this machine really
## does resist being pulled: draft_relevant() is true, alongside the plough.
##
## The telescoping driveshaft from the tractor's PTO stub to the input gearbox is NOT modelled
## (the one mechanical part left out on every implement); the gearbox and the input shaft
## running forward out of it are.

## Rotor turns per PTO shaft turn — cosmetic legibility gearing, see spin_from_pto. Power
## harrows really do gear DOWN hard from the PTO, so this one is honest about its direction as
## well as being readable.
const ROTOR_RATIO := 0.35

## Working depth (m below the ground line at full lower) — MEASURED off harrow.tscn, where the
## tines reach y = -0.23 against a ground line of y = -0.21. Shallower than the plough's shares
## by design (a harrow works the ploughed layer, it does not cut it), which is why the depth is
## the implement's own number: shared, the harrow would still be reporting draft with its tines
## 35 mm in the air.
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
	# TRANSVERSE axis: the tine shaft runs across the machine, so this rotor turns about local
	# X — not the vertical axis the mower's and spreader's discs use.
	spin_from_pto(_rotor, delta, ROTOR_RATIO, Vector3.RIGHT)

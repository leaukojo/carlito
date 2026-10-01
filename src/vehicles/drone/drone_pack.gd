class_name DronePack
extends RefCounted
## The pack's state (charge accumulator, temperature), ticked by DroneVehicle; DronePower holds the
## arithmetic. `soc` is read one tick late by the arming block (the pack integrates after the ESC
## currents are known). The accumulator stays a float; the published `soc` is rounded like fuel.


## Coulombs left, as a percentage. `reset` is the only recharge.
var soc := 100.0
## Pack temperature (degC): an I^2 R rise relaxed toward ambient, slower than an ESC
## (PACK_TEMP_TAU against ESC_TEMP_TAU).
var temp := DronePower.PACK_AMBIENT


## Integrates one tick against the four ESC currents and returns the pack current. Pass the TRUE
## currents, not the published ones: `pack_current` follows the real draw when a node drops.
func step(esc_amps: PackedFloat32Array, delta: float) -> float:
	var pack_a := DronePower.pack_current_a(esc_amps, DronePower.AVIONICS_A)
	soc = DronePower.soc_step(soc, pack_a, DronePower.PACK_CAPACITY_AH, delta)
	temp = DronePower.pack_temp_step(temp, pack_a, DronePower.PACK_AMBIENT,
			DronePower.PACK_TEMP_K, DronePower.PACK_TEMP_TAU, delta)
	return pack_a


## Terminal volts at this charge and draw: the OCV curve less the IR drop, so a punch-out sags the
## number. Replaces the base's alternator `battery` value.
func volts(pack_a: float) -> float:
	return DronePower.pack_volts(soc, pack_a, DronePower.PACK_R_INTERNAL)


## Any charge left? The master-switch half of the arming gate.
func has_charge() -> bool:
	return soc > 0.0


## A respawn replaces the pack (unlike `fuel`, which the base carries across): a flat pack would
## leave the craft unflyable.
func reset() -> void:
	soc = 100.0
	temp = DronePower.PACK_AMBIENT

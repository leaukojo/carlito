class_name DronePack
extends RefCounted
## The pack's state, owned and ticked by DroneVehicle. DronePower holds the arithmetic; this holds
## what remembers between ticks, the charge accumulator and the pack temperature. `soc` is read one
## tick late by the arming block, since the pack integrates at the bottom of the tick once the ESC
## currents are known. The accumulator stays a float and the published `soc` is rounded like fuel.


## Coulombs left, as a percentage. Full at birth, and `reset` is the only recharge the game has.
var soc := 100.0
## Pack temperature (degC), an I^2 R rise relaxed toward ambient. It lags further than an ESC
## does (PACK_TEMP_TAU against ESC_TEMP_TAU), because a 4S pack is a lot more metal.
var temp := DronePower.PACK_AMBIENT


## Integrate one tick against the four ESC currents, returning the pack current those made; the
## caller needs it for `pack_current`, and returning it avoids summing twice. Downstream of the
## ESCs by construction, so every coulomb spent traces to thrust the craft really made (rule 3).
## Call it with the true currents, not the published ones: `pack_current` must follow the real
## draw when a motor stops, rather than the held telemetry the bus is still publishing.
func step(esc_amps: PackedFloat32Array, delta: float) -> float:
	var pack_a := DronePower.pack_current_a(esc_amps, DronePower.AVIONICS_A)
	soc = DronePower.soc_step(soc, pack_a, DronePower.PACK_CAPACITY_AH, delta)
	temp = DronePower.pack_temp_step(temp, pack_a, DronePower.PACK_AMBIENT,
			DronePower.PACK_TEMP_K, DronePower.PACK_TEMP_TAU, delta)
	return pack_a


## Terminal volts at this charge and draw: the OCV curve less the IR drop, so a punch-out visibly
## sags the number. `battery` is the shared contract signal, and this replaces the base's
## alternator value with the pack's, since a battery-electric quad has no alternator.
func volts(pack_a: float) -> float:
	return DronePower.pack_volts(soc, pack_a, DronePower.PACK_R_INTERNAL)


## Is there any charge left at all? The master-switch half of the arming gate: an empty pack turns
## no motors whatever the pre-arm checks say.
func has_charge() -> bool:
	return soc > 0.0


## A respawn replaces the pack rather than cooling it, unlike `fuel`, which the base carries
## across: an empty pack stops the motors, so carrying a flat one over a teleport would leave the
## craft permanently unflyable.
func reset() -> void:
	soc = 100.0
	temp = DronePower.PACK_AMBIENT

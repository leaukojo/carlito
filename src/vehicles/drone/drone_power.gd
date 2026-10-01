class_name DronePower
extends RefCounted
## The drone's 4S LiPo pack: pure static math; `DronePack` holds the state (coulomb accumulator,
## pack temperature). Drives `battery` as `V_terminal = V_oc(soc) - I_pack * R_internal`, plus
## `pack_current`, `soc` and `pack_temp`. An honest model (rule 3); call `pack_current_a` with the
## TRUE per-ESC currents, never the published ones. `tests/test_drone_power.gd` walks the sizing.

## Cells in series. The OCV table below is per-cell; everything public here is per-PACK.
const CELLS := 4
## Rated capacity (Ah): THE knob that sets endurance.
const PACK_CAPACITY_AH := 10.0
## Pack internal resistance (ohm), all four cells plus wiring. THE sag knob.
const PACK_R_INTERNAL := 0.011
## Everything on the pack that is not a motor (A): flight controller, GPS, radio, gimbal. Constant
## because none of it is simulated.
const AVIONICS_A := 1.5
## Ambient (and startup / post-respawn) pack temperature, degC.
const PACK_AMBIENT := 20.0
## Steady-state pack heating: degC above ambient per A^2.
const PACK_TEMP_K := 0.00085
## Pack thermal time constant (s). Slower than the ESCs' 20 s on purpose: more mass.
const PACK_TEMP_TAU := 60.0

## Open-circuit voltage curve, per cell, piecewise-linear over state of charge. Two parallel
## arrays, ascending in soc (ORDER matters). Ends: 4.20 V off-charger, 3.15 V called empty (16.8 V /
## 12.6 V pack). Real LiPo shape: flat shoulder 100%-20%, then a knee, which is why the volts bar
## is a poor charge gauge and `soc` is its own signal.
const OCV_SOC_PCT: Array[float] = [0.0, 5.0, 10.0, 20.0, 40.0, 60.0, 80.0, 90.0, 100.0]
const OCV_CELL_V: Array[float] = [3.15, 3.30, 3.50, 3.70, 3.79, 3.87, 3.95, 4.07, 4.20]


## Pack open-circuit voltage (V) at a state of charge: OCV_CELL_V interpolated, times CELLS.
## Out-of-range soc pins to the table ends.
static func pack_ocv(soc_pct: float) -> float:
	var last := OCV_SOC_PCT.size() - 1
	var s := clampf(soc_pct, OCV_SOC_PCT[0], OCV_SOC_PCT[last])
	for i in range(1, OCV_SOC_PCT.size()):
		if s <= OCV_SOC_PCT[i]:
			var lo: float = OCV_SOC_PCT[i - 1]
			var span: float = OCV_SOC_PCT[i] - lo
			var f := 0.0 if span <= 0.0 else (s - lo) / span
			return CELLS * lerpf(OCV_CELL_V[i - 1], OCV_CELL_V[i], f)
	return CELLS * OCV_CELL_V[last]


## Terminal voltage (V) for the contract's `battery` signal: V = V_oc(soc) - I * R_internal.
## Sag is instantaneous (no recovery over time). Never negative: 0 V is truer than a negative volt.
static func pack_volts(soc_pct: float, current_a: float, r_internal: float) -> float:
	return maxf(pack_ocv(soc_pct) - maxf(current_a, 0.0) * maxf(r_internal, 0.0), 0.0)


## Total pack current: four ESC draws plus avionics. Pass TRUE currents, not published (they
## disagree after a node drop: an offline ESC stops drawing here but holds its published current).
## An empty array returns the avionics floor.
static func pack_current_a(esc_amps: PackedFloat32Array, avionics_a: float) -> float:
	var total := maxf(avionics_a, 0.0)
	for a in esc_amps:
		total += maxf(a, 0.0)
	return total


## State of charge (%) after one tick: coulomb counting, `dsoc = -100 * I * dt / (3600 * capacity_Ah)`.
## Clamped to [0, 100], monotonically falling (no regen). Non-positive capacity returns the clamped
## input.
static func soc_step(soc_pct: float, current_a: float, capacity_ah: float, delta: float) -> float:
	if capacity_ah <= 0.0 or delta <= 0.0:
		return clampf(soc_pct, 0.0, 100.0)
	var drawn_ah := maxf(current_a, 0.0) * delta / 3600.0
	return clampf(soc_pct - 100.0 * drawn_ah / capacity_ah, 0.0, 100.0)


## Pack temperature (degC) after one tick: first-order relax toward ambient + k*I^2, stable at any
## tick rate (the shape of `DroneProp.esc_temp_step`, kept separate so neither retunes the other).
static func pack_temp_step(temp: float, current: float, ambient: float, k: float,
		tau: float, delta: float) -> float:
	var target := ambient + maxf(k, 0.0) * current * current
	if tau <= 0.0 or delta <= 0.0:
		return target
	return temp + (target - temp) * (1.0 - exp(-delta / tau))

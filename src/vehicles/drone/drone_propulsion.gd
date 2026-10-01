class_name DroneProp
extends RefCounted
## Quad propulsion chain: pure statics. Demand -> four motor commands, speeds, thrusts, currents,
## temps, rotor rpm. Nothing reaches back to DroneVehicle. Constants' arithmetic: drone.gd @exports
## (max_attitude_torque, max_yaw_torque, prop_torque_ratio); rules: `src/vehicles/drone/CLAUDE.md`.


# ---------------------------------------------------------------- the airframe

## The airframe in DroneCAN esc_index order. Do not renumber; tests pin it to drone.tscn (a moved
## rotor inverts a control axis). Sign conventions for roll/pitch/yaw torque and blade spin:
##
## | idx | node     | x | z | spin | roll | pitch | yaw |
## |-----|----------|---|---|------|------|-------|-----|
## |  0  | RotorFL  | - | - |  +1  |  -1  |   +1  |  -1 |
## |  1  | RotorFR  | + | - |  -1  |  +1  |   +1  |  +1 |
## |  2  | RotorRL  | - | + |  -1  |  -1  |   -1  |  +1 |
## |  3  | RotorRR  | + | + |  +1  |  +1  |   -1  |  -1 |
const MOTORS := [
	{"node": "RotorFL", "spin": 1, "roll": -1, "pitch": 1, "yaw": -1},
	{"node": "RotorFR", "spin": -1, "roll": 1, "pitch": 1, "yaw": 1},
	{"node": "RotorRL", "spin": -1, "roll": -1, "pitch": -1, "yaw": 1},
	{"node": "RotorRR", "spin": 1, "roll": 1, "pitch": -1, "yaw": -1},
]

## Motor speed at full command and the contract `rotor_rpm` range max: the one mapping from
## normalized speed to rev/min.
const ROTOR_MAX_RPM := 12000


# --------------------------------------------- the ESC electrical / thermal model

## ESC electrical/thermal model constants: plain constants, not @export (a labelled model behind a
## published signal, not flight feel).
##
## Nominal pack voltage (V), 4S. Constant though the pack sags (`drone_power.gd`): feeding live
## terminal voltage back would close an algebraic loop and push a pinned motor from 76 A to ~89 A,
## past the contract's 80 A `esc_current` range.
const ESC_PACK_VOLTS := 14.8
## Combined motor+ESC efficiency (mechanical watts out per electrical watt in).
const ESC_ETA := 0.85
## No-load current per ESC (A): the floor a spun-down but powered motor still draws.
const ESC_I_NOLOAD := 1.0
## Ambient (and startup / post-respawn) ESC temperature, degC.
const ESC_AMBIENT := 20.0
## Steady-state heating: degC above ambient per A^2. Sized so a full-stick climb (~38 A) settles
## just under the 90 degC warn; re-check the envelope test if this moves.
const ESC_TEMP_K := 0.0445
## Thermal time constant (s): fast enough that a climb visibly heats the bars, slow enough to lag
## the stick.
const ESC_TEMP_TAU := 20.0


# ------------------------------------------------------------------- the mixer

## Quad-X mixer: four normalized motor commands in MOTORS order, thrust-fraction units
## (`collective` = share of max_thrust; `torque_to_demand` converts N*m to axis demand). Saturation
## is a per-motor clamp to [0, 1] with NO rescaling or compensation: a pinned motor loses authority,
## which the node failures need. sqrt is the thrust-to-speed mapping (thrust ~ w^2).
static func mix_quad_x(collective: float, roll: float, pitch: float, yaw: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(MOTORS.size())
	for i in MOTORS.size():
		var m: Dictionary = MOTORS[i]
		var u := collective + roll * float(m["roll"]) + pitch * float(m["pitch"]) + yaw * float(m["yaw"])
		out[i] = sqrt(clampf(u, 0.0, 1.0))
	return out


## The demand that produces `torque` N*m on an axis with lever `lever` (arm_x for roll, arm_z for
## pitch, prop_torque_ratio for yaw). Unbounded on purpose: the mixer clamps.
static func torque_to_demand(torque: float, lever: float, thrust_cap: float) -> float:
	var lever_scale := lever * thrust_cap
	if lever_scale <= 1e-9:
		return 0.0
	return torque / lever_scale


# ------------------------------------------------------------------- the motors

## One first-order spool step toward `command`, stable at any tick rate.
static func spool_step(omega: float, command: float, tau: float, delta: float) -> float:
	var target := clampf(command, 0.0, 1.0)
	if tau <= 0.0 or delta <= 0.0:
		return target
	return clampf(omega + (target - omega) * (1.0 - exp(-delta / tau)), 0.0, 1.0)


## One motor's thrust (N) at normalized speed `omega`: thrust ~ w^2, so all four at full make
## `thrust_cap`. Capped at thrust_cap/4.
static func motor_thrust(omega: float, thrust_cap: float) -> float:
	var w := clampf(omega, 0.0, 1.0)
	return maxf(thrust_cap, 0.0) / float(MOTORS.size()) * w * w


## Mean normalized motor speed [0, 1]; gates the rotor-borne vertical damper. Distinct from
## `rotor_rpm`, which averages the published per-ESC rpms.
static func mean_omega(omegas: PackedFloat32Array) -> float:
	if omegas.is_empty():
		return 0.0
	var sum := 0.0
	for w in omegas:
		sum += clampf(w, 0.0, 1.0)
	return sum / float(omegas.size())


# ------------------------------------ the per-ESC bus (contract count-4 signals)

## Mean of the PUBLISHED per-ESC rpms, not a second pass over `_omega`. NOT gated on `armed`: props
## take ~5*tau to spin down after disarm, so gating would publish zero while they still make lift.
static func rotor_rpm(rpms: PackedInt32Array) -> int:
	if rpms.is_empty():
		return 0
	var sum := 0
	for r in rpms:
		sum += r
	return roundi(float(sum) / float(rpms.size()))


## Per-motor rpm through the one ROTOR_MAX_RPM mapping.
static func esc_rpm(omegas: PackedFloat32Array, max_rpm: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(omegas.size())
	for i in omegas.size():
		out[i] = roundi(clampf(omegas[i], 0.0, 1.0) * float(max_rpm))
	return out


## One motor's phase current (A). Labelled honest model, electrical half only:
##
##     tau = torque_ratio * motor_thrust(omega, cap)     [N*m]  (the yaw reaction torque)
##     w   = omega * max_rpm * TAU / 60                  [rad/s]
##     I   = tau * w / (eta * v_pack) + i_noload         [A]
static func esc_current_a(omega: float, max_rpm: int, thrust_cap: float,
		torque_ratio: float, v_pack: float, eta: float, i_noload: float) -> float:
	var w := clampf(omega, 0.0, 1.0)
	var shaft := w * float(max_rpm) * TAU / 60.0
	var torque := maxf(torque_ratio, 0.0) * motor_thrust(w, thrust_cap)
	var denom := maxf(eta * v_pack, 1e-6)
	return maxf(torque * shaft / denom + i_noload, 0.0)


## One motor's temperature after one tick: labelled honest model, first-order relax toward
## ambient + k*I^2.
static func esc_temp_step(temp: float, current: float, ambient: float, k: float,
		tau: float, delta: float) -> float:
	var target := ambient + maxf(k, 0.0) * current * current
	if tau <= 0.0 or delta <= 0.0:
		return target
	return temp + (target - temp) * (1.0 - exp(-delta / tau))


## Fault bitfield, bit i = esc_index i, set while that ESC is over `warn` degC. Offline nodes OR
## in separately (`DroneBus.offline_esc_bits`).
static func esc_fault_bits(temps: PackedFloat32Array, warn: float) -> int:
	var bits := 0
	for i in temps.size():
		if temps[i] > warn:
			bits |= 1 << i
	return bits

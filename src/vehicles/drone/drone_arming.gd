class_name DroneArming
extends RefCounted
## The drone's arming state machine: pre-arm checks, failsafes, latching. Pure static logic;
## DroneVehicle holds the cross-tick state. `armed` is the ESC gate. `arming_state` is
## DISARMED/BLOCKED/ARMED (BLOCKED = asked and refused). `prearm_fail` is one bit per check.
## `failsafe` is the most severe active failure, or FS_NONE. The key and an empty pack cut arming
## unconditionally (reads DISARMED, not BLOCKED). Arming is a rising edge, disarming a level.

## uavcan.equipment.safety.ArmingStatus plus BLOCKED: the contract's `arming_state` enum, pinned by test.
enum { DISARMED = 0, BLOCKED = 1, ARMED = 2 }

## The contract's `failsafe` enum, pinned by test. Ordinals are a stable wire enum, NOT priority;
## severity order is in `failsafe_of`.
enum { FS_NONE = 0, FS_BATT_LOW = 1, FS_BATT_CRIT = 2, FS_GPS_LOST = 3, FS_GEOFENCE = 4,
		FS_MOTOR = 5 }

# --- pre-arm checks, one bit each (contract `prearm_fail`) ---
# A set bit is a failed check (opposite polarity to `node_online`). Bits are frozen like `status`:
# a new check appends at bit 7.

## Airframe not level enough to spin up: |pitch| or |roll| over ARM_TILT_DEG.
const PA_ATTITUDE := 1 << 0
## Pack too low to fly: below ARM_SOC_MIN.
const PA_BATTERY := 1 << 1
## At least one ESC node off the bus (DroneBus): fewer than four motors.
const PA_ESC := 1 << 2
## AHRS node off the bus: nothing self-levels without an attitude solution.
const PA_AHRS := 1 << 3
## Climb axis not centred: a deflected stick would leap the craft on arming.
const PA_STICK := 1 << 4
## A failsafe is already active (`failsafe` names which).
const PA_FAILSAFE := 1 << 5
## Selected mode needs a 3D fix and there is none. Gated on the mode, like ArduPilot's: STABILIZE
## and ALT_HOLD need no receiver.
const PA_GPS := 1 << 6

## Every bit this airframe can set; a new check must be added here or the sweep test misses it.
const PA_ALL := PA_ATTITUDE | PA_BATTERY | PA_ESC | PA_AHRS | PA_STICK | PA_FAILSAFE | PA_GPS

# --- thresholds ---

## Degrees of pitch/roll past which arming is refused: ~1/3 of the 32 deg tilt limit, a visible
## slope well inside normal flight, so a hill parking spot demonstrates the check.
const ARM_TILT_DEG := 10.0

## % SoC below which the pack will not launch. Above SOC_LOW on purpose: arming at the low-battery
## threshold would take off already inside a failsafe.
const ARM_SOC_MIN := 25.0

## % at which the low-battery failsafe commands RTL. Equals the contract's `soc` warn (pinned by
## test, JSON cannot read GDScript), so the dashboard bar turns danger exactly when it comes home.
const SOC_LOW := 20.0

## % at which the critical-battery failsafe lands where it stands (10% of the shipped 10 Ah pack).
const SOC_CRIT := 10.0

## Seconds the landed predicate must hold before auto-disarm: a pause on top of the 0.5 s
## `DroneSensors` debounce, not the detection (ArduPilot's default is 10 s).
const AUTO_DISARM_S := 3.0


## Everything arming logic reads, filled once by the vehicle.
##
## `mode_want` is the pilot's request after the fence, before failsafe forcing
## (DroneModes.wanted_mode): the resolved mode would close a loop (a GPS_LOST-forced ALT_HOLD
## would clear itself and toggle). `pos_fix` is the debounced predicate, never raw `fix_type`.
class Snapshot extends RefCounted:
	var pitch := 0.0        ## deg, + = nose up (VehicleTelemetry.pitch)
	var roll := 0.0         ## deg, + = starboard down (VehicleTelemetry.roll)
	var soc := 100.0        ## %, coulomb-counted pack charge
	var node_fail := 0      ## DroneBus roster failure mask (contract `node_fail`)
	var ahrs_node := -1     ## roster index of the AHRS node, resolved once at _ready
	var climb := 0.0        ## climb axis, [-1, 1]
	var pos_fix := false    ## debounced 3D-fix predicate (DroneModes.held_fix_ok)
	var mode_want := 0      ## DroneModes.STABILIZE — request after fence, before failsafes
	var fence_rtl := false  ## latched geofence breach (DroneModes.fence_latch)
	var failsafe := 0       ## FS_NONE — this tick's active failsafe, filled by failsafe_of() first


## Which failsafe the aircraft is reacting to. Priority by action forced, not enum ordinal:
## MOTOR (lost yaw authority) > BATT_CRIT (land) > BATT_LOW (RTL) > GEOFENCE (latch RTL) >
## GPS_LOST (mode fallback).
static func failsafe_of(s: Snapshot) -> int:
	if DroneBus.offline_esc_bits(s.node_fail) != 0:
		return FS_MOTOR
	if s.soc < SOC_CRIT:
		return FS_BATT_CRIT
	if s.soc < SOC_LOW:
		return FS_BATT_LOW
	if s.fence_rtl:
		return FS_GEOFENCE
	if DroneModes.uses_pos_fix(s.mode_want) and not s.pos_fix:
		return FS_GPS_LOST
	return FS_NONE


## The mode this failsafe demands (fed to DroneModes.resolve_mode as `forced`), or -1 for none.
## GEOFENCE and GPS_LOST return -1: resolve_mode already handles them. RTL for a low pack, LAND for
## a critical pack or dead motor.
static func failsafe_mode(fs: int) -> int:
	match fs:
		FS_MOTOR, FS_BATT_CRIT:
			return DroneModes.LAND
		FS_BATT_LOW:
			return DroneModes.RTL
	return -1


## Every pre-arm check, as a bitfield: the ONE place a refusal is decided (`arm_step` arms on
## `fails == 0`). `s.failsafe` must already be filled (call failsafe_of first), since PA_FAILSAFE
## checks it.
static func prearm_fail(s: Snapshot) -> int:
	var bits := 0
	if absf(s.pitch) > ARM_TILT_DEG or absf(s.roll) > ARM_TILT_DEG:
		bits |= PA_ATTITUDE
	if s.soc < ARM_SOC_MIN:
		bits |= PA_BATTERY
	if DroneBus.offline_esc_bits(s.node_fail) != 0:
		bits |= PA_ESC
	if not DroneBus.is_online(s.node_fail, s.ahrs_node):
		bits |= PA_AHRS
	if absf(s.climb) > DroneModes.STICK_DEADBAND:
		bits |= PA_STICK
	if s.failsafe != FS_NONE:
		bits |= PA_FAILSAFE
	if DroneModes.needs_pos_fix(s.mode_want) and not s.pos_fix:
		bits |= PA_GPS
	return bits


## The published `prearm_fail`: live checks while gating, 0 once armed (live bits would light
## PA_STICK/PA_ATTITUDE through every manoeuvre; a real FC stops pre-arm checks on arming).
static func published_fail(armed: bool, fails: int) -> int:
	return 0 if armed else fails


## The arming state the bus sees. BLOCKED needs a powered aircraft, a raised switch and a failed
## check. A craft that auto-disarmed with the switch still up reads DISARMED: it waits for the
## switch to be cycled (see arm_step).
static func state_of(armed: bool, arm_req: bool, power_ok: bool, fails: int) -> int:
	if armed:
		return ARMED
	if power_ok and arm_req and fails != 0:
		return BLOCKED
	return DISARMED


## One step: last tick's `armed` and this tick's inputs give this tick's `armed`. `power_ok` (key +
## pack charge) cuts unconditionally; a disarm request is refused in flight (`landed`).
static func arm_step(armed: bool, arm_req: bool, arm_req_prev: bool, power_ok: bool,
		fails: int, landed: bool, auto_now: bool) -> bool:
	if not power_ok:
		return false
	if armed:
		if auto_now:
			return false
		return arm_req or not landed
	return arm_req and not arm_req_prev and fails == 0


## Seconds armed and landed continuously; zeroed on takeoff or disarm.
static func disarm_hold_step(hold: float, armed: bool, landed: bool, delta: float) -> float:
	if not armed or not landed:
		return 0.0
	return hold + maxf(delta, 0.0)


## Has that timer run out?
static func auto_disarm_due(hold: float) -> bool:
	return hold >= AUTO_DISARM_S

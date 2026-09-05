class_name DroneArming
extends RefCounted
## The drone's arming state machine: pre-arm checks, failsafes, and latching logic. Pure static
## logic; DroneVehicle holds cross-tick state (armed latch, arm request edge, auto-disarm timer).
## `armed` is the ESC gate. `arming_state` is DISARMED/BLOCKED/ARMED (BLOCKED = asked and refused).
## `prearm_fail` is one bit per check. `failsafe` is the most severe active failure, or FS_NONE.
## The key and empty pack unconditionally cut arming (absent → DISARMED, not BLOCKED).
## Arming is a rising edge; disarming is a level, since a held switch is a standing instruction.

## uavcan.equipment.safety.ArmingStatus plus BLOCKED, the contract's `arming_state` enum
## verbatim;
## pinned by test.
enum { DISARMED = 0, BLOCKED = 1, ARMED = 2 }

## The failsafe ladder — contract's `failsafe` enum verbatim, also pinned by test. Ordinals are a
## stable wire enum, NOT priority; severity order is stated in `failsafe_of`.
enum { FS_NONE = 0, FS_BATT_LOW = 1, FS_BATT_CRIT = 2, FS_GPS_LOST = 3, FS_GEOFENCE = 4,
		FS_MOTOR = 5 }

# --- the pre-arm checks, one bit each (contract `prearm_fail`) -------------------
#
# A set bit is a failed check (0 = all pass), opposite polarity to `node_online`. Bits are frozen
# like `status`: a new check appends at bit 7, never renumbers.

## Airframe not level enough to spin up: |pitch| or |roll| over ARM_TILT_DEG.
const PA_ATTITUDE := 1 << 0
## Pack too low to fly: below ARM_SOC_MIN.
const PA_BATTERY := 1 << 1
## At least one ESC node off the bus (DroneBus) — mixer has fewer than four motors.
const PA_ESC := 1 << 2
## AHRS node off the bus — nothing self-levels without an attitude solution.
const PA_AHRS := 1 << 3
## Climb axis not centred — a deflected stick would leap the craft on arming.
const PA_STICK := 1 << 4
## A failsafe is already active — `failsafe` names which.
const PA_FAILSAFE := 1 << 5
## Selected mode needs a 3D fix and there isn't one. Gated on the mode, like ArduPilot's own GPS
## pre-arm check — STABILIZE/ALT_HOLD need no receiver at all.
const PA_GPS := 1 << 6

## Every bit this airframe can set — the value of an aircraft that fails everything; a new const
## must be added here too or the sweep test misses it.
const PA_ALL := PA_ATTITUDE | PA_BATTERY | PA_ESC | PA_AHRS | PA_STICK | PA_FAILSAFE | PA_GPS

# --- the thresholds -------------------------------------------------------------

## Degrees of pitch/roll past which arming is refused. ~1/3 of the 32 deg tilt limit — a slope you
## can see, well inside normal flight; lets a hill parking spot demonstrate the check.
const ARM_TILT_DEG := 10.0

## % SoC below which the pack won't launch. Deliberately above SOC_LOW: arming at the low-battery
## threshold would mean taking off already inside a failsafe. Five points ≈ a minute of hover.
const ARM_SOC_MIN := 25.0

## % at which the low-battery failsafe commands RTL. This is the contract's `soc` warn, pinned by
## a test,
## since JSON can't read GDScript — so the dashboard bar turns danger exactly when it comes home.
const SOC_LOW := 20.0

## % at which the critical-battery failsafe lands where it stands. 10% of the shipped 10 Ah pack ≈
## a minute of hover, about what an RTL from the fence radius costs.
const SOC_CRIT := 10.0

## Seconds the landed predicate must hold before auto-disarm. Shorter than ArduPilot's 10 s default
## because the landed predicate has already spent its own 0.5 s debounce in DroneSensors. This is a
## deliberate pause on top of a fact, not the detection.
const AUTO_DISARM_S := 3.0


## Everything arming logic reads, as one struct so fns take a state and the vehicle fills it once.
##
## `mode_want` is the pilot's request after the fence, before any failsafe forcing
## (DroneModes.wanted_mode) — reading the resolved mode would close a loop (a GPS_LOST-forced
## ALT_HOLD would clear itself and toggle).
## `pos_fix` is the debounced predicate, never raw `fix_type` — a failsafe is a decision.
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
## GPS_LOST (mode fallback). PA_BATTERY (too low to launch) and BATT_LOW (too low to stay up)
## are separate thresholds — not redundant, but complementary.
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


## The mode this failsafe demands, or -1 for none. Fed through DroneModes.resolve_mode so the
## one place a mode is decided knows the reason. GEOFENCE and GPS_LOST return -1 (their logic
## is already in resolve_mode). This only escalates: RTL for low pack, LAND for critical/dead motor.
static func failsafe_mode(fs: int) -> int:
	match fs:
		FS_MOTOR, FS_BATT_CRIT:
			return DroneModes.LAND
		FS_BATT_LOW:
			return DroneModes.RTL
	return -1


## Every pre-arm check, as a bitfield. Pure, exhaustive, the ONE place a refusal is decided —
## `arm_step` arms on `fails == 0` without re-testing anything.
##
## `s.failsafe` must already be filled (call failsafe_of first) — ordered rather than folded
## together because PA_FAILSAFE is a check about the failsafe.
##
## GPS check is gated on the mode (ArduPilot's rule, not a shortcut): STABILIZE/ALT_HOLD need no
## receiver. Calls DroneModes.needs_pos_fix rather than restating it.
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


## The published `prearm_fail`: live checks while gating, 0 once armed. A flying craft deflects its
## stick and leans past 10 deg constantly, so live bits in flight would light PA_STICK/PA_ATTITUDE
## through every manoeuvre. A real FC stops running pre-arm checks the moment it arms.
static func published_fail(armed: bool, fails: int) -> int:
	return 0 if armed else fails


## The arming state the bus sees. ARMED is a fact; the other two are the difference between nobody
## asking and the FC saying no.
##
## BLOCKED needs a powered aircraft and a raised switch: a refusal needs a request to refuse.
## A craft that auto-disarmed with the switch still up reads DISARMED, not BLOCKED: nothing is
## blocking it, it's waiting for the switch to be cycled (see arm_step).
static func state_of(armed: bool, arm_req: bool, power_ok: bool, fails: int) -> int:
	if armed:
		return ARMED
	if power_ok and arm_req and fails != 0:
		return BLOCKED
	return DISARMED


## One step of the state machine: last tick's armed, this tick's inputs, this tick's armed.
## Power_ok (key + pack charge) cuts unconditionally. Disarming is refused in flight (gated on
## landed predicate). Arming is a rising edge; every check must pass.
static func arm_step(armed: bool, arm_req: bool, arm_req_prev: bool, power_ok: bool,
		fails: int, landed: bool, auto_now: bool) -> bool:
	if not power_ok:
		return false
	if armed:
		if auto_now:
			return false
		return arm_req or not landed
	return arm_req and not arm_req_prev and fails == 0


## Post-landing timer: how long armed and landed continuously. Zeroed on takeoff or disarm.
## Shape matches DroneSensors.landed_hold and DroneModes.fix_hold_step.
static func disarm_hold_step(hold: float, armed: bool, landed: bool, delta: float) -> float:
	if not armed or not landed:
		return 0.0
	return hold + maxf(delta, 0.0)


## Has that timer run out? Split from the step so the threshold lives in one place.
static func auto_disarm_due(hold: float) -> bool:
	return hold >= AUTO_DISARM_S

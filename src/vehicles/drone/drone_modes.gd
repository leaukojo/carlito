class_name DroneModes
extends RefCounted
## The drone's flight modes — pure static logic, no node state. DroneVehicle keeps the per-tick
## state (altitude target, integrator, position anchor, two latches) and calls in here for every
## law. Tested in tests/test_drone_modes.gd.
##
## `flight_mode` is what was requested (bridge/Z key); `mode_actual` is what the FC is actually in
## after refusals and overrides. `resolve_mode` is the only place a mode is decided; nothing else
## may re-derive one. Published sensor values stay raw; only the mode reads a debounced predicate.

const SubsystemCounts := preload("res://src/input/subsystem_counts.gd")

## Ordinals are the contract's `flight_mode` / `mode_actual` enum verbatim — FROZEN, growing or
## reordering this silently desyncs the wire; test_drone_modes.gd pins both.
enum { STABILIZE = 0, ALT_HOLD = 1, LOITER = 2, RTL = 3, LAND = 4 }

## How many modes the Z key walks; read from the leaf-counts module so the router (which must not
## depend on a vehicle class) sees the same number.
const COUNT := SubsystemCounts.FLIGHT_MODES

## RTL's three legs. Internal only, not a contract enum: `mode_actual` reports RTL then LAND.
enum { RTL_CLIMB = 0, RTL_CRUISE = 1, RTL_LAND = 2 }

# --- altitude -------------------------------------------------------------------

## m/s climb stick commands at full deflection in ALT_HOLD. Bounded by what the integrator can
## hold: a steady climb needs `vertical_drag * v` of extra thrust (6.5*3 = 19.5 N = 0.13 of
## max_thrust) against RATE_I_MAX 0.15; ArduPilot's own PILOT_SPEED_UP default is 2.5 m/s.
const ALT_RATE_MAX := 3.0
## Desired climb rate per metre of altitude error (1/s). Outer half of the cascade.
const ALT_KP := 1.2
## Collective fraction per m/s of climb-rate error. 0.08*max_thrust = 12 N/(m/s) against
## `vertical_drag` 6.5, stiffer than the damping it works against.
const RATE_KP := 0.08
## Per m/s-second: the trim term that closes a commanded rate to zero — the only thing that learns
## a steady disturbance.
const RATE_KI := 0.05
## Anti-windup clamp on the integrator, in collective units: 0.15*max_thrust = 22.5 N ≈ 3.5 m/s of
## climb authority, just above the steady-state trim of 0.13.
const RATE_I_MAX := 0.15
## Stick deflection below which an axis counts as centred; above it hold targets follow the craft.
const STICK_DEADBAND := 0.05

# --- position -------------------------------------------------------------------

## rad of tilt per metre of position error. Saturates 32 deg tilt at ~9 m of error.
const POS_KP := 0.06
## rad of tilt per m/s of ground speed (damping). Loop balances at v = 0.24 * error.
const POS_KD := 0.25

# --- RTL and LAND ---------------------------------------------------------------

## m ABOVE HOME climbed before cruising home. Inside GEOFENCE_CEILING so a ceiling-breach RTL
## descends rather than climbing back through the fence.
const RTL_ALT := 40.0
## m of altitude slack before the climb leg counts as finished — tolerance, not a target.
const RTL_ALT_TOL := 2.0
## Horizontal m from home at which RTL hands over to LAND.
const RTL_ARRIVE_M := 3.0
## m/s descent in LAND — slow enough the 0.3 m/s landed-vertical gate is met on touchdown.
const LAND_RATE := 1.0

# --- the soft geofence ----------------------------------------------------------

## The fence is soft: breach latches a forced RTL, never brakes/blocks/teleports. `WorldBounds`
## is the hard last-resort wall, untouched.
##
## Horizontal radius (m) around home. ArduPilot's own default (150 m) is wrong for this 2000x2000 m
## map, which would make ordinary exploring a permanent RTL. 400 m is real line-of-sight range and
## is also the contract's `home_dist` range top (pinned by test) so the bar fills as it approaches.
const GEOFENCE_RADIUS := 400.0
## Ceiling (m) ABOVE HOME, not sea level, so a mountain home gets the same air. 120 m is the real
## EU/US recreational limit.
const GEOFENCE_CEILING := 120.0

# --- the fix the MODE decides on (see header) -----------------------------------

## s a fix change must stand before it moves the mode. Symmetric: a one-tick dropout must not drop
## a LOITER, a one-tick reacquisition must not re-enter one. 1.0 s ≈ ArduPilot's EKF-failsafe.
const FIX_DEBOUNCE := 1.0


## Does this fix support a position mode? The one place the threshold is applied.
static func has_pos_fix(fix_type: int) -> bool:
	return fix_type >= DroneSensors.FIX_3D


## Debounce accumulator: how long the raw fix has disagreed with the held one, continuously.
static func fix_hold_step(hold: float, raw_ok: bool, held_ok: bool, delta: float) -> float:
	if raw_ok == held_ok:
		return 0.0
	return hold + maxf(delta, 0.0)


## Held predicate `resolve_mode` reads: flips to the raw answer once disagreement stood for
## FIX_DEBOUNCE, else keeps last tick's answer.
static func held_fix_ok(raw_ok: bool, held_ok: bool, hold: float) -> bool:
	return raw_ok if hold >= FIX_DEBOUNCE else held_ok


# --- the two auto latches -------------------------------------------------------
#
# Both SET here, released by the pilot changing the requested mode (caller's job — a pilot action,
# not an aircraft rule). Both clear on disarm.

## Has the soft fence commanded a return? Latched so the override cannot chatter against the
## flight it causes (flying back inside the fence would otherwise release its own command).
static func fence_latch(latched: bool, armed: bool, pos: Vector3, home: Vector3,
		radius: float, ceiling: float) -> bool:
	if not armed:
		return false
	return latched or geofence_breach(pos, home, radius, ceiling)


## Is the craft in a breach the pilot already answered? Caller sets true when a mode change
## cancels a latched fence RTL; without this, `fence_latch` re-latches the same tick (craft still
## outside), so a fence RTL could only be cancelled from inside the fence. Holds while outside,
## clears on re-entry or disarm — ArduPilot's rule: cancel doesn't re-trigger until re-exit.
static func fence_answered(answered: bool, armed: bool, pos: Vector3, home: Vector3,
		radius: float, ceiling: float) -> bool:
	return answered and armed and geofence_breach(pos, home, radius, ceiling)


## Has an RTL reached its landing leg? Latches on `mode` (what the FC is actually doing), not the
## request — keyed off the request, a craft with RTL selected but refused (no fix) would latch
## early; restoring the fix later would then land wherever it stands instead of flying home.
## Latched (not per-tick) for the same reason as the fence: drifting outside arrival radius during
## descent must not climb away and repeat forever.
static func rtl_landing_latch(latched: bool, armed: bool, mode: int, rtl_phase: int) -> bool:
	if not armed:
		return false
	return latched or (mode == RTL and rtl_phase == RTL_LAND)


## Does this mode run the altitude cascade? Everything but STABILIZE (climb axis is a thrust trim
## there, loop not running). Decides whether a mode change may carry the climb-rate trim between
## cascade modes.
static func uses_cascade(mode: int) -> bool:
	return is_valid(mode) and mode != STABILIZE


# --- which mode the flight controller is actually in ----------------------------

## Is `mode` one this airframe has? An out-of-range byte is a peer describing a different
## aircraft, not an error — it lands on the safe pose.
static func is_valid(mode: int) -> bool:
	return mode >= 0 and mode < COUNT


## Modes the FC refuses without a position fix (LOITER, RTL). Factored out because DroneArming's
## pre-arm GPS check must gate on the exact same set.
static func needs_pos_fix(mode: int) -> bool:
	return mode == LOITER or mode == RTL


## Modes degraded (not refused) without a fix: the two above plus LAND, which still has to come
## down but loses its hold and drifts. Used by `failsafe` (GPS_LOST) to report that degradation.
static func uses_pos_fix(mode: int) -> bool:
	return needs_pos_fix(mode) or mode == LAND


## How far up the automatic-action ladder a mode sits: LAND above RTL above anything a pilot flies.
## The one statement of which override is more urgent. A fence breach cannot interrupt a landing,
## a failsafe can only ever make things more urgent.
static func auto_rank(mode: int) -> int:
	if mode == LAND:
		return 2
	if mode == RTL:
		return 1
	return 0


## What the pilot (plus fence) wants, before any failsafe forcing. Reads the request, not the
## resolved mode — reading the resolved mode would let a failsafe close a loop on itself (a
## GPS_LOST-forced ALT_HOLD would clear itself and toggle at the tick rate).
static func wanted_mode(requested: int, fence_rtl: bool) -> int:
	var want := requested if is_valid(requested) else STABILIZE
	if fence_rtl and auto_rank(RTL) > auto_rank(want):
		want = RTL
	return want


## The one place a mode is decided. Order: disarmed/unknown→STABILIZE; fence latch→RTL;
## failsafe forced mode (escalates only); LOITER/RTL without fix→ALT_HOLD; landing leg→LAND.
## LAND never refused for want of fix (drifts; failsafe reports GPS_LOST).
static func resolve_mode(requested: int, pos_fix: bool, fence_rtl: bool, armed: bool,
		rtl_landing: bool, forced := -1) -> int:
	if not armed:
		return STABILIZE
	var want := wanted_mode(requested, fence_rtl)
	if is_valid(forced) and auto_rank(forced) > auto_rank(want):
		want = forced
	if needs_pos_fix(want) and not pos_fix:
		return ALT_HOLD
	if want == RTL and rtl_landing:
		return LAND
	return want


## Z-key walk: STABILIZE -> ALT_HOLD -> LOITER -> RTL -> LAND -> STABILIZE. `posmod` so a mode that
## arrived negative still lands inside the ladder.
##
## Named fn (not inlined) so InputRouter.cycle_flight_mode mirrors this rule and
## tests/test_drone_modes.gd pins the two equal by calling both.
static func cycle(mode: int) -> int:
	return posmod(mode + 1, COUNT)


# --- the altitude cascade ------------------------------------------------------

## Desired climb rate (m/s): stick feedforward plus P on altitude error, clamped to the stick's own
## range. While deflected the target follows the craft (error zero, pure feedforward); centred, the
## target holds and P does the work.
static func alt_rate_target(alt_err: float, stick_rate: float) -> float:
	return clampf(stick_rate + ALT_KP * alt_err, -ALT_RATE_MAX, ALT_RATE_MAX)


## One integrator step, clamped both ways to RATE_I_MAX — the whole anti-windup scheme: a bound on
## the integrator makes recovery from collective saturation a known number of seconds.
static func alt_integ_step(integ: float, rate_err: float, delta: float) -> float:
	return clampf(integ + RATE_KI * rate_err * maxf(delta, 0.0), -RATE_I_MAX, RATE_I_MAX)


## Collective (thrust fraction) the altitude loop asks for: hover feedforward + P on rate error +
## trim. Clamped [0, ceiling] — ceiling is the human's full-climb collective, floor is 0 not the
## human's (see header).
static func alt_hold_collective(hover: float, rate_err: float, integ: float,
		ceiling: float) -> float:
	return clampf(hover + RATE_KP * rate_err + integ, 0.0, maxf(ceiling, 0.0))


# --- the position controller ---------------------------------------------------

## Tilt that flies the craft toward a point. PD, no integrator (see header).
##
## `err`/`vel` are in the craft's heading frame as (forward, right) m and m/s. The return is in
## `DroneVehicle.level_target_up`'s own tilt convention (x about right axis, y about forward axis),
## so a target ahead comes back as negative x — same sign as the manual `-input.throttle` path.
## Geometry, not a mistake: a positive rotation about the right axis leans the up-vector backward.
##
## Magnitude limited as a vector so total lean never exceeds `max_tilt_rad` however split.
static func position_tilt_demand(err: Vector2, vel: Vector2, max_tilt_rad: float) -> Vector2:
	var demand := Vector2(
			-(POS_KP * err.x - POS_KD * vel.x),
			POS_KP * err.y - POS_KD * vel.y)
	return demand.limit_length(maxf(max_tilt_rad, 0.0))


# --- home, RTL and the fence ---------------------------------------------------

## Horizontal distance (m) from `pos` to `home` — altitude is its own readout, folding it in would
## make a craft directly overhead read as far away.
static func home_distance(pos: Vector3, home: Vector3) -> float:
	return Vector2(pos.x - home.x, pos.z - home.z).length()


## Which leg of the return. Arrival tested first: a craft already over home has nothing to climb
## for, whatever its altitude.
static func rtl_phase_of(pos: Vector3, home: Vector3, rtl_alt: float, arrive_m: float) -> int:
	if home_distance(pos, home) <= maxf(arrive_m, 0.0):
		return RTL_LAND
	if pos.y < home.y + rtl_alt - RTL_ALT_TOL:
		return RTL_CLIMB
	return RTL_CRUISE


## The point the altitude/position controllers chase per leg: CLIMB straight up from where the
## craft is (clears terrain/buildings a diagonal would fly through); CRUISE home at RTL altitude
## (a target, not a floor — a higher craft descends to it); LAND home itself (station over the
## takeoff point), reached once `rtl_landing_latch` has fired and `resolve_mode` reports LAND.
static func rtl_target(home: Vector3, pos: Vector3, phase: int, rtl_alt: float) -> Vector3:
	var alt := home.y + rtl_alt
	if phase == RTL_CLIMB:
		return Vector3(pos.x, alt, pos.z)
	if phase == RTL_CRUISE:
		return Vector3(home.x, alt, home.z)
	return home


## Is the craft outside the soft fence? Radius and ceiling both measured from home, independently.
static func geofence_breach(pos: Vector3, home: Vector3, radius: float, ceiling: float) -> bool:
	if home_distance(pos, home) > maxf(radius, 0.0):
		return true
	return pos.y - home.y > ceiling

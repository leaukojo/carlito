extends Node
## InputRouter autoload — merges input sources into one normalized VehicleInput. All
## arbitration lives here: brake > accel > handbrake; bridge-active, gear-owns-direction.
## Sources pass Dictionary[StringName, Variant]; arbitrate_* are pure/static. Toggle owners
## (_lights, _pto, _armed, etc.) live here so keyboard and touch share state. Vehicles never
## know which source is active.

const KEY_LOCK := 1
const KEY_ON := 2
const KEY_IGNITION := 3

const GEAR_N := 0x00
const GEAR_D1 := 0x01
const GEAR_R := 0xFF

## m/s below which S (held with no accel) swaps D->R and W swaps R->D.
const REVERSE_ENGAGE_SPEED := 0.5

## Cycle lengths, declared once in a leaf module (router must not depend on a vehicle
## class, so these can't be read off RefuseBody.Cmd / DroneBus.NODES / DroneModes directly).
const Counts := preload("res://src/input/subsystem_counts.gd")
const BODY_CMD_COUNT := Counts.BODY_CMD
const NODE_FAIL_COUNT := Counts.DRONE_NODES
const FLIGHT_MODE_COUNT := Counts.FLIGHT_MODES
const NAV_MODE_COUNT := Counts.NAV_MODES
const SHEET_DETENT_COUNT := Counts.SHEET_DETENTS

const LocalSource := preload("res://src/input/sources/local_source.gd")
const BridgeSource := preload("res://src/input/sources/bridge_source.gd")


var _local_source := LocalSource.new()
var _bridge_source := BridgeSource.new()
var _touch_source: Object = null  ## optional on-screen source (touch_controls.gd), if present
var _vehicle: Node3D = null
var _current := VehicleInput.new()
var _lights := 1  ## headlight level owned here so keyboard + touch share one state
# Local tractor implement state, owned here so keyboard + touch share it; bridge path ignores these.
var _hitch_up := true  ## true = raised (transport), toggled by the local hitch key
var _pto := false      ## local PTO engage, toggled by the local PTO key
var _pto_mode := 0     ## local PTO speed (contract 'pto_mode': 0 = 540, 1 = 1000), cycled by its key
## Local hydraulic-remote spool, toggled by the local SCV key; shut is the default resting state.
## Has a key because the SCV is the drawbar tipping trailer's only control (no key = no way to tip
## it locally). Not proportional: 0 or 1, and the far end slews (GATE_TRAVEL_TIME / TIP_TRAVEL_S)
## to match the bridge's percentage ramp without a keyboard axis.
var _scv := false      ## local SCV spool open, toggled by the local SCV key
var _diff_lock := false   ## local rear diff lock, toggled by the local diff-lock key
var _fwd_drive := false   ## local MFWD engage, toggled by the local MFWD key
var _armed := false    ## local drone motor arm, toggled by the local arm key (like _pto)
var _flaps_down := false  ## local plane flaps extended, toggled by the local flaps key
## Drone cargo hook, owned here like _pto so key and touch share one switch. Released is the
## default: spawning with HOLD commanded would grab the first crate hovered over.
var _hardpoint := false   ## local hook HOLD command, toggled by the local hardpoint key
## Local DroneCAN failure injection, cycled (more than two states). Contract 'node_fail'; 0 = every
## node online. Bridge path ignores it — sloppyCAN is authoritative there.
var _node_fail := 0       ## bit i = DroneBus roster index i is off the bus
## Local flight-mode request, cycled (five positions). Contract 'flight_mode'; 0 = STABILIZE, the
## hand-flown default. Bridge path ignores it.
var _flight_mode := 0     ## DroneModes ladder position, cycled by the local flight-mode key (Z)
## Local autopilot request, cycled (two positions). Contract 'nav_mode'; 0 = STANDBY, the
## hand-steered default. Bridge path ignores it. There is no local `heading_cmd` beside it — no
## keyboard types a bearing, so a locally-engaged pilot holds the heading it captured on engage.
var _nav_mode := 0        ## BoatAutopilot ladder position, cycled by the local autopilot key (2)
## Local sheet request, cycled (SHEET_DETENT_COUNT detents). Contract 'sheet'; 0 = hauled in hard.
## Owned here like _lights and _pto so keyboard and touch share one switch. Bridge path ignores it
## and may send any value in the range — the detents exist only because a keyboard has no axis.
var _sheet := 0           ## detent index, walked by the local sheet key (3)
## Raised by default so a locally-driven train spawns able to move; lowering it cuts traction.
var _pantograph := true   ## local train pantograph raised, toggled by the local pantograph key
var _doors := false       ## local train door open request, toggled by the local doors key
## Local refuse body command, cycled (Idle -> Lift -> Dump -> Lower -> Idle). Owned here like
## _pto; bridge path ignores it. Position count is BODY_CMD_COUNT.
var _body_cmd := 0        ## RefuseBody.Cmd, contract 'body_cmd'
## Seconds the "ignition off" notice stays up — long, since the driver must go move the key.
const IGNITION_NOTICE_DWELL_S := 20.0
## Const because it is raised and cleared by text match — see GameState.notice_cleared.
const IGNITION_NOTICE_TEXT := "IGNITION OFF - MOVE THE ENGINE KEY"

## Edge latch for the "ignition off" notice — see _warn_if_ignition_off.
var _ignition_warned := false

## Set by the shell for a challenge attempt: local and touch are never merged, and with no live
## bridge the vehicle gets `locked_idle()`. A live bridge drives exactly as it does in free play.
var _bridge_only := false
## Debug-build override that lets the keyboard drive a challenge anyway (BootParams.challenge_keys),
## so a course can be authored and checked without sloppyCAN. Never true in a release export.
var _dev_keys := false
const DEV_KEYS_NOTICE_TEXT := "DEV: KEYBOARD DRIVES THIS CHALLENGE"


func _ready() -> void:
	_dev_keys = BootParams.challenge_keys()


func set_bridge_only(on: bool) -> void:
	_bridge_only = on
	if on and _dev_keys:
		GameState.notice.emit(DEV_KEYS_NOTICE_TEXT, 0.0)


## Vehicles register on _ready to read speed/gear. A new body clears _node_fail/_flight_mode/
## _nav_mode (avoiding inherited drone and boat settings) but keeps other toggles (_lights, _pto,
## _armed) as driver state. Respawn doesn't re-register, so node_fail stays a bench switch.
func register_vehicle(vehicle: Node3D) -> void:
	_vehicle = vehicle
	_node_fail = 0
	_flight_mode = 0
	# A new hull must not spawn with an engaged autopilot steering to the last boat's course.
	_nav_mode = 0
	# Nor with the last boat's trim: on a hull with no rig the sheet is inert but still latched.
	_sheet = 0
	# Cargo hook clears for the same reason: global key, no local indication.
	_hardpoint = false


## The touch UI registers itself as a second local source. It is
## polled and merged with the keyboard whenever the bridge is not driving.
func set_touch_source(source: Object) -> void:
	_touch_source = source


func clear_touch_source(source: Object) -> void:
	if _touch_source == source:
		_touch_source = null


func unregister_vehicle(vehicle: Node3D) -> void:
	if _vehicle == vehicle:
		_vehicle = null


func _physics_process(delta: float) -> void:
	# Autoloads tick before scene nodes, ahead of every vehicle's frame.
	# Bridge wins while it has fresh data; otherwise local input works untouched.
	var bridge_raw := _bridge_source.poll()
	if bridge_raw.get(&"active", false):
		_current = arbitrate_bridge(bridge_raw)
		_warn_if_ignition_off(bridge_raw)
		return
	_clear_ignition_notice()
	if _bridge_only and not _dev_keys:
		# Neither local source is polled, so no router toggle advances under the lock either.
		_current = locked_idle()
		return
	var raw := _local_source.poll(delta)
	if _touch_source != null:
		raw = merge_local(raw, _touch_source.poll())
	# Single headlight owner: either source's cycle edge advances the shared level.
	if bool(raw.get(&"lights_cycle", false)):
		_lights = _lights % 4 + 1
	raw[&"lights"] = _lights
	# Local implement toggles owned here too (same pattern as the headlight level).
	if bool(raw.get(&"hitch_toggle", false)):
		_hitch_up = not _hitch_up
	if bool(raw.get(&"pto_toggle", false)):
		_pto = not _pto
	if bool(raw.get(&"pto_mode_toggle", false)):
		_pto_mode = 1 - _pto_mode  # two modes, so the cycle is a flip
	if bool(raw.get(&"scv_toggle", false)):
		_scv = not _scv
	if bool(raw.get(&"diff_lock_toggle", false)):
		_diff_lock = not _diff_lock
	if bool(raw.get(&"fwd_drive_toggle", false)):
		_fwd_drive = not _fwd_drive
	if bool(raw.get(&"arm_toggle", false)):
		_armed = not _armed
	if bool(raw.get(&"flaps_toggle", false)):
		_flaps_down = not _flaps_down
	if bool(raw.get(&"hardpoint_toggle", false)):
		_hardpoint = not _hardpoint
	if bool(raw.get(&"node_fail_cycle", false)):
		_node_fail = cycle_node_fail(_node_fail)
	if bool(raw.get(&"flight_mode_cycle", false)):
		_flight_mode = cycle_flight_mode(_flight_mode)
	if bool(raw.get(&"nav_mode_cycle", false)):
		_nav_mode = cycle_nav_mode(_nav_mode)
	if bool(raw.get(&"sheet_cycle", false)):
		_sheet = cycle_sheet(_sheet)
	if bool(raw.get(&"pantograph_toggle", false)):
		_pantograph = not _pantograph
	if bool(raw.get(&"doors_toggle", false)):
		_doors = not _doors
	if bool(raw.get(&"body_cmd_toggle", false)):
		# Four commands, so the stalk cycles rather than flips.
		_body_cmd = (_body_cmd + 1) % BODY_CMD_COUNT
	raw[&"hitch_request"] = 1.0 if _hitch_up else 0.0
	raw[&"pto"] = _pto
	raw[&"pto_mode"] = _pto_mode
	raw[&"scv_flow"] = 1.0 if _scv else 0.0
	raw[&"diff_lock"] = _diff_lock
	raw[&"fwd_drive"] = _fwd_drive
	raw[&"arm"] = _armed
	raw[&"flaps"] = 1.0 if _flaps_down else 0.0
	raw[&"hardpoint_cmd"] = _hardpoint
	raw[&"node_fail"] = _node_fail
	raw[&"flight_mode"] = _flight_mode
	raw[&"nav_mode"] = _nav_mode
	raw[&"sheet"] = sheet_fraction(_sheet)
	raw[&"pantograph"] = _pantograph
	raw[&"doors"] = _doors
	raw[&"body_cmd"] = _body_cmd
	var speed := 0.0
	var gear := GEAR_N
	if _vehicle != null:
		speed = _vehicle.get_speed()
		gear = _vehicle.get_gear_byte()
	_current = arbitrate_local(raw, speed, gear)


## Tell the driver why throttle does nothing: `arbitrate_bridge` zeroes it silently whenever
## the key is off Ignition. Bridge-only (local input is always Ignition); fires on the edge,
## since emitting per tick would pin the message up for as long as the pedal is down.
func _warn_if_ignition_off(bridge_raw: Dictionary[StringName, Variant]) -> void:
	var wants_throttle := float(bridge_raw.get(&"accel", 0.0)) > 0.0
	if _current.key != KEY_IGNITION and wants_throttle:
		if not _ignition_warned:
			_ignition_warned = true
			GameState.notice.emit(IGNITION_NOTICE_TEXT, IGNITION_NOTICE_DWELL_S)
	elif _current.key == KEY_IGNITION:
		_clear_ignition_notice()


## Drop the notice the moment the key reaches Ignition rather than let the dwell run out.
## Also called when the bridge goes away, since local input is always at Ignition.
func _clear_ignition_notice() -> void:
	if _ignition_warned:
		_ignition_warned = false
		GameState.notice_cleared.emit(IGNITION_NOTICE_TEXT)


## The merged input for this tick. Returns the router's own struct, read-only by convention —
## no defensive copy, since a hand-written field mirror is a field that silently goes missing.
## `arbitrate_local` / `arbitrate_bridge` build a fresh struct every tick, so a held reference
## reads stale, never live. A caller that needs to keep or change one copies it itself.
func get_vehicle_input() -> VehicleInput:
	return _current


## Local node-failure walk behind the Y key: none -> node 0 -> node 1 -> ... -> last -> none.
## Shifts the mask one bit left, wrapping past the last back to none; handles any starting
## int (not just the normal NODE_FAIL_COUNT states) so a multi-bit bus-commanded mask still
## terminates instead of sticking or shifting silently off the end.
##
## Named static fn (not inlined) because DroneBus.cycle_fail mirrors this exact copy and
## tests/test_drone_bus.gd pins the two equal by calling both.
static func cycle_node_fail(bits: int) -> int:
	var next_fail := maxi(bits << 1, 1)
	return 0 if next_fail > (1 << (NODE_FAIL_COUNT - 1)) else next_fail


## Local flight-mode walk behind the Z key: STABILIZE -> ALT_HOLD -> LOITER -> RTL -> LAND ->
## STABILIZE. `posmod` (not `%`) so a negative starting mode still lands inside the ladder.
## Named static fn for the same reason as cycle_node_fail: DroneModes.cycle mirrors this, and
## tests/test_drone_modes.gd pins the two equal by calling both.
static func cycle_flight_mode(mode: int) -> int:
	return posmod(mode + 1, FLIGHT_MODE_COUNT)


## Local autopilot walk behind the 2 key: STANDBY -> HEADING HOLD -> STANDBY. Named static fn for
## the same reason as cycle_flight_mode: BoatAutopilot.cycle mirrors this, and
## tests/test_boat_autopilot.gd pins the two equal by calling both.
static func cycle_nav_mode(mode: int) -> int:
	return posmod(mode + 1, NAV_MODE_COUNT)


## Local sheet walk behind the 3 key: hauled in -> ... -> fully eased -> hauled in.
static func cycle_sheet(detent: int) -> int:
	return posmod(detent + 1, SHEET_DETENT_COUNT)


## The detent as the 0..1 the wire and VehicleInput carry. Spread across the whole range so the
## ends are reachable, which is why the divisor is COUNT - 1 and not COUNT.
static func sheet_fraction(detent: int) -> float:
	return float(posmod(detent, SHEET_DETENT_COUNT)) / float(maxi(1, SHEET_DETENT_COUNT - 1))


## Merge the keyboard and touch raw intents into one before arbitration:
## analog axes take the stronger request, steer sums (clamped), momentary bits OR
## together. Pure/static so it is unit-tested without the autoload. `lights` is not
## merged here — InputRouter owns the level and reads the merged `lights_cycle` edge.
static func merge_local(a: Dictionary[StringName, Variant],
		b: Dictionary[StringName, Variant]) -> Dictionary[StringName, Variant]:
	var out: Dictionary[StringName, Variant] = {
		&"accel": maxf(float(a.get(&"accel", 0.0)), float(b.get(&"accel", 0.0))),
		&"brake_reverse": maxf(float(a.get(&"brake_reverse", 0.0)), float(b.get(&"brake_reverse", 0.0))),
		&"steer": clampf(float(a.get(&"steer", 0.0)) + float(b.get(&"steer", 0.0)), -1.0, 1.0),
		&"handbrake": maxf(float(a.get(&"handbrake", 0.0)), float(b.get(&"handbrake", 0.0))),
		&"horn": bool(a.get(&"horn", false)) or bool(b.get(&"horn", false)),
		&"lights_cycle": bool(a.get(&"lights_cycle", false)) or bool(b.get(&"lights_cycle", false)),
		&"hitch_toggle": bool(a.get(&"hitch_toggle", false)) or bool(b.get(&"hitch_toggle", false)),
		&"pto_toggle": bool(a.get(&"pto_toggle", false)) or bool(b.get(&"pto_toggle", false)),
		&"pto_mode_toggle": bool(a.get(&"pto_mode_toggle", false)) or bool(b.get(&"pto_mode_toggle", false)),
		&"scv_toggle": bool(a.get(&"scv_toggle", false)) or bool(b.get(&"scv_toggle", false)),
		&"diff_lock_toggle": bool(a.get(&"diff_lock_toggle", false)) or bool(b.get(&"diff_lock_toggle", false)),
		&"fwd_drive_toggle": bool(a.get(&"fwd_drive_toggle", false)) or bool(b.get(&"fwd_drive_toggle", false)),
		# Flight axes (-1..1) sum-clamp like steer; toggles below edge OR like the others.
		&"elevator": clampf(float(a.get(&"elevator", 0.0)) + float(b.get(&"elevator", 0.0)), -1.0, 1.0),
		&"climb": clampf(float(a.get(&"climb", 0.0)) + float(b.get(&"climb", 0.0)), -1.0, 1.0),
		&"arm_toggle": bool(a.get(&"arm_toggle", false)) or bool(b.get(&"arm_toggle", false)),
		&"node_fail_cycle": bool(a.get(&"node_fail_cycle", false)) or bool(b.get(&"node_fail_cycle", false)),
		&"flight_mode_cycle": bool(a.get(&"flight_mode_cycle", false)) or bool(b.get(&"flight_mode_cycle", false)),
		&"nav_mode_cycle": bool(a.get(&"nav_mode_cycle", false)) or bool(b.get(&"nav_mode_cycle", false)),
		&"sheet_cycle": bool(a.get(&"sheet_cycle", false)) or bool(b.get(&"sheet_cycle", false)),
		&"flaps_toggle": bool(a.get(&"flaps_toggle", false)) or bool(b.get(&"flaps_toggle", false)),
		&"hardpoint_toggle": bool(a.get(&"hardpoint_toggle", false)) or bool(b.get(&"hardpoint_toggle", false)),
		# Train toggles edge the same way; InputRouter owns the latched state.
		&"pantograph_toggle": bool(a.get(&"pantograph_toggle", false)) or bool(b.get(&"pantograph_toggle", false)),
		&"doors_toggle": bool(a.get(&"doors_toggle", false)) or bool(b.get(&"doors_toggle", false)),
		# Every key here is required, not belt-and-braces: this dict is built explicitly, so a
		# missing key silently drops the keyboard's edge whenever a touch source is registered.
		&"body_cmd_toggle": bool(a.get(&"body_cmd_toggle", false)) or bool(b.get(&"body_cmd_toggle", false)),
	}
	return out


## What a bridge-only vehicle gets with no live bridge: key at Lock, handbrake on, every other
## field at its struct default. Also what the rig falls back to when the bridge goes stale
## mid-attempt, so a lost connection parks it rather than coasting.
static func locked_idle() -> VehicleInput:
	var out := VehicleInput.new()
	out.key = KEY_LOCK
	out.handbrake = 1.0
	return out


## Local (keyboard/gamepad) arbitration, pure for tests. Throttle only from accel; brake
## never throttle; full accel + full brake both pass through (stopping is brake > accel's
## job); key gates throttle. Reverse UX: S brakes while moving, engages R near standstill;
## W in R brakes, then re-engages D1 near standstill.
static func arbitrate_local(raw: Dictionary, speed: float, gear_byte: int,
		key: int = KEY_IGNITION) -> VehicleInput:
	var out := VehicleInput.new()
	out.steer = clampf(float(raw.get(&"steer", 0.0)), -1.0, 1.0)
	out.handbrake = clampf(float(raw.get(&"handbrake", 0.0)), 0.0, 1.0)
	out.key = key  # local key is always Ignition until the bridge owns it
	out.gear_auto = true
	out.horn = bool(raw.get(&"horn", false))
	out.lights = int(raw.get(&"lights", 1))  # local headlight cycle (turn/warning bits stay off)
	# Implement request from the InputRouter-owned local toggles (tractor only; ignored elsewhere).
	out.hitch_request = clampf(float(raw.get(&"hitch_request", 1.0)), 0.0, 1.0)
	out.pto = bool(raw.get(&"pto", false))
	out.pto_mode = int(raw.get(&"pto_mode", 0))
	out.diff_lock = bool(raw.get(&"diff_lock", false))
	out.fwd_drive = bool(raw.get(&"fwd_drive", false))
	# Refuse body command (garbage truck only). Has a key: a real stalk with four positions.
	out.body_cmd = int(raw.get(&"body_cmd", 0))
	# Hydraulic remote spool (tractor only). See _scv declaration for why it earns a key.
	out.scv_flow = clampf(float(raw.get(&"scv_flow", 0.0)), 0.0, 1.0)
	# The truck's `retarder` stays 0: no keyboard analogue worth inventing. The three DM1 lamp
	# bits stay false too, like turnL/turnR — no local source, off is correct.
	# Flight controls pass through (plane/drone only; ground vehicles ignore them).
	out.elevator = clampf(float(raw.get(&"elevator", 0.0)), -1.0, 1.0)
	out.climb = clampf(float(raw.get(&"climb", 0.0)), -1.0, 1.0)
	out.arm = bool(raw.get(&"arm", false))
	out.node_fail = int(raw.get(&"node_fail", 0))
	out.flight_mode = int(raw.get(&"flight_mode", 0))
	# Boat autopilot request (boat only; ignored elsewhere). `heading_cmd` stays at
	# HEADING_CMD_NONE: no keyboard types a bearing, and holding the heading captured on engage is
	# what the local path is FOR — see BoatVehicle.
	out.nav_mode = int(raw.get(&"nav_mode", 0))
	# The sheet, from the InputRouter-owned detent (sailboat only; inert on a hull with no rig).
	out.sheet = clampf(float(raw.get(&"sheet", 0.0)), 0.0, 1.0)
	# `led`/`beep` are indication, not control: no local source, stay at 0/false (arm tips dark).
	out.flaps = clampf(float(raw.get(&"flaps", 0.0)), 0.0, 1.0)
	# Cargo hook, from the InputRouter-owned local toggle (drone only; ignored elsewhere).
	out.hardpoint_cmd = bool(raw.get(&"hardpoint_cmd", false))
	# `gimbal_pitch`/`gimbal_yaw` stay at rest pose (bridge-only, camera looks straight ahead).
	# `beacon`/`strobe` stay false — no local source, bus is their only authority.
	# Train controls from the InputRouter-owned local toggles (train only; ignored elsewhere).
	out.pantograph = bool(raw.get(&"pantograph", false))
	out.doors = bool(raw.get(&"doors", false))

	var accel := clampf(float(raw.get(&"accel", 0.0)), 0.0, 1.0)
	var brake_rev := clampf(float(raw.get(&"brake_reverse", 0.0)), 0.0, 1.0)
	var near_standstill := absf(speed) <= REVERSE_ENGAGE_SPEED

	if gear_byte == GEAR_R:
		if accel > 0.0 and near_standstill and brake_rev <= 0.0:
			out.gear_request = GEAR_D1
			out.throttle = accel
		else:
			out.gear_request = GEAR_R
			out.throttle = -brake_rev
			out.brake = accel
	else:
		if brake_rev > 0.0 and near_standstill and accel <= 0.0:
			out.gear_request = GEAR_R
			out.throttle = -brake_rev
		else:
			if gear_byte >= 1 and gear_byte <= 6:
				out.gear_request = gear_byte
			else:
				out.gear_request = GEAR_D1 if accel > 0.0 else GEAR_N
			out.throttle = accel
			out.brake = brake_rev

	if out.key != KEY_IGNITION:
		out.throttle = 0.0
	# Local rear STOP follows the foot brake; sloppyCAN owns it once the bridge is live.
	out.lamps.brake_lamp = out.brake > 0.0
	return out


## Bridge (sloppyCAN) arbitration, pure for tests. While the bridge is active and sending a
## real gear byte, the byte owns direction — throttle is `accel` signed by it (+D1-D6, -R),
## local reverse UX ignored (gear_auto = false). Byte 0 means "no gear opinion", handing the
## gearbox back to auto. Brake is never throttle; key gates throttle; steer/handbrake/lights/
## horn pass through. Values arrive pre-normalized to VehicleInput ranges from bridge_source.
static func arbitrate_bridge(vals: Dictionary) -> VehicleInput:
	var out := VehicleInput.new()
	# Steer overrides, both pre-normalized to -1..1 from bridge_source: 'guidance' (tractor
	# auto-steer) wins as an external computer holding the wheel; 'rudder' (boat) IS steer.
	# Neither vehicle sends the other's key, so their order is arbitrary; absent both,
	# cars/trucks are untouched.
	out.steer = clampf(float(vals.get("guidance", vals.get("rudder", vals.get("steer", 0.0)))),
			-1.0, 1.0)
	out.handbrake = clampf(float(vals.get("handbrake", 0.0)), 0.0, 1.0)
	out.brake = clampf(float(vals.get("brake", 0.0)), 0.0, 1.0)
	out.key = int(vals.get("key", KEY_IGNITION))
	out.lights = int(vals.get("lights", 1))
	out.horn = bool(vals.get("horn", false))
	# Lamp/warning bits mirrored verbatim; absent bit defaults off.
	out.lamps.turn_left = bool(vals.get("turnL", false))
	out.lamps.turn_right = bool(vals.get("turnR", false))
	out.lamps.brake_lamp = bool(vals.get("brakeLamp", false))
	out.lamps.check_engine = bool(vals.get("checkEngine", false))
	out.lamps.battery_warn = bool(vals.get("battery", false))
	# ISOBUS implement request; absent → raised/off. bridge_source clamps hitch_pos to 0..100.
	out.hitch_request = clampf(float(vals.get("hitch_pos", 100.0)) / 100.0, 0.0, 1.0)
	out.pto = bool(vals.get("pto", false))
	# Driveline requests; absent → open diff, 2WD, 540 PTO (a real tractor's rest state).
	out.pto_mode = int(vals.get("pto_mode", 0))
	out.diff_lock = bool(vals.get("diff_lock", false))
	out.fwd_drive = bool(vals.get("fwd_drive", false))
	# Hydraulic remote: bridge-only, absent → valve closed.
	out.scv_flow = clampf(float(vals.get("scv_flow", 0.0)), 0.0, 1.0)
	# Flight controls, already %→unit normalized in bridge_source; absent → neutral/disarmed/
	# retracted. arm/flaps authoritative here, no local toggles.
	out.elevator = clampf(float(vals.get("elevator", 0.0)), -1.0, 1.0)
	out.climb = clampf(float(vals.get("climb", 0.0)), -1.0, 1.0)
	out.arm = bool(vals.get("arm", false))
	# Mirrored verbatim; local _node_fail latch not read, so a keyboard-injected failure
	# cannot survive sloppyCAN taking the bus.
	out.node_fail = int(vals.get("node_fail", 0))
	# Mirrored verbatim; local Z latch not read for the same reason as node_fail.
	out.flight_mode = int(vals.get("flight_mode", 0))
	# Boat autopilot, mirrored verbatim; local 2 latch not read for the same reason. `heading_cmd`
	# follows the `rudder` PRESENCE rule instead of a default: bridge_source writes the key only
	# when sloppyCAN sends it, and absent means "no course commanded", not a bearing of 0.
	out.nav_mode = int(vals.get("nav_mode", 0))
	out.heading_cmd = float(vals.get("heading_cmd", VehicleInput.HEADING_CMD_NONE))
	# The sheet, already %→fraction normalized in bridge_source; local 3 detent not read, for the
	# same reason as nav_mode. Absent → 0 → hauled in hard, which is a real trim, not a sentinel.
	out.sheet = clampf(float(vals.get("sheet", 0.0)), 0.0, 1.0)
	# DroneCAN indication, mirrored verbatim, no local timer — LEDs pulse only if sloppyCAN
	# toggles the colour.
	out.lamps.led = int(vals.get("led", 0))
	out.lamps.beep = bool(vals.get("beep", false))
	out.flaps = clampf(float(vals.get("flaps", 0.0)), 0.0, 1.0)
	# Flashing lamps, mirrored verbatim, no local timer.
	out.lamps.beacon = bool(vals.get("beacon", false))
	out.lamps.strobe = bool(vals.get("strobe", false))
	# Cargo hook, mirrored verbatim; local latch not read (same rule as arm/node_fail).
	out.hardpoint_cmd = bool(vals.get("hardpoint_cmd", false))
	# Gimbal command in contract degrees, bridge-only; absent → rest pose (camera forward).
	out.gimbal_pitch = float(vals.get("gimbal_pitch", 0.0))
	out.gimbal_yaw = float(vals.get("gimbal_yaw", 0.0))
	# Train controls mirrored from sloppyCAN; absent → lowered/shut.
	out.pantograph = bool(vals.get("pantograph", false))
	out.doors = bool(vals.get("doors", false))
	# J1939 chassis (truck). Retarder bridge-only, absent → released; DM1 lamps mirrored
	# verbatim, no blink timer.
	out.retarder = clampf(float(vals.get("retarder", 0.0)), 0.0, 1.0)
	out.lamps.red_stop = bool(vals.get("red_stop", false))
	out.lamps.amber_warn = bool(vals.get("amber_warn", false))
	out.lamps.protect_lamp = bool(vals.get("protect_lamp", false))
	# ISO 11992 trailer fault lamp, mirrored the same way — absent → off, no local timer.
	out.lamps.trailer_ebs_fault = bool(vals.get("trailer_ebs_fault", false))
	# SAE J2497 trailer bit (power-line only), same rule — absent → off, no local timer.
	out.lamps.trailer_abs_lamp = bool(vals.get("trailer_abs_lamp", false))
	# CiA 422 body command, mirrored while the bridge is live; absent → 0 Idle (stows the
	# body — an unpowered body network cannot be holding an arm up).
	out.body_cmd = int(vals.get("body_cmd", 0))
	var gear := int(vals.get("gear", GEAR_N))
	var accel := clampf(float(vals.get("accel", 0.0)), 0.0, 1.0)
	if gear == GEAR_R:
		out.gear_auto = false  # bridge byte is exact and owns direction
		out.gear_request = gear
		out.throttle = -accel
	elif gear >= GEAR_D1 and gear <= 6:
		out.gear_auto = false
		out.gear_request = gear
		out.throttle = accel
	else:
		# Byte 0 means "no gear opinion" (not park): hardware that never sends 0x077 would
		# otherwise leave the accelerator dead with no explanation. Gearbox drives itself as
		# with no bridge: forward, auto-shifting. Reverse still needs the explicit R byte.
		out.gear_auto = true
		out.gear_request = GEAR_D1 if accel > 0.0 else GEAR_N
		out.throttle = accel

	if out.key != KEY_IGNITION:
		out.throttle = 0.0
	return out

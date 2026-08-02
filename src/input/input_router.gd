extends Node
## InputRouter autoload — merges input sources into one normalized VehicleInput.
##
## Plan §4.3: three InputSources (keyboard/gamepad, touch, bridge) merge into a
## single VehicleInput. ALL arbitration lives here and nowhere else:
## throttle only ever comes from the accelerator (brake is never throttle); key must
## be Ignition for throttle; locally S brakes and engages R near standstill; when the
## bridge is active and not Neutral the gear owns direction. Vehicles never
## know which source is active.
##
## Arbitration is static/pure (like contract.gd's parser) so tests exercise it without
## the autoload lifecycle — tests/test_input_arbitration.gd MUST stay green. All three
## sources are live (local keyboard, touch via merge_local, bridge). Shared toggles the
## sources can only edge (_lights, _hitch_up, _pto) are owned HERE, not by a source.

const KEY_LOCK := 1
const KEY_ON := 2
const KEY_IGNITION := 3

const GEAR_N := 0x00
const GEAR_D1 := 0x01
const GEAR_R := 0xFF

## m/s below which S (held with no accel) swaps D->R and W swaps R->D.
const REVERSE_ENGAGE_SPEED := 0.5

## Positions on the refuse body's command stalk (contract 'body_cmd'). Deliberately MIRRORS
## RefuseBody.Cmd rather than reading it — the router normalizes input and must not depend on a
## vehicle class — so tests/test_input_arbitration.gd pins the two together instead. Grow both, or
## the local cycle silently stops reaching the new command while the bridge can still send it.
const BODY_CMD_COUNT := 4

const LocalSource := preload("res://src/input/sources/local_source.gd")
const BridgeSource := preload("res://src/input/sources/bridge_source.gd")


## The normalized per-tick input every vehicle consumes.
class VehicleInput:
	var throttle := 0.0    ## -1..1, signed by direction (never from the brake)
	var brake := 0.0       ## 0..1 foot brake
	var steer := 0.0       ## -1..1, negative = left
	var handbrake := 0.0   ## 0..1
	var gear_request := 0  ## RAMN gear byte: 0=N, 1..6=D1-D6, 255=R
	var gear_auto := true  ## true: byte is a direction intent, gearbox auto-shifts in D;
	                       ## false (bridge): byte is exact and owns direction
	var key := 1           ## 1=Lock, 2=On, 3=Ignition
	var horn := false
	var lights := 1        ## 1=OFF, 2=CLEARANCE, 3=LOW, 4=HIGH
	# Lamp/warning bits. sloppyCAN is the sole authority when the bridge is
	# live; these mirror it verbatim. Locally only brake_lamp is driven (from the foot
	# brake); turn signals + warning LEDs stay off (no local source, no blink timer).
	var turn_left := false
	var turn_right := false
	var brake_lamp := false   ## rear STOP state (0x1BB brake bit / local foot brake)
	var check_engine := false ## warning LED; defaults off when the bridge doesn't send it
	var battery_warn := false ## battery warning LED (distinct from the 'out' voltage)
	# ISOBUS implement request (tractor only). Flows through the struct
	# like the lamp bits — never a side channel. Default raised/off; other vehicles
	# ignore it (only TractorVehicle reads them).
	var hitch_request := 1.0  ## 0..1 requested hitch height (1 = raised/transport)
	var pto := false          ## PTO engage request
	var pto_mode := 0         ## PTO speed selection: 0 = 540, 1 = 1000 (contract 'pto_mode' enum)
	var diff_lock := false    ## rear differential lock request
	var fwd_drive := false    ## MFWD front-axle engage request
	var scv_flow := 0.0      ## 0..1 hydraulic remote (SCV) valve opening; no local control
	# Flight controls. Defaulted so ground vehicles ignore them (the hitch/pto pattern):
	# only PlaneVehicle reads elevator/flaps; only DroneVehicle reads climb/arm.
	var elevator := 0.0       ## -1..1, + = nose up (plane elevator)
	var climb := 0.0          ## -1..1, + = ascend (drone vertical rate)
	var arm := false          ## drone motor arm (rotors spin only when armed)
	var flaps := 0.0          ## 0..1 requested flap extension (plane only)
	# Train controls (flavor "train"). Same struct-not-side-channel rule as the ISOBUS/
	# flight fields; only TrainVehicle reads them. Default: pantograph down, doors shut.
	var pantograph := false   ## pantograph raise request (traction is cut while lowered)
	var doors := false        ## passenger door open request (honored at standstill only)
	# J1939 chassis (flavor "j1939", truck only). Same struct-not-side-channel rule as the
	# ISOBUS/flight/train fields: only TruckVehicle reads `retarder`, and the three DM1 lamp
	# bits are pure tell-tales nothing in the sim consumes. Defaults are released/off.
	var retarder := 0.0        ## 0..1 auxiliary driveline brake request; NO local key (scv_flow's shape)
	# J1939-73 DM1 lamp status byte, mirrored VERBATIM like turnL — no local source and no
	# local timer of ANY kind. checkEngine already IS DM1's Malfunction Indicator Lamp, so
	# nothing is added for it. DM1's real lamp states also include flash-1Hz and flash-2Hz;
	# those are deliberately unmodelled, because a blink would have to come from a local clock
	# and the standing rule forbids one (see the plane beacon exception in TODO.md).
	var red_stop := false      ## DM1 Red Stop Lamp — stop the vehicle
	var amber_warn := false    ## DM1 Amber Warning Lamp — needs attention, keep going
	var protect_lamp := false  ## DM1 Protect Lamp — a non-electronic fault (fluid out of range)
	# ISO 11992 trailer bus (flavor "iso11992", truck only) — the towed unit's counterpart of the
	# three DM1 bits above, and the only thing the trailer bus carries INTO the game. Mirrored
	# verbatim under the same rules: no local source, no local timer, absent bit = off.
	var trailer_ebs_fault := false  ## trailer EBS fault reported over the trailer bus
	# SAE J2497 / PLC4TRUCKS (flavor "j2497", truck only) — the NORTH AMERICAN trailer boundary,
	# and it is one bit because there is no data pair on the connector over there: trailer ABS
	# status rides the POWER line as LAMP ON / LAMP OFF. Same verbatim-mirror rules as everything
	# above, and it is meaningful only on a unit with no ISO 11992 bus.
	var trailer_abs_lamp := false   ## trailer ABS telltale off the power line (SAE J2497)
	# CiA 422 body network (flavor "cleanopen", truck only). It rides the struct like every other
	# subsystem field rather than a side channel, even though it arrives from a SECOND network across
	# a gateway — the router does not model buses, it normalizes one input per tick. Only the garbage
	# truck reads it (the firetruck has no body to command), and 0 = Idle is the safe default.
	var body_cmd := 0          ## RefuseBody.Cmd: 0 Idle, 1 Lift, 2 Dump, 3 Lower

	func copy() -> VehicleInput:
		var c := VehicleInput.new()
		c.throttle = throttle
		c.brake = brake
		c.steer = steer
		c.handbrake = handbrake
		c.gear_request = gear_request
		c.gear_auto = gear_auto
		c.key = key
		c.horn = horn
		c.lights = lights
		c.turn_left = turn_left
		c.turn_right = turn_right
		c.brake_lamp = brake_lamp
		c.check_engine = check_engine
		c.battery_warn = battery_warn
		c.hitch_request = hitch_request
		c.pto = pto
		c.pto_mode = pto_mode
		c.diff_lock = diff_lock
		c.fwd_drive = fwd_drive
		c.scv_flow = scv_flow
		c.elevator = elevator
		c.climb = climb
		c.arm = arm
		c.flaps = flaps
		c.pantograph = pantograph
		c.doors = doors
		c.retarder = retarder
		c.red_stop = red_stop
		c.amber_warn = amber_warn
		c.protect_lamp = protect_lamp
		c.trailer_ebs_fault = trailer_ebs_fault
		c.trailer_abs_lamp = trailer_abs_lamp
		c.body_cmd = body_cmd
		return c


var _local_source := LocalSource.new()
var _bridge_source := BridgeSource.new()
var _touch_source: Object = null  ## optional on-screen source (touch_controls.gd), if present
var _vehicle: Node3D = null
var _current := VehicleInput.new()
var _lights := 1  ## headlight level owned here so keyboard + touch share one state
# Local tractor implement state, owned here (like _lights) so keyboard + touch share it.
# The bridge path ignores these — sloppyCAN is authoritative there.
var _hitch_up := true  ## true = raised (transport), toggled by the local hitch key
var _pto := false      ## local PTO engage, toggled by the local PTO key
var _pto_mode := 0     ## local PTO speed (contract 'pto_mode': 0 = 540, 1 = 1000), cycled by its key
var _diff_lock := false   ## local rear diff lock, toggled by the local diff-lock key
var _fwd_drive := false   ## local MFWD engage, toggled by the local MFWD key
var _armed := false    ## local drone motor arm, toggled by the local arm key (like _pto)
var _flaps_down := false  ## local plane flaps extended, toggled by the local flaps key
## Raised by default so a locally-driven train spawns able to move (the _hitch_up
## "usable default" pattern); lowering it is what visibly cuts traction.
var _pantograph := true   ## local train pantograph raised, toggled by the local pantograph key
var _doors := false       ## local train door open request, toggled by the local doors key
## Local refuse body command, CYCLED by its key (Idle -> Lift -> Dump -> Lower -> Idle) rather than
## flipped, because there are four commands. Owned here like _pto so keyboard and touch would share
## one owner; the bridge path ignores it, where sloppyCAN is authoritative. The stalk's position
## count is BODY_CMD_COUNT, up with the other constants.
var _body_cmd := 0        ## RefuseBody.Cmd, contract 'body_cmd'
## Seconds the "ignition off" notice stays up: much longer than the default dwell, because it is
## the one notice the driver has to go DO something about (move the key in sloppyCAN).
const IGNITION_NOTICE_DWELL_S := 20.0
## The notice's exact text. A const because it is raised AND cleared by text — see
## GameState.notice_cleared.
const IGNITION_NOTICE_TEXT := "IGNITION OFF - MOVE THE ENGINE KEY"

## Edge latch for the "ignition off" notice — see _warn_if_ignition_off.
var _ignition_warned := false


## Vehicles register on _ready so arbitration can read speed/gear (local reverse
## needs them); they never expose anything else to the router.
func register_vehicle(vehicle: Node3D) -> void:
	_vehicle = vehicle


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
	# Autoloads tick before scene nodes, so this runs ahead of every vehicle's frame.
	# Bridge wins while it has fresh data; otherwise local input works untouched.
	var bridge_raw := _bridge_source.poll()
	if bridge_raw.get("active", false):
		_current = arbitrate_bridge(bridge_raw)
		_warn_if_ignition_off(bridge_raw)
		return
	_clear_ignition_notice()
	var raw := _local_source.poll(delta)
	if _touch_source != null:
		raw = merge_local(raw, _touch_source.poll())
	# Single headlight owner: either source's cycle edge advances the shared level.
	if bool(raw.get("lights_cycle", false)):
		_lights = _lights % 4 + 1
	raw["lights"] = _lights
	# Local implement toggles owned here too (same pattern as the headlight level).
	if bool(raw.get("hitch_toggle", false)):
		_hitch_up = not _hitch_up
	if bool(raw.get("pto_toggle", false)):
		_pto = not _pto
	if bool(raw.get("pto_mode_toggle", false)):
		_pto_mode = 1 - _pto_mode  # two modes, so the cycle is a flip
	if bool(raw.get("diff_lock_toggle", false)):
		_diff_lock = not _diff_lock
	if bool(raw.get("fwd_drive_toggle", false)):
		_fwd_drive = not _fwd_drive
	if bool(raw.get("arm_toggle", false)):
		_armed = not _armed
	if bool(raw.get("flaps_toggle", false)):
		_flaps_down = not _flaps_down
	if bool(raw.get("pantograph_toggle", false)):
		_pantograph = not _pantograph
	if bool(raw.get("doors_toggle", false)):
		_doors = not _doors
	if bool(raw.get("body_cmd_toggle", false)):
		# Four commands, so the stalk cycles rather than flips.
		_body_cmd = (_body_cmd + 1) % BODY_CMD_COUNT
	raw["hitch_request"] = 1.0 if _hitch_up else 0.0
	raw["pto"] = _pto
	raw["pto_mode"] = _pto_mode
	raw["diff_lock"] = _diff_lock
	raw["fwd_drive"] = _fwd_drive
	raw["arm"] = _armed
	raw["flaps"] = 1.0 if _flaps_down else 0.0
	raw["pantograph"] = _pantograph
	raw["doors"] = _doors
	raw["body_cmd"] = _body_cmd
	var speed := 0.0
	var gear := GEAR_N
	if _vehicle != null:
		speed = _vehicle.get_speed()
		gear = _vehicle.get_gear_byte()
	_current = arbitrate_local(raw, speed, gear)


## Tell the driver why the throttle does nothing. `arbitrate_bridge` zeroes throttle whenever the
## key is not at Ignition, and that is silent — a request with the key back at Lock/On simply has
## no effect, which reads as a broken game rather than a key position. Only the BRIDGE path can
## reach it (local input is always at Ignition), and it fires on the EDGE: the notice's dwell
## restarts on every re-show, so emitting per tick would pin the message on screen for as long as
## the pedal is down.
func _warn_if_ignition_off(bridge_raw: Dictionary) -> void:
	var wants_throttle := float(bridge_raw.get("accel", 0.0)) > 0.0
	if _current.key != KEY_IGNITION and wants_throttle:
		if not _ignition_warned:
			_ignition_warned = true
			GameState.notice.emit(IGNITION_NOTICE_TEXT, IGNITION_NOTICE_DWELL_S)
	elif _current.key == KEY_IGNITION:
		_clear_ignition_notice()


## Drop the notice the moment the key reaches Ignition, instead of letting the 20 s dwell run out.
## The dwell is long because the driver has to go DO something; once they have done it, a warning
## still sitting on screen is just wrong. Also called when the bridge goes away — local input is
## always at Ignition, so the condition cannot survive that either.
func _clear_ignition_notice() -> void:
	if _ignition_warned:
		_ignition_warned = false
		GameState.notice_cleared.emit(IGNITION_NOTICE_TEXT)


## Current merged input. Returns a fresh copy — callers own (and may mutate) it.
func get_vehicle_input() -> VehicleInput:
	return _current.copy()


## Merge the keyboard and touch raw intents into one before arbitration:
## analog axes take the stronger request, steer sums (clamped), momentary bits OR
## together. Pure/static so it is unit-tested without the autoload. `lights` is not
## merged here — InputRouter owns the level and reads the merged `lights_cycle` edge.
static func merge_local(a: Dictionary, b: Dictionary) -> Dictionary:
	return {
		"accel": maxf(float(a.get("accel", 0.0)), float(b.get("accel", 0.0))),
		"brake_reverse": maxf(float(a.get("brake_reverse", 0.0)), float(b.get("brake_reverse", 0.0))),
		"steer": clampf(float(a.get("steer", 0.0)) + float(b.get("steer", 0.0)), -1.0, 1.0),
		"handbrake": maxf(float(a.get("handbrake", 0.0)), float(b.get("handbrake", 0.0))),
		"horn": bool(a.get("horn", false)) or bool(b.get("horn", false)),
		"lights_cycle": bool(a.get("lights_cycle", false)) or bool(b.get("lights_cycle", false)),
		"hitch_toggle": bool(a.get("hitch_toggle", false)) or bool(b.get("hitch_toggle", false)),
		"pto_toggle": bool(a.get("pto_toggle", false)) or bool(b.get("pto_toggle", false)),
		"pto_mode_toggle": bool(a.get("pto_mode_toggle", false)) or bool(b.get("pto_mode_toggle", false)),
		"diff_lock_toggle": bool(a.get("diff_lock_toggle", false)) or bool(b.get("diff_lock_toggle", false)),
		"fwd_drive_toggle": bool(a.get("fwd_drive_toggle", false)) or bool(b.get("fwd_drive_toggle", false)),
		# Flight axes (-1..1) sum-clamp like steer; arm/flaps edges OR like the other toggles.
		"elevator": clampf(float(a.get("elevator", 0.0)) + float(b.get("elevator", 0.0)), -1.0, 1.0),
		"climb": clampf(float(a.get("climb", 0.0)) + float(b.get("climb", 0.0)), -1.0, 1.0),
		"arm_toggle": bool(a.get("arm_toggle", false)) or bool(b.get("arm_toggle", false)),
		"flaps_toggle": bool(a.get("flaps_toggle", false)) or bool(b.get("flaps_toggle", false)),
		# Train toggles edge like arm/flaps; InputRouter owns the latched state.
		"pantograph_toggle": bool(a.get("pantograph_toggle", false)) or bool(b.get("pantograph_toggle", false)),
		"doors_toggle": bool(a.get("doors_toggle", false)) or bool(b.get("doors_toggle", false)),
		# The refuse body cycle edges like the toggles above. This line is REQUIRED, not
		# belt-and-braces: this dict is built explicitly, so a missing key silently drops the
		# keyboard's edge for as long as a touch source is registered.
		"body_cmd_toggle": bool(a.get("body_cmd_toggle", false)) or bool(b.get("body_cmd_toggle", false)),
	}


## Local (keyboard/gamepad) arbitration, pure for tests. Rules:
## throttle only from accel; brake never throttle; full accel + full brake pass
## through (stopping is the brake > accel force hierarchy's job, in the spec);
## key gates throttle. Reverse UX: S brakes while moving, engages R near standstill;
## W in R brakes, then re-engages D1 near standstill.
static func arbitrate_local(raw: Dictionary, speed: float, gear_byte: int,
		key: int = KEY_IGNITION) -> VehicleInput:
	var out := VehicleInput.new()
	out.steer = clampf(float(raw.get("steer", 0.0)), -1.0, 1.0)
	out.handbrake = clampf(float(raw.get("handbrake", 0.0)), 0.0, 1.0)
	out.key = key  # local key is always Ignition until the bridge owns it
	out.gear_auto = true
	out.horn = bool(raw.get("horn", false))
	out.lights = int(raw.get("lights", 1))  # local headlight cycle (turn/warning bits stay off)
	# Implement request from the InputRouter-owned local toggles (tractor only; ignored elsewhere).
	out.hitch_request = clampf(float(raw.get("hitch_request", 1.0)), 0.0, 1.0)
	out.pto = bool(raw.get("pto", false))
	out.pto_mode = int(raw.get("pto_mode", 0))
	out.diff_lock = bool(raw.get("diff_lock", false))
	out.fwd_drive = bool(raw.get("fwd_drive", false))
	# Refuse body command from the InputRouter-owned local cycle (garbage truck only; every other
	# vehicle ignores it). Unlike the retarder below, a body command DOES have a keyboard analogue —
	# it is a stalk with four positions — so it gets a key.
	out.body_cmd = int(raw.get("body_cmd", 0))
	# scv_flow is left at its default 0 (valve closed): the hydraulic remote has no local
	# control, it is a bridge signal — the honest local state is a shut valve, not a guess.
	# The truck's `retarder` is left at 0 for the same reason (a retarder stalk has no keyboard
	# analogue worth inventing), and the three DM1 lamp bits stay false: they have no local
	# source at all, exactly like turnL/turnR, and off is their correct default.
	# Flight controls pass through (plane/drone only; ground vehicles ignore them).
	out.elevator = clampf(float(raw.get("elevator", 0.0)), -1.0, 1.0)
	out.climb = clampf(float(raw.get("climb", 0.0)), -1.0, 1.0)
	out.arm = bool(raw.get("arm", false))
	out.flaps = clampf(float(raw.get("flaps", 0.0)), 0.0, 1.0)
	# Train controls from the InputRouter-owned local toggles (train only; ignored elsewhere).
	out.pantograph = bool(raw.get("pantograph", false))
	out.doors = bool(raw.get("doors", false))

	var accel := clampf(float(raw.get("accel", 0.0)), 0.0, 1.0)
	var brake_rev := clampf(float(raw.get("brake_reverse", 0.0)), 0.0, 1.0)
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
	out.brake_lamp = out.brake > 0.0
	return out


## Bridge (sloppyCAN) arbitration, pure for tests. Rules: while the bridge is
## active and sending a REAL gear the byte OWNS direction — throttle is `accel` signed by the byte
## (+ in D1–D6, − in R), and local reverse UX is ignored (gear_auto = false, so the byte is used
## exactly). Byte 0 means "no gear opinion" and hands the gearbox back to auto (see below).
## brake is never throttle; key gates throttle; steer/handbrake/lights/horn
## pass through. Values arrive already normalized to VehicleInput ranges from bridge_source.
static func arbitrate_bridge(vals: Dictionary) -> VehicleInput:
	var out := VehicleInput.new()
	# Steer channel, with its two overrides — presence is the whole rule, and both arrive
	# already normalized to -1..1 from bridge_source:
	#   'guidance' (tractor auto-steer, from 'guidance_curvature'): an external computer is
	#     holding the wheel, so a guidance command wins over a steer command;
	#   'rudder' (boat): the rudder IS the steer channel.
	# Neither vehicle can send the other's key, so the order between them is arbitrary;
	# absent both, cars/trucks are untouched.
	out.steer = clampf(float(vals.get("guidance", vals.get("rudder", vals.get("steer", 0.0)))),
			-1.0, 1.0)
	out.handbrake = clampf(float(vals.get("handbrake", 0.0)), 0.0, 1.0)
	out.brake = clampf(float(vals.get("brake", 0.0)), 0.0, 1.0)
	out.key = int(vals.get("key", KEY_IGNITION))
	out.lights = int(vals.get("lights", 1))
	out.horn = bool(vals.get("horn", false))
	# Lamp/warning bits mirrored verbatim (sloppyCAN is the sole authority;
	# any absent bit defaults off, e.g. the warning LEDs).
	out.turn_left = bool(vals.get("turnL", false))
	out.turn_right = bool(vals.get("turnR", false))
	out.brake_lamp = bool(vals.get("brakeLamp", false))
	out.check_engine = bool(vals.get("checkEngine", false))
	out.battery_warn = bool(vals.get("battery", false))
	# ISOBUS implement request mirrored from sloppyCAN (sole authority). Absent →
	# raised/off, the §6 default-off convention. bridge_source clamps hitch_pos to 0..100.
	out.hitch_request = clampf(float(vals.get("hitch_pos", 100.0)) / 100.0, 0.0, 1.0)
	out.pto = bool(vals.get("pto", false))
	# Driveline requests mirrored the same way; absent → open diff, 2WD, 540 PTO, which is a
	# real tractor's rest state (you engage the lock and the front axle when you need them).
	out.pto_mode = int(vals.get("pto_mode", 0))
	out.diff_lock = bool(vals.get("diff_lock", false))
	out.fwd_drive = bool(vals.get("fwd_drive", false))
	# Hydraulic remote: bridge-only (there is no local SCV control), absent → valve closed.
	out.scv_flow = clampf(float(vals.get("scv_flow", 0.0)), 0.0, 1.0)
	# Flight controls mirrored from sloppyCAN (already %→unit normalized in bridge_source);
	# absent → neutral/disarmed/retracted. arm and flaps are authoritative here, no local toggles.
	out.elevator = clampf(float(vals.get("elevator", 0.0)), -1.0, 1.0)
	out.climb = clampf(float(vals.get("climb", 0.0)), -1.0, 1.0)
	out.arm = bool(vals.get("arm", false))
	out.flaps = clampf(float(vals.get("flaps", 0.0)), 0.0, 1.0)
	# Train controls mirrored from sloppyCAN (sole authority); absent → lowered/shut.
	out.pantograph = bool(vals.get("pantograph", false))
	out.doors = bool(vals.get("doors", false))
	# J1939 chassis (truck). The retarder is bridge-only (there is no local stalk), absent →
	# released; the three DM1 lamps are mirrored VERBATIM with the lamp bits above, absent → off.
	# No blink timer for any of them — see the VehicleInput field comments.
	out.retarder = clampf(float(vals.get("retarder", 0.0)), 0.0, 1.0)
	out.red_stop = bool(vals.get("red_stop", false))
	out.amber_warn = bool(vals.get("amber_warn", false))
	out.protect_lamp = bool(vals.get("protect_lamp", false))
	# ISO 11992 trailer bus: the towed unit's fault lamp, mirrored with the DM1 bits above and
	# under the same rules — absent → off, no local timer.
	out.trailer_ebs_fault = bool(vals.get("trailer_ebs_fault", false))
	# SAE J2497: the North American unit's ONE trailer bit, off the power line. Mirrored under
	# exactly the same rules — absent → off, no local timer.
	out.trailer_abs_lamp = bool(vals.get("trailer_abs_lamp", false))
	# CiA 422 body command. Mirrored from sloppyCAN like every other request while the bridge is
	# live, so the local cycle is ignored; absent → 0 Idle, which stows the body. That IS the honest
	# default here rather than a hold-in-place: an unpowered body network cannot be holding an arm up.
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
		# Byte 0 (or an unknown byte) is NOT "park the car": a CAN source that models no
		# gearbox — real hardware that never sends 0x077 — would otherwise leave the
		# accelerator dead with nothing on screen to explain it. It means "no gear opinion",
		# so the gearbox drives itself exactly as it does with no bridge at all: forward,
		# auto-shifting. Reverse still needs the explicit R byte (there is no bridge
		# equivalent of the local brake-at-standstill reverse gesture).
		out.gear_auto = true
		out.gear_request = GEAR_D1 if accel > 0.0 else GEAR_N
		out.throttle = accel

	if out.key != KEY_IGNITION:
		out.throttle = 0.0
	return out

extends RefCounted
## Bridge input source. Reads the freshness-gated inbound values the Bridge autoload polls
## from sloppyCAN and reports them as raw intents — interpretation (gear-owns-direction, key
## gating) happens in InputRouter, not here.
##
## Fields are the contract "in" names; the driving-relevant subset is normalized to
## VehicleInput ranges (percent → unit). Lamp/warning bits pass through as bools, mirrored
## verbatim.

## Curvature (1/km) at full steering lock: maps guidance_curvature to -1..1 steer.
## 127 1/km (7.9 m turn radius) is the i8 maximum so the whole range is usable.
const FULL_LOCK_CURVATURE := 127.0


func poll() -> Dictionary[StringName, Variant]:
	var v := Bridge.get_input_values()
	if v.is_empty():
		return {&"active": false}
	var out: Dictionary[StringName, Variant] = {
		&"active": true,
		&"drive_sourced": drive_sourced(v),
		&"accel": clampf(_num(v, "accel", 0.0) / 100.0, 0.0, 1.0),
		&"brake": clampf(_num(v, "brake", 0.0) / 100.0, 0.0, 1.0),
		&"steer": clampf(_num(v, "steer", 0.0) / 100.0, -1.0, 1.0),
		&"handbrake": clampf(_num(v, "handbrake", 0.0), 0.0, 1.0),
		&"gear": int(_num(v, "gear", 0)),
		# absent → Ignition: `arbitrate_bridge`'s own KEY_IGNITION default never fires once this
		# normalizes the key, and traffic with no key/ignition signal must still let a car drive.
		&"key": int(_num(v, "key", 3)),
		&"lights": int(_num(v, "lights", 1)),
		&"horn": _flag(v, "horn"),
		&"turnL": _flag(v, "turnL"),
		&"turnR": _flag(v, "turnR"),
		&"brakeLamp": _flag(v, "brakeLamp"),
		&"checkEngine": _flag(v, "checkEngine"),
		&"battery": _flag(v, "battery"),
		# ISOBUS hitch_pos % normalized by arbitrate_bridge; absent → raised/off.
		&"hitch_pos": clampf(_num(v, "hitch_pos", 100.0), 0.0, 100.0),
		&"pto": _flag(v, "pto"),
		&"pto_mode": int(_num(v, "pto_mode", 0)),
		&"diff_lock": _flag(v, "diff_lock"),
		&"fwd_drive": _flag(v, "fwd_drive"),
		# Car traction control; absent → TC on.
		&"tcs_off": _flag(v, "tcs_off"),
		# Hydraulic remote % → 0..1 valve; absent → closed.
		&"scv_flow": clampf(_num(v, "scv_flow", 0.0) / 100.0, 0.0, 1.0),
		# Flight controls % → unit; absent → neutral.
		&"elevator": clampf(_num(v, "elevator", 0.0) / 100.0, -1.0, 1.0),
		&"climb": clampf(_num(v, "climb", 0.0) / 100.0, -1.0, 1.0),
		&"arm": _flag(v, "arm"),
		&"flaps": clampf(_num(v, "flaps", 0.0) / 100.0, 0.0, 1.0),
		# Aircraft lamps: mirrored verbatim, absent → off, never blinked locally.
		&"beacon": _flag(v, "beacon"),
		&"strobe": _flag(v, "strobe"),
		# DroneCAN bus failure: bitfield, mirrored verbatim; absent = 0 = online.
		&"node_fail": int(_num(v, "node_fail", 0)),
		# Flight-mode (enum): absent → 0 STABILIZE. What the FC does comes back as mode_actual.
		&"flight_mode": int(_num(v, "flight_mode", 0)),
		# Boat autopilot mode (enum): absent → 0 STANDBY. What the pilot does comes back as
		# nav_mode_actual. `heading_cmd` beside it is presence-gated, at the bottom.
		&"nav_mode": int(_num(v, "nav_mode", 0)),
		# The sheet is a percentage on the wire like `scv_flow`; absent = hauled in hard.
		&"sheet": clampf(_num(v, "sheet", 0.0) / 100.0, 0.0, 1.0),
		# DroneCAN indication: led RGB565, beep bool, both mirrored; absent → off.
		&"led": int(_num(v, "led", 0)),
		&"beep": _flag(v, "beep"),
		# Cargo hook: mirrored verbatim; absent → false = released.
		&"hardpoint_cmd": _flag(v, "hardpoint_cmd"),
		# Gimbal contract degrees; absent → 0 rest pose.
		&"gimbal_pitch": _num(v, "gimbal_pitch", 0.0),
		&"gimbal_yaw": _num(v, "gimbal_yaw", 0.0),
		# Train: absent → lowered/shut.
		&"pantograph": _flag(v, "pantograph"),
		&"doors": _flag(v, "doors"),
		# J1939: retarder %, DM1 lamps mirrored, absent → off.
		&"retarder": clampf(_num(v, "retarder", 0.0) / 100.0, 0.0, 1.0),
		&"red_stop": _flag(v, "red_stop"),
		&"amber_warn": _flag(v, "amber_warn"),
		&"protect_lamp": _flag(v, "protect_lamp"),
		# ISO 11992 trailer fault: mirrored like DM1.
		&"trailer_ebs_fault": _flag(v, "trailer_ebs_fault"),
		# SAE J2497 trailer ABS: mirrored.
		&"trailer_abs_lamp": _flag(v, "trailer_abs_lamp"),
		# CiA 422 body (garbage truck); absent → 0 Idle.
		&"body_cmd": int(_num(v, "body_cmd", 0)),
	}
	# Boat rudder: presence overrides steer in arbitrate_bridge, normalized %→unit.
	if v.has("rudder"):
		out[&"rudder"] = clampf(_num(v, "rudder", 0.0) / 100.0, -1.0, 1.0)
	# Tractor guidance: same presence rule as rudder, curvature 1/km→steer unit for `steer`
	# (dashboard/telemetry keep reading that as before). The raw curvature also rides through
	# under its own key, clamped to the wire's +-127 1/km i8, for WheelDrive to derive the wheel
	# angle from the tractor's own wheelbase rather than through the speed-tapered rack.
	if v.has("guidance_curvature"):
		var curvature := clampf(_num(v, "guidance_curvature", 0.0), -FULL_LOCK_CURVATURE, FULL_LOCK_CURVATURE)
		out[&"guidance"] = steer_from_curvature(curvature)
		out[&"guidance_curvature"] = curvature
	# Boat autopilot course: same presence rule again, and here it is load-bearing rather than an
	# override — every bearing in [0,360] is legal, so there is no "no command" value to send.
	# Absent means the pilot holds the heading it captured; wrapped, so 360 arrives as 0.
	if v.has("heading_cmd"):
		out[&"heading_cmd"] = fposmod(_num(v, "heading_cmd", 0.0), 360.0)
	return out


## One wire value as a number. The inbound JSON is unchecked (a NaN arrives as null, and the
## page is not origin-gated), so anything but a number or bool reads as `default`.
static func _num(v: Dictionary, key: String, default: float) -> float:
	var x: Variant = v.get(key, default)
	match typeof(x):
		TYPE_INT, TYPE_FLOAT:
			return float(x)
		TYPE_BOOL:
			return 1.0 if x else 0.0
	return default


static func _flag(v: Dictionary, key: String) -> bool:
	return _num(v, key, 0.0) != 0.0


## Does the uplink carry a driving control at all? Read off the RAW values, since `poll()`
## defaults all three: sloppyCAN omits a control it has no source for, so a live bridge under
## traffic with no driver demand (anything but RAMN, J1939 and ISO 11783) carries none. Any one is enough (a hand-sent pedal frame; the drone panel's
## sticks claim all three).
static func drive_sourced(v: Dictionary) -> bool:
	return v.has("accel") or v.has("brake") or v.has("steer")


## Guidance curvature 1/km → steer unit. Saturates at full lock.
static func steer_from_curvature(curvature: float) -> float:
	return clampf(curvature / FULL_LOCK_CURVATURE, -1.0, 1.0)

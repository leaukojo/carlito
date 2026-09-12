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
		&"accel": clampf(float(v.get("accel", 0.0)) / 100.0, 0.0, 1.0),
		&"brake": clampf(float(v.get("brake", 0.0)) / 100.0, 0.0, 1.0),
		&"steer": clampf(float(v.get("steer", 0.0)) / 100.0, -1.0, 1.0),
		&"handbrake": clampf(float(v.get("handbrake", 0.0)), 0.0, 1.0),
		&"gear": int(v.get("gear", 0)),
		&"key": int(v.get("key", 1)),
		&"lights": int(v.get("lights", 1)),
		&"horn": bool(v.get("horn", 0)),
		&"turnL": bool(v.get("turnL", 0)),
		&"turnR": bool(v.get("turnR", 0)),
		&"brakeLamp": bool(v.get("brakeLamp", 0)),
		&"checkEngine": bool(v.get("checkEngine", 0)),
		&"battery": bool(v.get("battery", 0)),
		# ISOBUS hitch_pos % normalized by arbitrate_bridge; absent → raised/off.
		&"hitch_pos": clampf(float(v.get("hitch_pos", 100.0)), 0.0, 100.0),
		&"pto": bool(v.get("pto", false)),
		&"pto_mode": int(v.get("pto_mode", 0)),
		&"diff_lock": bool(v.get("diff_lock", false)),
		&"fwd_drive": bool(v.get("fwd_drive", false)),
		# Hydraulic remote % → 0..1 valve; absent → closed.
		&"scv_flow": clampf(float(v.get("scv_flow", 0.0)) / 100.0, 0.0, 1.0),
		# Flight controls % → unit; absent → neutral.
		&"elevator": clampf(float(v.get("elevator", 0.0)) / 100.0, -1.0, 1.0),
		&"climb": clampf(float(v.get("climb", 0.0)) / 100.0, -1.0, 1.0),
		&"arm": bool(v.get("arm", false)),
		&"flaps": clampf(float(v.get("flaps", 0.0)) / 100.0, 0.0, 1.0),
		# Aircraft lamps: mirrored verbatim, absent → off, never blinked locally.
		&"beacon": bool(v.get("beacon", false)),
		&"strobe": bool(v.get("strobe", false)),
		# DroneCAN bus failure: bitfield, mirrored verbatim; absent = 0 = online.
		&"node_fail": int(v.get("node_fail", 0)),
		# Flight-mode (enum): absent → 0 STABILIZE. What the FC does comes back as mode_actual.
		&"flight_mode": int(v.get("flight_mode", 0)),
		# Boat autopilot mode (enum): absent → 0 STANDBY. What the pilot does comes back as
		# nav_mode_actual. `heading_cmd` beside it is presence-gated, at the bottom.
		&"nav_mode": int(v.get("nav_mode", 0)),
		# The sheet is a percentage on the wire like `scv_flow`; absent = hauled in hard.
		&"sheet": clampf(float(v.get("sheet", 0.0)) / 100.0, 0.0, 1.0),
		# DroneCAN indication: led RGB565, beep bool, both mirrored; absent → off.
		&"led": int(v.get("led", 0)),
		&"beep": bool(v.get("beep", false)),
		# Cargo hook: mirrored verbatim; absent → false = released.
		&"hardpoint_cmd": bool(v.get("hardpoint_cmd", false)),
		# Gimbal contract degrees; absent → 0 rest pose.
		&"gimbal_pitch": float(v.get("gimbal_pitch", 0.0)),
		&"gimbal_yaw": float(v.get("gimbal_yaw", 0.0)),
		# Train: absent → lowered/shut.
		&"pantograph": bool(v.get("pantograph", false)),
		&"doors": bool(v.get("doors", false)),
		# J1939: retarder %, DM1 lamps mirrored, absent → off.
		&"retarder": clampf(float(v.get("retarder", 0.0)) / 100.0, 0.0, 1.0),
		&"red_stop": bool(v.get("red_stop", false)),
		&"amber_warn": bool(v.get("amber_warn", false)),
		&"protect_lamp": bool(v.get("protect_lamp", false)),
		# ISO 11992 trailer fault: mirrored like DM1.
		&"trailer_ebs_fault": bool(v.get("trailer_ebs_fault", false)),
		# SAE J2497 trailer ABS: mirrored.
		&"trailer_abs_lamp": bool(v.get("trailer_abs_lamp", false)),
		# CiA 422 body (garbage truck); absent → 0 Idle.
		&"body_cmd": int(v.get("body_cmd", 0)),
	}
	# Boat rudder: presence overrides steer in arbitrate_bridge, normalized %→unit.
	if v.has("rudder"):
		out[&"rudder"] = clampf(float(v.get("rudder", 0.0)) / 100.0, -1.0, 1.0)
	# Tractor guidance: same presence rule as rudder, curvature 1/km→steer unit.
	if v.has("guidance_curvature"):
		out[&"guidance"] = steer_from_curvature(float(v.get("guidance_curvature", 0.0)))
	# Boat autopilot course: same presence rule again, and here it is load-bearing rather than an
	# override — every bearing in [0,360] is legal, so there is no "no command" value to send.
	# Absent means the pilot holds the heading it captured; wrapped, so 360 arrives as 0.
	if v.has("heading_cmd"):
		out[&"heading_cmd"] = fposmod(float(v.get("heading_cmd", 0.0)), 360.0)
	return out


## Guidance curvature 1/km → steer unit. Saturates at full lock.
static func steer_from_curvature(curvature: float) -> float:
	return clampf(curvature / FULL_LOCK_CURVATURE, -1.0, 1.0)

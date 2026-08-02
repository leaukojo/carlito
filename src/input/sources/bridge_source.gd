extends RefCounted
## Bridge input source. Reads the freshness-gated inbound values the Bridge
## autoload polls from sloppyCAN and reports them as raw intents — like local_source.gd, every
## interpretation (gear-owns-direction, key gating) happens in InputRouter.
##
## Fields are the contract "in" names; the driving-relevant subset is normalized to VehicleInput
## ranges here (percent → unit). Lamp/warning bits (turnL/turnR/brakeLamp/checkEngine/battery)
## pass through as bools for LampSet + the dashboard tell-tales (mirrored verbatim).

## Curvature (1/km) the tractor drives at full steering lock — the scale that maps the
## contract's 'guidance_curvature' onto the -1..1 steer channel. 127 1/km is a 7.9 m turn
## radius, and it is deliberately the i8 maximum so the whole signal range is usable and a
## harder command simply sits on the stop.
const FULL_LOCK_CURVATURE := 127.0


func poll() -> Dictionary:
	var v := Bridge.get_input_values()
	if v.is_empty():
		return {"active": false}
	var out := {
		"active": true,
		"accel": clampf(float(v.get("accel", 0.0)) / 100.0, 0.0, 1.0),
		"brake": clampf(float(v.get("brake", 0.0)) / 100.0, 0.0, 1.0),
		"steer": clampf(float(v.get("steer", 0.0)) / 100.0, -1.0, 1.0),
		"handbrake": clampf(float(v.get("handbrake", 0.0)), 0.0, 1.0),
		"gear": int(v.get("gear", 0)),
		"key": int(v.get("key", 1)),
		"lights": int(v.get("lights", 1)),
		"horn": bool(v.get("horn", 0)),
		"turnL": bool(v.get("turnL", 0)),
		"turnR": bool(v.get("turnR", 0)),
		"brakeLamp": bool(v.get("brakeLamp", 0)),
		"checkEngine": bool(v.get("checkEngine", 0)),
		"battery": bool(v.get("battery", 0)),
		# ISOBUS implement inputs (tractor). Kept in contract units here (percent, flag);
		# arbitrate_bridge normalizes hitch_pos %→unit. Absent → raised/off (§6 default).
		"hitch_pos": clampf(float(v.get("hitch_pos", 100.0)), 0.0, 100.0),
		"pto": bool(v.get("pto", false)),
		"pto_mode": int(v.get("pto_mode", 0)),
		"diff_lock": bool(v.get("diff_lock", false)),
		"fwd_drive": bool(v.get("fwd_drive", false)),
		# Hydraulic remote (tractor). Contract % → 0..1 valve opening; absent → closed.
		"scv_flow": clampf(float(v.get("scv_flow", 0.0)) / 100.0, 0.0, 1.0),
		# Flight controls (plane/drone). elevator/climb are i8 %; normalize %→unit like
		# steer. arm is a bool. Absent → neutral/disarmed (arbitrate_bridge defaults them).
		"elevator": clampf(float(v.get("elevator", 0.0)) / 100.0, -1.0, 1.0),
		"climb": clampf(float(v.get("climb", 0.0)) / 100.0, -1.0, 1.0),
		"arm": bool(v.get("arm", false)),
		"flaps": clampf(float(v.get("flaps", 0.0)) / 100.0, 0.0, 1.0),
		# Train controls (train). Bools; absent → lowered/shut (arbitrate_bridge defaults them).
		"pantograph": bool(v.get("pantograph", false)),
		"doors": bool(v.get("doors", false)),
		# J1939 chassis (truck). retarder is a contract % → 0..1 request, like scv_flow; absent
		# → released. The three DM1 lamp bits pass through as bools for the dashboard tell-tales,
		# mirrored verbatim like turnL/turnR — absent → off, and never blinked locally.
		"retarder": clampf(float(v.get("retarder", 0.0)) / 100.0, 0.0, 1.0),
		"red_stop": bool(v.get("red_stop", false)),
		"amber_warn": bool(v.get("amber_warn", false)),
		"protect_lamp": bool(v.get("protect_lamp", false)),
		# ISO 11992 trailer bus (semi). The trailer's own fault lamp, passing through as a bool for
		# the dash tell-tale exactly like the DM1 bits — absent → off, never blinked locally.
		"trailer_ebs_fault": bool(v.get("trailer_ebs_fault", false)),
		# SAE J2497 / PLC4TRUCKS (the North American conventional). One power-line bit, passing
		# through as a bool for the dash telltale under the same rules — absent → off.
		"trailer_abs_lamp": bool(v.get("trailer_abs_lamp", false)),
		# CiA 422 body network (garbage truck), reached across the CiA 413 gateway. An enum byte
		# like pto_mode; absent → 0 Idle, the safe pose.
		"body_cmd": int(v.get("body_cmd", 0)),
	}
	# Boat rudder: included ONLY when sloppyCAN sends it —
	# presence is what makes it override 'steer' in arbitrate_bridge. Normalized %→unit
	# like steer.
	if v.has("rudder"):
		out["rudder"] = clampf(float(v.get("rudder", 0.0)) / 100.0, -1.0, 1.0)
	# Tractor guidance curvature: same presence rule as the rudder — included ONLY when
	# sloppyCAN sends it, because presence is what makes it override 'steer' in
	# arbitrate_bridge. Converted from 1/km to the steer channel's -1..1 here (the units
	# conversion, like steer's %→unit): FULL_LOCK_CURVATURE is the curvature the tractor
	# drives at full steering lock, so the command saturates exactly at the stop.
	if v.has("guidance_curvature"):
		out["guidance"] = steer_from_curvature(float(v.get("guidance_curvature", 0.0)))
	return out


## Guidance curvature (1/km) → the steer channel's -1..1. Pure/static so it is unit-tested
## like the arbitration rules; saturating at full lock is part of the conversion, not a
## fallback (a command for a tighter turn than the tractor can make sits on the stop).
static func steer_from_curvature(curvature: float) -> float:
	return clampf(curvature / FULL_LOCK_CURVATURE, -1.0, 1.0)

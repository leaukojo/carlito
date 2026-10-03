extends RefCounted
## What a hand on a wheel and a foot on a pedal do with an on/off key. A key asks for full lock or
## full pedal in one tick; a driver gets there over a few tenths of a second, and at speed turns
## the wheel ever more slowly, since the same angle makes ever more sideways g. Pure static steps:
## InputRouter owns the state, as it owns every local toggle.
##
## Local input only. The bridge is analog and drives exactly as sent, and so is the touch stick,
## so only the keyboard's steer is shaped; every local pedal (keys, touch buttons) is on/off and is
## shaped. Vehicles never see this: it is input, not a detuned spec (src/input/CLAUDE.md).

## Steer travel per second away from centre at a standstill, as a fraction of full lock.
const STEER_OUT_RATE := 0.9
## Road speed (m/s) at which the out-rate has halved. Above it the rate falls as 1 / v^2, which
## holds the sideways g a held key builds per second roughly level whatever the speed.
const STEER_V0 := 10.0
## Back toward centre (or through it) runs this many times faster than going out...
const STEER_RETURN_MUL := 3.0
## ...and never slower than this (fraction of lock per second): letting go straightens promptly.
const STEER_RETURN_MIN := 1.5

## Seconds for a pedal key to reach full travel, and to come back off it.
const ACCEL_APPLY_S := 0.4
const BRAKE_APPLY_S := 0.25
const PEDAL_RELEASE_S := 0.1


## Steer travel per second away from centre at this road speed (fraction of lock per second).
static func steer_out_rate(speed_ms: float) -> float:
	var r := absf(speed_ms) / STEER_V0
	return STEER_OUT_RATE / (1.0 + r * r)


## Steer travel per second back toward centre at this road speed.
static func steer_return_rate(speed_ms: float) -> float:
	return maxf(STEER_RETURN_MUL * steer_out_rate(speed_ms), STEER_RETURN_MIN)


## One tick of the shaped steer toward `target` (-1..1). Inward travel (toward centre, or toward a
## target nearer it on the same side) runs at the return rate; outward at the out rate. A reversal
## does both in one tick when it crosses centre mid-tick. Never overshoots the target.
static func steer_step(current: float, target: float, speed_ms: float, delta: float) -> float:
	if current == target or delta <= 0.0:
		return current
	var c := current
	var t := delta
	if c != 0.0 and (signf(target) != signf(c) or absf(target) < absf(c)):
		var stop := target if signf(target) == signf(c) else 0.0
		var dist := absf(c - stop)
		var in_rate := steer_return_rate(speed_ms)
		if in_rate * t < dist:
			return c + signf(stop - c) * in_rate * t
		c = stop
		t -= dist / in_rate
		if c == target:
			return c
	return move_toward(c, target, steer_out_rate(speed_ms) * t)


## One tick of a shaped pedal toward `target` (0..1): `apply_s` to full travel going down,
## PEDAL_RELEASE_S coming up.
static func pedal_step(current: float, target: float, apply_s: float, delta: float) -> float:
	var span := apply_s if target > current else PEDAL_RELEASE_S
	return move_toward(current, target, delta / maxf(span, 1e-6))

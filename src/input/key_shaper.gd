extends RefCounted
## What a hand on a wheel and a foot on a pedal do with an on/off key. A key asks for full lock or
## full pedal in one tick; a driver gets there over a few tenths of a second, and at speed turns
## the wheel ever more slowly, since the same angle makes ever more sideways g. Pure static steps:
## InputRouter owns the state, as it owns every local toggle.
##
## Local input only. The bridge is analog and drives exactly as sent, and so are the touch stick
## and the gamepad, so only the keyboard's steer is shaped; every key and touch pedal is on/off and
## is shaped. Vehicles never see this: it is input, not a detuned spec (src/input/CLAUDE.md).

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

## The player's KEY RESPONSE setting: how much of the timings above apply. Every time scales by
## it, so 0 passes the key straight through and 1 is the full hand-and-foot model. Cycled by the
## pause menu's SETTINGS page; the default sits near raw, for an arcade feel.
const SOFTENING_STEPS: Array[float] = [0.0, 0.15, 0.35, 0.65, 1.0]
const SOFTENING_LABELS: Array[String] = ["RAW", "ARCADE", "BALANCED", "SMOOTH", "REALISTIC"]
const DEFAULT_SOFTENING := 0.15


## The step after `amount`, wrapping; an off-step value goes to the first step above it.
static func next_softening(amount: float) -> float:
	for step in SOFTENING_STEPS:
		if step > amount + 1e-4:
			return step
	return SOFTENING_STEPS[0]


## The label of the step nearest `amount`.
static func softening_label(amount: float) -> String:
	var best := 0
	for i in SOFTENING_STEPS.size():
		if absf(SOFTENING_STEPS[i] - amount) < absf(SOFTENING_STEPS[best] - amount):
			best = i
	return SOFTENING_LABELS[best]


## Steer travel per second away from centre at this road speed (fraction of lock per second).
static func steer_out_rate(speed_ms: float) -> float:
	var r := absf(speed_ms) / STEER_V0
	return STEER_OUT_RATE / (1.0 + r * r)


## Steer travel per second back toward centre at this road speed.
static func steer_return_rate(speed_ms: float) -> float:
	return maxf(STEER_RETURN_MUL * steer_out_rate(speed_ms), STEER_RETURN_MIN)


## One tick of the shaped steer toward `target` (-1..1). Inward travel (toward centre, or toward a
## target nearer it on the same side) runs at the return rate; outward at the out rate. A reversal
## does both in one tick when it crosses centre mid-tick. Never overshoots the target. `softening`
## scales every travel time (0 = the key as pressed).
static func steer_step(current: float, target: float, speed_ms: float, delta: float,
		softening := 1.0) -> float:
	if current == target or delta <= 0.0:
		return current
	if softening <= 0.0:
		return target
	var c := current
	var t := delta / softening
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
## PEDAL_RELEASE_S coming up, both scaled by `softening`.
static func pedal_step(current: float, target: float, apply_s: float, delta: float,
		softening := 1.0) -> float:
	var span := (apply_s if target > current else PEDAL_RELEASE_S) * softening
	return move_toward(current, target, delta / maxf(span, 1e-6))

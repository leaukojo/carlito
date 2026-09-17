# Plan: a light, stepped brake trips `trailer_abs`

Opus, effort **high**, mode: measure-then-fix (log first, propose the fix in a short reply,
implement after a nod). Delete this file when done.

## Problem

On the `semi` with the laden box trailer (`truck_trailer_abs` challenge) any STEPPED brake
percentage, even a light one, trips `trailer_abs` almost at once at 40-50 km/h. Only a brake
ramped from 0 over ~8 s avoids it, and even that trips in the last few km/h unless released to a
coast under ~12 km/h. Truck 4 is barely playable (its course box is 240 m long,
`truck_trailer_abs_course.tscn`) and this is probably not real behaviour.

## Prompt

Read `src/vehicles/truck/CLAUDE.md` § Brakes first. Log per-tick trailer wheel slip around a
light brake step (scripted-bridge driver, `--fixed-fps 60`) and rank these hypotheses with data:
1. A one-tick slip spike: `trailer_abs` is the worst trailer wheel's slip > 0.30 on ANY tick
   (`truck_telemetry.gd` `trailer_abs_active`, `towed_body.gd` `max_wheel_slip`), and
   `Wheel._integrate_spin` applies the brake as an explicit `move_toward` AFTER the semi-implicit
   reaction step, so a step can strip a light wheel's spin before the tyre answers next tick.
2. The low-speed denominator: slip divides by `max(|v_long|, LOW_SPEED_FLOOR)`.
3. Oversized trailer brakes: semis and trailers are hand-tuned, not grip-derived like the Kenney
   specs, so full demand may simply exceed the tyre.
Candidate fixes, cheapest first: a ~0.1 s persistence before `trailer_abs` sets (a real ABS
cycle is about that long; telemetry only); re-sizing trailer brake torque; bringing the brake
into the implicit spin step (touches every wheeled vehicle: re-run `measure_vehicles` and the
brake tests). Then shorten the `truck_trailer_abs` box and re-write its briefing. Record the
conclusion in `src/vehicles/truck/CLAUDE.md` in one line.

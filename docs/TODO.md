# TODO — remaining work

## A locked handbrake never releases, at any throttle

`Drivetrain.wheel_engine_rpm` derives engine rpm directly from driven-wheel omega — no clutch,
no torque converter. Once the handbrake locks a wheel (omega settles to 0), `process()`'s
`target_rpm` clamps to `idle_rpm` regardless of throttle, so the torque curve is sampled near idle forever.
Confirmed with a scratch test (flat ground, handbrake full on, 100% throttle held): a ~0.1 s
launch transient lets the wheel slip a few cm (rpm briefly spikes to ~2500), then it re-settles
to zero, rpm collapses back to idle, and the car sits completely still — for as long as the test
ran (6 s), at full throttle the whole time. In a real car, full throttle against the handbrake
eventually spins the tires or stalls the engine against the resistance; here it just holds
forever once the wheel re-locks; nothing breaks it free again short of releasing the handbrake.

This blocks the "handbrake + throttle" hill-start technique, one reason the hill start is parked
(`docs/challenge_ideas.md` § Parked). Fixing it properly likely means giving the engine some way
to rev independent of a truly stalled wheel (a slip/clutch model, or a floor on transmissible
torque that isn't purely rpm-curve-driven) — a drivetrain model change, not a one-line fix.

## A light, stepped brake trips `trailer_abs`

Measured on the `semi` with the laden box trailer (`truck_trailer_abs` challenge): any STEPPED
brake percentage, even a light one, trips `trailer_abs` almost at once at 40-50 km/h. Only a
brake ramped from 0 over ~8 s avoided it, and even that tripped in the last few km/h unless
released to a coast under ~12 km/h. That makes Truck 4 barely playable (its `Box` is 240 m long
to leave room) and is probably not real behaviour. Unverified hypotheses, in order:

- **A one-tick slip spike.** `trailer_abs` is the worst trailer wheel's slip > 0.30 on ANY tick
  (`truck_telemetry.gd:118`, `towed_body.gd:max_wheel_slip`). `Wheel._integrate_spin`
  (`wheel.gd:194`) applies the brake as an explicit `move_toward` AFTER the semi-implicit
  reaction step, so a brake step can strip a light wheel's spin in one tick before the tyre force
  answers on the next.
- **The low-speed denominator.** Slip divides by `max(|v_long|, LOW_SPEED_FLOOR)`, so near a
  stop a small speed error reads as a large ratio.
- **Oversized trailer brakes.** The semis and trailers are hand-tuned, not grip-derived like
  the Kenney specs, so full demand may simply exceed the tyre.

Start by logging per-tick trailer wheel slip around a light brake step. Candidate fixes: a
~0.1 s persistence before `trailer_abs` sets (a real ABS cycle is about that long; telemetry
only), bringing the brake into the implicit spin step (touches every wheeled vehicle — re-run
`measure_vehicles` and the brake tests), or re-sizing the trailer brake torque. Then re-tune the
`truck_trailer_abs` course box and its briefing.

## The farm has no split-grip mud and no varying soil

`tools/gen_farm_playground.gd` paints level_1's WALLOW as uniform Mud (channel 5, grip 0.5) and
the FIELD as uniform channel-4 soil, both through `stamp_splat` with `falloff = 0.0`. So
`tractor_mud` passes in plain 2WD (13.9 s against 14.1 s with `fwd_drive`) and `tractor_plough`'s
draft never changes along the row; both ship as warm-ups for now. Fix in the generator: a
split-grip patch (one side firmer; see `docs/challenge_ideas.md` § Tractor 2 for why uniform mud
leaves the diff lock useless) and a soil weight that varies along the plough row. Then re-bake +
`check_bakes`, confirm a 2WD FAIL and a diff-lock/MFWD PASS on Tractor 2, and restore the lessons
in both defs' briefings and hints (`src/challenges/defs/tractor_mud.tres`, `tractor_plough.tres`).

## No sloppyCAN dashboard for the train or the plane

sloppyCAN has a vehicle panel per family (`drone.js`, `truck.js`, `tractor.js`, `boat.js` on
`vehicle-panel.js`). Train and plane were left out because each panel is reached from a protocol
tab or mode — DroneCAN, J1939, ISO 11783, NMEA 2000 — and there is none for either. Detection
needs no contract change: both families already have exclusive `dir:'out'` signals.

## Truck model hygiene (per-axle springs, spring-brake notice, honest tests/tools)

Five phases, each measured before the next, in `docs/plans/truck_model_hygiene.md`. Biggest
payoff is the per-axle spring rate: every truck rides nose-up (the Kenney ones on their rear
stops) because one rate serves a rear axle carrying 2-3x the front's load.

## Shader warmup misses post-load materials

`ShaderWarmup` compiles every material the level holds at load (hidden instances included),
but gl_compatibility still compiles synchronously on the first draw of anything that arrives
later: a V / garage body swap, an E attachment or trailer, and the light-count variants when
headlights or night first light a material. Each shows as a one-frame hitch on web. A fix is a
warmup pass per swap (instantiate the body off-screen for a frame with grown cull margins) and
a load-time frame with headlights on; not a one-liner, needs a hitch measurement first.

## Bake output is not byte-deterministic

A full `bake_levels` run rewrites the `output_hash` of levels whose `input_hash` did not change
(seen on level_1/2/4/5 after touching only the sun in three other levels). Every re-bake therefore
dirties every manifest. Something in the bake serialises in varying order (dictionary iteration,
sub-resource ids or generated uids are the usual suspects). Find it, or hash a canonical form.

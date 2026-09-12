# TODO — remaining work

## A locked handbrake never releases, at any throttle

`Drivetrain.wheel_engine_rpm` (`src/vehicles/base/drivetrain.gd:87-91`) derives engine rpm
directly from driven-wheel omega — no clutch, no torque converter. Once the handbrake locks a
wheel (omega settles to 0), `process()`'s `target_rpm` clamps to `idle_rpm`
(`drivetrain.gd:264`) regardless of throttle, so the torque curve is sampled near idle forever.
Confirmed with a scratch test (flat ground, handbrake full on, 100% throttle held): a ~0.1 s
launch transient lets the wheel slip a few cm (rpm briefly spikes to ~2500), then it re-settles
to zero, rpm collapses back to idle, and the car sits completely still — for as long as the test
ran (6 s), at full throttle the whole time. In a real car, full throttle against the handbrake
eventually spins the tires or stalls the engine against the resistance; here it just holds
forever once the wheel re-locks; nothing breaks it free again short of releasing the handbrake.

This blocks the "handbrake + throttle" hill-start technique in `docs/challenge_ideas.md` (Car 13)
exactly as designed — see the warning in `docs/plans/challenges.md`. Fixing it properly likely
means giving the engine some way to rev independent of a truly stalled wheel (a slip/clutch
model, or a floor on transmissible torque that isn't purely rpm-curve-driven) — a drivetrain
model change, not a one-line fix. Scope it before Phase 3 of the challenges plan touches Car 13,
or drop the handbrake-hold pass condition for that challenge.

## No sloppyCAN dashboard for the train or the plane

sloppyCAN has a vehicle panel per family (`drone.js`, `truck.js`, `tractor.js`, `boat.js` on
`vehicle-panel.js`). Train and plane were left out because each panel is reached from a protocol
tab or mode — DroneCAN, J1939, ISO 11783, NMEA 2000 — and there is none for either. Detection
needs no contract change: both families already have exclusive `dir:'out'` signals.


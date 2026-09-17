# Plan: respawn is a reset

Opus, effort **high**, mode: plan-then-implement (one agent reads, proposes the hook shape in a
short reply, then implements after a nod). Delete this file when done.

## Problem

`BaseVehicle.respawn()` resets pose, velocity and wheels; everything else survives — fuel,
coolant, SoC, engine hours, the drone's `_armed_prev`, InputRouter's latched hardpoint toggle,
a carried crate. `ChallengeRunner.restart()` promises "same aux state every attempt" and got it
by rebuilding the body. Three round-two findings traced to this one gap, and every new stateful
subsystem will add another.

## Prompt

Read `src/vehicles/base/base_vehicle.gd`, every family's `respawn()` override, `InputRouter`'s
per-vehicle state (`register_vehicle`), `ChallengeRunner.start/restart`, `TowHost`, `DroneHook`.
Design ONE reset seam: `BaseVehicle.reset_session_state()` (name it as the codebase would),
called by `respawn()` after the teleport and by `register_vehicle`; each family overrides to
reseed its telemetry/aux models and release attachments; InputRouter clears its latched toggles
through the same call (rule 5: arbitration state stays in `src/input/`). Decide and document
which of the two respawn semantics is canonical (pose-only vs fresh body) and make
`ChallengeRunner.restart()` use the seam instead of rebuilding, unless rebuilding is required for
a reason you can state. Add a gdUnit4 test per family that respawns after draining fuel/SoC and
asserts the reseed. Record the rule in `src/vehicles/CLAUDE.md` in one line.

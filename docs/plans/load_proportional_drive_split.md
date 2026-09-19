# Plan: the open diff across every driven wheel kills traction on rough or soft ground

Opus, effort **high**, mode: **plan-mode first** (pick the split model, justify it), then
accept-edits. Delete this file when done; distil into `src/vehicles/CLAUDE.md` § Wheels,
suspension and the 60 Hz tick and § Drivetrain and brakes.

## Problem

`WheelDrive.tick` splits drive torque evenly per driven wheel (`axle_torque / _driven_count`) —
an open differential across every driven wheel, including across axles. Total thrust is therefore
`driven_count x the weakest wheel's grip`. On a bump one lightly-loaded wheel spins up (measured
at slip 20-40, engine on the limiter) and starves three loaded wheels, so a wheeled vehicle on
uneven or soft ground loses almost all tractive force. Both `CLAUDE.md` bullets above currently
document the even split as a known limitation.

## Prompt

Make the split **load-proportional**: each driven wheel takes the share of axle torque its normal
load carries. Last tick's `RayWheel.suspension_force` is the only load available at that point in
the tick (this tick's springs are not read yet); fall back to an even split when no driven wheel
carries load. **Weigh a grip-aware and an axle-locked variant against it first and say why you
chose what you chose** — do not land the edit before that argument exists.

Then do the whole re-derivation, not just the edit:

- **Evidence level.** Build a dev roughness level (unregistered, F6-runnable, a real Level with a
  VehicleSpawn) with patches of increasing unevenness in two lanes, asphalt and mud, plus a
  headless tool that drives a variant through each patch and reports crossed/stuck. Before/after
  on that tool is the evidence.
- **Suite.** Run gdUnit, especially `test_vehicle_catalog`'s force-hierarchy test and
  `test_wheel_spin`.
- **Sweeps stay with the user.** Every acceleration and tracking figure moves. Hand over
  `measure_vehicles -- all 45`, `measure_vehicles -- all 45 track strict` and `measure_grade`
  rather than running them, and name exactly which numbers in `docs/vehicles.md` to expect to
  change.
- **Docs.** Rewrite the two `CLAUDE.md` bullets that describe the even split, and the MFWD claim
  that rests on it — present-state, no history.

## Known from a previous attempt

Load-proportional took the SUV on mud from stuck on random bumps (and slow everywhere) to
crossing everything except a 50 cm V-ditch wall — which is genuinely above the
`tan a <= mu*grip - crr` = 16.7 deg ceiling for mud and should stay impossible. Flat-ground
launch also got faster. Decide whether that is desirable or wants a bias limit (a cap on how far
one wheel's share may exceed an even one).

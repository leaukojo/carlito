# Plan: the driven axle turns a small load difference into a large force difference

Effort **high**, mode: **plan-mode first**, then accept-edits. Opus. Delete this file when done;
distil into `src/vehicles/CLAUDE.md` § Wheels (and delete the stopgap note in
`gen_kenney_vehicles.gd`'s `race` entry).

## CI is red on this right now

`.github/workflows/ci.yml`'s `tracking` job runs `measure_vehicles -- all 45 track strict`, which
exits 1 on any FAIL, and `deploy` is `needs: [build, tracking]`. `hatchback-sports` FAILS
(1.071 m drift / 0.348 deg heading over 200 m), so **dev does not deploy until this is fixed or
the body is given a workaround**. That is the reason this plan is not "nice to have".

## Problem

A body accelerating in a straight line with zero steer input picks up a heading error in the
first ~4 s and then holds it. Measured on `race` at `anti_roll_rate` 7000, mid-launch:

| | left | right | difference |
| --- | --- | --- | --- |
| rear suspension compression | 0.0900 m | 0.0868 m | 0.8 % |
| rear longitudinal tyre force | 3803.8 N | 3220.6 N | **18 %** |

583 N at a 0.63 m half-track is a real yaw moment, and nothing steers it back. By f=360 the axle
is symmetric again and the bar reads ~0 — the drift is already banked.

**An 0.8 % load difference must not produce an 18 % force difference.** That ratio is the defect;
the anti-roll bar is only what creates the load difference in the first place. Suspects, in order:
the per-wheel drive-torque split in `WheelDrive` / `Drivetrain`, and `RayWheel.load_scaled_mu`.

What is already ruled out, so it is not re-litigated:

- **Not the COM heights** and **not `mu_lat`.** Those were the first guesses; neither moves it.
- **Not the axle pairing.** Every wheel's `anti_roll_partner` was printed and is correct.
- **Not body asymmetry.** `wheel_positions` are symmetric in x on every failing body.
- **Not the bar's uncancelled residue.** Wheels tick in array order, which used to leave the
  pair's two forces mismatched (+28.1 / -22.3 N on a `race` axle). That is fixed — both wheels
  read `RayWheel._bar_compression` now — and the drift did not move (1.148 -> 1.178 m).
- **Not tunable via the bar rate.** Drift scales with rate on `race` (0 -> 0.001 m, 2000 -> 0.633,
  7000 -> 1.148) but NOT monotonically across bodies: `hatchback-sports` at 3500 measures
  1.392 m, WORSE than at 7000. No rate satisfies both roll and tracking.

## Reproducers

`measure_vehicles -- hatchback-sports 45 track` is the live one (FAIL, ~1.07 m). Set
`anti_roll_rate` to 0 in `hatchback-sports_spec.tres` and it PASSES at 0.029 m — that is the
switch that isolates the mechanism, not a fix (the body then rolls 12.2 deg and lifts a wheel).

`race-future` PASSES at 0.067 m, ~25x the fleet norm of ~0.003 m. It is the canary: the amplifier
is live fleet-wide and the straight-line gate is only where it happens to cross 1.0 m.

## The stopgap to undo

`race` ships with `"anti_roll_rate": 0.0` in the recipe purely to clear it off the gate. It cost
nothing measurable there (roll at the grip peak 5.6 deg without the bar against 3.3 with it, both
inside the 4-8 deg target), which is why that body and no other could give its bar up. **Restore
CAR_BASE's 7000 on `race` as the last step of this plan** and confirm it tracks — that is the
real proof the amplifier is gone.

## Verify

`measure_vehicles -- all 45 track strict` (the CI gate itself, multi-minute — the user runs it),
plus `-- <variant> 45 corner` on every bar-carrying body to confirm roll at the grip peak has not
moved: pickup 6.7, pickup-flat 6.8, race 5.6 (bar off) / 3.3 (bar on), suv 13.6, van 5.2,
delivery 4.4, sedan 5.3 deg. The gdUnit suite must stay green (1649 cases).

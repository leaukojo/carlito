# 2026-11-26: gather for the standing rig's flake

Item: "Gather for the standing rig's flake" (Sonnet). No code changed. HEAD 88ba4c5, 16-core
machine, no other Godot run alongside (runs were sequential under `godot_run`'s lock).

## Runs

| Run | Count | Result |
|-----|-------|--------|
| `tests/test_tow_host.gd` alone, `-a tests/test_tow_host.gd` | 10 | 10 pass, 55/55 cases each, 9.2 to 9.5 s |
| the same file plus a one-line `print` of skew and peak rate (scratch copy `tests/zz_probe_tow_host.gd`, deleted; everything else identical) | 10 | 10 pass, 55/55 |
| the probe copy with `--fixed-fps 60` before `-a` | 5 | 5 pass, 55/55, 4.5 s (half the wall time) |
| full suite `-a tests` | 3 | 3 pass, 2637/2637 each, 108 s |

## Figures (the probe, every one of the 15 probe runs read the same to 6 decimals)

| Kind | skew (rad) | peak relative yaw rate (rad/s) | coupled |
|------|-----------|-------------------------------|---------|
| semi | -0.000000 | 0.000000 | yes |
| tractor | -0.000003 | 0.000006 | yes |

The test's limits are 1e-3 rad and 1e-4 rad/s. The tractor sits at 0.3 % of the first and 6 % of
the second. `--fixed-fps 60` changes neither figure.

## Reading

- The run is deterministic at HEAD: 25 runs of the file (10 + 10 + 5), 3 inside the suite, no
  failure and no early stop. The earlier failure (c2847f4: tractor skew 0.0727 rad, rate
  0.141 rad/s, semi -0.00287 rad, ~40 of 55 cases run) is 4 orders of magnitude over what HEAD
  reads and has not recurred; 116 commits sit between c2847f4 and HEAD (the two that touch
  `src/vehicles/base` or the test file: 95e8029, 92c4303, neither towing).
- A run that stops at ~40 of 55 cases is not the test failing: gdUnit4 runs a failed case to the
  end and goes on. An early stop is the process dying or being killed (a second Godot started on
  the checkout, a timeout, a crash), and a rig read in a run under such load or on a stalled
  physics step would give the large skew.
- Hypotheses for a later diagnose, none tested: (1) the failing runs were a different checkout
  state (an uncommitted edit or a stale `.baked.scn`/import cache at c2847f4); (2) a Godot run
  started alongside, so the physics server stepped irregularly; (3) fixed by a commit since.

## Result

The flake did not reproduce, so the diagnose line has no failing run to compare against: it is
not ready (skill § Diagnose only: "an item whose figures are missing is not ready"). It waits for
the next failure, kept as output with the commit hash and whether another Godot ran.

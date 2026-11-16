# 2026-11-16: standing bodies alternate on the rolling moment's patch (Queue A2, Opus)

Started at 0cd8c31. Gather plus one test, nothing fixed. HEAD = 0cd8c31 (code as c903d45);
patch = HEAD + `2026-11-15-rolling-moment.patch`; test = patch + the A2 law (below). Three
detached worktrees outside the repo (`.godot/` copied), removed after. Logs, the probe diffs and
the table script stay in `C:/Users/Ccamy/AppData/Local/Temp/claude/rm-logs/a2/` (`rest_<tree>.log`,
`cross_<tree>.log`, `probe_head.diff`, `test_on_patch_wheel.diff`, `tab.py`, `run.sh`).

**Verdict: the A2 law does not bring both back. Hand-back to Fable (Queue A2).** The bobtail
reads worse with it; the cross cell reads quiet with it only because its rest pose moved off a
discontinuity of the contact query. In both cases the first term to step is `compression`, not
anything along the wheel.

| run | HEAD | patch | test |
| --- | --- | --- | --- |
| bobtail `rest reading:` axle step | 0.11 kg | 0.34 kg | **0.59 kg** (sign changes 2.7 /s, the others 0.7) |
| 10 % cross, FL `suspension_force` alt after 15 s | 0.10 N | 69.66 N | 0.17 N |
| 10 % cross printed line | +3.0 / -0.7 mm, 0.045 m/s | same | +3.3 / -0.5 mm, 0.050 m/s |

## The probe

The gather's (`2026-11-16-gather-rolling-moment.md` appendix, with `park_cell=`) plus, per wheel:
`compression`; `dcomp` (its difference over the tick, what the damper reads); the four terms of
`suspension_force` (`spring_rate * compression`, the clamped damper force, `bar_force`,
`link_slope * force_long`), stored in `tick` as probe fields; `_stick.x`, `_patch_spring.x`,
`long_cap`; `a` = the slope of `combined_slip_force`'s x in the slip speed at the wheel's slip, times
`delta / _patch_long_mass` (1 = the slip curve stops the contact in one tick). Runs, each tree,
`--fixed-fps 60`:

```
timeout 600 node tools/godot_run.mjs -- --headless --path . --fixed-fps 60 res://tools/measure_semi_launch.tscn -- semi steady strict trailer=bobtail
timeout 900 node tools/godot_run.mjs -- --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- doc=park park_cell=semi:cross:5.7
```

The test, in `RayWheel._slip_force` before the caps:
`if omega == 0.0: tyre.x = clampf(_patch_long_mass * slip_vel / _patch_delta, -_patch_budget.x, _patch_budget.x)`.

## 1. Bobtail, rest window: `compression` steps first, by 1.8 µm

Rear left (driven), patch. `link` is 0 on every tick (`link_slope` 0 on this body); `_stick.x`
and `_patch_spring.x` are 0 (no wheel is `_patch_held`).

| tick | susp | spring | damper | bar | dcomp (m) | force_long | a |
|---|---|---|---|---|---|---|---|
| 438 | 18765.63 | 18765.52 | 0 | 0.1146 | 0 | 0.0703 | 0.9274 |
| 439 | 18761.96 | 18764.88 | -3.0382 | 0.1146 | -1.758e-06 | 0.0704 | 0.9272 |
| 440 | 18768.25 | 18765.52 | 2.6057 | 0.1288 | 1.758e-06 | -0.7588 | 0.9275 |
| 441 | 18761.55 | 18764.81 | -3.3821 | 0.1146 | -1.957e-06 | 0.5993 | 0.9272 |
| 442 | 18764.81 | 18764.81 | 0 | -1.9e-04 | 0 | -1.5476 | 0.9272 |

- Both rears step at tick 439 (RR -1.788e-06 m, damper -3.09 N), in the tick the body's pitch rate
  jumps (-5.83e-05 -> -4.89e-05 rad/s); `force_long` moves a tick later (-0.76 N); both fronts step
  at 441 (+3.4 and +3.9 µm, damper +2.7 and +3.1 N). The spring term moves 0.6 N; the damper's
  finite difference makes the step a 3 N force.
- Between steps `compression` is flat to the digit for 3 to 6 ticks while the body pitches at
  -5.8e-05 rad/s (about 1 µm a tick at the rear's arm) and creeps forward at 6e-05 m/s, its speed
  growing 6e-07 m/s a tick under the four wheels' +0.07 N each (0.29 N on 7.6 t: 3.8e-05 m/s², as
  measured). The contact's drop moves in steps the body's motion does not explain tick by tick.
  The body sits 2800 m along the strip (`pos` z 2800.0017, constant to the digit over the window:
  the float32 spacing there is 0.24 mm); not traced further.
- HEAD, same window: `compression` flat on every tick (`dcomp` 0); what moves is `bar`
  (-0.80 / +0.11 N on a 4-tick pattern), the partner's compression.
- `a`: rears 0.927, fronts 1.000. The rears (lowest) step first, but the test, which puts every
  standing wheel at the one-tick stop, reads 0.59 kg: the alternation is not the curve's
  under-damping.

## 2. 10 % cross: `compression` snaps onto the sweep's bracket edge

Front left, patch (`link` 0; the wheel is `_patch_held`, so `pspring_x` carries the hold):

| tick | susp | spring | damper | bar | dcomp (m) | force_long | pspring_x | a |
|---|---|---|---|---|---|---|---|---|
| 770 | 31264.90 | 26973.94 | 6.3487 | 4284.62 | 7.838e-06 | -2600.28 | -2593.81 | 0.6788 |
| 771 | 31380.54 | 27000.00 | 87.9587 | 4292.58 | 1.086e-04 | -2607.80 | -2603.52 | 0.6809 |
| 772 | 31348.33 | 27000.00 | 0 | 4348.33 | 0 | -2613.79 | -2602.72 | 0.6801 |
| 773 | 31212.98 | 26974.38 | -114.67 | 4353.27 | -1.068e-04 | -2605.60 | -2596.06 | 0.6775 |
| 774 | 31393.94 | 27000.00 | 86.4817 | 4307.46 | 1.068e-04 | -2610.39 | -2612.04 | 0.6810 |

- The spring term reads 27000.00 exactly: `compression` 0.1125 m, a drop of 0.2075 m = 166/256 of
  the 0.32 m travel. `cast_motion`'s fractions sit on a 1/256 grid (1.25 mm of drop; read off the
  values, 166, 153 and 156/256 recur to the digit, not from the engine's source), and
  `settled_drop` clamps the gap-corrected drop into `[safe_drop, unsafe_drop]`
  (`wheel.gd:823-824`). The corner sinks about 4 µm a tick toward the edge (spring +1 N a tick at
  770); on the edge the drop snaps to it, off it the drop reads 0.107 mm deeper: a discontinuity of
  0.107 mm in the contact's drop, which the damper turns into +88 / -115 N. `settled_drop`'s doc
  says "exact on a face"; this wheel stands on a face.
- Where each tree's FL rests after 15 s: HEAD 0.112356 m (0.14 mm short of the edge), patch on it
  (0.1125 on 1721 of the hold's 3601 ticks), test 0.112515 (0.015 mm past it, 315 ticks on it,
  quiet). The
  other wheels that rest on the grid (the trailer's 5.20 L at 153/256 in all three trees, the
  test's rear left at 156/256) do not alternate: an edge alone holds still; a corner sinking
  across it does not.
- Per wheel after 15 s, patch: FL 69.66 N (a 0.679), FR 22.97 N (a 0.468, the lowest on the unit),
  rears 2.1 N (a 1.000 / 0.815), trailer 0.01 to 0.08 N (a 0.53 to 1.00). The wheels with the
  lowest `a` (FR, the trailer's right side) do not lead; the one on the edge does.
- The patch's only change to a brake-held wheel is `surface_drag_force` gone; that moved the
  FL's rest pose 0.14 mm, onto the edge. The edge is in the contact query at HEAD.

## For other items (seen, not acted on)

- `settled_drop`'s 0.107 mm jump on a face is unit 3a's contact code (`_contact_pass`,
  `settled_drop`, `cylinder_support`): the Fable line's subject.
- The measure strip puts the semi 2800 m from the origin: the "To consider" item on the 6 km
  strip (`2026-11-14-sweep-rest-disagree.md`) may own the bobtail's 1.8 µm steps.

## Deferred

The cause of both: Queue A2, now `diagnose ... Fable`. A3 stays after it.

## Commits

The journal's only.

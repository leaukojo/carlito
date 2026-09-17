# Plan: split-grip mud and varying soil on the farm

Sonnet, effort **medium**, mode: direct. Delete this file when done.

## Problem

`tools/gen_farm_playground.gd` paints level_1's WALLOW as uniform Mud (`CH_MUD`, grip 0.5) and
the FIELD as uniform `CH_FIELD`, both through `_paint()` → `stamp_splat` with `falloff = 0.0`.
So `tractor_mud` passes in plain 2WD (13.9 s against 14.1 s with `fwd_drive`: uniform mud gives
the diff lock nothing to do) and `tractor_plough`'s draft never changes along the row. Both defs
are titled `[NOT-TESTED]`.

## Prompt

Read `kit/CLAUDE.md` and `src/levels/CLAUDE.md` first. In the generator (seeded, destructive-
by-button, never per-frame): paint the wallow as a split-grip patch, one side firmer, so one
driven wheel spins while the other holds, and give the plough row a soil weight that varies
along its length. Re-bake + `check_bakes`. Measure with the scripted-bridge driver: Tractor 2
must FAIL in 2WD and PASS with diff lock or MFWD; Tractor 3's `engine_load` must visibly change
along the row. Then rewrite both defs' briefings and hints around that lesson
(`src/challenges/defs/tractor_mud.tres`, `tractor_plough.tres`) and drop `[NOT-TESTED]`.

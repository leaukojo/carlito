# Plan — Tools: one copy of each measure, generator and gate helper

`tools/` repeats the same setup across the measure tools (spawn, spec overrides, PI hold, labels,
CLI parsing), the vehicle and level generators, and the CI / hook / preflight gates. This plan
folds each into one home, in the order the review proposes, with each step checked by a replay or
a `doc=` rerun. Findings: `reviews/C_tools_dedup.md` (its summary table and suggested order). L5
(hand-templated `.tscn`) is not recommended there and stays out.

Written 2026-11-05. Status: **not started.**
Serves: authoring tools that stay deterministic and cheap to change.
State: done — H1 resolver, H3 `--check` (partly); next — phase 1; open findings — none.

## Phase 1 — `MeasureRig` (effort: high; mode: plan-mode-first)

- M1–M7: `MeasureRig.spawn`, `own_ground_drive`, `pi_hold`, the trailer-roll table, the labels,
  the variant lists (a new `spec_of` on `VehicleCatalog`), `rig_bodies` / `towed_mass`.
- No bake risk. Check: every `doc=` preset re-run in the background (`--fixed-fps 60`), with the
  regions unchanged. Compare like with like: a lone run against a lone run.
- Done when every region is byte-identical.

## Phase 2 — Vehicle generators (effort: medium; mode: accept-edits)

- K1: one new shared vehicle-generator IO script in `tools/`. K2: `_axles` through `BrakeSizing.axle_geometry`.
- Check: a regen leaves the shipped bodies with no git diff, and `test_kenney_variants` /
  `test_boat_variants` are green.

## Phase 3 — Gate helpers (effort: medium; mode: accept-edits)

- H1 rest: the `.ps1` copy, pre-commit and the runs that bypass `godot_run.mjs`.
- H3 rest: pre-commit, `preflight.ps1` and the Stop hook call `gen_js_contract.mjs --check`.
- H2: the annotation regex folds into `check_gd_text.mjs`, and `tools/godot_verdict.mjs
  --bakes|--errors` replaces the bake-verdict and leak-noise copies.
- Check: `preflight.ps1` passes, a deliberately stale bake and a staged bad file each fail, and a
  CI run on a branch is green.

## Phase 4 — Level generators (effort: high; mode: plan-mode-first)

- L1, L2 and L4. Then L3 in tools only; RoadPath waits for a rebake, since editing it re-stales
  six levels.
- Check: each `rebuild_level.ps1 -Level <id>` replay diff is empty, then `check_bakes`. Follow the
  `level-edit` skill.

## Phase 5 — The rest (effort: medium; mode: accept-edits)

- M8–M10, T1, T2 and the review's dead-code list (including widening `check_orphans.mjs` to `tools/`).
- M11 goes in its own commit, since it moves measured figures. Regenerate the `doc=` regions it
  touches in the same commit.

# Plan — Test suite: assertions that can fail, shared fixtures, missing tests

Some tests cannot fail, some sweeps pass on an empty fixture, one test fails on an unbaked clone
without saying why, fixtures are copied across files, and two pure pieces of rule-8 logic have no
test. Findings: `reviews/D_tests.md`, sections 1–8 (numbers below are that file's).

Written 2026-11-05. Status: **not started.**
Serves: rule 8, a green suite that means the logic holds.
State: done — nothing; next — phase 1; open findings — none.

## Phase 1 — Tests that cannot fail (effort: medium; mode: accept-edits)

- 1.1: drive `body_cmd_toggle` edges through the router.
- 1.2: assert the lug guard against `shift_down_rpm`.
- 1.3: a non-multiple tick case.
- 1.4: delete the tautology.
- 1.5: drive the wheel and assert the applied force.
- 1.6: delete `test_tow_host.gd:577` and the `:195` equality. First check on Godot 4.7 whether a
  subclass `const` can shadow its parent's (`:1232`).
- 1.7: fix or rename the three over-promising tests. The GPS figure needs a cited geodesic value
  from a page actually opened.
- 2.1: the non-null guard goes into `_spec_of` (see phase 2's shared helper).
- 2.2 and 3.1: `weight_text` tested on a `user://` probe, and the shipped-level check declares
  its bake dependency.
- Done when each fixed test is shown to fail on a deliberately broken implementation (one quick
  local edit each, reverted), and the suite is green.

## Phase 2 — Shared fixtures and table-driven tests (effort: medium; mode: accept-edits)

- 5.1: a new shared helper script in `tests/` with `root_property` and `spec_of` (non-null
  assert).
- 5.2: one shared minimal bakeable level.
- 5.3: one `idle_router()`.
- 5.4: the small copies.
- 4.1: two table-driven tests (toggle and cycle edges survive `merge_local`; the
  `[key, sent, field, absent_default]` bridge table). The per-feature tests keep only their
  non-generic parts. Builds on `docs/plans/17_gameplay_architecture.md` phase 1, which
  rewrites `merge_local` first.
- Done when the suite is green with the same test count minus the merged ones.

## Phase 3 — Duplicates (effort: low; mode: accept-edits)

- Section 4's table and 4.2 (golden values instead of run-twice).
- Done when the suite is green.

## Phase 4 — Missing tests and small notes (effort: medium; mode: accept-edits)

- 6.1: `Bridge._all_finite` / `_is_instance_array` cases.
- 6.2: `ground_snap.ray_plane` and `road_draw_tool._to_world_curve`, including scaled and
  mirrored transforms.
- 6.3: heading at 45° and just west of north.
- 7: the `1e-6` rpm tolerances become `1e-3`, and the loose `assert_bool(a < b)` calls become
  `assert_float` where a failure needs the value.
- 8: the small notes.
- Done when the suite is green.

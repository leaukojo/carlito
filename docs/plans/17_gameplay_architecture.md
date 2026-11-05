# Plan — Gameplay architecture: input, dashboard, composition, UI helpers

The rest of the gameplay review. The LAB page looks live while sloppyCAN owns the input.
`merge_local` lists every key by hand, and two cycles bypass `cycles.gd`. The dashboard's in-lamp
map is a hand mirror with a silent default, and `Dashboard.bind` has a dead fallback. Challenges
depend on a UI screen for a contract question. Five UI helpers are copied. Two code comments are
wrong. Findings: `reviews/B_gameplay_architecture.md` A1, A3, A4, B1, B2, B3, C1, C2, D, E4, E7.

Written 2026-11-05. Status: **not started.**
Serves: rules 3, 5 and 6, so a new signal, key or screen cannot go silently missing.
State: done — nothing; next — phase 1; open findings — none.

## Phase 1 — Input (effort: medium; mode: accept-edits)

- A3: `merge_local` merges generically. The analog axes are explicit (`accel`, `brake_reverse`,
  `handbrake` max; `steer`, `elevator`, `climb` sum-clamp), and every other key is ORed over the
  union. Rewrite the three `test_action_registry.gd` probes in the same change (a dict carrying
  each key comes out).
- A4: `Cycles.lights` and `Cycles.body_cmd`.
- E7: `vehicle_input.gd:56`'s `tcs_off` comment (local TC off exists).
- Done when `test_input_arbitration` and `test_action_registry` are green.

## Phase 2 — Dashboard (effort: medium; mode: accept-edits)

- B1: the in-lamp `active` dict becomes a `const` table (contract name → field). `handbrake` and
  `esc_off` stay explicit cases. Add a `test_dashboard.gd` case requiring every bool "in" signal
  to be in the table or the explicit set.
- B3: delete `Dashboard.bind`'s fallback (bind after spawn is the contract). Fix the comment, the
  `docs/systems.md` mention and the baker's "default_vehicle is a variant" comment
  (`level_baker.gd:160`). That file is bake-hashed: the whole-line comment re-stales nothing, but a
  code change beside it (`:161`'s `family_of`) re-stales every level, so leave that code alone.
- B2: the user decides whether the INHIB lamp shows the raw `body_inhibit` or keeps its stated
  presentation exception.
- Done when the suite is green and the user has seen the cluster on two vehicles.

## Phase 3 — Composition (effort: medium; mode: accept-edits)

- C1: `has_gearbox` moves from `VehicleSelect` to `VehicleCatalog` (or a `src/shell/` helper).
  `ChallengeDef`, `ChallengeRegistry` and `VehicleSelect` all call it there.
- C2: `BaseVehicle.fit_tyre(tyre)`, called by `boot.gd`'s `_fit_tyre`.
- A1: the LAB rows grey out while the bridge is live (fallback included), with a "set by
  sloppyCAN" note as the CONTROLS sheet has. Add the reason to `docs/systems.md`. Decide
  re-check per frame vs on open.
- E4: `vehicle_spawn.gd:13`'s `is_water` comment says "bake-gate coverage flag".
- Done when the user has opened LAB with sloppyCAN connected and disconnected.

## Phase 4 — UI helpers (effort: low; mode: accept-edits)

- Review table D: one `_draw_centered`, an `Instrument` base for the `value` setter,
  `UiTheme.button`, and new `card_button` / `columns_for` statics on `CardGrid`.
- Done when the user has looked over the cluster, the gauges and the three select screens on
  desktop and touch.

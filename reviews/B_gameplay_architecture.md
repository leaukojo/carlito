# Review: gameplay architecture (input, shell, UI, challenges, level scripts)

Scope: `src/input/`, `src/shell/`, `src/ui/`, `src/challenges/`, `src/levels/` (scripts),
`src/bridge/` (read-only context). Docs checked against the code: `docs/systems.md`,
`docs/level_kit.md`, `docs/making_a_level.md`.

Method: static read of the scripts and the contract (`contract/carlito_contract.json`). Nothing
was run: this clone has no Godot binary and no import cache. **CONFIRMED** means the code path was
traced end to end. **PLAUSIBLE** means the mechanism is real, but whether it matters depends on
traffic or intent that only a run or the user can settle.

Ranked most severe first within each section. Each finding gives the site, what is wrong, a
concrete failure where there is one (the cleanups have none), and the smallest fix.

---

## A. Rule 5: arbitration and side channels around `VehicleInput`

### A1. The LAB page looks live while sloppyCAN owns the input (CONFIRMED, UI and doc gap) — **DOC SIDE DONE** (496ec6c); UI greying open
`src/ui/pause_menu.gd:382-423` (`_build_lab`). The LAB switches never reach the bridge's input:
`arbitrate_bridge` ignores them, and `blend_local_driving` (`input_router.gd:779-796`) leaves them
out of the driving group in fallback. That is intended. `test_input_arbitration.gd:425, 501, 515`
pin it ("nor does fallback"). The LAB page greys a row for two reasons: the challenge lock
(`_lab_locked`) or the body lacking the hardware (`_caps`). It never greys for a live bridge, so
while sloppyCAN is connected it shows switches that act on nothing.
`docs/systems.md` § Input pipeline ▸ LAB says "local only", but lists only the challenge lock and
a missing hardware fit as the reasons a switch goes stock.
- Failure: with sloppyCAN live (driving, or in fallback under CANopen or CHAdeMO traffic), set
  ANTI-LOCK BRAKES off. The page shows ABS OFF, but ABS stays on and ESC is not cascaded off.
  Nothing on the page says why.
- Fix: grey the LAB rows while `Bridge.is_active()`, with a "set by sloppyCAN" style note as the
  CONTROLS sheet does. The page is built once when the menu opens, and `Bridge` keeps polling
  under the pause, so either re-check per frame or accept a page that is stale until reopened.
  Add "a live bridge, fallback included" to the doc's reasons.

### A2. The touch HAND latch keeps toggle state outside the router (CONFIRMED, rule and doc conflict) — **DONE, exception named** (496ec6c, 0f68e39)
`src/ui/touch_controls.gd:714-731` (`_latch_button`, `LATCH_KEYS`). The touch overlay owns a
latched handbrake level (`_held[&"handbrake"]`), keeps it through widget rebuilds, and reports it
every poll. The registry row says this is deliberate (`action_registry.gd:57-58`: "on touch it
latches … Key stays momentary"). But two documents state the rule with no exception:
`docs/systems.md:80` ("Toggle state is owned by the router, never a source") and
`src/input/CLAUDE.md:10` ("sources only report per-frame edges").
- Consequence: the router cannot see or reset the latch. `reset_vehicle_cycles` does not cover it,
  so it outlives a respawn, and the keyboard cannot release it. A body change clears it only when
  the pad's gate hides it (boat, drone).
- Fix: either move the latch into `InputRouter` (a `_handbrake_latch` toggled by a
  `handbrake_toggle` edge from touch, its caption read back through `touch_state` like PTO and
  ARM), or name the exception in `docs/systems.md` and `src/input/CLAUDE.md`. Which one is your
  call.

### A3. `merge_local` repeats every edge key by hand (CONFIRMED, over-built)
`src/input/input_router.gd:604-639`. Twenty-seven keys are listed by hand, and a comment says that
a missing key silently drops the keyboard's edge. Three tests guard that list by probing
`merge_local({}, {})`: `test_action_registry.gd:47, 65, 79` check that it carries every touch
`poll_key`, every touch widget key and every LocalSource key. `driving_edges_only` (`:762`)
already relies on the naming convention instead (`*_toggle`, `*_cycle`).
- Fix: merge generically. Treat the analog axes (`accel`, `brake_reverse`, `handbrake`: max;
  `steer`, `elevator`, `climb`: sum-clamp) explicitly, and OR every other key over the union of
  both dicts. A generic merge returns `{}` for `merge_local({}, {})`, so the three tests fail as
  written. Their intent (no touch or keyboard key is dropped) still holds: rewrite them in the same
  change to merge a dict carrying each key and assert it comes out.

### A4. Cycles are still inlined beside `cycles.gd` (CONFIRMED, minor)
`src/input/input_router.gd:452` (`_lights % 4 + 1`) and `:496`
(`(_body_cmd + 1) % BODY_CMD_COUNT`). `cycles.gd` says it holds "one copy each" of the local
walks. These two are walks too, and they bypass it.
- Fix: add `Cycles.lights` and `Cycles.body_cmd`, with `BODY_CMD` already in
  `subsystem_counts.gd`.

---

## B. Rule 3: what the dashboard shows

### B1. The in-lamp map is a hand-written mirror with a silent default (CONFIRMED, latent)
`src/ui/dashboard.gd:933-966`. Lamps for bool "in" signals are generated from the contract. Their
state comes from an `active` dict built every frame by hand (contract name → a value read off
`VehicleInput`), read through `active.get(sig_name, false)`. All 24 current bool "in" signals are
covered. A 25th would get a lamp that is dark forever, with no warning and no test. The "out" side
is guarded properly: `_resolve_fields` warns once at bind. `VehicleInput`'s header names the same
hazard for its own fields ("a hand-written field mirror is a field that goes missing silently").
- Fix: split the dict into a `const` table, contract name → `VehicleInput` or `LampInput` field
  name, read with `get()`. Keep the two entries that compute rather than copy as explicit cases:
  `handbrake` (`> 0.0`) and `esc_off` (mixes in the `ST_ESC` flash).
  Then add a `test_dashboard.gd` case that every bool "in" signal in the contract is in the table
  or the explicit set.

### B2. The UI overrides `body_inhibit` (PLAUSIBLE, low)
`src/ui/dashboard.gd:877-882`. The INHIB lamp is forced dark while `body_bus` is false, even when
telemetry says `body_inhibit = true`. Telemetry is right as defined: the contract's
`body_inhibit` description says "A down body network (see body_bus) implies inhibit". So the
cluster deliberately shows a value different from the one the bus carries, which is the kind of
UI-side derivation rule 3 is wary of. The comment admits it, and the BODY BUS lamp beside it
explains the state.
- Fix: changing telemetry would contradict the contract, so the only code fix is to show the raw
  value. Otherwise, keep it as a stated presentation exception. Your call; low stakes either way.

### B3. `Dashboard.bind`'s fallback treats a family as a variant (CONFIRMED, dead path) — **DOC SIDE DONE** (a151952); code fallback open
`src/ui/dashboard.gd:276-279`. `VehicleCatalog.family_of(level.info.default_vehicle)` is called on
a family name: every `*_info.tres` stores a family (`"car"`, `"boat"`), and `level.gd:91` and
`level_info.gd` treat it as one. For `"car"`, `"truck"`, `"tractor"` and `"boat"`, `family_of`
returns `""`, because none of them is also a variant key. The fallback runs only when
`GameState.current_vehicle == ""`, and the shell binds only after a spawn. So it runs only when the
very first level of a session fails to spawn, and for those four families it then yields `""`, the
same family it was meant to replace. The comment ("default_vehicle is a VARIANT
("bullet")") contradicts the data. `kit/bake/level_baker.gd:160` hedges both ways.
- Fix: delete the fallback (bind after spawn is the contract), or make it
  `vtype = level.info.default_vehicle`. Then fix the comment, the `docs/systems.md:206` mention
  ("`Dashboard.bind` falls back to `LevelInfo.default_vehicle`"), and the baker's "default_vehicle
  is a variant" comment.

---

## C. Rule 6: composition and reach-through

### C1. Challenges and the shell depend on a UI screen for a contract question (CONFIRMED)
`src/challenges/challenge_def.gd:47` and `src/shell/challenge_registry.gd:181` call
`VehicleSelect.has_gearbox` (`src/ui/vehicle_select.gd:610`). That is a static on a UI screen
holding a contract query plus a family list (`plane`, `train`). The data model (`ChallengeDef`) and
the registry validator both pull in the garage screen's class.
- Fix: move `has_gearbox` next to the data it reads, either `VehicleCatalog` or a small
  `src/shell/` helper. `VehicleSelect`, `ChallengeDef` and `ChallengeRegistry` then all call it
  there.

### C2. The shell reaches through the vehicle to fit tyres (CONFIRMED, minor)
`src/shell/boot.gd:863-871` (`_fit_tyre`). The shell calls
`body.drive.fit_tyre(body.spec.ground_drive, …)`, two levels into the vehicle's internals. Every
other shell → vehicle call is one method (`respawn`, `cycle_implement`, `set_attachment`).
- Fix: add `BaseVehicle.fit_tyre(tyre: TyreClass)` and call that.

No level → UI or level → shell reach was found. `src/levels/**/*.gd` never names `Dashboard`,
`Boot`, `InputRouter` or the touch overlay. `PauseMenu` emits signals only.

---

## D. Duplicated UI helpers

| Helper | Copies | Fix |
|---|---|---|
| `_draw_centered(font, at, text, size, color)` | `attitude_indicator.gd:176`, `depth_readout.gd:93`, `gauge.gd:99`, `wind_rose.gd:196` (same body; the attitude copy routes through its `_draw_at`) | one static in a shared instrument helper (or `UiTheme`) taking the `CanvasItem` |
| `_set_value(v)` setter (compare, assign, `queue_redraw`) | `dash_bar.gd:28`, `depth_readout.gd:28`, `gauge.gd:30` | a tiny `Instrument extends Control` base with `value` |
| `_btn(text, on_press)` (200 × TOUCH_MIN button) | `challenge_briefing.gd:79`, `challenge_result.gd:87`, `challenge_select.gd:370` (+ rim option) | `UiTheme.button(ref, text, on_press, rim := RIM)` |
| Card button frame (4–5 stylebox overrides via `CardGrid.card_box`) | `level_select.gd:120`, `challenge_select.gd:173`, `vehicle_select.gd:405` | `CardGrid.card_button(ref, border_w, lit)` (the header already says the frame is shared) |
| Card column fit (`floor((avail + gap) / (card_w + gap))`, clamped) | `level_select.gd:105`, `challenge_select.gd:159` | `CardGrid.columns_for(ref, card_w, gap, avail, max_cols, n)` |

---

## E. Docs that disagree with the code

1. **DONE** (6312755) **`docs/systems.md:182-188`, pause-menu table.** It gives
   `setup(caps, density, ui_scale, wind_preset, current_preset, wind_from_deg, night_on)`. The
   code is `setup(caps, state := State.new())` (`pause_menu.gd:152`, `State` at `:49-67`,
   built in `boot.gd:426-445`). The table also has no SPAWN POINT row (`pause_menu.gd:218`).
   Lines 183-184 list GARAGE/LEVEL on G / 4 but not CHALLENGES on 5.
2. **DONE** (0110d0d) **`docs/systems.md:127, 189`, "held for the session" / SETTINGS "session-held".** SETTINGS is
   saved to `user://` (`UserSettings`, `boot.gd:465-516`). The page also has more than density and
   UI scale: extended debug, KEY RESPONSE, TRACTION CONTROL, STABILITY CONTROL and AUTO HOLD. The
   session-held state is LAB, CONDITIONS and the garage's gearbox choice (`boot.gd:52`). The
   garage's tyre choice is saved (`UserSettings.set_tyre`).
3. **DONE** (3db0f02) **`docs/systems.md:56`, "0 = D".** In automatic, byte 0 gives D only with the accelerator
   pressed. Otherwise it gives N, or P for a body already parked (`input_router.gd:905-913`).
4. **DONE, docs fix** (c863dae; the `vehicle_spawn.gd:13` comment is open) **`docs/systems.md:239` and `vehicle_spawn.gd:13`, `is_water`.** (`making_a_level.md:89`
   says only "for boat spawns" and "a bake gate", which is accurate.)
   `is_water` is read only by the bake gate (`level_baker.gd:178`). `VehicleSpawn.accepts` and
   `Level.pick_spawn` ignore it, and the drown respawn uses `spawn_transform`, not a water
   marker (`water_surface.gd:178` → `BaseVehicle.respawn`). The "drown-respawn spot" and "safe
   respawn after a car falls in" claims are false at runtime. Every shipped water marker filters
   to `boat`, so nothing misbehaves today. An empty-filter water marker placed first in tree
   order, though, would spawn a car in the sea.
   - Fix: say "bake-gate coverage flag" in the docs, or make `accepts` honour it
     (`is_water == (family == "boat")`).
5. **DONE, docs** (a151952) **`docs/systems.md:206` and `dashboard.gd:278`, default_vehicle as a variant.** See B3.
6. **DONE** (496ec6c) **`docs/systems.md:80`, toggle ownership.** See A2. **§ Input pipeline ▸ LAB, the reasons a
   switch goes stock.** See A1.
7. **OPEN** (a `.gd` comment, outside session 2's scope) **`src/input/vehicle_input.gd:56`, the `tcs_off` comment.** It says "bridge-only: local drives
   with TC on". Local TC off is SETTINGS ▸ TRACTION CONTROL (`input_router.gd:514`), as
   `docs/systems.md` says.
8. **DONE** (8bc95e1) **`docs/systems.md:195, 204`, minor omissions.** `LevelRegistry.LEVELS` also carries `dev` and
   `arena`. The vehicle selector also emits `gearbox_chosen` and `tyre_chosen`.

`docs/level_kit.md` and `docs/making_a_level.md` otherwise match the level scripts. The terrain
knob names and defaults (`chunk_cells` 64, blend sharpness 8, `sand_height` / `dirt_slope_deg` /
`rock_slope_deg`, `channel_surface`), the `WorldBounds` defaults, and the bake spawn gate all agree.

---

## Checked and clean

- Who drives: every consumer of "who drives" uses `InputRouter.bridge_drives()`: touch,
  ActionRegistry context and the cluster's local lamps. `Bridge.is_active()` appears in the UI
  only as "a peer is connected" (bridge-owned greying and the MANUAL gearbox enable), and it is the
  same freshness gate the router's `live` reads.
- `ChallengeFrame` takes lamps and inputs from `InputRouter.get_vehicle_input()` and signals from
  `to_bridge_dict()`. No side channel. The runner ticks after the vehicles (`PHYSICS_PRIORITY`
  100).
- `PauseMenu` applies nothing itself. It keeps display copies of what the shell handed it, and
  every change goes back through a signal to `boot.gd`, which applies it and persists it. Its
  ESC-cascade note reuses the router's pure `InputRouter.lab_raw` and `lab_esc_cause`
  (`pause_menu.gd:558-562`) rather than re-deriving the cascade.
- `LevelSelect` and `ChallengeSelect` return ids or paths through signals. `VehicleSelect` gets the
  level's predicates as values or callables (`has_spawn_for`), never the level node.

Not reviewed: `src/vehicles/` (outside scope); feel and transients (need a run).

# Plan — Challenges: bridge-only goals that teach CAN

Add a challenge mode beside free play. The player picks a challenge from a new CHALLENGES
screen, reads a briefing, and completes a goal while driving **over the bridge only**: keyboard
and touch driving are locked out. A small set of arenas hosts the challenges; each challenge
brings its own course (spawn, zones, markers), lighting and fog. The catalogue, with the wire
facts it depends on, is `docs/challenge_ideas.md`.

Written 2026-09-11. Status: **Phases 1-7 done** (1-4 on 2026-09-11, 5-7 on 2026-09-12), Phase 7's
checkpoint played clean; **Phase 8a done** (2026-09-12), its play checkpoint open, and 8b waits on it;
**Phase 9 done** (2026-09-12).

**Car 13 is authored for the brake-pedal method only.** A locked handbrake wheel never releases at
any throttle (`docs/TODO.md` § A locked handbrake never releases, at any throttle — a drivetrain
model gap, not a tuning number). `RollbackGoal` cannot tell brake from handbrake, so the pass
condition stands; only the hint teaches just the brake method until the drivetrain is fixed.
Delete this file when the last phase ships, after distilling its conclusions into the relevant
`CLAUDE.md` files and `docs/systems.md`.

## Decisions already made

- **Shared arenas**, not one scene per challenge: a few small arenas plus existing levels, each
  hosting several challenges (allocation below).
- **All challenges open.** A pass is marked done with a best time. Nothing is locked.
- **Progress has its own store**, `ChallengeProgress` → `user://challenges.cfg` (IndexedDB on
  web), always on. It is independent of `ShellPrefs`, whose `ENABLED` switch is off for
  boot-path testing and must not take progress with it. The player can reset it from the
  CHALLENGES screen, behind a confirmation.
- **Briefing = goal + constraints**, with a HINT button that reveals the signals involved.
- **A new CHALLENGES important button** beside GARAGE and LEVEL, plus a key. It opens its own
  card screen, grouped by vehicle.
- **No contract change.** Challenges read the telemetry that already exists. Publishing
  challenge state to sloppyCAN would be a later, paired release, and is out of scope here.
- **Carlito changes solve the challenges; sloppyCAN is not reshaped around them.** sloppyCAN
  may change, but only with general features it would want anyway — the uplink sources it is
  genuinely missing (Phase 9) qualify; a challenge mode, challenge state or challenge-specific
  hook does not. How a player's frames coexist with sloppyCAN's own ECU traffic
  is sloppyCAN's concern, not this plan's.
- **Visibility needs no new rendering.** A pitch-black challenge is lighting with no sun, zero
  ambient and a black sky; a blind challenge is heavy fog. Both are applied to the level's
  environment for the length of the attempt.
- **E is the one local key a challenge may allow**, and only Truck 1 does: coupling has no
  signal.
- **Gear byte 0 stays "no gear opinion"** in arbitration. A gear-teaching challenge instead
  carries the manual-gear constraint (fail while `VehicleInput.gear_auto` is set and moving).

## Architecture

| piece | where | what it does |
| --- | --- | --- |
| `ChallengeDef` | `src/challenges/challenge_def.gd` (Resource) | id, title, variant (the family is derived through `VehicleCatalog`, never stored), `attachment` (a scene path from the family's catalog, since E is locked; `""` = bobtail / detached), `allow_attach_key`, arena level id, course scene **path** (never a PackedScene: an island course ships in its arena's level pack, unmounted when the registry loads), `spawn_jitter_m` / `_deg` (seeded, per attempt), briefing, hint, `par_s`, `visibility` (DAY / DARK / FOG + `fog_density`), ordered `goals`, `constraints` |
| goal + constraint primitives | `src/challenges/goals/` | `ChallengeCheck` resources stepped on a `ChallengeFrame`: `RUNNING / PASS / FAIL`, plus `RESET` from a fail zone. Unit-tested (rule 8) |
| `ChallengeFrame` | `src/challenges/challenge_frame.gd` | one tick's input: the wire dict (`to_bridge_dict()`, so goals judge the published value under its contract name), the `VehicleInput`, the body pose, the wheel contacts, the free payloads |
| `ZoneShape` / `ChallengeZone` | `src/challenges/` | pure box / ring geometry with inclusive edges; the course node that produces it, named by goals by node name |
| `ChallengeAttempt` | `src/challenges/challenge_attempt.gd` | pure: the clock, the ordered goals, constraints judged first, the par, `reset()` on any respawn. Runs `duplicate()`s of the def's checks, so a def holds no state |
| `ChallengeRegistry` | `src/shell/challenge_registry.gd` | ordered list grouped by family, the `LevelRegistry` sibling. `problems(def)` is the validation `test_challenge_registry` holds every def to |
| `ChallengeProgress` | `src/shell/challenge_progress.gd` | best time per id (done = has one); memory-only when headless |
| `ChallengeRunner` | `src/challenges/challenge_runner.gd`, a node the shell adds under the level | instances the course under the level root. Every start (and `restart()`, the retry) spawns a FRESH body at the course marker (`Level.set_vehicle(variant, at)`) and sets the def's attachment before the first tick, so the TowHost countdown lays exactly that at the course pose and every attempt starts with the same aux state. Steps the attempt at `process_physics_priority` 100, after every vehicle's tick. RESET: the warning as a notice, then `respawn()`. PASS / FAIL: `finished`. Any respawn is handled on the NEXT tick (the semi and tractor read `spawn_transform` after `respawned` fires): attempt reset, `prev_origin` INF, the def's attachment re-asserted (an E-coupled trailer does not survive), the next start's jitter rolled. `end()` restores the lighting, unparents the course and re-points the body's `spawn_transform` at `Level.pick_spawn` |
| `ChallengeVisibility` | `src/challenges/challenge_visibility.gd` | pure apply / restore of DARK and FOG on `Level.environment()` / `sun_light()`, returning a snapshot. Reads every property before writing any: setting `fog_mode` resets `fog_density` |
| course | `<id>_course.tscn`; a def whose zone names match may share another's (Car 8 runs Car 4's, Car 14 Car 2's). A course on a main-pack level lives in `src/challenges/courses/` | spawn marker, zones (finish, box, checkpoint, gate, fail), visible markers, payloads. Instanced under the level root at attempt start. Authored with an `ArenaPreview` (`src/challenges/arena_preview.gd`): in the editor only it shows the arena, named by level id so the course takes no dependency edge on it, as an unowned top-level internal child at the world origin; at runtime it frees itself, and the registry fails one naming another arena. `ChallengeZone` is `@tool` only for an editor-only translucent volume |
| dev entry | `ChallengeRegistry.DEV_DEFS`, `src/challenges/dev/` | a debug build's `--challenge=<id>` / `CARLITO_CHALLENGE` (`BootParams.challenge`) boots into `_start_challenge`. The `dev_box_stop` fixtures (DAY, DARK, FOG 0.12, on flatland) are never listed and never stored, but are held to `problems()` and the bake-isolation test |
| bridge-only lock | `InputRouter` (rule 5: arbitration lives only there) | `set_bridge_only`: local and touch are never polled; with no live bridge (or a stale one) the input is `locked_idle()`, key at Lock and handbrake on. A debug build honours `--challenge-keys` / `CARLITO_CHALLENGE_KEYS` so the keyboard can drive while authoring |
| shell lock | `boot.gd` `_start_challenge(def)` / `_begin_challenge(def)` / `_end_challenge()` | `_start_challenge` loads the def's arena with its body and begins once `_finish_load` is done. `_begin_challenge` adds the runner after `set_night(false)`; `_end_challenge` ends it before restoring night, so the runner's snapshot is always the day lighting. The session is not saved during an attempt; the result is a notice, and a pass goes to `ChallengeProgress`. Blocks G / V / garage, E (unless `allow_attach_key`), N (`Level.day_night_locked`) and the CONDITIONS page with a notice; suspends the session CONDITIONS for the level's own and restores them on exit; hides the touch driving layer. Choosing a LEVEL ends the attempt. Touch has no ATTACH during an attempt (it sits on the hidden driving layer), so Truck 1's E is keyboard-only until Phase 10 decides otherwise |
| UI | `src/ui/` | CHALLENGES button, `ChallengeSelect` cards, briefing + HINT, objective line + timer, result panel |

**Courses are runtime overlays, never arena content.** A course is not under `AuthoringRoot` and
not a dependency of the arena `.tscn`. The bake hash covers the level scene and everything it
depends on (`LevelBaker.gather_bake_inputs`), so zones authored inside an arena would re-stale its
bake on every tweak; as overlays they never do, the baker needs no new scene-tag group, and a
course can sit on an existing level (flatland, level_1, level_6) with no bake work at all. Arena
geometry the car drives on (ramps, pits, the causeway, drops) stays in the arena and is baked
(rule 1).

**Goals read three things**: the telemetry (what the wire carries), `VehicleInput` (lamp bits,
`gear_auto`, `led` — the rule-5 struct, never a side channel), and course geometry. A briefing
quotes the wire resolution wherever a goal depends on it (§ Wire facts in the catalogue).

**Arenas are `LevelRegistry` entries** with `arena: true`, which hides them from LEVEL select like
`dev` does (`dev` means a test asset; an arena ships) while keeping them in bake, `check_bakes` and
the smoke run. `boot.gd _save_session` never records an arena, so an arena is never the place a
reload resumes.

**A new island arena's courses are generated with it**: its generator's `courses` stage places
zones and markers by distance along the same saved road curves the level drives on
(`tools/gen_car_arena.gd`), so a course cannot drift off its road; a hand edit to a course is lost
on the next run of that stage.

### Goal and constraint primitives

Goals, one class each in `src/challenges/goals/`:
- `ReachZoneGoal`. Ordered waypoints are a chain of these on RING zones.
- `StopInZoneGoal`: |velocity| below a speed for N s (the body's velocity, not the signed forward
  `speed`, so a sideways drift is not a stop), every wheel contact inside, optional heading
  tolerance.
- `SignalBandGoal`: out of band inside the zone fails. On a thin zone it is the entry-speed gate
  (`kmh`); it also covers the speed band and a band held along a path (`agl`, `engine_load`). It
  shares `WindowGoal` with the two lamp goals: an optional `exit_zone` makes any other way out of
  the zone fail (a trap left by its side, a corridor through its roof).
- `SignalReachGoal`: a value at a point (`axle_load` on the scale, `pto_rpm`), or a state reached
  (`armed`, `trailer_connected`).
- `LampWindowGoal`: a gap tolerance of 1.05 s, a legal flasher's longest dark phase, so a source
  that blinks the bit passes.
- `LampFrequencyGoal`: 1.0-2.0 Hz from rising edges, with 50 ms of tolerance, because inbound bits
  change only between rendered frames.
- `RingLapGoal`: net 360 deg swept about the centre; leaving the ring fails.
- `PayloadInZoneGoal`.
- `GimbalAimGoal`: on the `_actual` readbacks, through `DroneGimbal.basis_of`.
- `InputEqualsGoal`: any of a list of values, under a mask (`led`; `lights` at LOW or HIGH).
- `RollbackGoal`: rollback distance after a held stop, measured along the latched forward axis.

Constraints, each of which fails the attempt. Each is judged from its `from_goal` on, so goal 0
can engage something (Boat 1's HEADING HOLD) that a constraint then forbids leaving:
- `par_s` on the def, set only where time is the point (`challenge_ideas.md` intro).
- `SignalLimitConstraint`: `accLat`.
- `ForbiddenValueConstraint`: a flag set (`trailer_abs`) or a forbidden mode (`mode_actual`,
  `nav_mode_actual`).
- `ManualGearConstraint`: `gear_auto` while `ST_MOVING`.
- `FailZoneConstraint`: RESET, meaning respawn with a warning and reset the attempt.

Every boundary is inclusive, and every hold (and the par) is met on exactly its tick. Zone entry
also counts a path that crossed the zone between two ticks, so a thin gate cannot be skipped at
speed. Goals judge Carlito's own values, which are finer than the wire's resolution, so a band a
briefing quotes needs margin past that resolution at its edges.

### Arena allocation

| arena | ships in | challenges |
| --- | --- | --- |
| car island (new, small) | level pack | Car 1-16 |
| flatland (existing, no bake) | main `.pck` | Car 17-18, Drone 6 |
| truck-yard island (new, small) | level pack | Truck 1-4 |
| farm: level_1's fields, or a small new island if Phase 2 finds no usable split-grip patch and curved row there | level pack | Tractor 1-4 |
| level_6 Skyport (existing) | level pack | Drone 1-5 |
| level_6's boat playground (existing) | level pack | Boat 1-4 |

New arenas are islands under `src/levels/island/`, so they ship as level packs (0.1-0.6 MB each
by the current figures in `docs/deploying.md` § Download size) and add nothing to the boot
download. Each one needs a `Web <id>` export preset and its entry in
`tests/test_export_filter.gd` (`docs/deploying.md` § Level packs).

## Phases

Each phase suggests a model, an effort level and a permission mode.

### 1. Review the challenges and this plan — done

Conclusions are folded into the sections above and into `docs/challenge_ideas.md`.

### 2. Measure and spike the risky challenges
**Model:** Sonnet 5 · **Effort:** medium · **Mode:** normal

Throwaway measurements. Record the numbers in `challenge_ideas.md` and commit no code. Measure with
local keys or a scratch script wherever sloppyCAN cannot send the signal yet. Par times are not
set here: they depend on final geometry and belong to the authoring phases.

- **Steep ramp:** the grade at which D6 stalls and D1 sits on the limiter
  (`measure_vehicles` on a grade, or a scratch level).
- **Entry gates and boxes:** braking distance from a candidate entry speed for Car 3 (sedan) and
  Truck 4 (laden semi rig), and the box length that leaves room to stop by feedback.
- **Hill start:** a grade where a car rolls back when the brake comes off, and the rollback of
  the handbrake method.
- **Weighbridge:** `axle_load` empty and after 1-8 dump cycles, to set the target band.
- **Trailer ABS:** whether a hard stop from the entry speed with the box trailer really fires
  `trailer_abs`.
- **Rock out of a ditch:** whether a pit exists that D1 alone cannot climb but rocking can.
- **Mud:** a split-grip patch that 2WD cannot leave but diff lock and/or MFWD can.
- **Plough:** `engine_load` against `hitch_pos` 0-10 % and against the Field weight.
- **Auto-steer:** commanded against driven radius at 2, 8 and 15 km/h.
- **Ice:** the grip value that makes `slip` spike clearly at the course's driving speed.
- **Fog:** the density that keeps the vehicle readable at chase-camera distance and hides
  anything past about 15 m.
- **Dark:** how far the headlights actually reach on a zero-ambient level.
- **Drone:** whether `baro_alt` and `agl` really diverge over hills.
- **Desk check:** the wire resolution of the flavored signals a goal quotes (`axle_load`,
  `pto_rpm`, `engine_load`, `agl`, `home_dist`) in sloppyCAN's flavor packers.

### 3. Challenge core (pure logic) — done

Conclusions are folded into the sections above.

### 4. The bridge-only lock — done

Conclusions are folded into § Architecture. The shell guards and the hidden touch layer have no
unit test; their driving check is a debug-boot attempt (`--challenge=dev_box_stop`).

### 5. Runner, courses and environment — done

Conclusions are folded into § Architecture. Open for the user's drive test: the three
`dev_box_stop` fixtures, windowed with `--challenge-keys`, and the course's arena preview and zone
volumes in the editor.

### 6. Shell and UI — done

CHALLENGES joined GARAGE/LEVEL as a top-level important button and key (5 — every letter was
already bound): `ActionRegistry` row `challenge_select`, `TouchControls.STACK_HEAD`/
`_shell_signals()`, `boot.gd _show_challenge_select` / `_close_challenge_select` /
`_on_challenge_picked`. Reachable during an attempt too, like LEVEL: picking a challenge there
ends the one running the same way picking a level does.

`ChallengeSelect` (`src/ui/challenge_select.gd`) is a three-page overlay (grid / briefing /
reset-confirm), the same page-swap idiom as `PauseMenu`: cards grouped by family, each showing
its `ChallengeProgress` done state and best time and reusing `card_grid.gd`'s frame with the
arena's own screenshot as the thumbnail (a challenge ships no art of its own). Picking a card
opens the briefing page (goal text, PAR, a HINT toggle, START); START emits `challenge_chosen`.
RESET PROGRESS sits behind a confirm page and calls `ChallengeProgress.reset()` directly, since
the screen already holds the reference.

`ChallengeHud` (top-center "GOAL n / m  elapsed  PAR") is built and freed alongside the runner in
`_begin_challenge` / `_end_challenge`, the same overlay-lifecycle pattern as `CoachCue`.
`ChallengeResult` (RETRY / NEXT / MENU) replaces the old pass/fail notice in
`_on_challenge_finished`. Decided: RETRY is the same respawn the R key already performs mid-attempt
(the runner resets the attempt on *any* respawn, whatever caused it) — the button owns no restart
logic of its own, it just calls `boot._respawn()`. NEXT walks `ChallengeRegistry.in_family()` for
the next sibling; MENU calls `_end_challenge()`.

`_finish_load` already saved the session before `_begin_challenge` ran (Phase 5), so this needed
no fix.

Skipped: the `?challenge=<id>` web deep link. `BootParams.challenge()` is deliberately debug-build
only today; exposing a challenge start to release web via query string is a policy change (shareable
attempt links), not plumbing, and needs a decision before it's built.

### 7. Car arena: vertical slice — done, checkpoint open

`car_arena` (`src/levels/island/car_arena/`, its own level pack and `Web car_arena` preset) is
owned by `tools/gen_car_arena.gd` (`scaffold` → import → `courses` → bake): a flat plateau disc at
6 m, r 180 m, carrying three asphalt roads built from straights and true arcs — the STRIP (z 0,
x -160..160), the CORNERS road (north of it, x -160..105, 90 deg corners L R R L at r 15 m, 90 m
apart) and the WINDING road (south of it, x -150..77, S-bends at r 35 m). Off the strip, the
plateau east of those two roads' ends is empty for Phase 8's mesa/ramp, pit, lagoon causeway and
ice road; the strip's east end carries Car 3's overrun zone (x 48..160).

Car 1-4 are `car_start_up`, `car_easy_turns`, `car_box_stop` and `car_turn_signals`
(`src/challenges/defs/`, all `sedan-sports`). Car 3's box starts 8 m past the gate: a car that
crossed at the 50 km/h minimum cannot stop short of it, so the gate really does stop a crawl.

A throwaway scripted-bridge driver (writing `Bridge._inbound`, which a desktop run never touches)
drove each through the real lock and runner: Car 1 PASS in D1 at 16.2 s and FAIL
on gear 0; Car 2 PASS at 40 km/h, 24.7 s; Car 3 PASS entering at 58 km/h and braking at the gate,
15.6 s, FAIL at 45 km/h, RESET when overrunning at 90; Car 4 PASS steady and blinking at 30 km/h,
47.6 s, FAIL with no signal.

- **Checkpoint: the user plays Car 1-4 over sloppyCAN with their own tooling.** Fix what they
  find before authoring more. The arena's challenge cards read "no screenshot" until Phase 14.

### 8. Remaining car challenges (5-18)
**Model:** Sonnet 5 · **Effort:** medium · **Mode:** accept-edits

**8a — done, checkpoint open.** The course-only six, no bake work: Car 6 `car_box_blind` (strip,
FOG, Car 3's course without the box paint — `_box_stop(strip, marked)`), Car 8 `car_turn_blink`
(Car 4's course, `LampFrequencyGoal` per signal window), Car 10 `car_speed_trap` (strip, kmh 48-52
through a paved-width `Trap` left only into `TrapExit`), Car 14 `car_corner_budget` (Car 2's
course, |accLat| <= 4.0, par 26 s), Car 17 `car_blind_circle` and Car 18 `car_blind_slalom`
(flatland, FOG, hand-authored courses in `src/challenges/courses/`, positions quoted as lat/lon
in the briefing — move a zone, recompute them). Every FOG def is at `fog_density` 0.12.

Measured with a throwaway scripted-bridge driver (writes `Bridge._inbound`, `--fixed-fps 60`):
Car 6 PASS at 60 km/h braking at the gate (15.3 s), FAIL at 45; Car 8 PASS blinking at 1.43 Hz
(45.2 s), FAIL steady; Car 10 PASS at 50 (20.9 s), FAIL at 55; Car 14 steady-speed runs pass at 34 /
37 / 40 km/h (27.4 / 25.5 / 23.9 s, peak |accLat| 2.89 / 3.39 / 3.93) and break the limit from 42
on the first bend — par 26 s fails the 34 km/h crawl; Car 17 PASS at 25 km/h (18.0 s), FAIL
driving straight; Car 18 PASS at 25 km/h (26.7 s).

- **Checkpoint: the user plays 6, 8, 10, 14, 17, 18 over sloppyCAN** and judges the fog density
  by eye.

**8b — the geometry batch** (Car 5, 7, 9, 11, 12, 13, 15, 16), in the plateau's empty north-east
block (x 30..170, z -50..-170) and the south band past the winding road. Roads with grades are the
Turtle plus a rise on `straight()` (RoadBuilder already handles grades and pitch kinks); conform
builds embankments and pits from the curve alone.
- RAMP to a mesa, ~7-8 deg: Car 9 (manual gear, measured par), Car 13 (a hold zone on the ramp).
- EMBANKMENT road with tight corners: Car 7 (par) with a low `FailZone` box under deck height;
  Car 16 on the same road with spawn jitter.
- LAGOON carved below sea level, crossed by a narrow causeway road: Car 5 (DARK, `InputEqualsGoal`
  lights [3, 4], then the far end; a fail zone over the water).
- PIT (a V road): Car 12, wall grade measured so D1 cannot climb out but rocking can. Two failed
  geometry passes means stop and hand off.
- ICE road: splat channel 4 renamed Ice (grip measured), painted under the deck on a bend: Car 15.
- Parking APRON painted asphalt: Car 11 (`StopInZoneGoal` with a heading tolerance).
- Re-scaffold → `--import` → `courses` → bake → `check_bakes`; the DARK challenge needs the user's
  eye on headlight legibility.

### 9. sloppyCAN uplink sources — done

Every tractor and truck "in" signal now has a sloppyCAN source. The carriers are listed in
`challenge_ideas.md` § Wire facts; the mechanism (a decoder registry, the own-address rule, the
freshness rule) is in sloppycan's `CLAUDE.md`. A command frame reaches the game from the wire, from
sloppyCAN's TX scheduler, and through `carlito-bridge.html`, and the owning panel drives it too.
The tractor and truck dashboards gained Commands sections, and the trailer lamps sit beside the
DM1 selectors. The drone's LED / hook / gimbal and the boat's autopilot also decode from frames.

`diff_lock`, `fwd_drive` and `retarder` are panel-only. The TC1 and TSC1 layouts are J1939-71's,
and the local copy is a scan the Read tool can only render with poppler installed. Installing it
is what would unblock both decoders.

### 10. Truck yard (Truck 1-4)
**Model:** Sonnet 5 · **Effort:** medium · **Mode:** accept-edits

- Couple-and-deliver (the E exception), the refuse-truck pair (Tipping refused, then
  Weighbridge), and Trailer ABS. Truck 1 and 4 need only RAMN signals.

### 11. Farm (Tractor 1-4)
**Model:** Sonnet 5 · **Effort:** medium · **Mode:** accept-edits

- **Prerequisite:** if Phase 2 shows the driven radius does not follow `guidance_curvature`, fix
  the mapping in Carlito first — the contract calls it the reciprocal of the turn radius.
- The mud patch uses a splat channel with split grip; the plough field needs channel 4 soil
  with a varying weight (see `src/levels/CLAUDE.md`).
- Auto-steer needs a curved row the player can see.
- **Open:** `bridge_source.gd` folds `guidance_curvature` into `steer`, so no goal can tell
  auto-steer from a hand on the wheel. Either `VehicleInput` carries the fact (a field, and a
  rule-5 change), or Tractor 4's briefing accepts both.

### 12. Drone range (Drone 1-6)
**Model:** Sonnet 5 · **Effort:** medium · **Mode:** accept-edits

- Courses on level_6: crates and a drop zone, a gimbal marker, and a terrain-following route over
  level_6's own relief (a course adds no terrain; if level_6 has no suitable strip, that is a
  level_6 edit and re-bake). Drone 6 is a fog course on flatland.

### 13. Water (Boat 1-4)
**Model:** Opus 5 · **Effort:** high · **Mode:** plan-mode-first

- **Gate:** the user reviews the boat ideas first; they are provisional.
- Courses on level_6's boat playground. Current and wind come from the arena's authored
  side-cars; sea depth follows the level's `Sea.y` rules (`src/levels/CLAUDE.md`).

### 14. Docs, shipping and cleanup
**Model:** Sonnet 5 · **Effort:** low · **Mode:** accept-edits

- A challenges section in `docs/systems.md`, and gotchas in the relevant `CLAUDE.md` files.
- Arena thumbnails and challenge cards.
- Export presets and `test_export_filter` entries for the new islands.
- `preflight`.
- Distil this plan, then delete it.

## Verification (every phase that touches code)

The gdUnit4 suite, the headless smoke, the parse check, `check_bakes` and `preflight`. Sweep
for new GDScript warnings. The real test is **the user playing the challenges over sloppyCAN**:
from Phase 7 on, each arena ends with a play session before the next one starts.

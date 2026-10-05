# Mechanical update — finding briefs

Audit of the land vehicles' mechanical model (Kenney cars and vans, Kenney trucks, the hand-built
semis and their trailers, the tractor and its drawbar trailer), 2026-10-05. Plane, drone, boat and
train are out of scope.

Each numbered file is one **brief** for a planning agent: what is wrong or missing, where it lives,
why it matters, what binds a fix, and what "done" looks like. A brief is **not a plan**: the
planning agent turns it into one (see § Where plans go).

## Recommended order

| # | Brief | Size | Needs first |
| --- | --- | --- | --- |
| 01 | `01_tractor_wheel_visual_spin.md` — tractor tyres visually spin 1.83x / 1.22x too fast | trivial | — |
| 02 | `02_engine_torque_model.md` — a fuel cut gives zero torque instead of engine braking | small | — |
| 03 | `03_tyre_static_friction.md` — no static friction: held vehicles creep | medium | — |
| 04 | `04_brakes_and_parking.md` — brake, handbrake and retarder sized from the tyre, launch torque and the service brake, not the hardware | medium-large | 03 (to measure parking) |
| 05 | `05_engine_driveline_inertia.md` — the engine has no rotating mass | large | 02 |
| 06 | `06_shift_schedule.md` — fixed-rpm shifting (a sedan cruises 60 km/h in 2nd at ~5000 rpm), start gear, shift trace | medium | 05 (recommended) |
| 07 | `07_body_scale_and_yaw_inertia.md` — toy-scale Kenney geometry with real mass | medium | — |
| 08 | `08_handling_balance.md` — `rear_lat_grip` stands in for roll-stiffness distribution | medium | 07 |
| 09 | `09_ackermann_steering.md` — parallel steer scrubs in tight turns | small | — |
| 10 | `10_wheel_radius_and_contact.md` — one 0.36 m ray wheel for every body | large | 04, 05, 06 |
| 11 | `11_tractor_implements_and_draft.md` — weightless implements, ramped draft | medium | — |
| 12 | `12_tyre_classes_and_surfaces.md` — user-swappable tyres, tyre x surface response (future) | medium-large | 03, 04 (08 ideally) |
| 13 | `13_minor_items.md` — wind, aero balance, rolling-resistance vector, ideal ABS/TC, taper | small each | — |

Why this order: 01 is a free visual fix. 02 and 03 are foundations that later briefs measure
against (03 in particular: no parking or hold figure means anything until a held wheel holds). 04
retires the most patches per unit of work. 05 is the largest driveline change and 06 builds on
it. 07 comes before 08 because balance is tuned on the final inertia. 10 re-derives gearing and
brakes, so it goes after the briefs that change them. 12 is the user's future feature and needs
04's decoupling of brakes from tyres.

Two cross-dependencies the table does not show:
- **The shift trace (06 Part C) is the tool for judging 05's launches.** Build it first: as the
  first phase of 05, or ahead of it.
- **04 sizes the foot brake against first gear at converter stall, and 05 Part B may add converter
  torque multiplication (1.8-2.2x at stall).** Either 04 sizes brakes with that margin, or 05 B
  re-checks the brakes when it lands.

## The three root causes

Most findings trace to one of these; each brief says which.

1. **The engine is a torque source.** No rotating mass, rpm is a smoothed copy of wheel speed,
   and a fuel cut produces zero torque rather than engine braking (02, 05, 06).
2. **The tyre has no static friction.** Below 1.5 m/s its force is proportional to sliding speed,
   so nothing holds a vehicle still (03, 04).
3. **Hardware ratings are derived from other ratings, and toy-scale geometry carries real mass.**
   Brakes come from the tyre, the handbrake from launch torque, the retarder from the brake (04);
   the Kenney bodies have ~60 % of a real wheelbase under real masses and COM heights (07, 08).

## Agreed philosophy (user, 2026-10-05)

- **Keep the Kenney models.** The physics stays honest for the vehicle the geometry describes: a
  short-wheelbase body of real mass behaves like a short real car (more pitch, more load transfer).
  Judge pitch and launch behaviour against a real vehicle of that footprint, not a full-size one.
  Never fake a full-size figure: no hidden longer physics wheelbase, no stretched models, no lowered
  COM to hit a number.
- **A patch that compensates for a missing phenomenon goes when the phenomenon is modelled.** Each
  brief lists the patches it would retire. A patch is retired on measurement, not on argument.
- **Future feature:** tyres the user can change (all-season car, lug for truck and tractor, winter
  on snow) to see the effect (12).

## Common context for every brief

Read before planning:
- Root `CLAUDE.md`, `src/vehicles/CLAUDE.md`, the family file (`src/vehicles/truck/CLAUDE.md`,
  `src/vehicles/tractor/CLAUDE.md`, `src/vehicles/kenney/CLAUDE.md`), `src/input/CLAUDE.md`,
  `tools/CLAUDE.md`.
- `docs/vehicles.md` (§ Physics derivations and figures, § Measuring a vehicle, § Gradeability,
  § Rough and soft ground), `docs/heavy_vehicles.md`.
- `docs/TODO.md`: its drivetrain items that the audit covers (engine as a rotating mass, the
  coupling model, creep and hill hold, shift policy, the shift trace, the tractor's launch gear)
  now live in briefs 05 and 06. What stays there (CVT, diesel governor and hand throttle, real
  gear counts) builds on those two briefs.

Constraints that bind every brief:
- Godot 4.7.1 + Jolt. Physics is **locked at 60 Hz** with interpolation (root rule 9). Never raise
  the tick; never remove or weaken a 60 Hz clamp (`src/vehicles/CLAUDE.md` § The 60 Hz tick). A
  new torque on a wheel goes **inside** the semi-implicit spin step (`RayWheel._integrate_spin`,
  through `spin_compliance`), never as a post-tick correction.
- Feel changes follow the `vehicle-feel` skill. Kenney bodies change in the recipes of
  `tools/gen_kenney_vehicles.gd` plus a regen, never in their `.tres` / `.tscn`. The semis
  (`src/vehicles/truck/semi_spec.tres`, `conventional_spec.tres`), the trailers
  (`src/vehicles/truck/trailers/*_spec.tres`) and `src/vehicles/tractor/trailers/farm_tipper_spec.tres`
  are hand-authored, with their derivations in header comments that must be rewritten with them.
- Pure logic gets gdUnit4 tests (root rule 8). Suites most briefs touch: `test_drivetrain`,
  `test_wheel_spin`, `test_vehicle_catalog`, `test_kenney_variants`, `test_truck`, `test_tractor`,
  `test_trailer`, `test_drawbar_trailer`, `test_tow_host`, `test_input_arbitration`,
  `test_body_inertia`.
- Telemetry is read out of the sim that produced the motion (root rule 3). A contract change goes
  through the `contract-edit` skill.
- The "Rejected — do not re-propose" lists in `src/vehicles/CLAUDE.md` and the family CLAUDE.md
  files bind. Where a brief argues against an entry it says so; reversing one is the user's call.
- Measuring: `tools/CLAUDE.md` § Measure tools (`measure_vehicles`, `measure_grade`,
  `measure_rough`, `measure_semi_launch`). The figure tables in `docs/vehicles.md` are generated by
  `doc=<id>` presets and refreshed by re-running, never by hand. Long sweeps run in the background
  with `--fixed-fps 60`. CI gates: `measure_vehicles -- all 45 track strict` and
  `measure_semi_launch -- <unit> strict`.
- The user verifies by driving; any verification scene is a real Level with a VehicleSpawn.

Evidence: figures marked **computed** were derived from code and spec numbers during the audit,
not measured in game. Re-measure before relying on one. Figures marked **measured** are quoted from
`docs/vehicles.md` or a spec header.

## Where plans go

Plans go to `docs/plans/<snake_case>.md` in the house format: `# Plan — <title>`, a one-paragraph
goal, `Written <YYYY-MM-DD>. Status: **not started.**`, then phases, each with a suggested effort
level (low / medium / high) and permission mode (normal / accept-edits / plan-mode-first).

When a brief's work lands, its lasting content is distilled into `docs/` (plus at most one
CLAUDE.md line) per the root CLAUDE.md § Where things go, the `docs/TODO.md` items that build on
it are re-read against the result, and the brief is deleted.

CI: `docs/TODO.md` cites `mechanical_update/05_…` and `06_…` in backticks, and
`tools/check_docs.mjs` (run in CI) fails on a path that does not exist. So `mechanical_update/` is
committed together with the TODO edit, and deleting brief 05 or 06 means repointing those TODO
references in the same change.

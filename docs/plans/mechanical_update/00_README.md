# Mechanical update — finding briefs

Audit of the land vehicles' mechanical model (Kenney cars and vans, Kenney trucks, the hand-built
semis and their trailers, the tractor and its drawbar trailer), 2026-10-05. Plane, drone, boat and
train are out of scope.

Each numbered file is one **brief** for a planning agent: what is wrong or missing, where it lives,
what binds a fix, and what "done" looks like. A brief is **not a plan** (see § Where plans go).

## Recommended order

| # | Brief | Size | Needs first | Planning effort | Phases |
| --- | --- | --- | --- | --- | --- |
| 01 | tractor tyres visually spin 1.83x / 1.22x too fast | trivial | — | landed | — |
| 02 | a fuel cut gives zero torque instead of engine braking | small | — | landed | — |
| 03 | no static friction: held vehicles creep | medium | — | landed | — |
| 04 | brake, handbrake and retarder sized from the tyre, launch torque and the service brake, not the hardware | medium-large | 03 (to measure parking) | landed | — |
| 04b | a truck that loses its air is tested only in parts; its trailer does not brake | small | 04 | landed | — |
| 04c | diffs couple after each wheel's brake step, so AWD bodies and the tractor creep on enough brake | medium | 04 | landed | — |
| 04d | P (park): the pawl as a lock of the gearbox output, contract v48 with sloppyCAN | small (+ sloppyCAN) | 04, 04c | landed | — |
| 05 | engine inertia, coupling, creep — the engine had no rotating mass | large | 02 | landed (`docs/drivetrain.md` § Crank and coupling, § Converter, § Hill hold) | — |
| 06 | shift policy, start gear, shift trace — fixed-rpm shifting (a sedan cruised 60 km/h in 2nd at ~5000 rpm) | medium | 05 | landed (`docs/drivetrain.md` § The shift policy; `docs/heavy_vehicles.md` § Tractor, implement & ISOBUS) | — |
| 06b | the heavy vans' drivetrain — they ran the 8 t trucks' engine and gearing | small-medium | 05, 06 | landed (`docs/sources.md`, the heavy vans' drivetrain) | — |
| 07 | toy-scale Kenney geometry with real mass | medium | — | landed (`docs/vehicles.md` § Inertia, § Pitch, § Balance, § Braking) | — |
| 07b | crawl-speed tyre caps and the patch under the hub | medium-large | 07 | landed (`docs/vehicles.md` § One-tick caps, § Slip floor, § Pitch) | — |
| 14 | `14_semi_shift_ring_and_drift.md` — (1) the semi's shift ring: landed (`docs/vehicles.md` § Pitch); (2) a slow yaw mode drifts the semis centimetres: parked until the semis take the tyre law | small (2) | 07b | landed. (2) medium: name the mode first | (2) one |
| 09 | parallel steer scrubs in tight turns | small | — | landed (`docs/vehicles.md` § Steering geometry) | — |
| 10 | one 0.36 m ray wheel for every body | large | 04, 05, 06 | landed (`docs/vehicles.md` § Physics derivations: Wheel radius, Contact; `docs/sources.md`) | — |
| 11 | weightless implements, ramped draft | medium | — | landed (`docs/heavy_vehicles.md` § Draft, hitch, linkage, § The four implements; `docs/vehicles.md` § Inertia; `docs/sources.md`) | — |
| 12 | user-swappable tyres, tyre x surface response | medium-large | 03, 04 | landed (`docs/vehicles.md` § Tyres and surfaces; `docs/sources.md` § Sourced figures; `docs/vehicle_measurements.md` § Tyre classes by surface) | — |
| 13 | minor items — wind, aero balance, rolling-resistance vector, ideal ABS/TC, taper, twin-rear visual | small each | — | landed (`docs/vehicles.md` § Aero balance, § Crosswind, § Road resistance, § Rejected designs; `docs/sources.md`) | — |
| 15 | bars and tyre laws buy the limit margin but not a road car's linear understeer | medium | — | landed (`docs/vehicles.md` § Balance: roll steer, the 60 Hz loop, declared angular damping, the corner pass; § Steering geometry; `docs/sources.md` § Roll steer, § Linear understeer; follow-ups in `docs/TODO.md` § Handling follow-ups) | — |
| 16 | `16_drivetrain_control.md` — 6-ratio trucks and tractor, no governor or hand throttle, no CVT, a linear pedal, fuel blind to rpm | large | 10, 11 (items 1-3); 05, 06 | high: two contract changes, sourced pedal and BSFC maps, a CVT decision | two plans: pedal map + fuel (any time), then gear counts, governor, CVT |

"Planning effort" is the effort level for the agent that WRITES the plan (low / medium / high /
xhigh / max): how much design is open, how much must be sourced, how many rules or user decisions it
meets; not the size of the change.

Order: 10's contact shape starts from 07b's patch; 14's drift when the semis take the tyre law
(`docs/vehicles.md` § Balance); 10 after the briefs that re-derive gearing and brakes; 12 needs
04's decoupling of brakes from tyres; 16's gear counts after 10 (which re-derives gearing) and its
governor after 11 (the draft load it holds PTO speed against).

Two cross-dependencies the table does not show:
- **The shift trace judges every launch.** `measure_vehicles -- <variant> <s> trace`
  (`docs/vehicle_measurements.md` § Measuring a vehicle): its gates (dwell, landing, hunting, front axle) and
  each shift's slip are what a driveline change is read against.
- **04 sized the foot brake against first gear at converter stall, and the converter's torque
  ratio ships at 1.0** (05; a real one's ~2.0 fails seven more bodies' static stall hold,
  `docs/drivetrain.md` § Converter). `BrakeSizing.stall_hold_margin` reads
  `Drivetrain.stall_axle_torque`, so `test_vehicle_catalog` re-checks every body when the ratio
  moves. The brakes sit inside the coupled diff solve (04c), so the AWD and MFWD bodies are judged
  on their brake total.

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
  on snow) to see the effect (12, landed: `docs/vehicles.md` § Tyres and surfaces).

## Common context for every brief

Read before planning:
- Root `CLAUDE.md`, `src/vehicles/CLAUDE.md`, the family file (`src/vehicles/truck/CLAUDE.md`,
  `src/vehicles/tractor/CLAUDE.md`), `src/input/CLAUDE.md`,
  `tools/CLAUDE.md`.
- `docs/vehicles.md`, `docs/drivetrain.md`, `docs/vehicle_measurements.md` (§ Measuring a vehicle,
  § Gradeability, § Rough and soft ground), `docs/heavy_vehicles.md`.
- The engine as a rotating mass, the coupling model, creep and hill hold, the shift policy and the
  shift trace landed with 05 and 06 (`docs/drivetrain.md`); what builds on them is brief 16.

Constraints that bind every brief:
- Godot 4.7.1 + Jolt. Physics runs at **60 Hz** (the engine default) with interpolation. Never raise
  the tick; never remove or weaken a 60 Hz clamp (`src/vehicles/CLAUDE.md` § Physics). A
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
- `docs/vehicles.md` § Rejected designs and the "Rejected" notes in `docs/heavy_vehicles.md`
  bind. Where a brief argues against an entry it says so; reversing one is the user's call.
- Measuring: `docs/vehicle_measurements.md` § Measure-tool run lines (`measure_vehicles`, `measure_grade`,
  `measure_rough`, `measure_semi_launch`). The figure tables there are generated by
  `doc=<id>` presets and refreshed by re-running, never by hand. Long sweeps run in the background
  with `--fixed-fps 60`. CI gates: `measure_vehicles -- all 45 track strict` and
  `measure_semi_launch -- <unit> strict`.
- Known oddities in the figure tables (baseline 2026-10-16, all gates green; not regressions, do not
  chase unless the brief touches them): the 2WD tractor's floored mud bumps_10 / bumps_20 times
  swing run to run (`docs/vehicle_measurements.md` § Rough and soft ground); the `semi` moves ~10 mm in 60 s parked across a 30 %
  slope on the foot brake, every other cell under 1 mm (`doc=park`, unexplained); the
  `hatchback-sports` mud ditch_35 takes 10.3 s against ~3.5 s for its neighbours (unexplained).
- The user verifies by driving; any verification scene is a real Level with a VehicleSpawn.

Evidence: **computed** figures are derived from code and spec numbers, not measured in game
(re-measure before relying on one); **measured** figures are quoted from `docs/vehicle_measurements.md` or a
spec header.

## Where plans go

Plans go to `docs/plans/<snake_case>.md` in the house format: `# Plan — <title>`, a one-paragraph
goal, `Written <YYYY-MM-DD>. Status: **not started.**`, then phases, each with a suggested effort
level (low / medium / high) and permission mode (normal / accept-edits / plan-mode-first).

When a brief's work lands, its lasting content is distilled into `docs/` (plus at most one
CLAUDE.md line) per the root CLAUDE.md § Where things go, the `docs/TODO.md` items that build on
it are re-read against the result, and the brief is deleted.

CI: a doc that cites a brief's path in backticks fails `tools/check_docs.mjs` once the brief is gone,
so deleting a brief means repointing its references in the same change. Code comments cite briefs by
number and `check_docs` does not read code: grep for the number.

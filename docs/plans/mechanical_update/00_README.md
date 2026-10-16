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
| 05 | engine inertia, coupling, creep — the engine had no rotating mass | large | 02 | landed (`docs/vehicles.md` § Crank and coupling, § Converter, § Hill hold) | — |
| 06 | shift policy, start gear, shift trace — fixed-rpm shifting (a sedan cruised 60 km/h in 2nd at ~5000 rpm) | medium | 05 | landed (`docs/vehicles.md` § The shift policy; `docs/heavy_vehicles.md` § Tractor, implement & ISOBUS) | — |
| 06b | the heavy vans' drivetrain — they ran the 8 t trucks' engine and gearing | small-medium | 05, 06 | landed (`docs/vehicles.md` § Sourced figures, the heavy vans' drivetrain) | — |
| 07 | `07_body_scale_and_yaw_inertia.md` — toy-scale Kenney geometry with real mass | medium | — | high: declared gyration reverses "never set inertia"; each fudge needs a real lever found | two to three: yaw-inertia decision + mechanism, de-fudge per body, restate the pitch / front-lift targets (the brief carries the measured front-axle launch figures) |
| 08 | `08_handling_balance.md` — `rear_lat_grip` stands in for roll-stiffness distribution | medium | 07 | high: the tyre-model change ripples into brake split and the grade / launch ceilings; tyre data to source; understeer targets from the user | several: step-steer tool first, per-axle bars, cornering-stiffness load model, retire `rear_lat_grip` |
| 09 | `09_ackermann_steering.md` — parallel steer scrubs in tight turns | small | — | low: pure geometry, spec fraction defaulting to 0, mean angle unchanged; one decision (which wheel the lock limits) | one |
| 10 | `10_wheel_radius_and_contact.md` — one 0.36 m ray wheel for every body | large | 04, 05, 06 | xhigh: every body and trailer, the tractor linkage geometry, a Rejected entry (MFWD lead ratio) | several, likely two plans: radius (re-derive every body), then contact shape (web perf study) |
| 11 | `11_tractor_implements_and_draft.md` — weightless implements, ramped draft | medium | — | medium (high if the draft law is reshaped): implement mass is plain; speed-independent draft needs an angular-bound derivation and reverses "keep the speed ramp" | two to three: implement mass + axle load, draft law, draft control if wanted (contract) |
| 12 | `12_tyre_classes_and_surfaces.md` — user-swappable tyres, tyre x surface response (future) | medium-large | 03, 04 (08 ideally) | high: a feature with many user decisions, across vehicles, levels and UI | several: tyre-class resource, cross-level surface identity (untangle `SOIL_CHANNEL`), tyre x surface table, swap UI, level content |
| 13 | `13_minor_items.md` — wind, aero balance, rolling-resistance vector, ideal ABS/TC, taper | small each | — | per item: 1 wind low (wait for a windy land level); 2 aero centre of pressure medium; 3 rolling-resistance vector low (fold into 05 or 10); 4 cycling ABS/TC medium (user decision first); 5 taper: a decision, no plan; 6 (converter creep): landed with 05 | one each |

"Planning effort" is the effort level for the agent that WRITES the plan (low / medium / high /
xhigh / max): how much design is open, how much must be sourced, how many rules or user decisions it
meets; not the size of the change.

Order: 07 before 08 (balance is tuned on the final inertia); 10 after the briefs that re-derive
gearing and brakes; 12 needs 04's decoupling of brakes from tyres.

Two cross-dependencies the table does not show:
- **The shift trace judges every launch.** `measure_vehicles -- <variant> <s> trace`
  (`docs/vehicles.md` § Measuring a vehicle): its gates (dwell, landing, hunting, front axle) and
  each shift's slip are what a driveline change is read against.
- **04 sized the foot brake against first gear at converter stall, and the converter's torque
  ratio ships at 1.0** (05; a real one's ~2.0 fails seven more bodies' static stall hold,
  `docs/vehicles.md` § Converter). `BrakeSizing.stall_hold_margin` reads
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
  on snow) to see the effect (12).

## Common context for every brief

Read before planning:
- Root `CLAUDE.md`, `src/vehicles/CLAUDE.md`, the family file (`src/vehicles/truck/CLAUDE.md`,
  `src/vehicles/tractor/CLAUDE.md`), `src/input/CLAUDE.md`,
  `tools/CLAUDE.md`.
- `docs/vehicles.md` (§ Physics derivations and figures, § Measuring a vehicle, § Gradeability,
  § Rough and soft ground), `docs/heavy_vehicles.md`.
- `docs/TODO.md`: its drivetrain items that the audit covers (engine as a rotating mass, the
  coupling model, creep and hill hold, shift policy, the shift trace, the tractor's launch gear)
  landed with 05 and 06 (`docs/vehicles.md`). What stays there (CVT, diesel governor and hand
  throttle, real gear counts, a progressive pedal map, fuel from delivered power) builds on them.

Constraints that bind every brief:
- Godot 4.7.1 + Jolt. Physics is **locked at 60 Hz** with interpolation (root rule 9). Never raise
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
- The "Rejected — do not re-propose" lists in `src/vehicles/CLAUDE.md` and the family CLAUDE.md
  files bind. Where a brief argues against an entry it says so; reversing one is the user's call.
- Measuring: `docs/vehicles.md` § Measure-tool run lines (`measure_vehicles`, `measure_grade`,
  `measure_rough`, `measure_semi_launch`). The figure tables in `docs/vehicles.md` are generated by
  `doc=<id>` presets and refreshed by re-running, never by hand. Long sweeps run in the background
  with `--fixed-fps 60`. CI gates: `measure_vehicles -- all 45 track strict` and
  `measure_semi_launch -- <unit> strict`.
- The user verifies by driving; any verification scene is a real Level with a VehicleSpawn.

Evidence: **computed** figures are derived from code and spec numbers, not measured in game
(re-measure before relying on one); **measured** figures are quoted from `docs/vehicles.md` or a
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

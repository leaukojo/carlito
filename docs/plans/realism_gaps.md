# Plan — Close the realism gaps the measure tables show

A read of every table in `docs/vehicle_measurements.md` against real-world orders of magnitude
(from memory, no source opened) found figures more than ~30 % off what each body simulates. This
plan fixes each one at its source: a sim bug where there is one, a vehicle parameter otherwise.
A gap stays only where the Kenney body's proportions force it, and is then said in the doc.

Written 2026-11-13. Status: **not started.**
Serves: standing rule 3 (telemetry out of an honest sim): `fuel_rate`, `engine_load`, `speed`,
grip and brake figures a learner can compare with a real vehicle's.
State: done: `doc=top` table (top speed, quarter mile). Next: phase 1. Open findings: none.

Each phase is one session, ends with the suite and the `vehicle-feel` skill's steps where a spec
moves, and re-runs only the `doc=` tables it names (background, `--fixed-fps 60`). The plane is
out of scope. Real-world targets below are from memory: each phase opens a source for its target
before tuning to it (root CLAUDE.md: a sourced figure cites a page actually opened).

## Phase 1 — Semi road load (effort: medium, mode: investigate then fix)

Symptom: `semi` + 24 t at 70 km/h burns 8.0 L/h at 11 % load (real: roughly double); 8.5 L/h at
50 km/h, more than at 70; about the 8 t `garbage-truck`'s burn.
- The road load is not the fault: `doc=top`'s run prints `balance: tyres 3370 N - resistance
  3214 N (declared 3214)` at 88 km/h, the 32 t's `crr` 0.007 plus drag on 2.18 + 0.6 m² (trailer
  `box_spec.tres`). That is ~55 kW at the wheels at 70 km/h, which 8.0 L/h (~78 kW of diesel)
  cannot supply, and 11 % `engine_load` of ~300 kW is 33 kW. So `fuel_rate` and `engine_load`
  under-read on the semi (the 8 t `garbage-truck`'s 8.3 L/h for ~19 kW is plausible). Start in
  the fuel and load model: what the cruise hold averages, and the torque the crank carries
  against the tyres' force through the 12-speed's ratio and `efficiency`.
- Rig `drag_area` 2.78 m² in all against a real rig's 5-6 m²: raise it second (tractor or
  trailer spec), with a sourced target.
- Explain the 50 > 70 km/h burn (gear and rpm per hold); fix if it is a fuel-map fault.
- Add L/100 km to the cruise table's cell.
- Re-run: `doc=cruise`, `doc=wind`, `doc=top`, `doc=accel` (the governed tops must hold).

## Phase 2 — Kenney trucks: mass and centre of mass (effort: high, mode: tune)

Symptom: `garbage-truck` (8 t) and `firetruck` (7.5 t) launch 0-50 in ~6 s (real 12-15 s), climb
60.8 % from rest (real 20-30 %), corner 0.71 / 0.68 g without tipping (real 0.4-0.55 g).
- Decide per body whether the model's footprint against the 1.8 m car supports a real mass
  (15-25 t). If yes: raise mass, `com_y`, brake sizing and springs together, and fix the
  reference labels. If the body is too small for it: keep it, relabel the reference as a light
  truck of its size, and say so in the doc.
- Their `drag_area` (1.95 / 1.86 m²) gets the same check as phase 1.
- Re-run: `doc=accel`, `doc=cornering`, `doc=grade`, `doc=braking`, `doc=brake_fade`,
  `doc=brake_check` (its 0-of-7 miss against the field runs is re-judged at the new mass),
  `doc=top`.

## Phase 3 — Surface grip (effort: low, mode: tune)

Symptom: snow all-season 0.40-0.47 g and winter ~0.5 g (real 0.2-0.3 / 0.3-0.4), nearly equal to
wet; wet ~0.5 g (real ~0.7).
- Retune the `Surface` snow and wet grip and the `TyreClass` factors on them; ice, mud and field
  read plausible and stay.
- The `garbage-truck` mud tyre on ice reads 0.78 g cornering beside 0.08-0.13: find the artefact
  in the cornering pass's path g when the body slides.
- Re-run: `doc=tyres`; check `doc=grade` mud is unmoved.

## Phase 4 — Cars near the line (effort: medium, mode: tune)

One spec at a time, each against a sourced target:
- `race`, `race-future`: both leave the 40 m strip sideways near 280-290 km/h with zero steer
  (`doc=top`: `left the strip`). Find why (tracking pass at speed, aero balance) before any tune.
- `race-future`: 0-100 3.3 s and 293 km/h against its hypercar reference; torque-bound with a
  converter stall. Raise power or relabel the reference.
- `pickup`: 0-100 9.6 s (ref 7.0); 78 % RWD grade (real 35-40 %): check the axle load split and
  `com_y`; the grade may be the short tall Kenney body (then say so).
- `sedan-sports`: skid pad 0.80 g, under `sedan`'s 0.85: tyre fit or balance.
- `delivery`, `delivery-flat`, `ambulance`: 0-100 18-21 s (ref 12-13) and cruise fuel ~40 % low
  (`drag_area` 1.2 m², real box van ~2); raising drag also brings the 171-176 km/h tops down.
- `suv`: 223 km/h and gaining (class ~180): a governor (`speed_limit_kmh`) or gearing.
- Semi hot stop: 545 °C lengthens the stop 1 %: check the fade curve against its source.
- ESC leaves 0 % yaw on every body: leave (ideal controller, labelled).
- Re-run: `doc=accel`, `doc=top`, `doc=cornering`, `doc=cruise`, `doc=grade`.

## Phase 5 — Trim redundant measurements (effort: low, mode: edit)

Only where the readings are essentially the same:
- `doc=accel`: drop the `tc` figure from the 0-50 / 0-100 cells for bodies with `tcs_equipped`
  (floored and `tc` match to 0.02 s); keep it for `race-future` and the semis.
- Twin bodies: keep one of `sedan` / `taxi`, `pickup` / `pickup-flat`, `delivery` /
  `delivery-flat`, `semi` / `semi-conventional` in `doc=cornering`, `doc=esc` and `doc=accel`
  rows unless phases 2-4 make them differ; `doc=top` keeps every body.
- `trailer_roll_p7` against `trailer_roll`'s corner column: confirm the two agree per config,
  then keep one.
- Lower `DOCS_CHAR_CAP` by the characters removed.

## Missing tables (a later plan, not this one)

Boat, train and drone have no generated table (the drone has a tool); braking covers six bodies;
no table prints each body's engine power beside its mass.

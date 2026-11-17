# Plan — Close the realism gaps the measure tables show

A read of every table in `docs/vehicle_measurements.md` against real-world orders of magnitude
(from memory, no source opened) found figures more than ~30 % off what each body simulates. This
plan fixes each one at its source: a sim bug where there is one, a vehicle parameter otherwise.
A gap stays only where the Kenney body's proportions force it, and is then said in the doc.

Written 2026-11-13. Status: **not started.**
Serves: standing rule 3 (telemetry out of an honest sim): `fuel_rate`, `engine_load`, `speed`,
grip and brake figures a learner can compare with a real vehicle's.
State: done: `doc=top` table (top speed, quarter mile); phase 4's first bullet (`race`,
`race-future`: the side force's centre behind the COM, user's choice 2026-11-17,
`.claude/review_journal/sessions/2026-11-17-race-yaw-mode.md`); phase 1's fault was the cruise
hold (a laden rig coasting through the band; `CRUISE_DRIFT`), the rig keeps 2.78 m² (its
silhouette's; user's choice 2026-11-18); phase 1 done. Phase 2 done (drive test OK 2026-11-18): the
bodies are car-width, so the 12-14 t class that carries the driveline (user's choice
2026-11-18; `docs/sources.md` § The Kenney trucks' class; `doc=grade` / `braking` / `brake_fade`
/ `brake_check` carry no firetruck row, so not re-run): `firetruck` 12 t, `com_y` 0.90 (0-50
8.6 s, tips after the front saturates at 0.62 g, K 0.57 / 0.70); `garbage-truck` unchanged (8 t
empty, 13 t full); springs and brakes stay; the handbrake-lock guard and the retarder floor
narrowed (user's choices). Phase 3 done (drive test OK 2026-11-18): `Surface` wet 0.75 (Bosch [68]), snow
0.34 and Summer / Studded snow factors from VTI's measured peaks (`docs/sources.md` [214]; the
review moved snow from 0.40, which had divided by Wong's 0.85 dry, not the bodies' mu ~1; AutoBild
[215] confirms); `doc=grade` unmoved; the mud tyre's 0.78 g on ice read 0.07 g since becd1d6.
Next: a snow-strip re-drive at 0.34, then phase 4. Open findings: the Winter-over-all-season 1.2
on snow rests on unopened pages ([66], [67]; [215] has no all-season); AutoBild's summer stops
1.8x the winters' on snow [215] against VTI's 1.28-1.54 (Summer's factor keeps VTI's); the
600 Nm retarder is an unsourced estimate (Allison 3000: 1490-2170 Nm per a search summary; the
1.6 ceiling then binds the empty garbage truck); the laden firetruck rolls in the 70 km/h 30 %
step with ESC on: the Kenney trucks carry no `esc_roll_lift_g` (R13 roll-over control); the
garbage truck's tables are its empty 8 t. The fixed hold
moved every body's cruise burn up 10-40 % (`delivery` 90 km/h 7.8 L/100 km): phase 4's "cruise
fuel ~40 % low" on the vans is re-judged against the new table before any drag change.

Each phase is one session, ends with the suite and the `vehicle-feel` skill's steps where a spec
moves, and re-runs only the `doc=` tables it names (background, `--fixed-fps 60`). The plane is
out of scope. Real-world targets below are from memory: each phase opens a source for its target
before tuning to it (root CLAUDE.md: a sourced figure cites a page actually opened).

## Phase 1 — Semi road load: done (see State)

## Phase 2 — Kenney trucks: mass and centre of mass: done (see State)

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

## Phase 3 — Surface grip: done (see State)

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

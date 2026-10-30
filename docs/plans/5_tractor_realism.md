# Plan — A tractor that climbs, grips and tips like a tractor

The tractor reads like a stiff truck where a real one is limited: it climbs 76-79 % on asphalt in
MFWD and 32-42 % in mud (`docs/vehicle_measurements.md` § Gradeability: `tools/measure_grade.tscn`), against the 35-45 % firm
/ 15-25 % wet-field reference that table quotes; and it corners to a 0.79 g slide with 2.5 deg of
roll and never tips (`docs/vehicle_measurements.md` § Cornering), where a real tractor's front axle swings on a centre pivot and
the machine rolls over on its stability triangle well before the lugs let go. This plan sources
the real limits, finds which model term carries each gap, and closes them with real mechanisms,
never a detune (`src/vehicles/CLAUDE.md` § Physics). The user gave the go-ahead on 2026-10-24 to
lift the Kenney handling freeze for the tractor bodies (`tractor-kenney`, `tractor-cvt`) only.

Written 2026-10-24. Status: **not started.**
Serves: the tractor lessons — MFWD and diff lock earning their keep on a slope, slip and draft on
a real lug's grip, and the rollover a tractor driver is taught to fear (the roll angle and
lateral g on the bus mean something only if the body can tip).
State: done — nothing; next — phase 0; open findings — none.

Independent of the converter bodies: the tractors are clutch bodies.

## Phase 0 — What "too dynamic" is, sourced and measured (effort: medium; mode: plan-mode-first)

- Ask the user what reads wrong when driving: launch, cornering, slope, bounce, steering, speed.
  The phases below cover the measured gaps; a felt gap they miss becomes its own phase, with the
  user's OK.
- Source, from pages actually opened, each graded: a farm tractor's restart / operating slope
  limits (the doc's 35-45 % / 15-25 % reference has no source in `docs/sources.md` yet); an
  R-1W lug's traction coefficient on concrete or asphalt (sources.md row "Soil factors": none found
  yet, keep looking: ASABE, OECD tractor test reports, tyre maker data); the oscillating front
  axle's travel (typ. ±8-12 deg, a maker's spec sheet for the 6R / 8R class) and the lateral
  rollover threshold it gives (NIOSH / ASABE stability-triangle literature).
- Measure which ceiling binds each gap (no edit): `measure_grade -- tractor-kenney verbose` and
  `mfwd`, `mud mfwd` (the tool prints traction / torque / tip ceilings); the cornering pass
  (`measure_vehicles -- tractor-kenney 40 track corner`) and `measure_semi_launch`'s tractor runs
  for the roll and the front loads at the limit.
- Output: one table, sim against source per figure (grade asphalt / field / mud, lateral limit,
  tip angle), with the term that carries each gap. Done when the user has seen it and picked which
  of phases 1-2 go ahead.

## Phase 1 — The lug's grip on hard ground (effort: high; mode: plan-mode-first)

Only if phase 0 sources a lug's hard-surface grip under the shipped one.
- The change is the R-1W class's factor in `TyreClass` (a class property: the fitment stays the
  body's), per surface; never a body `mu_long` / `mu_lat` detune.
- Every tractor table moves: `doc=grade`, `doc=cornering`, `doc=braking`, `doc=tyres`,
  `doc=rough`, and the plough holds (`-- tractor-kenney 20 plough`, against D497).
- `test_vehicle_catalog` (brake locks the stock tyre), `test_tractor` pass.

## Phase 2 — The oscillating front axle (effort: high; mode: plan-mode-first)

A real mechanism, absent today: the front axle is a beam on a longitudinal pivot, so the two front
wheels share the front load freely (no front roll stiffness) until the pivot reaches its stop;
the body rolls on the triangle of the two rears and the pivot until then.
- A `GroundDriveSpec` flag defaulting off (`src/vehicles/CLAUDE.md` § Structure), with the stop
  angle as data, sourced in phase 0. Solved where the wheel loads are (the suspension step), never
  a post-tick force; read the front loads and the roll out of the sim (standing rule 3).
- Pure logic (the pivot's load split and stop) gets gdUnit4 tests (standing rule 8).
- Check the side-slope park (`doc=park` cross) and the rough course (`doc=rough`): the pivot is
  also why a tractor keeps four wheels down over bumps.
- Measure the new lateral tip threshold (cornering pass, the full-lock step) against the phase 0
  source; a tractor that now tips is the point, not a regression.

## Phase 3 — Re-measure and the docs (effort: medium; mode: accept-edits)

- Baseline at HEAD first, in one background script, like with like (alone against alone).
- Every `doc=` table carrying a tractor row, `-- all 45 trace` (the front-axle gate), the hitch
  and plough passes; update `docs/tractor.md` (the rollover paragraph's "static threshold is about
  1 g"), `docs/vehicle_measurements.md`'s gradeability notes and `docs/sources.md`.
- The docs caps bind (`tools/check_docs.mjs`; every cap was full on 2026-10-24): trim what the
  change retires; a raised cap is the user's call.
- Done when the tables read the new figures and the user has driven a slope, a field and a fast
  turn on `tractor-kenney` for feel.

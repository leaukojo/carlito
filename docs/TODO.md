# TODO

Open work lives as one prompt per file in `docs/plans/` (effort + mode in each header; a
finished plan is deleted, its conclusion distilled per root `CLAUDE.md` § Working style). Accepted
constraints that are not work are recorded beside the code they bind.

## Not yet a plan (short notes, so they are not forgotten)

- **The sedan is slower than its recipe comment says.** `gen_kenney_vehicles.gd` (CAR_BASE)
  claims 219.8 km/h / 8.35 s to 100 at 6012 rpm; it measures 200.5 km/h / 9.10 s at 5490 rpm
  (2026-09-23). It already read that before the differentials. A 20 km/h top-speed loss points at
  resistance or gearing, so find the commit before rewriting the comment.
- **Hill-climb figures moved between 2026-09-18 and 2026-09-23 on bodies the differentials did
  not touch:** sedan 43.6 → 38.6 %, tractor 2WD 44.3 → 59.1 %, garbage-truck 33.0 → 40.7 %. The
  pre-differential tree reads the same, so an earlier commit moved them, deliberately or not.
  Probably the same cause as the sedan above.
- **The semi is slow against a real 32-36 t rig:** 0-50 in 16.7 s against ~8.5, and a top speed of
  86.5 km/h against ~105.
- **Every launch runs 10-40 % slower than its real reference.** The converter makes no torque
  multiplication (`src/vehicles/CLAUDE.md` § Drivetrain and brakes, a deliberate compromise).
  Adding it re-opens every acceleration figure and the brake-over-drive derivation.
- **The 2WD tractor, floored in mud, never pulls away:** a quarter pedal in gear 1 is already
  past the grip peak. The lever is a clutch or a softer low-throttle map, never the diff.
- **Drive checks for the differentials** are pending.
- **Work `docs/to_investigate.md` down before it becomes a second TODO.** Each fixed guard deletes
  a prose rule. Cheapest next: assert `BaseVehicle`'s layer is VEHICLE; text-pin
  `export_presets.cfg`'s `thread_support`/PWA; a catalog-wide lamp-path test; strip comments in
  `check_orphans.mjs`; one setter for `mass` + `set_corner_mass_from`.
- **Baker error on a GridMap with `cell_center_y = true`** (`kit/CLAUDE.md` states it as prose).
  `level_baker.gd` is a bake input, so land it with the phase 7 batch 3 re-bake
  (`docs/plans/docs_review.md`).
- **Re-run `measure_grade` once:** its torque ceiling now samples the converter's launch rpm
  instead of idle, so its printed torque-limit column reads higher than any old run.
- **Investigate: did the converter model move the hill-climb figures?** A held vehicle revs to
  `Drivetrain.converter_free_rpm` instead of idle, which would raise some standing-start climbs
  (tractor, garbage truck). Check whether `git log -S converter_free_rpm` lands between
  2026-09-18 and 2026-09-23; if so, it explains the hill-climb (and maybe the sedan) note above.
- **Measure tools could write their own figure tables.** If `measure_vehicles` / `measure_grade` /
  `measure_rough` emitted the markdown tables `docs/vehicles.md` quotes, a figure would refresh by
  re-running the tool instead of going stale by hand.

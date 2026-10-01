---
name: vehicle-feel
description: Steps for a change to how a vehicle drives (gearing, mass, tyres, wheels, diff, wing, governor, brakes) on a Kenney or watercraft body or a hand-built spec.
---

Rules: `src/vehicles/CLAUDE.md` (+ the family's nested file). Steps:

1. Generated body (`kenney/*`, `watercraft/*`): edit the recipe in `tools/gen_kenney_vehicles.gd`
   / `tools/gen_boat_variants.gd`, never the `.tscn` / `.tres`. A tyre (`mu_*`) edit re-derives
   brakes, so it is a recipe edit too. A hand-built spec (semi, trailers, drone, plane, train):
   edit the `.tres` the shipped scene loads, then skip to step 3.
2. Regen (`tools/CLAUDE.md` § Rare generators) and diff: only the intended values move, and
   hand-authored collision survives.
3. Run the suite (`test_vehicle_catalog`, `test_kenney_variants` / `test_boat_variants`, the
   family's tests). A failing derived-value test is fixed in the recipe, not the spec.
4. Re-measure the changed variant (`tools/CLAUDE.md` § Measure tools): `measure_vehicles` for
   accel/top speed, `track` for straight-line, `corner` for an anti-roll change, `measure_grade`
   / `measure_rough` for a diff or traction change. Hand `all` / `baseline` sweeps to the user.
5. A figure in `docs/vehicles.md` / `docs/heavy_vehicles.md` that moved gets the new value and
   date.
6. Ask the user to verify by driving.

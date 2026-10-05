# 10 — Wheel radius and contact shape

Shared context: `00_README.md`. Root cause: a simplification held in place by tuning. Size: large
(touches every body). Do after briefs 04, 05 and 06, which re-derive brakes and gearing anyway.

## Summary

Every land body and trailer uses one physics wheel radius, 0.36 m, and its contact is a single
ray straight down from the hub. Real radii run from ~0.31 m (saloon) to ~0.5 m (truck) and
~0.85-0.95 m (tractor rear). The radius is pinned by tuning (gearing, brakes and grip ceilings are
all sized around 0.36), not by physics. A ray has no tyre shape, so steps and ditches behave unlike
a rolling tyre.

## What happens

- `tools/gen_kenney_vehicles.gd` `WHEEL_RADIUS = 0.36` for every Kenney body, pinned by
  `test_kenney_variants.test_every_body_runs_the_kit_wheel_radius`; the semi, conventional,
  trailer and farm-tipper specs also declare 0.36.
- `RayWheel.tick` casts one ray of `rest_length + wheel_radius` along the body's down axis from the
  hub anchor; the contact is the single hit, the force runs along the hit normal.
- Visual radius is separate (`wheel_visual_radius*`, `visual_lift`); brief 01 is the visible
  symptom of the mismatch on the tractor (0.44 / 0.66 m drawn).
- `Drivetrain.road_radius` = `wheel_radius` scales gear selection.
- Tractor CLAUDE.md: "Physics radius stays 0.36 (`road_radius`: gears, 40 km/h gear)". Tractor
  Rejected entry: "An MFWD lead ratio between the axles: it would be wind-up, not feel (both share
  the one physics radius)." `src/vehicles/CLAUDE.md`: "RayWheel is single-radius".

## Why it matters

- Overall gearing scales linearly with radius, so a radius change is a re-derivation of gearing,
  brake torque, handbrake, retarder, wheel inertia and grip ceilings, not a blocker.
- Ray contact: a kerb is climbed the instant the ray passes it (no rearward obstacle force, a
  compression spike held by `max_suspension_force`); a ditch narrower than the tyre catches the ray
  where a real tyre would bridge it. `measure_rough`'s ditches (20 / 35 / 50 cm) are where this
  shows, and a real 0.9 m tractor tyre would treat them very differently from a 0.36 m ray.
- The tractor's front and rear tyres really differ; a real MFWD runs a lead ratio matched to their
  rolling circumferences. With a per-axle radius, a lead ratio becomes meaningful again (reversing
  the Rejected entry is the user's call).

## Options (the planner chooses)

- A per-body, then per-axle, physics radius matching the drawn tyre, with gearing re-derived to keep
  road speeds; `Drivetrain.road_radius` per driven axle.
- A shaped contact: a sphere or cylinder shape cast, or several rays per wheel. Cost matters:
  4-12 wheels per rig at 60 Hz on the web build (perf target: 60 fps in the worst view on the
  deployed web build, root CLAUDE.md).

## Constraints

- `BaseVehicle.rest_ride_height()` spawns, `visual_lift`, radius-normalised wheel scenes, the
  right-side flip on the child.
- Gameplay rays mask `Layers.SOLID` (root CLAUDE.md).
- Tractor: the rear visual 0.66 m is a ceiling because the spreader hopper sweeps the tread
  (`test_three_point_hitch`); the linkage, implements and drawbar are authored against today's
  geometry (`Drawbar` pin 0.40 m over the road; chassis = scene coordinate + 0.3935).
- Trailers scale the kit wheel on the instance; `test_drawbar_trailer.test_the_wheel_visuals_match_the_specs_anchors`.
- 60 Hz clamps are sized on `corner_mass`, independent of radius; the spin step uses
  `wheel_inertia` and `wheel_radius`.

## Done

- The physics radius matches the drawn tyre per axle, or a stated reason says why not; gearing,
  brakes and inertias re-derived; the radius pin test replaced.
- A contact-shape decision documented, with its perf cost on the web build.
- `measure_rough`, `measure_grade` and the accel table regenerated.

## Open decisions (user)

- Per-axle radius and an MFWD lead ratio (reverses a Rejected entry).
- Shape-cast contact vs a single ray.

## Related

Brief 01, 04, 05, 06, 11.

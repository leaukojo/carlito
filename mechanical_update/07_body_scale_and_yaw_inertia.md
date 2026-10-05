# 07 — Body scale and yaw inertia

Shared context: `00_README.md`. Root cause 3 (toy-scale geometry with real mass). Size: medium. Do
before brief 08 (balance is tuned on the final inertia).

## Summary

The Kenney bodies are short: roughly real width, ~60 % of a real wheelbase, under real masses and
real COM heights. The physics is honest for that footprint, which is a city car's carrying a
saloon's mass. **User decision (2026-10-05): keep the Kenney models and keep the physics honest;
judge each body against a real vehicle of the same footprint.** This brief lists the tuning that
bends bodies toward full-size figures, the targets that ask for full-size figures, and the one
property that is an artefact rather than a footprint fact: yaw inertia.

## Facts (from the specs)

- `sedan`: wheelbase 1.58 m (front axle z -0.822, rear 0.762), track 1.26 m, collision boxes
  1.8 m wide x 2.88 m long (plus an upper box), COM ~0.48 m above the road. COM height / wheelbase
  ~0.30, against ~0.20 on a full-size saloon. A Smart Fortwo (1.87 m wheelbase) is the real
  footprint class.
- `suv` 1.58 m wheelbase; `garbage-truck` 1.94 m (a real refuse truck: ~3.9-4.5 m);
  `tractor-kenney` 2.12 m (Kenney body at scale 1.35). The hand-built semis have a real 3.60 m
  wheelbase and are out of this brief's scope.
- Consequence: longitudinal load transfer per g is ~1.5x a full-size saloon's; the front axle
  unloads hard on a rear-biased launch.

## What bends toward full size

Real hardware, inside real ranges, to keep:
- Anti-dive and anti-squat link slopes (`CAR_BASE` 0.4 / 0.5 of 100 %, road cars run 20-50 % /
  30-70 %; `TRUCK_BASE` anti-squat 0.5).
- Springs sized per axle from a ride frequency (`ride_hz`, `_derive_springs`).

Fudges that exist to hit full-size behaviour (`tools/gen_kenney_vehicles.gd`):
- `garbage-truck` `com_y` 0.85 instead of 1.05, "bounded by the launch, not the rollover … the
  body wheelied". Truck CLAUDE.md: "COM sits at real height; never lower a COM to buy a rollover
  threshold back", and `src/vehicles/CLAUDE.md`: "never a lower COM". Same spirit for a launch.
- `TRUCK_BASE` springs 400 kN/m (~2.5 Hz on the front corner) at ~0.6 / 0.8 of critical damping,
  "bounded by launch pitch on the toy 1.94 m wheelbase".

Targets that ask for full-size figures:
- Launch pitch is judged against full-size cars: the `CAR_BASE` comment says "a launch pitches
  the SUV 6 deg; a real car pitches 1-2", and `docs/vehicles.md` § Pitch frames the link geometry
  as fixing a pitch "~3x a real car".
- The `measure_vehicles` tracking pass fails a tick with the whole front axle off the ground (a
  CI gate). Keep the gate (a wheelie on a road car is wrong at any footprint) but reach it with
  real levers.

A correct consequence, not a fudge: the `sedan`'s `brake_bias_front` 0.873 (87 % front, against
~65-75 % on full-size saloons) follows from the transfer. Leave it.

## Yaw inertia

- Jolt computes the inertia tensor from the collision boxes at uniform density about the declared
  COM. Rule (`src/vehicles/CLAUDE.md` § Wheels and ground): "Never set `RigidBody3D.inertia`";
  guard `tests/test_body_inertia.gd`. Uniform density puts as much mass in the overhangs as in the
  engine bay.
- **Computed** for the `sedan` from its two boxes: Izz ~1000 kg·m², k² = Izz/m ~0.87 m², front x
  rear axle distance from the COM (a x b) ~0.60 m², so the yaw dynamic index k²/(a·b) ~1.45.
  Road cars are commonly quoted near 1 (the planner should source a figure per class, including
  short cars), because their mass concentrates between the axles. An index above 1 makes yaw lag
  the steering and overshoot more; it may be part of what `rear_lat_grip` (brief 08) is
  compensating.
- Lever: declare radii of gyration (per body or per class) and set the tensor from them. That
  reverses the "never set inertia" rule. The rule exists so a COM move (`TowedBody.set_load_offset`)
  and a runtime mass rewrite (`BaseVehicle.set_live_mass`, the refuse hopper) keep the tensor right
  (`test_body_inertia`: the tensor scales with a runtime mass rewrite; roll and pitch follow the
  custom COM). A declared gyration tensor scaled by live mass and shifted by parallel axis for COM
  moves would keep both properties. **User decision.**

## Constraints

- `src/vehicles/CLAUDE.md`: "Weight split: declare `front_weight` in the recipe. A raw `com_z` is
  only for a body tuned by driving (garbage truck)"; "A car-family COM height (`com_y`) stays
  below ~45 % of the body's AABB height. If a narrow body tips before it slides, the levers are the
  anti-roll bar or `mu_lat`, never a lower COM."
- Tractor: COM is `com_y_frac` of the scaled AABB; front unload is fixed with `front_weight`,
  never COM height (tractor CLAUDE.md).
- Springs are re-derived through the generator; `test_kenney_variants.test_springs_are_what_the_generator_derives`.
- Re-measure: `measure_vehicles` (accel, track, corner, brake), plus a step-steer check (the
  2026-10-03 step-steer probe in `docs/vehicles.md` § Balance was a one-off, not a shipped tool).

## Done

- Every Kenney body is tuned within real hardware ranges for its footprint. Each fudge is removed
  or restated as an honest choice (e.g. the garbage truck at real COM height, its wheelie handled
  by weight distribution, traction control or gear 1).
- The pitch and front-lift targets are restated for the footprint (e.g. pitch per g against
  COM height / wheelbase), or kept with a stated reason.
- Yaw inertia: decision taken; if declared, the index sits in a realistic band and the inertia
  tests express the new rule.

## Open decisions (user)

- Declared radii of gyration (a rule change) or not.
- What reference the pitch and front-lift checks use.

## Related

Brief 08 (balance), 04 (brake split follows the transfer), `docs/vehicles.md` § Pitch, § Balance,
§ Inertia.

# 11 — Tractor: implement weight and draft

Shared context: `00_README.md`. Root cause: a missing phenomenon (implement weight), plus a draft
law shaped by a 60 Hz bound. Size: medium. No hard dependency; brief 10 (tractor tyre radius)
touches the same machine.

## Summary

Implements on the three-point hitch weigh nothing, so lifting a plough or carrying a full
spreader never moves load between the axles. That load shift is the defining tractor phenomenon
(it is why front ballast weights exist). The draft force ramps up from zero over the first 2 m/s,
where real draft is mostly speed-independent; the ramp is held there by a 60 Hz angular bound, not
by a physical reason. The hitch has position control only.

## What happens

- Tractor CLAUDE.md § Implements: "VISUAL only: no collision, joint or body in the subtree."
  Code: `src/vehicles/tractor/implement_base.gd`, `three_point_hitch.gd`, `implement_catalog.gd`,
  `implements/` (plough, harrow, mower, spreader).
- `TractorVehicle._apply_draft` (`src/vehicles/tractor/tractor.gd`): force = rated
  `draft_max_force` (12 kN) x depth x soil x speed ramp, applied at `ThreePointHitch.hitch_point()`
  below the COM, along the tractor's forward axis.
- `TractorTelemetry.draft_newtons` (`src/vehicles/tractor/tractor_telemetry.gd`, ~lines 87-92):
  magnitude x `clamp(|v| / DRAFT_SPEED_REF)` (2 m/s), capped at `body_mass * |v| / delta`, signed
  against travel. So it is already 0 at rest and can never push the tractor; without the ramp it
  would still be 0 at a standstill.
- The ramp's comment gives two reasons: "a constant rearward force would shove a standing tractor
  out of the furrow" (not true of the capped, signed law above) and "It is also the 60 Hz margin".
  The second is the real one. Below `DRAFT_SPEED_REF` the law is a linear damper `F = -k v`, kept
  well damped at 60 Hz (`k * dt / m < 0.5`). The one-tick cap bounds only the LINEAR impulse, and
  the force acts ~1.3 m behind the COM, so a larger force could spin the chassis. Guard:
  `test_tractor.test_the_shipped_rating_keeps_the_60hz_damper_margin`, whose comment says raising
  the rating "means the force needs a real angular bound too, not just a bigger number".
- The drawbar trailer (`farm_tipper`) is a real body with mass and a 12 % nose weight: towed weight
  is modelled; mounted weight is not.

## Real-world reference (the planner should source exact figures)

- Mounted three-furrow plough ~0.8-1.2 t; fertiliser spreader with a full hopper 1-3 t; mower
  ~0.5-1 t. Lifting a heavy mounted implement unloads the front axle and lightens the steering;
  in work the implement's weight and draft load the rear.
- Draft is mostly speed-independent at working speeds (ASABE D497 form: a constant term plus
  speed and speed-squared terms). At a standstill it only resists motion; it never pushes.
- Draft control (the Ferguson system): the hitch adjusts depth to hold draft constant, alongside
  position control. ISOBUS already carries `draft_force` and `hitch_pos_actual`.

## Scope ideas (the planner decides)

- Implement mass and COM per implement, applied through the linkage (a force at the hitch, or
  folded into the tractor's live mass and COM the way `TowedBody.set_load_offset` moves a
  trailer's), so lifting and lowering change axle loads and pitch. A spreader could lose mass as it
  spreads, like the refuse hopper gains it; check that against the root non-goal "crop/farm
  simulation" (payload mass is fine; modelling the crop is not).
- A speed-independent draft above crawl speed, which needs the angular bound the guard test asks
  for; Tractor CLAUDE.md § Draft says "Keep the speed ramp", so dropping or reshaping it is a rule
  change for the user.
- Optional draft-control hitch mode (hitch control, not crop simulation).

## Constraints

- Implements stay visual (no body in the subtree) unless the user changes that rule.
- Tractor CLAUDE.md § Draft: draft is ONE force at the hitch; "engine_load / rpm sag / wheel_slip
  are its consequences; never add a draft term to them (rule 3)"; "Keep the speed ramp: it is the
  60 Hz margin"; "The force sits below the COM on purpose"; the linkage is posed before draft reads
  `ball_lift()` / `hitch_point()`.
- Tractor CLAUDE.md § Body: "Traction is ballast (`mass`, `front_weight`)"; COM is `com_y_frac`;
  front unload is fixed with `front_weight`, never COM height.
- `BaseVehicle.set_live_mass` is the one runtime mass write (it re-shares `corner_mass` for the
  60 Hz clamps).
- A draft-control mode, or any new hitch signal, is a contract change (`contract-edit` skill).
- Measuring: no tool reports front-axle load with an implement lifted vs lowered today; the planner
  may need one (`measure_grade` and `measure_rough` drive the tractor without implements).

## Done

- Lifting a heavy implement visibly lightens the front axle (axle load, steering); lowering it
  loads the rear.
- If the draft law changes: it stays a resistance (never a push), stays inside a stated angular
  bound at 60 Hz, and its guard test expresses the new margin.
- Tests for the load model and the draft law; tractor docs updated (`docs/heavy_vehicles.md`
  § Tractor, implement & ISOBUS).

## Open decisions (user)

- Implement masses; whether the speed ramp is reshaped (rule change); whether draft control is
  wanted (and on the bus).

## Related

Brief 10 (tractor tyre radius). Brief 03 does not bear on the draft law (see its "Not this gap").

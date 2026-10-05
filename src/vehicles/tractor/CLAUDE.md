# Tractor & implements — rules

Tour: `docs/heavy_vehicles.md` § Tractor, implement & ISOBUS and § The drawbar. Shared towing (`TowHost`, `TowedBody`, `Articulation`):
`src/vehicles/CLAUDE.md` § Towing.

## Draft

- Draft is ONE force (rated × depth × soil × speed ramp) at the hitch from `_tick_extras`.
  `engine_load` / rpm sag / `wheel_slip` are its consequences; never add a draft term to them (rule 3).
- Keep the speed ramp: it is the 60 Hz margin, and a constant force would shove a standing tractor
  out of the furrow. Guard: `test_the_shipped_rating_keeps_the_60hz_damper_margin`.
- Depth comes from the implement (`tool_depth()`), lift from `ThreePointHitch.ball_lift()`, and
  `_tick_extras` poses the linkage BEFORE reading it (else a tick stale).
- "In soil" is splat channel 4 "Field" (not Dirt; Auto-splat wipes it: `src/levels/CLAUDE.md`).
- The force sits below the COM on purpose; do not move it to chase pitch.
- `engine_load` is not monotone in draft (delivered over peak torque): verify above peak-torque rpm.

## Body

- Suspension IS the tyres: stiff and short-travel is the picture, not a softening target.
- Traction is ballast (`mass`, `front_weight`), never the torque curve or `final_drive`: low-end
  torque at `converter_free_rpm` pulls a drawbar trailer away.
- A pull-away is a powershift launch (`launch_engage_s`, `launch_gear` D3); D1 is the bogged-start
  fallback, never detuned. Guard: `test_drivetrain` (the launch tests).
- The COM is `com_y_frac` of the body AABB, never a metre figure (`scale` moves). Front unload is
  fixed with `front_weight`, never COM height.
- `scale` 1.35 is bounded by what it does not reach: linkage, implements, tipper.
- Physics radius stays 0.36 (`road_radius`: gears, 40 km/h gear). The rear visual 0.66 is the
  ceiling: the spreader hopper sweeps the tread past it (`test_three_point_hitch`).
- Chassis coordinate = scene coordinate + 0.3935 (`ThreePointHitch` / `Drawbar` mount);
  `test_drawbar_trailer` / `test_three_point_hitch` compose it.

## Drawbar

- Pin datum is **0.40 m over the road, never the semi's -1.05** (a fifth-wheel plate height).
  `farm_tipper` is authored at the eye with ground at y = -0.40. This file is the one owner.
- `ImplementCatalog.TOWED` routes ids before anything is instanced; `test_drawbar_trailer` sweeps it.
- The pin is fixed: a swinging bar moves the hole while the joint stays put.
- Roll ±25 deg (a rut must not lever the tractor); never narrow toward the fifth wheel's ±1.5.
- Yaw is `Drawbar.SWING_MAX_DEG` (80, the rear tyres), not `Articulation.JACKKNIFE_MAX_DEG`; swept by test.
- Size `TIP_COM_SHIFT_Z` by what stays on the pin (nose weight 12 %, not a 27 % share).
- Two vocabularies, `consumers()` and `connections()`, agree (SCV ⟺ HYDRAULIC, tested).
- No bus claim is content (attached steel, electronic silence), not an omission.
- `Drawbar` is a direct child of the scene root, never under `Model` (regen wipes it:
  `kenney/CLAUDE.md`).
- A never-ticked towed body keeps its authored wheel-root transforms: `farm_tipper.tscn` authors
  `Wheels/*` at the hubs for the selector card / garage.

## Implements

- Declared in CODE (`Connection.*`), never exported data. Device classes are unique
  (`test_implement_catalog`); draft-relevant implies `tool_depth() > 0`. Gating lives in
  `ThreePointHitch`.
- VISUAL only: no collision, joint or body in the subtree. Authored lowered, origin on the lower
  pin line (ground y = -0.21); geometry is measured off the scene. Moving a merged leaf mesh
  means listing it in `static_merge_skip()`.
- `spin_from_pto` ratio is cosmetic (540 rpm aliases at 60 fps); published rpm stays honest.
- The foot brake is rear-only (`brake_bias_front` 0) and engages MFWD while held
  (`brake_engages_front_axle`), so the shaft brakes the fronts and `fwd_drive_state` reads true.
  Guard: `test_the_foot_brake_engages_the_front_axle_and_brakes_only_the_rears`.
- `wheel_speed` reads the REAR axle only (MFWD changes the driven set). `pto_mode` is a gearbox
  off `PTO_RATED_RPM`; `test_tractor` pins it against redline.
- Absent signals publish a real 0 / false every tick.
- `cycle_implement()` is duck-typed: `boot.gd` / `VehicleCatalog` never learn implements exist.
- `scv_flow` has a local key (Q), binary, gated by `running`; owner `InputRouter._scv`.

## Rejected / expected

- An MFWD lead ratio between the axles: it would be wind-up, not feel (both share the one physics radius).
- Level 1's first E at the tractor spawn is refused by the fit check (scenery close behind): that
  is the check working; pull forward.

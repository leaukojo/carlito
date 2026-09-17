# Plan — heavy vehicle feel: truck tyres and coupling, tractor suspension and traction

Goal: the truck and tractor families are structurally honest (real joint, apportioned trailer
brakes, retarder with a slip backstop, draft as one force) but their NUMBERS are a car's: car
tyre grip on a 32 t rig, a sedan's suspension under a 4 t tractor, and a first-gear torque three
times what the rear axle can put down. Each phase is a spec retune or one small mechanism, and
each is proven by the measure tools before the next. Delete this file when done and distil each
phase's conclusion into the family `CLAUDE.md` named in it.

Written 2026-09-17. Status: **not started.**

**Order dependency.** `truck_model_hygiene.md` phases 3 (per-axle springs) and 4 (spawn at rest
height) come FIRST: every number below is measured against the rig's static pose, and today that
pose is nose-up on a compromise spring and still settling from the spawn drop. Retuning tyres or
dampers on top of that is tuning against noise. Phase T1 (tyre mu) may run before hygiene 3 if
needed, since it moves grip, not pose. `centre_of_mass_heights.md` comes AFTER this plan.

Read first, every phase: root `CLAUDE.md`, `src/vehicles/CLAUDE.md` § Wheels, § Measuring, §
Towing; `src/vehicles/truck/CLAUDE.md` whole (the brake/retarder arithmetic, the fifth wheel,
the four trailers); `src/vehicles/tractor/CLAUDE.md` (the draft force, its 60 Hz margin).
Kenney-generated specs (`garbage-truck`, `firetruck`, `tractor-kenney`, ...) are edited in
`tools/gen_kenney_vehicles.gd`'s recipe and regenerated, never in the `.tres` (the regen wipes
it). The semi, conventional and the four trailers are hand-authored `.tres` with reasoning in
their headers — keep the reasoning, move the numbers.

## What is wrong today (the evidence)

Truck (`semi_spec.tres`, `conventional_spec.tres`, the four trailers, `TowHost`):

- `mu_long` 1.0 / `mu_lat` 0.95 on every unit and trailer; a real truck tyre on dry asphalt is
  0.7-0.8. So a coupled rig brakes and corners at nearly 1 g, the main "arcade" tell in the
  family. Every brake number is DERIVED from mu (`BRAKE_GRIP_FRAC * mu_long * load * r`), so
  this is a re-derivation, not a number edit.
- The one damper pair is sized bobtail: rear corner 1.92 t, k 240 kN/m, damping ratio
  `12000 / (2 sqrt(240000 * 1920))` = 0.28. Coupled to the box the plate adds 6.47 t to that
  axle (5.16 t per rear corner): 1.09 Hz and a ratio of 0.17. A laden rig pitch-rocks after a
  bump or a brake release. Hygiene phase 3 fixes the RATE; this plan makes sure the DAMPER is
  sized for the coupled load, not the bobtail one.
- The fifth wheel's yaw is a free hinge (`Generic6DOFJoint3D`, yaw limited to ±75° with no
  spring, damping or friction). A greased plate still carries dry friction of the order of
  1-3 kN·m; today only tyre lateral grip damps trailer sway.
- Trailer brakes apply the same tick as the pedal. Air reaches a trailer's chambers 0.3-0.5 s
  after the tractor's; the lag is what makes a rig "push" on the first brake application.

Tractor (`tractor-kenney` recipe, `tractor.gd`):

- Suspension is a sedan's: k 70 kN/m on 1 t corners is 1.33 Hz, damping ratio 0.36, 0.35 m of
  travel. A real tractor has a rigid rear axle on tyre compliance alone and usually a rigid
  front: 2.5-3 Hz, a few cm of "travel", and it jolts. It should ride like a tractor.
- Gear-1 wheel force is `700 * 7 * 5.5 * 0.9 / 0.36` = 67 kN against a rear axle weight of
  ~20 kN at mu 1.0 — 3.4× traction. Real tractors are ballasted so that ratio is ~1.5, and the
  MFWD engage adds nothing here because both axles share one physics radius.
- The body is a compact/toy tractor (2.2 m long, 1.57 m wheelbase, 0.45 m rear tyres) carrying
  a 4 t spec; a real 4 t tractor is twice the length on 0.8 m tyres. Phase R0.
- COM is 0.35 m over the road on a machine whose real COM is ~0.9 m — deferred to
  `centre_of_mass_heights.md`, but note that the front-wheel lift under draft that tractors are
  known for needs both the stiff springs (this plan) and the height (that one).

## Phase T1 — truck tyres are truck tyres

Effort **medium-high**. Mode: **plan-mode first** (the brake hierarchy is arithmetic that must be
re-derived, not re-measured), then accept-edits. Opus for the derivation, Sonnet for the sweep.

1. Target: `mu_long` 0.80, `mu_lat` 0.75 on both tractor units, the four trailers, and the
   Kenney `truck` family recipe (`garbage-truck`, `firetruck`, `delivery`, ...; check which
   recipe rows are family `truck` — the vans/pickups are `car` and keep car tyres).
2. Re-derive, in plan mode, every number that hangs off mu, and write the derivation into the
   report before touching a file:
   - `brake_torque` on each hand-authored spec: `BRAKE_GRIP_FRAC * mu_long * per-wheel static
     load * r`. For the units that is the bobtail static rear load PLUS the plate load (the
     spec header's own arithmetic); for each trailer, its bogie load. `handbrake_torque` stays a
     flat quarter of the service brake (the ~25 % holding-grade rule).
   - The retarder band: `RETARDER_MAX_FRAC * BRAKE_GRIP_FRAC * mu_long * g / 2` drops from
     0.93 to 0.74 m/s² on the grip-derived trucks, BELOW `test_truck`'s 0.9 floor. Decide:
     raise `RETARDER_MAX_FRAC` to 0.25 (0.93 again, and the hand-built units go 1.46 → 1.82,
     over the 1.6 ceiling) or move the band to [0.7, 1.5]. The band exists to keep brake >
     drive > handbrake; recompute that hierarchy and pick the option that keeps it, then say
     which in `truck/CLAUDE.md` § Brakes.
   - `RETARDER_SLIP_TARGET`'s margin: `test_truck` pins the settled slip against the spec's own
     grip curve and static rear load, so it re-derives itself — confirm it still passes.
   - The trailer `brake_demand` blend and the ISO 11992 `trailer_abs` threshold are unaffected
     (they read slip, not mu).
   - Climb: the rig is grip-limited on the 25 % grade (`truck/CLAUDE.md` § The fifth wheel).
     At mu 0.8 the coupled drive axle holds ~0.8 × 101 kN = 81 kN against gear 1's 110 kN, so
     it still climbs but spins more readily. Re-measure the launch (`measure_semi_launch -- semi`
     and `-- semi-conventional`): steer-axle load ≥ 8.6 kN and pitch < 4° must hold, and the
     grade climb must still complete. If it does not, the lever is `torque_curve`'s low end or
     ballast, never mu back up.
3. `min_steer_frac` / `steer_falloff_speed` on the units were sized against mu_lat 0.95
   ("16.5° at 30 km/h, tighter than mu_lat allows" in the recipe comments). At 0.75 the taper
   should tighten a little (more understeer margin at speed): re-run `measure_vehicles -- semi
   45 track strict` and the coupled variant; a tracking FAIL here is the steer taper, not the
   tyre.
4. Tests: `test_truck`, `test_trailer`, `test_vehicle_catalog`, `test_kenney_variants` (it
   re-derives brakes from the recipe). Update any literal that quoted 1.0.
5. Verify by driving: brake from 80 km/h coupled (should take visibly longer, no lock without
   the pedal floored), a 90° corner at 40 km/h coupled (the trailer should now push wide before
   the tractor does), a bobtail standing start at full throttle (wheelspin, briefly).
6. Distil into `truck/CLAUDE.md` § Brakes (the retarder band decision) and a line in
   `src/vehicles/CLAUDE.md` § Wheels: tyre class sets mu (car ~1.0, truck ~0.8, tractor lug
   ~1.0 on soil / 0.8 on asphalt), and everything brake-shaped is derived from it.

## Phase T2 — dampers sized for the coupled load

Effort **low**. Mode: accept-edits. One Sonnet sub-agent. After hygiene phase 3.

1. With `spring_rate_rear` in place, size the units' rear `damper_bump` / `damper_rebound` for
   the COUPLED rear corner mass (bobtail rear + plate share / 2), targeting a damping ratio of
   0.30-0.35 laden. Bobtail that reads ~0.5, over-damped, which is how an unladen truck feels
   (it skips over bumps). Quote both ratios in the spec header as a formula, the numbers in
   `test_trailer`'s travel-band test alongside the springs.
2. Hygiene phase 3 scales dampers by `sqrt(rate_rear / rate)` to keep the ratio at the bobtail
   load; this phase then multiplies by `sqrt(coupled_corner / bobtail_corner)` on the rear. Do
   both in one place (the spec) and say so.
3. The one-tick damper clamp (`corner_mass * |v| / dt`) is sized from `spec.mass / 4` = 2 t,
   and at 12-20 kN·s/m the damper is two orders below it (2000 / (1/60) = 120 kN per m/s), so
   it never binds. Confirm by arithmetic in the report; do not touch the clamp.
4. Verify: `measure_semi_launch -- semi` P1/P5 (pitch settle time after the drop should shorten;
   read it off the tool), then coupled over the level-1 speed bump at 30 km/h by driving:
   one bounce, not three.
5. Distil into `truck/CLAUDE.md` § The fifth wheel (one line beside the spring-rate rule).

## Phase T3 — fifth-wheel friction and trailer brake lag

Effort **medium**. Mode: accept-edits. Opus (two small mechanisms on a jointed body — the
"two churning physics properties" trap in `truck/CLAUDE.md` applies).

Fifth-wheel friction:

1. `CouplingProfile` gets `yaw_friction_nm := 0.0` (0 = today). The semi's profile ships
   ~2000 N·m; the tractor drawbar's stays 0 (a pin in an eye is nearly free).
2. Apply it in `TowHost.tick_towing` as a torque pair about the joint's world yaw axis: on the
   trailer `-sign(relative_yaw_rate) * min(friction, I_trailer_yaw * |rate| / dt)` and the
   equal-and-opposite on the chassis. Coulomb, so it is a `damped_force`-shaped one-tick clamp
   against the RELATIVE yaw rate, never a spring to zero angle (a spring would re-centre the
   trailer and that is not a plate). Do NOT use the joint's own angular motor/spring params:
   Jolt's 6DOF motor is a velocity target, not friction, and it fights the yaw limit.
3. Tests (`tests/test_tow_host.gd` or the trailer suite — check where `TowHost` pure logic is
   tested): sign opposes relative rate, magnitude capped by the one-tick rule, 0 at 0 rate.
4. Verify: `measure_vehicles -- semi 45 track strict` coupled (straight-line tracking at speed
   should not change), then a lane change at 60 km/h coupled by driving: the trailer should
   settle in one swing.

Trailer brake lag:

5. `TowedBody.tick_towed` receives `brake01`; give it a first-order lag: `_brake_actual =
   move_toward(_brake_actual, brake01, delta / TRAILER_BRAKE_LAG_S)` with `TRAILER_BRAKE_LAG_S`
   0.35 on apply, 0.5 on release (chambers vent slower than they fill). The handbrake (spring
   brakes) is NOT lagged: it is a mechanical lock on air loss. Publish
   `trailer_brake_demand` off the LAGGED value (it reports what the trailer really brakes
   with, `truck/CLAUDE.md` § ISO 11992).
6. The retarder's share of the blend is unaffected (it is on the tractor).
7. Test: the lag rises and falls at its two rates, saturates, never exceeds the command.
8. Verify by driving: a firm stop coupled from 60 km/h — the tractor should dip first, the
   trailer catch up a beat later, no jackknife tendency on the flat.
9. Distil into `truck/CLAUDE.md` § The fifth wheel (friction) and § ISO 11992 (the lag).

## Phase R0 — the tractor is the size of a tractor

Effort **high**. Mode: **plan-mode first**, then accept-edits. Opus (the hitch, drawbar and
implement datums are all measured off this scene, and every one of them moves).

The evidence. `tractor-kenney.tscn`'s hull is 1.61 × ~1.6 × 2.21 m, wheelbase 1.57 m, rear tyre
visual radius 0.45 m, front 0.30 m — a compact/toy tractor at `KIT_SCALE` 1.2 — carrying a 4 t
spec. A real 4 t tractor is 4.0-4.5 m long on a 2.4-2.7 m wheelbase with rear tyres of radius
0.75-0.85 m and fronts of 0.45-0.55. Even against its own body the rear tyre is small (real
rear tyre diameter ≈ 40 % of overall length, which on this body would be r ≈ 0.45-0.5). Every
mass-shaped number in R1/R2 and `centre_of_mass_heights.md` phase 5 is a real-tractor number,
so the body must be a tractor first.

1. Mechanism: a per-variant `scale` override in `gen_kenney_vehicles.gd`'s `VARIANTS` row,
   multiplied into `KIT_SCALE` in `_analyze`'s `xform` (line ~866: `basis.scaled(ONE *
   KIT_SCALE * ov.scale)`, translation likewise). Default 1.0 so no other body moves; the
   tractor ships 1.35 (body 2.99 × 2.17 wide, wheelbase 2.12 m — the width is the limit: level
   1's field gates and the drawbar trailer's track are authored against 1.6 m, and 2.2 m is
   already a wide compact). Decide the exact factor in plan mode from those clearances, not
   from the ideal.
2. Wheels: `WHEEL_TRACTOR_REAR` radius 0.45 → 0.62, `WHEEL_TRACTOR_FRONT` 0.30 → 0.40 (ratio
   1.55), tread half-widths scaled with them (the flush-X rule places the outer face at the
   body side, so a wider tyre moves the wheel_x_out — check the sweep in `test_kenney_variants`).
   **Physics radius stays 0.36 on both axles**: RayWheel is single-radius by design and
   `visual_lift` absorbs the mismatch (`wheel_visual_radius_rear` precedent, already 0.45 vs
   0.36). Do not touch `WHEEL_RADIUS`: gear selection, the 40 km/h road speed, the retarder
   arithmetic and every `measure_vehicles` figure ride on it. Note the honest cost in the
   report: the rear visual now sits 0.26 m proud of its physics contact, so the ray's contact
   point is inside the drawn tyre; on a kerb the drawn tyre will clip before the physics one
   does. Acceptable for a field machine; say so in `tractor/CLAUDE.md`.
3. Wheel anchors: `_analyze` reads them off the GLB, so they scale with the model; `rest_length`
   / anchor y follow R1. Body-space datums that DO NOT scale automatically and must be re-derived
   against the new hull:
   - `Drawbar.PIN_LOCAL` (0, 0.40, 1.60) — read off the scene's `Pin` marker at runtime, so
     move the marker: z to the new rear face, y stays the trailer datum (0.40 is authored into
     `farm_tipper.tscn`'s ground plane; `tractor/CLAUDE.md`: never the semi's −1.05).
   - `ThreePointHitch` node transform (hand-authored, re-added last by the generator, line
     ~546): lower-link pivots to the new rear face and axle height. Implements are authored
     "origin on the lower pin line, ground at y = −0.21" — that −0.21 is the tractor's OLD
     lower-pin height over the road, and every implement's `tool_depth()` is measured against
     it. Either keep the lower pins at the same height over the road (preferred: nothing
     under `implements/` moves, only the hitch's reach) or re-author the datum and every
     implement. Decide in plan mode; the four-bar solve (`ball_lift()`) is geometry off the
     hitch scene, so the lift stroke (0.57 m today) scales with whatever the hitch is given.
   - `HoodCam` marker, `_fallback_lamp_y` for `tractor-kenney` (1.22), the chase-camera
     framing `get_camera_framing()` returns, the garage/selector card framing
     (`gen_vehicle_thumbs`).
   - `test_drawbar_trailer`'s corner sweep (trailer boxes vs tyres and chassis at
     `SWING_MAX_DEG`) and level 1's spawn: the tractor spawn has scenery close behind it, so a
     longer body may make the first E refuse at spawn (the fit check working) — move the
     spawn marker if so.
4. Spec consequences: `mass` stays 4000 here (R2 owns ballast); `drag_area` is derived from
   the AABB so it grows ~1.8× (crr, cd unchanged) — top speed is rpm-bound so nothing moves,
   but re-record the accel figure. `wheel_inertia` 4.0 was for a 0.45 tyre; a 0.62 rear tyre is
   ~2× (I ∝ r²) — set 6.0 rear-equivalent, single value, and check the semi-implicit spin step
   is unaffected (it is a divisor ≥ 1, so a bigger inertia only slows spin-up: safe).
5. Regenerate: `gen_kenney_vehicles`, then `gen_vehicle_thumbs` (WINDOWED) + import, then
   re-bake nothing (vehicles are not baked). `test_kenney_variants`, `test_tractor`,
   `test_drawbar_trailer`, `test_implement_catalog` (draft-relevant implies positive
   `tool_depth()` — the datum decision above is what keeps this green).
6. Verify: `measure_vehicles -- tractor-kenney 45 track strict`; hitch every implement with
   the hitch down on level 1's field and read F3 `draft_force` at full lower (must still reach
   100 % on the plough, and the harrow's tines must be in the soil, the 35 mm-in-the-air bug
   `tractor/CLAUDE.md` records); couple the drawbar trailer and drive the field edge; the
   selector card and the garage.
7. Distil into `tractor/CLAUDE.md`: the variant scale, why the physics radius did not follow
   the visual, and which datum was kept fixed.

## Phase R1 — the tractor rides like a tractor

Effort **medium**. Mode: accept-edits. One Sonnet sub-agent. After R0 and hygiene phases 3-4.

1. In the recipe row for `tractor-kenney`: `spring_rate` → 260 kN/m (2.57 Hz on a 1 t corner),
   `rest_length` → 0.12 m, `damper_bump` → 13 kN·s/m, `damper_rebound` → 16 kN·s/m (ratio
   0.40-0.50; a tractor's tyre has little hysteresis but we are modelling the whole axle). Static
   sag reads `1000 * 9.8 / 260000` = 3.8 cm, 31 % of the new travel — the same fraction band
   the truck family targets. `max_suspension_force` 110 kN stays (it is 11 g per corner).
2. With `spring_rate_rear` available, put the rear at 300 kN/m: the rear carries the drawbar
   nose weight and the implement, and the 0.45 m rear tyre is stiffer than the 0.30 front.
3. The draft-damper margin test in `test_tractor` (`k*dt/m < 2` on the draft force) is
   independent of the springs. The three-point hitch geometry is measured off the scene, not
   the ride height, so `ball_lift()` is unaffected; the implement's `tool_depth()` reads its own
   scene, but the tractor now sits ~5 cm lower at rest — check the plough's "in soil" depth at
   full lower against `docs/heavy_vehicles.md`'s quoted 0.055 m tool, and the harrow's tines,
   with the hitch DOWN on level 1's field. If a tool now reads full depth a stroke earlier,
   that is the picture and the number still agreeing; note it and leave the hitch alone.
4. Verify: `measure_vehicles -- tractor-kenney 45 track strict`, `-- tractor-kenney 45 coast`
   (no hull contacts — 12 cm of travel over level 1's ruts must not bottom; if it does the
   lever is `rest_length` 0.15, not the rate), the drawbar trailer coupled over the same ruts.
   Drive it over the field edge: it should pitch sharply and settle in one motion.
5. Distil into `tractor/CLAUDE.md`: a tractor's "suspension" is its tyres, the numbers are
   sized to 2.5-3 Hz on purpose, and the sag/travel fraction rule.

## Phase R2 — tractor traction: ballast, not torque

Effort **medium**. Mode: accept-edits. One Sonnet sub-agent. After R0 (a 5.5 t spec on the
2.2 m body would widen the mass-versus-size mismatch R0 closes) and T1 (the mu decision).

1. The torque-to-grip ratio in gear 1 is 3.4. Two honest levers: mass (ballast weights and
   liquid-filled tyres are how real tractors solve exactly this) and the rear weight split. Ship
   `mass` 5500 kg with `front_weight` 0.38 (rear axle 3.4 t, 33 kN; ratio drops to ~2.0 at
   mu 1.0 and the added mass lands where the draft reaction wants it). Do NOT trim the torque
   curve or `final_drive`: idle torque is what pulls the drawbar trailer away
   (`truck/CLAUDE.md` § Pulling away, the same law).
2. Consequences to re-derive: the draft force's 60 Hz margin (`k*dt/m` gets smaller — safer),
   `brake_torque`/`handbrake_torque` (recipe-derived from mass and mu, so the regen does it),
   the drawbar trailer's nose weight fraction (12 % of the TRAILER, unchanged), and
   `measure_vehicles` reports draft figures against `spec.mass` (the `-- semi` trap in
   `tractor/CLAUDE.md`) — re-record the numbers quoted in `docs/heavy_vehicles.md`.
3. Top speed in 6th is rpm-bound (redline 2600 / (1.6 × 5.5) at r 0.36 = 11.1 m/s, 40 km/h),
   so mass does not move it; acceleration and the governor-droop climb on level 1's grade will.
   Quote before/after 0-30 km/h and the grade climb speed.
4. MFWD: leave the single physics radius (a lead-ratio model is wind-up, not feel). Note in
   the report that engaging the front axle now adds 38 % of weight's worth of grip at the
   moment it is needed, which is the honest reason the button exists.
5. Tests: `test_kenney_variants` re-derives brakes; `test_tractor` draft margin; the pto/
   wheel_speed tests are mass-independent.
6. Verify: `measure_vehicles -- tractor-kenney 45 track strict`; full-throttle standing start on
   asphalt (some spin, then hook-up) and on the field (spin until MFWD or the diff lock, which
   is the lesson the two buttons teach).
7. Distil into `tractor/CLAUDE.md`: traction is ballast, the ratio, and the "never the torque
   curve" rule.

## Not in this plan

- COM heights for the units, trailers and tractor: `centre_of_mass_heights.md`.
- Engine braking, tyre load sensitivity, shift cut: `wheeled_feel_shared.md` (shared code; the
  truck and tractor opt in there with their own fractions).
- Per-axle spring rates and the spawn drop: `truck_model_hygiene.md` phases 3-4, which this plan
  waits on.
- The tanker's surge model, the tipper's interlock, the air system: honest and documented; no
  feel finding.

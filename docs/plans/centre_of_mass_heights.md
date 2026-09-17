# Plan — centre-of-mass heights: bodies that lean, transfer load, and can roll over

Goal: every wheeled body carries its centre of mass at roughly HALF its real height, so nothing
leans in a corner, load transfer is negligible, and rollover is geometrically impossible. That
flatness is the single biggest "video game" tell across car, truck and tractor. Raising the COM
is one number per family in the Kenney recipe and one per hand-authored spec — but it is the
riskiest retune in the vehicle set, because it changes what every tracking, launch and travel
measurement was taken against, and it makes rollover a real outcome the game currently has no
answer to. So this plan is LAST after `truck_model_hygiene.md` and `heavy_vehicle_feel.md`, and
its first phase builds the safety net. Delete this file when done; distil into the `CLAUDE.md`
files named per phase.

Written 2026-09-17. Status: **not started.** Blocked on: hygiene phases 3-4, heavy-feel T1/R1.

Read first: root `CLAUDE.md` rules 3 and 9, `src/vehicles/CLAUDE.md` § Wheels and § Measuring,
`tools/gen_kenney_vehicles.gd` (`com_y` is a FAMILY figure, `com_z` per body via
`front_weight`), `truck/CLAUDE.md` § The fifth wheel (the plate share is `center_of_mass.z`
against the bogie; y is the trailer's own decision, documented in each trailer's header),
`base_vehicle.gd` (`CENTER_OF_MASS_MODE_CUSTOM`; the inertia tensor is Jolt's off the collision
hull and is NOT moved by the COM write — check whether `inertia` is set anywhere; if it is the
hull's, a raised COM still rolls about the hull's centroid and this plan needs an explicit
`inertia` per spec, which is the first thing phase 1's Opus decides).

## The numbers (body-space y over the road; ground plane = anchor.y − (rest + r − static sag))

| body | today | real | half-track | rollover g today | rollover g at real | tyre mu |
| --- | --- | --- | --- | --- | --- | --- |
| sedan | 0.20 | 0.50 | 0.69 | 3.4 | 1.4 | 1.1 |
| suv | 0.20 | 0.70 | ~0.72 | 3.6 | 1.0 | 1.0 |
| semi unit (bobtail) | ~0.45 | 1.00 | ~0.95 | 2.1 | 0.95 | 0.75 (after T1) |
| box trailer, laden | 0.65 | 1.80 | ~0.95 | 1.5 | 0.53 | 0.75 |
| tractor | 0.35 | 0.90 | ~0.60 | 1.7 | 0.67 | 1.0 |

Rollover g = half-track / COM height, the static tip-over threshold on a flat road; a body
rolls before it slides when it is below its tyre mu. So at real heights: the car stays
slide-first (correct), the SUV is marginal (correct — SUVs roll), the bobtail is marginal, and
the laden trailer and the tractor are ROLL-FIRST (correct, and lethal in real life). The
game must decide what happens then before it ships those two.

## Phase 1 — the safety net: a body that ends up on its roof

Effort **medium**. Mode: **plan-mode first**, then accept-edits. Opus.

1. Decide the response to an overturned body. Options, pick one in plan mode: (a) automatic
   respawn after N seconds inverted with the existing notice path (`GameState.notice.emit`,
   the body-interlock shape), which `respawn_is_a_reset.md` makes safe if it has landed —
   check its status first; (b) leave it to the player's existing respawn key with a notice
   only. Recommend (b) plus the notice: an automatic reset hides the consequence the height
   was raised to create. Either way the detection is pure: `up.dot(Vector3.UP) < cos(threshold)`
   held for `OVERTURNED_S` on `BaseVehicle`, tested.
2. A jointed rig on its side: `TowHost` must not fight it. Check that the joint's roll limit
   (±1.5° plate, ±25° drawbar) against a trailer on its side does not launch the tractor;
   `measure_semi_launch` has no such phase, so add a "tip" phase (drive a coupled rig into a
   40 km/h step-steer and record whether it rolls, and the joint forces if it does).
3. The chase camera and the water kill volume are unaffected (camera reads position, water
   reads layer); the F3 overlay should show roll angle already via `roll_deg` — confirm.
4. Distil into `src/vehicles/CLAUDE.md` § Wheels (one line: overturned is a detected state with
   a notice, never an auto-reset).

## Phase 2 — inertia follows the COM

Effort **medium**. Mode: accept-edits. Opus (Jolt specifics).

1. Determine how the body's inertia tensor is set today. Jolt derives it from the collision
   shapes about the shape centroid, then the custom COM shifts the frame — but a Kenney hull
   is a box the size of the silhouette, so the roll inertia is about right and the COM offset
   is the only thing changing. Verify by reading `RigidBody3D.inertia` at runtime for the
   sedan (print in a headless run) and comparing with a box of the body's AABB.
2. If the tensor is sane, nothing to do; if it is the hull-centroid one and the raised COM
   makes the body roll about a point below its mass, set `inertia` explicitly per spec from
   `VehicleMath.inertia_of` on the body AABB (the plane's `body_extents` precedent). A body
   that receives an explicit `inertia` must keep it through `set_corner_mass_from`'s mass
   rewrite (the refuse hopper) — Jolt rescales a custom inertia with mass, confirm.
3. Distil into `src/vehicles/CLAUDE.md` § Wheels.

## Phase 3 — the car family

Effort **medium**. Mode: accept-edits. One Sonnet sub-agent; Opus only if tracking fails.

1. Recipe `com_y` for family `car`: 0.20 → 0.48. Per-body overrides: `suv` / `suv-luxury` 0.62,
   `race` / `race-future` 0.30 (they are 0.9 m tall), `van` / `delivery` / `ambulance` 0.65
   (these are family `car` in the recipe with tall bodies — check the rows and the AABB
   heights `gen_kenney_vehicles` measures; a COM above 45 % of the body's AABB height is wrong
   for anything). Regenerate.
2. What moves and must be re-measured: `measure_vehicles -- all 45 track strict` (a higher COM
   makes the rear-drivers' lift-off transfer real, so a body that tracked can now wander —
   the lever is `mu_lat` front/rear, never the COM back down); the steady-state lateral-g
   reading added in `wheeled_feel_shared.md` phase 2 if landed, else add it now. Downforce
   travel budget in `test_vehicle_catalog` is COM-independent.
3. The suspension will now show body roll: sedan at 0.9 g with 1.4 Hz springs and no anti-roll
   bar rolls ~5-6°, which is a real (soft) saloon. Add an anti-roll term ONLY if the SUV's roll
   at the limit exceeds ~8°: a pure `anti_roll_force(comp_l, comp_r, rate)` transferring spring
   load between the two wheels of an axle (equal and opposite, so it adds no net vertical
   force — no energy, no clamp needed beyond the existing suspension cap), field
   `anti_roll_rate` on `GroundDriveSpec`, 0 = none, tested.
4. Verify by driving: sedan at 100 km/h through level 1's S-bend leans and settles; SUV at the
   limit lifts an inside wheel before it rolls; race car stays flat. Handbrake turns should now
   transfer visibly.
5. Distil into `src/vehicles/CLAUDE.md` § Wheels: `com_y` per body class as a fraction of AABB
   height (car ~0.35, SUV/van ~0.42, race ~0.30), and the anti-roll rule.

## Phase 4 — truck units and trailers

Effort **high**. Mode: **plan-mode first**, then accept-edits. Opus.

1. Semi and conventional `center_of_mass.y`: 0.35 → 0.95 body space (verify the unit's ground
   plane off its anchors at the post-hygiene static pose; target ~1.0 m over the road). The
   Kenney `truck` recipe `com_y` 0.30 → 0.75 (`garbage-truck`, `firetruck`; the refuse hopper's
   mass rewrite does not move the COM, `truck/CLAUDE.md` § The refuse body — keep that).
2. Trailers, one at a time, each its own decision written into its `.tres` header:
   box 1.6 m over the road (palletised freight is NOT floor-only in reality; the header's
   current "sits on the floor" reasoning is what this phase overturns), flatbed 0.9 (steel on
   the deck), tanker 1.5 (and its surge model shifts z only — a lateral slosh term is out of
   scope, say so), tipper 1.3 lowered, and the raised body moves it further: `set_load_offset_z`
   already forces custom COM mode; add a y term for the tipper only, tested.
3. What moves: `kingpin_share()` (z only, unchanged by y); the joint's ±1.5° roll limit now
   carries a real overturning moment — a laden box at 0.53 g rollover threshold WILL take the
   tractor with it at 0.6 g lateral, which is the true behaviour and the reason phase 1 exists.
   Re-run `measure_semi_launch` both units (pitch, steer-axle load — the higher COM adds
   weight transfer on launch, so the 8.6 kN floor is the number to watch), the new tip phase,
   and `measure_vehicles -- semi 45 track strict` coupled to each trailer.
4. Speed taper (`min_steer_frac` 0.21 at 25 m/s) may need to tighten so a full-lock input at
   80 km/h coupled does not roll the rig without warning; decide from the tip phase's numbers.
5. Distil into `truck/CLAUDE.md` § The fifth wheel (the heights, the rollover threshold per
   trailer as a formula, the taper decision) and delete each header's "low on purpose" line.

## Phase 5 — the tractor

Effort **medium**. Mode: accept-edits. One Sonnet sub-agent. After heavy-feel R0 (the body is
scaled up) and R1 (springs).

1. Recipe `com_y` for `tractor-kenney` as a FRACTION of the scaled body's AABB height, ~0.45
   (a real tractor's COM sits at about 45 % of its height; on the R0 body that is ~0.85-0.95 m
   over the road — the table above assumed the real machine, and the fraction is what stays
   true if the scale factor changes again). With R1's stiff springs the front-wheel lift
   under heavy draft becomes real: `draft_max_force` 12 kN at the hitch (below the COM,
   nose-down moment) against the tyre reaction at ground level — recompute the pitch moment
   balance in the report; the honest outcome is a light front end, not a wheelie, and if the
   front unloads past ~70 % at rated draft the lever is R2's ballast split, not the height.
2. Rollover g drops to 0.67 against lug mu 1.0: a tractor on a side slope tips before it
   slides, which is the real machine and the thing level 1's field edges will now teach.
   Check the drawbar's ±25° roll limit with the trailer on a rut (the reason it is 25° and
   not 1.5°) still holds the trailer's roll off the tractor.
3. Verify: `measure_vehicles -- tractor-kenney 45 track strict`, a full-draft plough pass on the
   field (F3 front-axle load), the field-edge side slope by driving.
4. Distil into `tractor/CLAUDE.md`.

## Not in this plan

- The plane's ground COM (`center_of_mass` y −0.2 on a tricycle gear): fine, it is a low-wing
  light aircraft and it never corners hard on the ground.
- Boat, drone, train: not reviewed for feel yet; the boat's `keel_offset` is its own COM-height
  story and belongs to a boat review.

# TODO — remaining work

## 1. Perf pass

Profile the **deployed** web build first — F3 overlay (FPS / frame ms / draw calls /
primitives / VRAM) in the worst view of each level; budget: 60 fps on a mid-range laptop,
< ~500 draw calls. Measure, change ONE thing, re-measure; no speculative optimization.
Hard constraints: physics stays 60 Hz + interpolation; never set `scaling_3d/scale.web`
below 1; the `.web` overrides (msaa_3d.web=0, soft shadows off) already exist — check they
still apply before adding new ones. If a level is heavy on draw calls, suspect its bake
(chunk count / material dedup — the bake stats predict draw calls) before touching
renderer settings.

**Measure download the same way — on the deployed build, gzipped.** GitHub Pages gzips
`.wasm` and `.pck` in transit, so the raw export sizes are not the number a visitor waits
on: first load is ~19 MB over the wire (wasm ~10.2, pck ~8.3, js ~0.07), and the service
worker makes every later visit free. Two consequences worth keeping in mind before
optimizing for size. The wasm is the **majority of first load** and is engine, not content.
And raw size and transferred size can move in OPPOSITE directions — baked-mesh attribute
compression cut the pck 6.2 MB raw but cost 0.24 MB gzipped, because quantized attributes
carry more entropy than the float arrays gzip was exploiting. It was kept for the parse and
vertex-bandwidth win, not for download. Compare gzipped before/after or the conclusion will
be wrong.

- **Level-wide scatter MultiMeshes:** the baker currently emits one MultiMeshInstance3D
  per chunk × item (level 3: 159 MMs for 1024 instances, ~6 per MM). Merging to one MM
  per item level-wide would drop that to ~one per item mesh — the biggest win in the
  flying view, where chunk frustum culling buys nothing anyway. Cost: level-sized AABBs
  (always drawn, incl. shadow pass). Moderate `level_baker.gd` change; bump
  `BAKER_VERSION`, re-bake all.
- **Tractor hitch + implement draw calls:** the three-point linkage is ~42 unmerged
  `MeshInstance3D` and each of the four implements another ~20-25, all of it in frame whenever
  you drive the tractor. Measure the tractor view specifically (V through all four machines);
  if it bites, the fix is merging the static parts of each subtree (the housing, the PTO guard,
  an implement's frame) into one mesh per group — the articulating pivots have to stay separate.
- **First-appearance shader stutter (mobile web):** `gl_compatibility` has no ubershader, so
  every material variant compiles the first frame it is visible — cresting a hill into unseen
  geometry hitches. The **spawn view** is already covered: `boot.gd`'s `HOLD_FRAMES` keeps the
  loading screen up for 3 frames after the level enters the tree, so the first draw (and its
  compile stall) happens behind the overlay. That is a cover, not a fix, and it does nothing
  for geometry that scrolls in later. The real fix is still a warm-up pass behind the loading
  screen (draw each baked chunk material once off-screen), not a hack. Measure how many
  distinct materials a level actually ships first — if the bake's material dedup is already
  tight, the pass is cheap.
- **Slip-dust particle compile:** `base_vehicle.gd:_build_dust()` builds its
  ParticleProcessMaterial in code, so the draw shader compiles on the first wheel slip — a
  visible hitch the first time you break traction. Warm-up means actually rendering a puff
  somewhere, so it belongs with the shader warm-up pass above rather than on its own.

### Load-time suggestions (measured 2026-08-01, not yet done)

- **Levels 2-5 do not belong in the boot download — the biggest first-load win left.** The
  `.pck` is one blob fetched in full before anything runs, and baked levels are ~12 MB of its
  ~21 MB raw; `level_3` alone is 9.5 MB of that. A first visit boots `level_1` (1.3 MB) and
  may never open the others, yet waits on all of them. Shipping the non-default levels as a
  second `.pck` fetched on demand (`ProjectSettings.load_resource_pack()` behind the existing
  LoadingScreen, which already has a progress bar and a threaded-load path to hang it on)
  would cut first load by roughly 40%. Not a config tweak: it touches the export preset, the
  CI export step and the cache-busting/promote ritual in `docs/deploying.md` (a second
  artifact needs the same SHA-stamped name), and the PWA worker's precache list decides
  whether "offline" still means all five levels. Decide that last part first — it is the part
  that changes what the feature IS.
- **`level_3` is 8x the geometry of any other level** — 421,851 verts against level_1's
  54,219, and 9.5 MB of the 12 MB of baked levels. Nothing else in the project is close, so
  it sets the download, the parse time and the worst-view draw cost single-handedly. Before
  building the pck split above, check whether the island simply has more building than it
  needs, or whether its scatter/kit pieces are escaping the bake's material dedup. A content
  answer here is worth more than an engineering answer to the shipping problem.
- **Custom export template with unused modules stripped.** The wasm is ~10.2 MB gzipped and
  is now the majority of first load — bigger than all content combined. Nothing in the
  content pipeline can touch it. Only worth starting once the pck split above has landed,
  since it is by far the more invasive of the two (a per-release engine build in CI).
- **~650 KB of kit textures are duplicated or unreachable, and neither is safe to just
  delete.** One colormap (`451b163d`) ships three times — `kit/raw/garage/`,
  `kit/raw/parked/` and `src/vehicles/kenney/models/Textures/` are byte-identical, ~350 KB
  across both VRAM formats. The other six colormaps are genuinely different images that only
  LOOK duplicated because S3TC/ETC2 is fixed-rate per pixel, so they all land at 174.8 KB
  regardless of their 8-12 KB sources; do not re-derive that from pck sizes. Separately,
  ~307 KB of `kit/raw/racing/` textures (four `tankcoBanner` variants, both `_net`, both
  `_checkers`) are referenced by no shipped scene at all, because `export_filter=
  "all_resources"` ships every texture whether or not anything reaches it. Both fixes are
  traps in their obvious form: deleting a duplicate breaks the pack's `.glb` import (each
  resolves its texture from the sibling `Textures/` folder, and the baker re-inlines those
  materials every bake, so the change silently reverts), and name-excluding the unreferenced
  racing files re-arms the failure `docs/deploying.md` documents — the day someone places a racing
  fence, the web export alone dies with `No loader found for resource` and nothing local
  reproduces it. If it is worth doing, do the guard first: a bake-time check that FAILS CI
  when a baked level references an export-excluded texture. With that in place the exclude
  list cannot rot silently, and the ~307 KB is free. The 350 KB colormap duplicate needs
  either GLB surgery or content-hash texture dedup in the baker — over-engineering at that
  size, revisit only if the kit grows more shared textures.

## 2. Procedural engine audio (deliberately last — nothing may depend on it)

An RPM-driven procedural engine loop per vehicle: the horn already proves the pattern
(synthesized AudioStreamWAV, zero assets) and the drivetrain RPM is real, so the seam is
one audio player on BaseVehicle with pitch from `rpm` and gain from throttle/load — no
architecture change. Boat wind/engine and tractor PTO whine follow the same pattern.
Lands after the perf pass. Verify: engine pitch follows the tacho through the gears;
silent in menus.

## 3. Road drag is an accident — replace the stand-in with an honest model

**There is a DIRTY TEMPORARY FIX in `src/vehicles/base/base_vehicle.gd` to remove here**
(`ROAD_LINEAR_DAMP` + the guarded block in `_ready`). Delete both when this lands.

There is no drag model anywhere in `src/vehicles/`. What was actually setting every wheeled
vehicle's top speed was Godot's **default** `physics/3d/default_linear_damp = 0.1` — a value
nobody chose, linear in v where real aero is quadratic, and about **8x too strong** at
35 m/s (3722 N on the default car, against ~480 N of real aero for that frontal area). It
also bites hardest where reality is weakest, at low speed, so it was blunting acceleration
as well as top end.

Measured with `tools/measure_vehicles.tscn` (see `docs/systems.md` § Measuring a vehicle),
full throttle on a flat full-grip strip, before / after the stand-in:

| variant | top speed before | after | 0-100 km/h before | after |
| --- | --- | --- | --- | --- |
| sedan-sports (default car) | 128 km/h, stuck in **gear 4** | 212 km/h, gear 6 | 7.05 s | 5.30 s |
| race | 153 km/h | 289 km/h | 4.03 s | 3.47 s |
| van | 92 km/h | 165 km/h | never | 9.13 s |
| garbage-truck | 54 km/h | 85 km/h | never | never |
| tractor-kenney | 54 km/h | 118 km/h | never | 41.9 s |

The headline symptom was that **gears 5 and 6 were dead weight on the car**: it plateaued at
4752 rpm in 4th, below `shift_up_rpm = 5600`, so the top two ratios could never engage.

The stand-in fixed that for the default car (it now tops out in 6th), but **an `all` sweep
with `tools/measure_vehicles.tscn` shows unreachable ratios are widespread and not purely a
drag problem** — `sedan`, `suv`, `suv-luxury`, `taxi` and `police` still top out in 5 of 6,
and the bikes in 2 or 4 of 6. Some of that is gearing that was never matched to the torque
curve, so the re-tune pass below is not optional cleanup: it is where those specs get looked
at. Re-measure each spec after touching it.

The stand-in is a flat reduced `linear_damp` (0.033) applied in `_ready` to wheel-driven
chassis only. Two exclusions, both of which are themselves reasons to do this properly:

- Free-body vehicles (boat, drone, plane) and the train are untouched — they run their own
  drag through `VehicleMath`, and the engine default is an accidental extra on top of it
  that this item should also clean up.
- **The bikes are excluded**, keyed off `spec.angular_damping > 0.0` because that flag is
  set on nothing else. At 260 kg the default damp was the only thing holding them to a sane
  number; reducing it took them from 175 to **314 km/h**. A linear constant cannot serve
  both a 260 kg bike and an 8000 kg truck — which is the whole argument for the real model.

The real fix is standing rule 3's shape: an honest, clearly-labelled per-vehicle
`0.5 * rho * Cd*A * v^2` aero term plus a rolling-resistance term, `Cd*A` and crr as
`VehicleSpec` exports, with the chassis on `DAMP_MODE_REPLACE` at 0 so nothing rides an
engine default again. Pure math, so it gets gdUnit4 tests per rule 8. Budget a re-tune pass
over every vehicle's gearing afterwards, and re-check the §6 brake hierarchy holds at the
new top speeds.

## 4. The semi tops out at 33 km/h — not a drag bug, and not an easy fix

Separate from the drag item above and **not caused by it** (31 km/h before that change,
33 km/h after). Bobtail, flat full-grip strip, full throttle, no trailer: the semi climbs
normally to ~32 km/h in gear 3, plateaus there, eventually upshifts to gear 4 and then
*loses* speed. `tools/measure_vehicles.tscn -- semi` reproduces it in about 30 s.

A first pass eliminated every cheap explanation by diffing it against the **garbage-truck,
which reaches 85 km/h on identical numbers**. Both specs share mass (8000 kg), wheel radius,
`wheel_inertia`, `gear_ratios`, `final_drive`, `shift_up_rpm`/`shift_down_rpm`, `grip_curve`
and `mu_long`. Ruled out, with the evidence:

- **Air / spring brakes.** Traced: both reservoirs rise 7.0 → 12.0 bar and never approach
  `AIR_SPRING_BRAKE_BAR`. The gate never fires.
- **The retarder.** `retarder_equipped = true` on the garbage truck too, and the local input
  has no retarder key, so the request is 0 either way.
- **Gearing and shift points.** Byte-identical between the two specs.
- **Torque.** The semi's curve is *higher* everywhere (975/1500 Nm against 520/1040). It
  makes more torque and goes slower, which is the whole puzzle.
- **The delayed upshift is a red herring.** It sits at 2695 rpm — above `shift_up_rpm` 2600
  — without shifting, because `Drivetrain.process` deliberately decides auto-shift on
  *ground speed*, not on `drive_wheel_omega`, so wheelspin can't make the box hunt. The
  shift rpm is the slip-free one (~2601), right at the boundary. Working as designed.

What is left, and where the next session should start: the semi is probably **traction-
limited at the drive axle**, so its extra torque never reaches the road. It is a 4x2 with
one driven axle, and its geometry puts less on that axle than the garbage truck's does —
centre of mass at z -0.15 between axles at -1.15 and +0.95 gives the drive axle **47.6 %**
of the weight, against **59.8 %** for the garbage truck (COM -0.14, axles -1.302 / +0.642).
That is a ~20 % traction deficit, which does not by itself explain a 60 % speed deficit, so
there is a second factor — suspect the interaction between that load, the much stiffer rear
spring (240000 N/m, set for a fifth-wheel load this bobtail run does not have) and the slip
the wheel settles at. Instrument `RayWheel`'s longitudinal force and normal load per corner
rather than reasoning about it; the estimates above are what made this look easy twice.

Worth checking whether it also affects the **coupled** rig, which is the state the spec was
tuned for — a bobtail-only fault and a fault that survives coupling are different bugs.

## Drone follow-ups (from 2026-07-23 code review)

- **Map containment for flight:** boundary walls top out at y=+10; the drone flies over
  them into the collision-less far sea and only respawns below y=-20. Decide: taller
  walls, a ceiling, or an out-of-bounds volume.
- **`ST_GROUND` honesty:** the drone (no wheels) publishes "all wheels on ground" = true
  while hovering — a false CAN-side reading (the boat shares the quirk). Fold into the
  `status` bitfield finalization with sloppyCAN (see Open questions).

## Plane follow-ups (from 2026-07-23 code review)

- **The beacon blink is a standing-rule exception, and should stop being one.** The
  anti-collision beacon (`LampSet.BEACON_*`, `spec.flash_lamp_paths`) is the ONE lamp in
  the project pulsed from a local clock instead of a mirrored sloppyCAN bit. It is a gap in
  the contract rather than an override of it — there is no beacon signal to mirror, and a
  beacon that does not flash is not a beacon. Resolve by giving the contract a toggling
  beacon bit (sloppyCAN owns the toggle, exactly like the turn lamps), then delete
  `BEACON_PERIOD`/`BEACON_ON_FRAC` and mirror it verbatim. Until then the exception is
  documented in `lamp_set.gd`'s header and must not be cited as licence to add a timer to
  any lamp that DOES have an authoritative source. Wing strobes stay unmodelled meanwhile.
- **DM1's flashing lamp states are a contract gap, the same shape as the beacon.** The J1939-73
  DM1 lamp status byte encodes four states per lamp — off, on, **flash at 1 Hz**, **flash at
  2 Hz** — and the two flashing ones are how a real cluster separates "fault active" from
  "fault pending". `red_stop` / `amber_warn` / `protect_lamp` model the on/off bit only,
  because a flash would have to come from a local clock and the standing rule forbids one.
  This is a gap in the contract, NOT licence to add a timer: resolve it the same way the
  beacon should be resolved — sloppyCAN owns the toggle and the game mirrors the bit, exactly
  like the turn lamps. Noted in `input_router.gd`'s VehicleInput comments and the contract
  `desc` so it is not rediscovered as a bug.
- **The dashboard `lights` chip shows road-car labels on the plane.** The contract enum is
  `OFF/CLEARANCE/LOW/HIGH` and is shared by all eight vehicles, but on the plane those
  levels drive an aircraft ladder (`VehicleSpec.LampStyle.AIRCRAFT`): off / beacon+nav /
  taxi beam / landing beam. So the chip reads "LOW" while the taxi light is on. The level
  numbers are the protocol and are right; only the display name is vehicle-wrong. Fixing it
  means per-vehicle enum labels in the dashboard (`ENUM_CHIPS`, `dashboard.gd:16`) or a
  per-vehicle label override in the contract — neither is worth it before the sloppyCAN
  frame layout is finalized. Cosmetic; noted so it is not rediscovered as a bug.

## Rail follow-ups

- **`rail_track.gd` stays in `src/levels/base/`** (decided Phase 4): `level_baker.gd`
  preloading `src/levels/base/rail_track.gd` inverts the usual kit→src layering and puts a
  `src/` path in `BAKE_CODE_INPUTS`, but the node's runtime consumers (`TrainVehicle`,
  `Level`'s spawn/roster gate) all live in `src/`, and it belongs beside its sibling runtime
  level nodes (`heightmap_terrain.gd`, `vehicle_spawn.gd`). Moving it to `kit/` would restore
  the layering only to split it from everything that uses it. No failure mode either way;
  left as-is.
- **Multi-loop random spawn is deferred:** the plan sketched `_spawn_vehicle` picking a
  closed loop at random when a level has more than one. No level does (level 5 has one), and
  the train self-places on the first/only closed loop via `RailTrack.find_closed_rail`.
  Building random choice means the level passing the chosen loop into the train before its
  `_ready` — a level↔train coupling with no content behind it. Revisit if a level ever ships
  two closed loops; until then one-loop self-placement is the whole story.

## Towed bodies — shipped for the truck, still open for the tractor

The truck's towed body shipped: a cab-over tractor unit on a real `Generic6DOFJoint3D` pulling
four semi-trailers (`src/vehicles/truck/`, `docs/systems.md`). What is left:

- **TRAILER LAMPS DO NOT LIGHT.** The four trailers' tail and marker lenses are static unlit
  meshes, so a coupled rig's stop lamp and turn indicators are the TRACTOR's only — which on a
  9 m combination is the wrong end of the vehicle and reads as a bug. The obstacle is real:
  `LampSet` resolves `VehicleSpec`'s lamp NodePaths **from the vehicle root**, and the trailer is
  a separate body under the level, so nothing today can reach across. Two ways in, and the first
  looks right:
  1. give `TowedBody` its own `LampSet` built from lamp NodePaths on the TRAILER's spec, and have
     `SemiTractor` drive it from the lamp bits already on `VehicleInput` each tick — no side
     channel, so the "lamp state rides `VehicleInput`" rule holds, and bridge-driven bits stay
     mirrored verbatim;
  2. teach `LampSet` a second resolve root, which is a smaller diff but leaves one `LampSet`
     owning nodes in two bodies with two lifetimes.
  Either way the trailer's lenses need `material_override` treatment like every other lamp, and
  the four `.tscn`s need their lens node names on their specs. **No contract change** — a trailer
  lamp is the same `brake_lamp` / `turn_left` / `turn_right` bit, shown at both ends.
- **A tractor drawbar trailer is still not built, and the trailer work made it CHEAPER but not
  CHEAP.** It was deferred out of the ISOBUS build-out (`docs/plans/tractor_improvements.md`) — the
  tipping trailer was to be one of four implements and is as much work as the other three combined;
  the power harrow took its slot, so all four shipped implements are three-point-mounted. It would
  unlock the drawbar-vs-three-point contrast (a drawbar only pulls, it does not lift) —
  `ImplementBase.Connection.DRAWBAR` is declared and unused, waiting for exactly this — and give
  `scv_flow` a second consumer beside the spreader's hopper gate. What the truck work now hands it,
  and what it does not:
  - **Reusable as-is:** `TowedBody` (a jointed RigidBody3D on its own unmodified `RayWheel`s, its
    own suspension loads and slip, `set_load_offset_z`), `Articulation.coupled_pose` for spawn and
    respawn, and the whole two-body housekeeping checklist the semi paid for — child of the level
    and not of the tractor, couple on the first physics tick, match velocity at the pin before the
    joint exists, `remove_child` before `queue_free` on a drop, re-lay AND reset the wheels on
    respawn, exclude the RID from the camera, freeze it for the garage, and the reactive
    couple-then-look fit check. That list is most of what made the semi expensive and none of it
    has to be rediscovered.
  - **Not reusable:** the geometry (a drawbar tipping trailer is a whole new scene, and geometry
    was the dominant cost of every trailer), and the joint itself — a fifth wheel locks all three
    linear axes at the kingpin and near-zero roll, whereas a drawbar eye on a pin is free in yaw
    AND roll and carries almost no vertical load, so it is a different `Generic6DOFJoint3D`
    configuration that has to be driven and measured on its own. `SemiTractor` is also the wrong
    host: it owns coupling, the air draw and the ISO 11992 publishing, none of which a tractor has,
    so the tractor side is new code against `ThreePointHitch`'s gating precedent rather than a
    subclass of the semi. Nor may it reuse the trailers' `y = -1.05` coupling datum, which is the
    fifth-wheel plate height.
  - So: roughly one trailer's geometry plus a joint tuning pass and a tractor-side coupler, against
    the semi's geometry-plus-physics-plus-bus. Worth doing; not a free ride on top of the semi.
- **A RAISED TIPPER BODY HAS NO COLLISION.** The tipping body's `CollisionShape3D` is authored for
  the LOWERED pose and deliberately does not follow the tip: re-transforming a shape every tick
  rebuilds the compound and re-derives the inertia tensor at 60 Hz, on the one body that is also
  writing its own `center_of_mass`, and two churning physics properties on a jointed body is how a
  rig starts buzzing. That was the right call, but it leaves a gap the interlock's shape opens: the
  raise interlock refuses the RAISE DIRECTION ONLY (rolling away with the body up must hold it, not
  command it down onto whatever is under it), so you really can drive off with 5.2 m of body in the
  air — and it will pass visually through a bridge it should hit. Nothing crashes and no signal
  lies; it looks wrong. The cheap honest fix is a second, disabled `CollisionShape3D` authored in
  the RAISED pose, swapped once when `body_pos01()` crosses a threshold rather than posed per tick
  — two rebuilds a tip instead of sixty a second, and both of them while the rig is parked. Measure
  the kingpin before and after either way.

## sloppyCAN-side follow-ups (joint work across both repos)

- **The CAN map covers the car subset only.** sloppyCAN's coverage check warns on load that 42
  contract "out" signals are declared but never packed into a frame: `lean`, `hitch_pos_actual`,
  `pto_state`, `pto_rpm`, `engine_load`, `implement_connected`/`implement_type`, `diff_lock_state`,
  `fwd_drive_state`, `wheel_speed`, `ground_speed`, `wheel_slip`, `engine_hours`, `draft_force`,
  `pitch`, `roll`, `rudder_actual`, `trim`, the air/retarder/axle/body/hopper truck block, the
  trailer block, `altitude`, `vspeed`, `flaps_actual`, `rotor_rpm`, `armed`, the rail block,
  `grade`, `coupler_force`. So everything past the car publishes telemetry the game shows on its
  own dashboard but that never reaches the bus — which is the one thing the pairing exists to do.
  The check is working as designed; the map just has not kept up with the contract. Needs frame IDs
  and byte layouts agreed on the sloppyCAN side (see the ISOBUS framing question below — the
  tractor/implement signals are the natural first batch, and the ones with a real J1939/ISOBUS
  layout to copy rather than invent).

## Shell prefs are switched off for development

- **`ShellPrefs.ENABLED` is `false`** (`src/shell/shell_prefs.gd`). Nothing is read from or
  written to `user://shell.cfg`, so every visit boots from defaults: no remembered
  level/vehicle, the first-run coaching cue shows every run, dashboard density stays AUTO.
  A remembered session is confusing while the boot path itself is what's being changed. All
  the persistence logic is intact — flip the const back to `true` to reintroduce it, and at
  that point decide whether the pause menu needs a "Reset saved settings" entry (there is no
  in-game way to clear the file today; on web it lives in the `/userfs` IndexedDB, on desktop
  in `%APPDATA%\Godot\app_userdata\Carlito\`). Deep links (`?level=…`) are a separate path and
  are unaffected.

## Open questions (decide when they block something)

Anything below that moves the contract is now a **paired change across two repos**: it
lands on the `dev` branch of both `carlito` and `sloppycan` and both get promoted
together, or the live stable pair ends up on mismatched versions. That applies to the
`status` bitfield layout (and the `ST_GROUND` honesty item under Drone follow-ups), the
ISOBUS framing decision, the per-axle `slip` split, and the beacon / DM1 lamp bits under
Plane follow-ups. See `docs/deploying.md`.

- **Threads stay off in the web export while sloppyCAN embeds the game** (`variant/thread_support=
  false`). Cross-origin isolation is inherited down the frame tree: an iframe is only isolated if
  the TOP-level document is, and sloppyCAN is plain GitHub Pages with no COOP/COEP and (by design)
  no service worker. Carlito's own PWA worker makes `/carlito/stable/` isolated when opened
  directly, but it cannot rescue the frame — a threaded build shows Godot's "Cross-Origin Isolation
  / SharedArrayBuffer missing" error box instead of booting. Verified side by side in one embedder:
  the non-threaded v1 build boots in that same iframe, the threaded one does not. Re-enabling
  threads is only on the table if sloppyCAN itself becomes cross-origin isolated (its own COI
  service worker + `allow="cross-origin-isolated"` on the iframe + a CORP audit of every
  cross-origin subresource it loads) — and that reintroduces a service worker there, which the
  two-channel layout currently relies on not existing. Measure first: on `gl_compatibility` the
  render path is main-thread anyway, so quantify what threads actually buy before paying that.
- ISOBUS framing on the sloppyCAN side: 29-bit extended IDs (proper J1939) vs the
  existing 11-bit scheme — sloppyCAN/RAMN decision; this side is agnostic.
- `status` bitfield final bit layout (fixed together with sloppyCAN frame packing).
- Per-axle split of the `slip` signal (telemetry already sims per-axle slip; the contract
  carries one value).



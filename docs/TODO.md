# TODO — remaining work

## Boat has no wind/current model

`WindField` (`src/levels/base/wind_field.gd`) is sampled by the drone and the plane
(`WindField.at(self)` in `drone.gd`/`plane.gd`) but not by `BoatVehicle` — the boat is the
one free body with no outside-force disturbance. `VehicleMath.air_damper` (opposes velocity
relative to wind, not ground) already exists for the flight bodies; wiring the same call
into the boat's hull/drag terms looks like the cheap route. Worth scoping once picked up.

## Perf pass

Profile the **deployed** web build first — F3 overlay (FPS/frame ms/draw calls/primitives/
VRAM) in the worst view of each level; budget 60 fps on a mid-range laptop, no draw-call
number is a target until profiled there. Measure, change ONE thing, re-measure. Physics
stays 60 Hz + interpolation; never set `scaling_3d/scale.web` below 1 (`.web` overrides
msaa_3d.web=0, soft shadows off, already exist). Heavy on draw calls → suspect the bake
before renderer settings.

**Measure download gzipped, on the deployed build.** GitHub Pages gzips `.wasm`/`.pck` in
transit: first load is ~19 MB over the wire (wasm ~10.2, pck ~8.3, js ~0.07), later visits
free via the service worker. Raw and transferred size can move opposite ways — baked-mesh
attribute compression cut the pck 6.2 MB raw but cost 0.24 MB gzipped (quantized attributes
carry more entropy than gzip was exploiting; kept for parse/vertex-bandwidth). Compare
gzipped before/after.

- **Suspension/sensor query caching was never measured.** `RayWheel._query`,
  `ChaseCamera._query` and `DroneSensorSuite`'s shared query are cached-and-refilled rather
  than `PhysicsRayQueryParameters3D.create()`d per cast — should save ~720 heap objects/sec
  from the wheels alone, but no before/after was captured on the deployed build. Needs a
  baseline.
- **What a full six-level bake costs CI.** `.github/workflows/ci.yml` bakes every registered
  level on every push (`.baked.scn` is untracked build output). Record the step's duration
  here; if it dominates, cache the bake by `input_hash` rather than dropping the step.
- **Level-wide scatter MultiMeshes.** The baker emits one MultiMeshInstance3D per chunk ×
  item (level_3: 52 MMs for 249 instances). One MM per item level-wide is the biggest win
  flying, where chunk frustum culling buys nothing; cost is level-sized AABBs, always drawn
  including shadow pass. Moderate `level_baker.gd` change; bump `BAKER_VERSION`, re-bake all.
- **Tractor hitch + attachment draw calls.** The three-point linkage is 42 unmerged
  `MeshInstance3D`, each implement another 20-33, the drawbar farm tipper 52 more when
  hitched — all in frame while driving the tractor. Measure that view (E through every
  implement); fix is merging each subtree's static parts into one mesh per group, leaving
  articulating pivots and the tipping body separate.
- **First-appearance shader stutter (mobile web).** `gl_compatibility` has no ubershader, so
  every material variant compiles on its first visible frame — cresting a hill into unseen
  geometry hitches. `boot.gd`'s `HOLD_FRAMES := 3` hides the spawn view's compile stall
  behind the loading screen only; geometry scrolling in later still hitches. Real fix: a
  warm-up pass behind the loading screen (draw each baked chunk material once off-screen);
  cheap if bake dedup is tight.
- **Slip-dust particle compile.** `wheel_drive.gd:_build_dust()` builds its
  ParticleProcessMaterial in code, so the draw shader compiles on first wheel slip. Warming
  it means rendering a puff — belongs with the warm-up pass above.

### Load-time (measured 2026-08-30)

- **Levels 2-6 don't belong in the boot download — the biggest first-load win left.** The
  `.pck` is one 21.6 MB blob fetched whole before anything runs; baked levels are ~12 MB of
  it, `level_3` alone 9.0 MB. A first visit boots `level_1` (1.2 MB) and may never open the
  others. Shipping non-default levels as a second `.pck` fetched on demand
  (`ProjectSettings.load_resource_pack()` behind the existing LoadingScreen) would cut first
  load by roughly 40%. Touches the export preset, CI export step, and the cache-busting/
  promote ritual (`docs/deploying.md` — a second artifact needs the same SHA-stamped name).
  Decide first what the PWA precache list should hold.
- **`level_3` is ~8× the geometry of any other level** — 421,591 verts vs `level_1`'s
  54,139, 9.0 of the 12 MB of baked levels. Sets the download, parse time and worst-view
  draw cost single-handedly. Before building the pck split, check whether the island has
  more building than it needs, or its scatter/kit pieces escape the bake's material dedup —
  a content answer is worth more than an engineering one here.
- **Custom export template with unused modules stripped.** Wasm is ~10.2 MB gzipped, bigger
  than all content combined and untouchable by the content pipeline. Only worth starting
  after the pck split lands; a per-release engine build in CI is far the more invasive of
  the two.
- **~950 KB of kit textures are duplicated or unreachable, and neither is safe to delete.**
  One colormap (`451b163d`) ships three byte-identical times — `kit/raw/garage/`,
  `kit/raw/parked/`, `src/vehicles/kenney/models/Textures/` — ~700 KB redundant across the
  two VRAM formats. The other six colormaps only look duplicated because S3TC/ETC2 is
  fixed-rate per pixel and all land at 174.8 KB regardless of 8-12 KB sources — don't
  re-derive that from pck sizes. Separately, six `kit/raw/racing/` textures reach no shipped
  scene (`billboard`/`billboardLow`/`billboardLower`/`flagTankco`/`_tankcoBanner`, both
  `_net`), ~255 KB, because `export_filter="all_resources"` ships every texture regardless
  of reachability. Both fixes are traps in obvious form: deleting a duplicate breaks the
  pack's `.glb` import (each resolves its texture from the sibling `Textures/` folder,
  re-inlined every bake, so the change silently reverts); name-excluding the unreferenced
  racing files re-arms the `docs/deploying.md` failure — a placed racing fence dies with
  `No loader found for resource` and nothing local reproduces it. Guard first: a bake-time
  check that fails CI when a baked level references an export-excluded texture, then the
  exclude list can't rot and the ~255 KB is free. The colormap duplicate needs GLB surgery
  or content-hash texture dedup in the baker — over-engineering at this size; revisit only
  if the kit grows more shared textures.

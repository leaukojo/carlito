# Carlito — Architecture Overview

Architecture map for agents. Product summary and standing rules: root `CLAUDE.md`; directory
rules: the nested `CLAUDE.md` files. Per-system detail: `docs/systems.md` (plumbing),
`docs/vehicles.md` (framework, tyres, brakes), `docs/handling.md` (the body), `docs/drivetrain.md`,
`docs/truck.md`, `docs/tractor.md`, `docs/boat.md`, `docs/flight.md`, `docs/rail.md`,
`docs/level_kit.md`; measured figure tables and the measure tools (read to measure or quote a
figure): `docs/vehicle_measurements.md`; sourced figures and references (read only to check or
change a sourced value): `docs/sources.md`. Open work: `docs/plans/`; backlog: `docs/TODO.md`.
What goes where (CLAUDE.md / code comment / `docs/`): root `CLAUDE.md` § Working style.

## The big idea: one contract, everything flows through it

`contract/carlito_contract.json` defines every signal crossing the game↔simulator boundary:
name, direction (`in`/`out`), type, unit, range, warning threshold, enum, vehicles. Unique by
(name, dir). Full semantics: `docs/systems.md` § Signal contract.

Generated from or validated against it: **Contract autoload** validates at startup;
**dashboard** walks it for tell-tales/bars; **bridge** marshals telemetry by contract name;
sloppyCAN consumes a generated JS copy (`tools/gen_js_contract.mjs`).

## Runtime data flow

```
sloppyCAN (browser JS)                         Godot game (wasm)
     |  postMessage {carlitoInput}                  |
     v                                              v
window.__carlito stash  --poll 60 Hz-->  Bridge autoload
                                              |
                                        InputRouter  <-- keyboard / touch sources
                                              |   (ALL input arbitration lives here, pure + tested)
                                              v
                                        one VehicleInput
                                              |
                                        BaseVehicle (RigidBody3D)
                                              |
                                        VehicleTelemetry (read from the sim, never faked)
                                              |
Bridge --publish 20 Hz--> window.__carlito.publish() --> postMessage {carlitoOutput}
```

One input path, honest telemetry, web-only transport: `docs/systems.md` § Input pipeline,
§ Telemetry & dashboard, § Bridge.

## Vehicles

- `src/vehicles/base/` is the framework — new vehicle = new spec + scene, no code:
  `VehicleSpec`+`GroundDriveSpec` (`.tres`), `Drivetrain`, `RayWheel`, `VehicleMath`,
  `BaseVehicle`, `WheelDrive`, `ChaseCamera`, `LampSet`, `Horn`, towing trio
  `TowHost`/`CouplingProfile`/`TowedBody`/`Articulation`. Detail: `docs/systems.md`,
  `docs/vehicles.md` (its header lists the rest).
- `BaseVehicle` is family-agnostic; `WheelDrive` is the wheeled ground-drive half it owns.
  Subclasses hook `_make_telemetry()`/`_tick_extras(input, delta)`: `TractorVehicle`,
  `TruckVehicle`/`SemiTractor` (J1939), `BoatVehicle` (buoyancy), `DroneVehicle` (DroneCAN),
  `PlaneVehicle` (CANaerospace), `TrainVehicle` (rail spline).
- `VehicleCatalog` maps cosmetic variants onto families (V cycles variants, E cycles
  attachments via `cycle_implement()`); contract/dashboard/bridge see only the family. Tire
  grip is per-surface via `Surface` (`HeightmapTerrain.channel_surface`).

### The tractor and the truck

Tractor (20 ISOBUS signals) and truck (J1939 chassis; per variant a CANopen body network, an
ISO 11992 trailer bus, or none): `docs/tractor.md`, `docs/truck.md`.

## Levels and the authoring kit

- A level is a `Level` script + `LevelInfo` resource (allowed vehicles) + `VehicleSpawn`
  markers, registered in `LevelRegistry.LEVELS`; the shell (`boot.gd`) boots straight into one.
- Authored with the kit (`kit/` + `addons/carlito_kit`): heightmap terrain with color-splat
  ground, GridMap palettes, `KitPiece` prefabs, seeded scatter, spline `RoadPath` roads
  (rails via `RailProfile`). Walkthrough: `docs/making_a_level.md`; reference:
  `docs/level_kit.md`.
- The bake tool merges render meshes per chunk and welds drivable geometry into one
  level-wide collision body, input-hash-stamped; CI fails on stale bakes. `Level` loads
  `<level>.baked.scn` at runtime; an export plugin strips authoring content.

## Testing & CI

- gdUnit4 covers the pure logic (root rule 8); run lines: root `CLAUDE.md` § Running.
- CI (`.github/workflows/ci.yml`): editor-type gate → head-include check → import →
  stale-bake check → bake → gdUnit4 → headless smoke → baked-level smoke → web export +
  level packs, plus a parallel tracking gate.
- Deploy channels: root `CLAUDE.md` rule 7, `docs/deploying.md`. The Godot 3 backup lives at
  `../_old/CARLITO_SLOPPYCAN_V1_BACKUP/carlito/`.

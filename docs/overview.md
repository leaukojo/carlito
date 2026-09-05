# Carlito — Architecture Overview

A browser-based CAN-bus driving sandbox: drive vehicles (car / truck / tractor / boat /
drone / plane / train) while exchanging live CAN signals with the sloppyCAN/RAMN simulator.
Godot 4.7, web-first, physics locked at 60 Hz + interpolation.

`CLAUDE.md` is the working reference (commands, rules, gotchas), with directory-scoped
gotchas in nested `CLAUDE.md` files beside the code they constrain (`src/vehicles/`,
`src/levels/`, `src/ui/`, `contract/`, `kit/`); `docs/systems.md`, `docs/vehicles.md`,
`docs/heavy_vehicles.md` and `docs/level_kit.md` hold per-system detail; `TODO.md` lists
remaining work and accepted compromises.

## How to read these docs

Rationale-first, to stop settled decisions being undone. A justification is not a
description — read the code for the plain fact. Prose length tracks interest, not code
size. "ALL"/"every"/"never" states intent, not a verified invariant — check before quoting
one. What is deliberately imperfect is in `TODO.md` § Accepted compromises.

## The big idea: one contract, everything flows through it

`contract/carlito_contract.json` defines every signal crossing the game↔simulator boundary:
name, direction (`in`/`out`), type, unit, range, warning threshold, enum, vehicles. Signals
are unique by (name, dir). Full semantics: `docs/systems.md` § Signal contract.

Everything else is generated from or validated against it: the **Contract autoload**
validates at startup; the **dashboard** generates its tell-tales and bars by walking it; the
**bridge** marshals outbound telemetry by contract name; sloppyCAN consumes a generated JS
copy (`tools/gen_js_contract.mjs`).

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

One input path (arbitration detail: `docs/systems.md` § Input pipeline), honest telemetry
(detail: § Telemetry & dashboard), web-only transport (detail: § Bridge).

## Vehicles

`src/vehicles/base/` is the framework: `VehicleSpec` + embedded `GroundDriveSpec` (`.tres`,
all drive tuning — a new vehicle is a new spec + scene, no code), `Drivetrain` (pure math),
`RayWheel` (raycast suspension), `VehicleMath` (shared dampers/yaw/attitude math for the
free-body vehicles), `BaseVehicle`, `WheelDrive`, `ChaseCamera`, `LampSet`, `Horn`, and the
towing trio `TowHost`/`CouplingProfile`, `TowedBody`, `Articulation`. Framework detail:
`docs/systems.md`; per-family detail: `docs/vehicles.md`, `docs/heavy_vehicles.md`.

`BaseVehicle` is family-agnostic across all seven families; `WheelDrive` is the wheeled
ground-drive half it owns. Vehicles needing per-tick systems beyond driving subclass through
two seams: `_make_telemetry()` and `_tick_extras(input, delta)`. Subclasses: `TractorVehicle`
(widest signal cluster), `TruckVehicle`/`SemiTractor` (J1939 + refuse body / towed body),
`BoatVehicle` (buoyancy), `DroneVehicle` (DroneCAN), `PlaneVehicle` (CANaerospace),
`TrainVehicle` (rail spline sim).

`VehicleCatalog` maps cosmetic variants (taxi, firetruck, ambulance, …) onto families — V
cycles variants, E cycles attachments (`cycle_implement()`); the contract/dashboard/bridge
only ever see the family. Tire grip is per-surface via the terrain's painted splat channels
(`channel_grip`).

### The tractor and the truck

The tractor (20 ISOBUS signals) and the truck (J1939 chassis plus, per variant, a CANopen
body network, an ISO 11992 trailer bus, or none) are built around commercial-vehicle network
standards. Full detail — implements, drawbar trailer, J1939/ISOBUS/ISO 11992 breakdowns,
four truck variants and four semi-trailers — is in `docs/heavy_vehicles.md`.

## Levels and the authoring kit

Levels are self-contained scenes composed by the shell (`boot.gd`: boot straight into a
level → play). A level = `Level` script + `LevelInfo` resource (allowed vehicles) +
`VehicleSpawn` markers, registered in `LevelRegistry.LEVELS`.

Authored with the kit (`kit/` + `addons/carlito_kit`): heightmap terrain with color-splat
ground, GridMap palettes, `KitPiece` prefabs, seeded scatter, spline `RoadPath` roads
(including rails, via `RailProfile`). Full authoring walkthrough: `docs/making_a_level.md`;
tool reference: `docs/level_kit.md`.

The bake tool merges render meshes per chunk and welds drivable geometry into one
level-wide collision body; bakes are input-hash-stamped, CI fails on stale bakes. At runtime
`Level` loads `<level>.baked.scn`; an export plugin strips authoring content.

Levels are signal playgrounds, not missions: a level's job is to give contract signals a
place to visibly perform (grades for `engine_load`, hairpins for slip, fields for hitch/PTO,
water courses for pitch/roll).

## Testing & CI

gdUnit4 covers all pure logic (drivetrain, input arbitration, telemetry, lamps, buoyancy,
terrain/scatter/road/bake math); run headless with the console Godot binary (commands:
`CLAUDE.md`). CI (`.github/workflows/ci.yml`): import → tests → headless smoke → stale-bake
check → baked-level smoke → web export, plus a parallel tracking gate. `dev` auto-publishes
on every push (cache-busted); `stable` moves only on the manual promote workflow — see
`docs/deploying.md`.

Code is MIT, assets CC0. The previous generation of the game lives outside the project at
`../CARLITO_SLOPPYCAN_V1_BACKUP/carlito/` as a behavior/layout reference only; nothing is
ported from it.

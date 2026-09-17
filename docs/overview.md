# Carlito — Architecture Overview

A browser-based CAN-bus driving sandbox: drive vehicles (car / truck / tractor / boat /
drone / plane / train) while exchanging live CAN signals with the sloppyCAN/RAMN simulator.
Godot 4.7, web-first, physics locked at 60 Hz + interpolation.

`CLAUDE.md` is the working reference (commands, rules, gotchas), with directory-scoped
gotchas in nested `CLAUDE.md` files beside the code they constrain (`src/input/`,
`src/vehicles/`, `src/levels/`, `src/ui/`, `contract/`, `kit/`); `docs/systems.md`,
`docs/vehicles.md`, `docs/heavy_vehicles.md` and `docs/level_kit.md` hold per-system detail;
`TODO.md` lists remaining work.

## How to read these docs

Written for a human looking something up: the fact first, in as few words as it takes, and
a `why:` tail only where a reader would otherwise undo the decision. Tables and bullets over
paragraphs; no narration, no history. The reasoning that stops an agent re-proposing a
rejected idea lives in the nested `CLAUDE.md` files, not here. "ALL"/"every"/"never" states
intent, not a verified invariant — check before quoting one. A knowingly-imperfect decision
is recorded beside the code it constrains, in the nested `CLAUDE.md` files, with what undoing
it would cost.

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

One input path (`docs/systems.md` § Input pipeline), honest telemetry (§ Telemetry &
dashboard), web-only transport (§ Bridge).

## Vehicles

- `src/vehicles/base/` is the framework — new vehicle = new spec + scene, no code:
  `VehicleSpec`+`GroundDriveSpec` (`.tres`), `Drivetrain`, `RayWheel`, `VehicleMath`,
  `BaseVehicle`, `WheelDrive`, `ChaseCamera`, `LampSet`, `Horn`, towing trio
  `TowHost`/`CouplingProfile`/`TowedBody`/`Articulation`. Detail: `docs/systems.md`,
  `docs/vehicles.md`, `docs/heavy_vehicles.md`.
- `BaseVehicle` is family-agnostic; `WheelDrive` is the wheeled ground-drive half it owns.
  Subclasses hook `_make_telemetry()`/`_tick_extras(input, delta)`: `TractorVehicle`,
  `TruckVehicle`/`SemiTractor` (J1939), `BoatVehicle` (buoyancy), `DroneVehicle` (DroneCAN),
  `PlaneVehicle` (CANaerospace), `TrainVehicle` (rail spline).
- `VehicleCatalog` maps cosmetic variants onto families (V cycles variants, E cycles
  attachments via `cycle_implement()`); contract/dashboard/bridge see only the family. Tire
  grip is per-surface via `channel_grip`.

### The tractor and the truck

The tractor (20 ISOBUS signals) and the truck (J1939 chassis plus, per variant, a CANopen
body network, an ISO 11992 trailer bus, or none). Full detail — implements, drawbar trailer,
J1939/ISOBUS/ISO 11992, four truck variants, four semi-trailers — in `docs/heavy_vehicles.md`.

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
- Levels are signal playgrounds: grades for `engine_load`, hairpins for slip, fields for
  hitch/PTO, water courses for pitch/roll.

## Testing & CI

- gdUnit4 covers all pure logic (drivetrain, input arbitration, telemetry, lamps, buoyancy,
  terrain/scatter/road/bake math); run headless with the console Godot binary (`CLAUDE.md`).
- CI (`.github/workflows/ci.yml`): editor-type gate → head-include check → import →
  stale-bake check → bake → gdUnit4 → headless smoke → baked-level smoke → web export +
  level packs, plus a parallel tracking gate.
- `dev` auto-publishes on every push (cache-busted); `stable` moves only on the manual
  promote workflow — `docs/deploying.md`.
- Code is MIT, assets CC0. `../CARLITO_SLOPPYCAN_V1_BACKUP/carlito/` is a behavior/layout
  reference only; nothing is ported from it.

# Carlito — Architecture Overview

A browser-based CAN-bus driving sandbox: drive vehicles (car / truck / tractor / boat /
bike / drone / plane / train) while exchanging live CAN signals with the sloppyCAN/RAMN
simulator. Godot 4.7, web-first, physics locked at 60 Hz + interpolation.

This document is the human-readable map. `CLAUDE.md` is the working reference (commands,
rules, gotchas); `docs/systems.md` and `docs/level_kit.md` hold per-system detail;
`TODO.md` lists the remaining work.

## The big idea: one contract, everything flows through it

`contract/carlito_contract.json` defines every signal that crosses the game↔simulator
boundary: name, direction (`in` = simulator drives the game, `out` = game telemetry), type,
unit, range, warning threshold, enum, which vehicles carry it. Signals are unique by
(name, dir).

Everything else is generated from or validated against it — never hand-duplicated:

- The **Contract autoload** loads and validates it at startup; tests fail if a signal disappears.
- The **dashboard** generates its tell-tale lamps and bars by walking the contract for the active
  vehicle (only the two radial gauges are hand-built widgets).
- The **bridge** marshals outbound telemetry by contract name, and both sides stamp the contract
  version on messages and warn on mismatch.
- The sloppyCAN side consumes a **generated JS copy** (`tools/gen_js_contract.mjs` →
  `../sloppycan/carlito_contract.js`) — regenerated after every contract edit.

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

Key rules baked into that flow:

- **One input path.** Vehicles consume exactly one normalized `VehicleInput` from `InputRouter`.
  Arbitration (bridge-active → the CAN gear byte owns direction; brake always beats throttle;
  ignition key gates throttle; lamp/ISOBUS bits ride the same struct) is static pure functions,
  unit-tested. When bridge input is fresh (< 300 ms) it wins; otherwise local input.
- **Honest telemetry.** RPM comes from the drivetrain, slip from the tires, GPS from position.
  Aux systems (fuel/coolant/battery) are simple models, not random numbers. Every non-trivial
  derivation is a pure static function with a unit test.
- **Web-only transport.** The bridge is inert on desktop; the JS shim is installed by the web
  export's Head Include (source: `src/bridge/web/head_include.html`).

## Vehicles

`src/vehicles/base/` is the framework: `VehicleSpec` (a `.tres` resource holding ALL drive
tuning — adding a vehicle is a new spec + scene, no code), `Drivetrain` (pure math), `RayWheel`
(one-ray suspension with the clamps that keep 60 Hz stable — don't touch), `VehicleMath`
(the dampers, yaw torque and attitude extraction the free-body vehicles — boat, drone,
plane — share), `BaseVehicle`, `ChaseCamera`, `LampSet`, procedural `Horn`.

Vehicles needing per-tick systems beyond driving subclass `BaseVehicle` through exactly two
virtual seams: `_make_telemetry()` (return a telemetry subclass) and `_tick_extras(input, delta)`
(run last each physics tick). The tractor (`TractorVehicle`, the widest signal cluster in the
game — see below), the truck (`TruckVehicle`, J1939 chassis + refuse body; `SemiTractor` extends
it again for the towed body), the boat (`BoatVehicle`, probe buoyancy), the flying pair — the drone
(`DroneVehicle`, DroneCAN flavor: arm/climb, rotor thrust) and the plane (`PlaneVehicle`,
CANaerospace flavor: elevator/flaps, prop thrust + lift) — and the train (`TrainVehicle`,
`"train"` flavor: pantograph/doors, a 1D consist sim on a rail spline, kinematic loco) are
the subclasses.

On top of the contract *families*, `VehicleCatalog` maps cosmetic *variants* (the
Kenney car-kit bodies: taxi, firetruck, ambulance, …) onto them — V cycles variants
in-game, and E cycles whatever hangs off the back of one (the tractor's implement, the semi's
trailer — the shell duck-types `cycle_implement()`). Two keys, two axes, so neither changes
meaning depending on what you are driving; the contract, dashboard and bridge only ever see
the family. Tire grip is
per-surface: wheels sample the terrain's painted splat channels (`channel_grip`), so an
ice strip or a painted asphalt road changes feel without touching collision.

### The tractor (the widest cluster: 20 ISOBUS signals)

The tractor is one body with **four swappable implements** — plough, power harrow, rotary
mower, fertilizer spreader — plus a detached state, cycled with E (the shell duck-types
`cycle_implement()`, so nothing outside the tractor knows implements exist). Each machine
teaches a different one of the **five real tractor↔implement connections**: the three-point
linkage, the drawbar (declared, unused until a trailer exists), the PTO stub shaft, the SCV
hydraulic remote, and the ISOBUS data link. The last two are non-visual — logical state, no
hoses or cables modelled — and what an implement *declares* is load-bearing: the data link
decides whether it claims an address at all (`implement_connected` / `implement_type`), and
the PTO/SCV declarations decide whether drive and flow reach it. A mechanical-only plough is
therefore attached and electronically silent, exactly as on a real ISOBUS tractor.

The signals are real rather than indicator bits. `ThreePointHitch` is solved as a four-bar
linkage, so implements visibly tip back as they lift; `diff_lock` and `fwd_drive` (MFWD)
genuinely change the driveline, gated on spec flags true only on the tractor;
`wheel_speed`/`ground_speed`/`wheel_slip` are the ISO wheel-based-vs-ground-based pair read
out of the same sim; `guidance_curvature` lets the simulator steer (auto-steer, overriding the
steer channel like the boat's rudder); `scv_flow` runs the spreader's hopper gate ram. The
keystone is **`draft_force`**: a draft-relevant implement lowered into level 1's painted field
puts a real rearward force at the hitch point, and the rpm sag, `engine_load` and `wheel_slip`
that follow are consequences of that one force — never separately faked numbers.

### The truck (the family that teaches network topology)

Where the tractor is one bus done widely, the truck is **several buses done side by side**, and
the contrast between them is the content. Four variants share one J1939 chassis (air-brake
reservoirs that genuinely gate the brakes, a retarder that is a real driveline torque, an axle load
summed off the suspension, the DM1 lamp bits), and then diverge:

- the **garbage truck** adds a **CiA 422** CANopen body network across a **CiA 413** gateway — a
  thick boundary, a second bus that can go *down*, and an interlock computed on the chassis and
  published on the body;
- the **firetruck** is the control case: identical chassis, no body network, body signals at zero;
- the **cab-over semi** tows a free-roaming trailer on a real `Generic6DOFJoint3D` and carries
  **ISO 11992** — a deliberately thin boundary, five messages about brakes and running gear and
  nothing about what the trailer *is*;
- the **North American conventional** tows the same trailers with **no trailer bus at all**, and
  says everything it can say about them in one power-line bit (**SAE J2497**). With a trailer
  coupled, `trailer_connected` reads false and the trailer bars sit at zero — attached steel and
  bus silence.

Four semi-trailers (box, tipper, tanker, flatbed) and **not one of them adds a signal**: they earn
their place through mass, what they plug into the towing unit, and which tractor-side signals they
move. `E` cycles the trailer, `V` the body — the same two axes as everywhere else.

## Levels and the authoring kit

Levels are self-contained scenes composed by the shell (`boot.gd`: boot straight into a level →
play, with level select and the vehicle selector as sections of the pause overlay). A level =
`Level` base script + a `LevelInfo` resource (allowed vehicles)
+ `VehicleSpawn` markers. Adding one to the game = a `LevelRegistry.LEVELS` entry.

Levels are authored with the kit (`kit/` + the `addons/carlito_kit` editor plugin): generated
heightmap terrain with a color-splat ground, GridMap palettes for road/tile kits, `KitPiece`
prefabs placed from a thumbnail dock, seeded/painted scatter for vegetation, and spline
`RoadPath` roads that conform the terrain (incl. bridge profiles with a solid underside
for water spans) — all under one `AuthoringRoot`. The **bake tool**
then merges render meshes per chunk, harvests prop collision per chunk, and welds all drivable
geometry into a single level-wide collision body, which kills chunk-seam ghost collisions.
Bakes are input-hash-stamped; CI fails on stale bakes. At runtime `Level` loads
`<level>.baked.scn` and drops the authoring subtree; an export plugin guarantees authoring
content never ships. **Rails** are a `RoadPath` carrying a `RailProfile` (a Rail checkbox in
the Roads panel swaps it in) — the same draw/conform/bake path — but the train needs the
spline at runtime, so the baker also emits a `RailTrack` node holding the curve; level 5 is
the railway built on this (`tools/gen_rail_level.gd`).

Levels are **signal playgrounds**: there are no missions — the sandbox is the CAN telemetry,
and a level's job is to give contract signals a place to visibly perform (grades for
`engine_load`, hairpins for slip, fields for hitch/PTO, water courses for pitch/roll).

## Testing & CI

- **gdUnit4** covers all pure logic: drivetrain, input arbitration, telemetry derivations, lamps,
  buoyancy, terrain/scatter/road/bake math. Run headless with the console Godot binary (see
  CLAUDE.md for exact commands).
- **CI** (`.github/workflows/ci.yml`): import → tests → stale-bake check → headless smoke (boots
  the shell, which drives straight into a level like everything else does) → web export.
  Pushes to `dev` publish the **dev** channel on GitHub Pages with cache-busted filenames
  (export basename embeds the commit SHA); **stable** moves only on the manual promote
  workflow, which copies the approved dev bytes — see `docs/deploying.md`.

Code is MIT, assets CC0. The previous generation of the game lives outside the project at
`../CARLITO_SLOPPYCAN_V1_BACKUP/carlito/` — its deployed build may be observed as a
behavior/layout reference, but its code is never read or copied.

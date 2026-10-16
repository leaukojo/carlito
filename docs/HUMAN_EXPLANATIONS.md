# Carlito, explained from scratch

A plain-language tour of how the game works, for someone joining the project. Detailed
references: `docs/overview.md`, `docs/systems.md`, `docs/vehicles.md`,
`docs/heavy_vehicles.md`, `docs/level_kit.md`. This file trades precision for readability.

## What is this?

A browser driving sandbox (car, truck, tractor, boat, drone, plane, train) that exchanges
CAN-style messages with a companion simulator (sloppyCAN/RAMN) in the same page. Throttle in
sloppyCAN accelerates the car; real RPM, speed, GPS and lamps stream back. Levels make signals
visible: a grade raises `engine_load`, a hairpin makes tires slip.

The one exception is **challenges**: short goal-driven lessons (stop in a box, take a bend on
ice, plough a field, couple a trailer and deliver it, ...) that teach CAN by making you drive *through* sloppyCAN. The keyboard
is locked out for the attempt; you read the signals and send the commands yourself. Each pass is
timed, and your best times are kept between visits. Press 5 (or CHALLENGE) to pick one.

It's built in Godot 4.7 and exported to WebAssembly. Physics runs at 60 Hz with interpolation for
smooth rendering.

## The contract

`contract/carlito_contract.json` lists every signal crossing the game-simulator boundary (name,
direction, type, unit, range, warning threshold, vehicles). Nothing else hand-maintains a list: the
`Contract` autoload validates it, the dashboard and bridge walk it, the simulator uses a generated
JS copy (`tools/gen_js_contract.mjs`). Both sides stamp a contract version on every message and
warn on mismatch. Detail: `docs/overview.md`, `docs/systems.md`.

## How input flows, start to finish

Flow: sloppyCAN -> postMessage -> `window.__carlito` stash -> `Bridge` (web-only) -> `InputRouter`
(also keyboard/touch) -> one `VehicleInput` -> `BaseVehicle` (diagram: `docs/overview.md`).

**InputRouter is the only place input decisions are made.** It merges keyboard, touch and
gamepad, and when fresh bridge data carrying a driving control (throttle, brake or steer) is
arriving (recent, not stale) the bridge wins outright. A live bridge that sends no driving
control leaves the driving to you and keeps the rest (lamps, gear, switches). All
the rules — brake is never throttle, the ignition key must be on to drive, the simulator's
gear byte decides forward vs reverse when it's in control — live here as pure static
functions with unit tests. Vehicles never know or care where their input came from; they
just consume one normalized `VehicleInput` every physics tick, which is why the same car
works with a keyboard, a phone touchscreen, and a CAN simulator with no vehicle code
changing.

Key presses are eased (KEY RESPONSE setting, RAW to REALISTIC); gamepad, touch stick and bridge are
analog and never eased.

## Vehicles

`src/vehicles/base/` is a small framework: a `VehicleSpec` `.tres` (all driving-feel numbers; a new
vehicle is a spec plus a scene), pure-math `Drivetrain`, one-raycast `RayWheel`, and `BaseVehicle`,
which subclasses extend only through `_make_telemetry()` and `_tick_extras()`. Detail:
`docs/overview.md`, `docs/systems.md`.

The **tractor** adds twenty ISOBUS-style signals. Press E to cycle the implement (spreader, plough,
power harrow, mower, tipping trailer, or nothing); what a machine declares over the data cable
decides what the bus reports. The trailer has no electronics beyond lamps, so it reports as nothing
attached, like a real dumb trailer. Signals do real work: the diff lock ties the rear wheels,
`guidance_curvature` lets the simulator steer, and the plough puts a real rearward force at the
hitch (engine bog, load climb and slip all follow from it). Detail: `docs/heavy_vehicles.md`.

The **truck** family carries several networks: four variants share one J1939 chassis bus (air
pressure is a real brake gate); the garbage truck adds a CANopen body bus behind a gateway; the
cab-over semi tows over a brakes-only bus; the conventional tows with no trailer bus. "Nothing on
the bus" and "nothing there" are different states. Detail: `docs/heavy_vehicles.md`.

The **train** is a 1D sim of carriages on a spline joined by spring couplers; the locomotive body
follows it each tick. Raise the pantograph to draw power; the reverser rides the shared gear byte.

The **drone** speaks DroneCAN: each ESC, the GPS, the power module and the attitude sensor is its
own node that broadcasts unprompted. Press Y and one node goes silent: a killed ESC really stops
the motor and the craft spins, but its reported rpm and current freeze at the last values, as on a
real bus. Spotting a stale-but-plausible number is the point.

A **VehicleCatalog** lists variants (taxi, ambulance, two semi units) on the families. The contract
sees only families; the two semis share a family and script, and only one has a trailer bus.

**Telemetry is honest.** RPM comes from the drivetrain that actually moved the car, slip from
the tire model, GPS from position. The few things a driving sim doesn't naturally produce
(fuel level, coolant temperature, engine load) are simple physically-plausible models,
clearly labelled — never random numbers.

## Levels

A level is a scene (terrain, props, spawns, a `LevelInfo` of allowed vehicles); the shell (`boot.gd`)
loads it and wires camera, dashboard and bridge. Authoring uses the in-editor kit, but what ships is
a hash-stamped bake (merged meshes per chunk, one welded collision body); CI fails a stale bake.
Water is a flat height API for buoyancy (waves are shader-only) plus a respawn volume for land
vehicles.

## What you see on screen

The game drives first: the page loads straight into a car on a flat plain, standalone or inside
sloppyCAN (`?level=&vehicle=` picks others). Five top-left buttons (MENU, VEHICLE, LEVEL, CAMERA,
CHALLENGE; F5 hides them); Esc/MENU opens RESUME, RESPAWN, CONDITIONS, CONTROLS, SETTINGS.

- **GARAGE**: families, bodies, a live 3D preview with specs; unspawnable machines show the reason.
- **LEVEL**: screenshot cards with the download weight (each island is a separate download).
- **CONTROLS** is generated from one table (`ActionRegistry`), as are the touch buttons.
- **CONDITIONS**: wind, current, day/night; session-wide, not saved.
- **SETTINGS** (saved): cluster COMPACT/FULL/OFF (F2), UI size, F3 readouts, KEY RESPONSE, traction control.

Any size: one theme is rebuilt at a scale from the window's short edge; screens and grids reflow.

## Testing and CI

All the pure logic is covered by gdUnit4 unit tests. Anything with logic worth testing is
written as a static pure function, so tests don't need a running game. Every push runs CI
(`docs/overview.md` § Testing & CI); `dev` publishes itself, `stable` moves only on the manual
promote button (`docs/deploying.md`). The house rules and their reasons are root `CLAUDE.md`'s
standing rules.

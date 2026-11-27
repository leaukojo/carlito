[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# How the simulator is built

<p class="lead">This page explains how the simulator's code is put together, for readers who want
to change it: the signal file, the vehicles, the levels and the tests.</p>

## The engine and the web page

Carlito is made with Godot 4.7, a free, open-source game engine (a program that provides the
drawing, the physics and the sound, so that a project only adds its own parts). Godot exports the
simulator to WebAssembly, a format web browsers run directly, so the simulator runs in a web page
with nothing to install. The physics runs 60 times a second. A screen that refreshes 120 times a
second would show each physics position twice, and motion would stutter, so between two physics
steps the engine draws each vehicle at an in-between position (this is called physics
interpolation).
<!-- project.godot common/physics_interpolation=true; physics ticks per second: the engine default, 60 -->

Most islands are separate downloads (level packs), fetched the first time you open them, so the
page loads quickly the first time and nobody downloads islands they never visit.
<!-- src/shell/level_packs.gd header; docs/deploying.md § Level packs -->

## One file lists every signal

Every signal that passes between the simulator and sloppyCAN is listed in one file,
`contract/carlito_contract.json`: its name, its direction, its type, unit and range, its warning
threshold, and which vehicles send it. Nothing else keeps its own list, so a signal cannot be
spelled one way in the simulator and another way in sloppyCAN. The simulator checks the file when
it starts. The dashboard builds its lamps and bars from it. The bridge (below) packs and unpacks
signals by the names in it. And sloppyCAN uses a JavaScript copy generated from it
(`tools/gen_js_contract.mjs`). Each side stamps its messages with the file's version number and
a hash (a short fingerprint computed from the file's content, which changes whenever the content
does), and warns when the other side's does not match, so an out-of-date copy on either side shows
at once.
<!-- docs/overview.md § The big idea: one contract, everything flows through it; bridge.gd contract_mismatch, Contract.data.content_hash -->

## From a sloppyCAN command to the wheels

1. sloppyCAN runs in the same browser page as the simulator. It sends its commands as browser
   messages (`postMessage`).
2. A small script loaded with the simulator's page (`window.__carlito`) keeps the latest value of each
   command and the time it arrived.
3. The `Bridge` reads those values at every physics step. A value older than 0.3 s counts as
   stale and is ignored.
4. The `InputRouter` merges them with the keyboard, the touch screen and the gamepad into one
   `VehicleInput`, and decides [who drives](controls.md#who-drives-local-or-sloppycan).
5. The vehicle reads that one `VehicleInput` at every physics step. It never knows where its
   input came from, which is why the same vehicle works from a keyboard, a phone or a CAN
   simulator without a line of vehicle code changing.
6. In the other direction, the bridge reads the vehicle's telemetry 20 times a second and sends
   it to sloppyCAN.
<!-- bridge.gd header: polls the stash each physics tick, FRESHNESS_MS 300, PUBLISH_HZ 20 -->

The bridge works only in the web build, because `postMessage` exists only in a browser. In the
editor and in a desktop build it stays off, and the keyboard, touch screen and gamepad drive.

Every input rule lives in `src/input/` as a small function that takes values and returns values.
Such a function needs no simulation running, so a test can hand it, for example, "brake and
accelerator both pressed at 20 km/h" and check what comes out.

## Vehicles

Every vehicle is built on one small framework in `src/vehicles/base/`:

- **A spec**, a `VehicleSpec` resource file (`.tres`), holds every number that sets how the
  vehicle drives: mass, engine, gears, tyres, suspension and the rest. A new vehicle of an
  existing kind is a new spec and a new scene, with no new code.
- **`Drivetrain`** is the engine, clutch and gearbox, as pure maths ([The engine](engine.md),
  [Gearbox and shifting](gearbox.md)).
- **`RayWheel`** is a wheel made of the tyre's cylinder, swept down its suspension travel. Where it
  meets the ground, the spring and tyre forces are worked out
  ([How the simulation works](simulation.md)).
- **`BaseVehicle`** is the body, a Godot `RigidBody3D` (a solid object the physics engine moves),
  that puts the parts together. Each family adds its own parts in a subclass (a version of
  `BaseVehicle` that inherits everything it does and adds to it): `TractorVehicle`,
  `TruckVehicle`, `BoatVehicle`, `DroneVehicle`, `PlaneVehicle` and `TrainVehicle`. A subclass
  hooks in at only two points, the telemetry it reports (`_make_telemetry()`) and its own work at
  each physics step (`_tick_extras()`), so the shared code stays the same for every family.
<!-- docs/overview.md § Vehicles -->

`VehicleCatalog` lists the bodies within a family, such as the taxi and the ambulance among the
cars or the two semi tractor units among the trucks. The signal file knows only the seven
families, so every body of a family reports the same signals.

The numbers sent to sloppyCAN are read from the simulation that moved the vehicle: rpm from the
drivetrain, slip from the tyre model, position from the body. The few values a driving simulation
does not produce on its own, such as the fuel level or the coolant temperature, come from simple
models, labelled as such ([Fuel, coolant, battery and air](auxiliary.md)), never from random
numbers.

## Levels

A level is a Godot scene: the ground, buildings and props, water if there is any, spawn points
for vehicles, and a `LevelInfo` resource listing which vehicles may drive there. A shell scene,
`src/shell/boot.tscn`, loads the level and adds the camera, the dashboard and the bridge, so
levels, vehicles and the screens stay separate pieces. A web address ending in
`?level=<id>&vehicle=<family>` opens that level and vehicle directly.
<!-- boot_params.gd: "?level=x&vehicle=y" -->

Levels are built in the Godot editor with the project's own tools, the Kit panel. What the
simulator ships is not the edited scene but a bake of it. The baker merges the meshes (the 3D
shapes) of each area into one, and joins every drivable surface into one collision body. Why? The
graphics card draws one big mesh far faster than a thousand small ones, and the physics checks one
body faster than many. Each bake records a fingerprint of everything it was made from, and when a
level changes after its bake, the automatic checks fail until it is baked again.

Water is a flat surface at a known height. A volume under the surface respawns a vehicle that
drives in.

## The screens

The interface fits any window, from a phone to a large monitor: one theme (fonts, sizes,
spacing) is rebuilt at a scale taken from the window's shorter side whenever the window changes
size, and the menus reflow. The pause menu's CONTROLS page and the touch screen's buttons are
both generated from one table of actions, `ActionRegistry`, so a new control appears on both
without being written twice.
<!-- src/ui/ui_scale.gd and src/input/action_registry.gd headers -->

## Testing and publishing

Anything with logic worth testing is written as a function that takes values and returns values,
so a test can call it without starting the simulator. gdUnit4, a test framework for Godot, runs
those tests: the drivetrain, the signal file, the input rules, GPS and odometer, and the terrain,
scatter, road and bake maths. For example, a test can ask the GPS function for the latitude 111 m
north of the origin, and check that it comes out a thousandth of a degree higher.
<!-- .claude/CLAUDE.md standing rule 8 -->

Every push to GitHub runs the automatic checks (CI): the import, the bake check, the tests, a
short run of the simulator without a window, and the web export. The `dev` branch publishes itself to
the dev site at every push; the stable site changes only when someone presses the promote button.
Both addresses are in the repository's README.
<!-- .github/workflows/ci.yml; docs/deploying.md § The two channels -->

## Related

- [Making a level](making-a-level.md): building a level in the Godot editor.
- [Controls and who drives](controls.md): the input rules.
- In the repository, `docs/overview.md` is the developer map: short, dense notes written for AI
  coding agents, with a pointer to each part's own document.

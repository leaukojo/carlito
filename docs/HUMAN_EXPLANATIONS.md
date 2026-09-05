# Carlito, explained from scratch

A plain-language tour of how the game works, for someone joining the project. Detailed
references: `docs/overview.md`, `docs/systems.md`, `docs/vehicles.md`,
`docs/heavy_vehicles.md`, `docs/level_kit.md`. This file trades precision for readability.

## What is this?

Carlito is a driving sandbox that runs in the browser: car, truck, tractor, boat, drone,
plane or train, around small levels. No missions or scores — the point is the **signals**:
while you drive, the game continuously exchanges CAN-bus-style messages with a companion
simulator (sloppyCAN/RAMN) in the same web page. Press the throttle in sloppyCAN and the car
in Carlito accelerates; the car's real RPM, speed, GPS and warning lamps stream back the
other way. Levels exist to make those signals visible: a steep grade makes `engine_load`
climb, a hairpin makes the tires slip, a field gives the tractor's hitch and PTO something
to do.

It's built in Godot 4.7 and exported to WebAssembly. Physics runs at a locked 60 Hz with
interpolation for smooth rendering.

## The one idea that organizes everything: the contract

`contract/carlito_contract.json` is the heart of the project. It lists every signal that
crosses the game↔simulator boundary: name, direction (`in` = simulator drives the game,
`out` = game reports telemetry), type, unit, valid range, warning threshold, and which
vehicles carry it.

Nothing else hand-maintains a signal list. The `Contract` autoload loads and validates the
JSON at startup; the **dashboard** builds its warning lamps and bar gauges by walking it for
the current vehicle (add a signal, a lamp appears — no UI code); the **bridge** decides what
telemetry to send the same way; the simulator side uses a generated JS copy
(`tools/gen_js_contract.mjs`).

Adding or changing a signal is a one-file edit plus a regeneration step. Both sides stamp a
contract version on every message and warn if they differ, so they can never silently
disagree about what a signal means.

## How input flows, start to finish

```
sloppyCAN (JS in the page)
      | postMessage
      v
window.__carlito stash          <- a tiny script injected into the exported HTML
      | polled 60x/sec
      v
Bridge (autoload)               <- inert on desktop; web-only
      v
InputRouter (autoload)          <- ALSO reads keyboard + touch controls
      v
one VehicleInput struct         <- throttle, brake, steer, gear, lamps, hitch...
      v
BaseVehicle (the physics body)
```

**InputRouter is the only place input decisions are made.** It merges keyboard and touch,
and when fresh bridge data is arriving (less than 300 ms old) the bridge wins outright. All
the rules — brake is never throttle, the ignition key must be on to drive, the simulator's
gear byte decides forward vs reverse when it's in control — live here as pure static
functions with unit tests. Vehicles never know or care where their input came from; they
just consume one normalized `VehicleInput` every physics tick, which is why the same car
works with a keyboard, a phone touchscreen, and a CAN simulator with no vehicle code
changing.

## Vehicles

`src/vehicles/base/` is a small framework:

- **VehicleSpec** (`.tres`, wheeled half — wheels, suspension, tires, brakes, road
  resistance — in an embedded **GroundDriveSpec**) holds all the driving-feel numbers: mass,
  wheel positions, torque curve, gear ratios, brake strength. A new vehicle is a new spec
  plus a scene, no new code.
- **Drivetrain** is pure math (torque, gears, real RPM computed back from wheel speed).
- **RayWheel** is a one-raycast-per-wheel suspension and tire model, clamps tuned to keep
  physics stable at exactly 60 Hz — the tick rate is locked because of this.
- **BaseVehicle** ties it together: reads input, runs wheels and drivetrain, publishes
  telemetry, drives lamps and horn.

Vehicles needing extra behavior (tractor hitch/PTO, boat buoyancy) subclass BaseVehicle
through exactly two hooks: `_make_telemetry()` and `_tick_extras()`. They never override the
main physics loop, so every vehicle's core behavior stays identical and testable.

The **tractor** carries the most signals of anything in the game — twenty, borrowing the
names farm machinery really uses on its ISOBUS bus. One tractor body; press E to cycle what
hangs off the back (fertilizer spreader, plough, power harrow, rotary mower, tipping
trailer, or nothing), each using a different mix of the five real tractor↔implement
connections (three-point linkage, drawbar, PTO shaft, hydraulic hose, data cable). What a
machine declares over the data cable decides what the bus reports about it.

The trailer is the odd one out: a separate ten-tonne body on a real joint and its own
wheels, not bolted on like the implements. A drawbar only pulls — hitch it and the
three-point linkage still rises and falls behind it, doing nothing, because you can't lift a
trailer with a linkage. It has no electronics beyond its lamps, so ten tonnes of attached
steel reports on the bus as nothing attached, exactly like a real dumb trailer.

Signals do real work rather than light up lamps: locking the differential really ties the
rear wheels to one shaft, `guidance_curvature` lets the simulator take the wheel (GPS
auto-steer), and dropping the plough into the painted field puts a genuine rearward force at
the hitch — engine bog, load-bar climb and rear-wheel slip are consequences of that one
force, not separately invented numbers. Signal-by-signal detail: `docs/heavy_vehicles.md`.

The **truck** family shows that real vehicles carry several networks at once. All four
variants share one J1939 chassis bus — air pressure is a genuine brake gate, not a
decorative bar — and then diverge: the garbage truck adds a second CANopen bus for its body
behind a gateway; the firetruck has no body network; the cab-over semi tows a trailer over a
thin bus that only talks about brakes; the North American conventional tows the same
trailers with no trailer bus at all, saying everything it can in one power-line lamp. Same
lesson as the plough: "nothing on the bus" and "nothing there" are different states. Full
breakdown in `docs/heavy_vehicles.md`.

The **train** takes the same idea furthest: an electric multiple-unit consist on rails, not
roads (a "Rail" checkbox gives the road tool a track profile instead of asphalt; the level's
rail loop becomes the line it rides). Instead of steering, its motion is a small 1D physics
sim — each carriage a weight sliding along the spline, connected by spring couplers, feeling
grade and brakes — and the locomotive body is moved to match that sim each tick, so the
speed/acceleration readouts stay honest. Raise the pantograph to draw power (drop it and
traction cuts, like a real overhead line), doors open only at a standstill, and the reverser
rides the same gear byte every other vehicle uses. Extra gauges (line voltage, motor
current, brake-pipe pressure, coupler force) are honest simple models borrowing rail
terminology, not real electronics.

The **drone** answers a question the others don't: what if the bus isn't a bus, but a
network? Every other vehicle here has one computer that knows everything. A quadcopter
isn't built that way. DroneCAN (the language ArduPilot and PX4 peripherals actually speak,
and the reason you can buy a $15 CAN speed controller or a $30 CAN GPS) treats the aircraft
as a small committee: each motor's speed controller is its own computer with its own
address, and so are the GPS, the power module, the attitude sensor and the rangefinder.
Nobody polls them — each one just talks ("I am node 11, healthy, motor at 6,400 rpm, drawing
15 amps, at 31 degrees") and whoever cares, listens. The flight controller is one more voice
on the wire, not a master.

Which means the interesting thing a drone can do on a bench is stop talking. Press Y and one
node drops off the network. Kill an ESC and that motor really stops, the mixer really loses
a quarter of its authority on every axis, and the craft really starts to spin — nothing
compensates, because nothing would on a real airframe. But watch the readouts: the dead
motor's rpm, current and temperature don't fall to zero, they freeze at whatever they last
said, because a computer that has stopped talking cannot tell you it has stopped. Learning
to spot a stale-but-plausible number is most of what this vehicle is for. Kill the GPS
instead and the craft demotes itself from position hold to altitude hold and says so in a
second signal, rather than pretending it still knows where it is. Everything else on the
aircraft — the pack that sags under throttle, satellites lost flying between buildings,
pre-arm checks refusing to spin motors on a slope — gives you something honest to watch a
dropped node against.

On top of the families (car, truck, tractor, boat, drone, plane, train — what the contract
and dashboard know about), a **VehicleCatalog** lists variants: individual bodies like the
taxi, the ambulance, the two semi tractor units. The garage cycles through them; the
contract never sees variants, only families. Usually cosmetic, but not always — the two
semis are the same family and script, and only one has a trailer bus.

**Telemetry is honest.** RPM comes from the drivetrain that actually moved the car, slip
from the tire model, GPS from position. The few things a driving sim doesn't naturally
produce (fuel level, coolant temperature, battery voltage, engine load) are simple
physically-plausible models, clearly labelled — never random numbers.

## Levels

A level is a self-contained scene: terrain, props, spawn points, and a `LevelInfo` resource
saying which vehicles are allowed. The shell (`boot.gd`) loads a level, spawns a vehicle,
wires up the camera, dashboard and bridge. Levels, vehicles and UI are independent scenes
composed at runtime — nothing is hardwired.

Levels are authored with an in-editor kit (terrain brushes, GridMap tile palettes, prefab
placement dock, vegetation scatter brushes, spline-based roads that flatten the terrain
under them), but what ships is a bake: a tool merges the static authoring content into a few
big meshes per chunk and welds every drivable surface into one collision body (no phantom
bumps at chunk seams). Each bake is hash-stamped; CI fails on a stale bake.

Water is its own system: a flat height API for the boat's buoyancy (visual waves are
shader-only, never touch physics), plus a "you drove into the lake" respawn volume for land
vehicles.

## What you see on screen

**The game drives first.** No front door, no menu asking you to choose before you know what
you're choosing between: the page loads, a mountain level comes up, you're already in a
car. True standalone and inside sloppyCAN alike — one boot path. A link can ask for
something specific (`?level=…&vehicle=…`); otherwise the game remembers where you were last
time.

Everything else hangs off **Esc** (or touch MENU): RESUME, VEHICLE, LEVEL, CONTROLS,
SETTINGS.

- **VEHICLE**: families down the left, that family's bodies as pictures in the middle, what
  it can tow underneath, and a single live 3D preview on a turntable with the machine's
  specs (including what it speaks on the bus, read out of the contract). Machines this level
  won't spawn are still browsable and preview, carrying the reason on the card.
- **LEVEL**: a grid of screenshots with a description and a download weight on each — the
  city level is a 14 MB bake, and you find that out before you wait for it.
- **CONTROLS** is generated, never typed. One table (`ActionRegistry`) describes every bound
  key; this sheet and the touchscreen buttons are both built from it, key names read live
  from the input map. A control can't exist without being documented, or be documented
  without being reachable. Controls the current vehicle doesn't have are greyed with the
  reason rather than hidden.
- **SETTINGS**: currently one thing, how much instrument cluster you want (FULL, COMPACT,
  OFF, or AUTO — quietly goes compact on a phone or when sloppyCAN is already showing the
  numbers).

**It has to work at any size.** No fixed layout: one theme is rebuilt at a scale derived
from the window's short edge, and every screen sizes itself from that — card grids reflow
their column count, the tell-tale row wraps, the touchscreen button stack wraps into another
column rather than running off the bottom of a short window. (The engine's own content
scaling would have been simpler, but both its modes also resize the 3D render target, which
the web performance budget can't pay for.)

## Testing and CI

All the pure logic — drivetrain math, input arbitration, telemetry derivations, buoyancy,
terrain/road/scatter/bake math — is covered by gdUnit4 unit tests (over 1,100 test
functions). Anything with logic worth testing is written as a static pure function, so tests
don't need a running game.

Every push runs CI: import → tests → two headless boot smokes → stale-bake check → web
export. `dev` auto-publishes with cache-busted filenames; `stable` moves only on the manual
promote button (`docs/deploying.md`). `tools/preflight.ps1` runs the same gates locally; a
pre-commit hook catches the common footguns (stale bakes, stale contract copy, editor-only
type annotations that would silently break the web build).

## House rules worth knowing (and why)

A digest for orientation — `CLAUDE.md`'s standing rules are the authoritative copy.

- **Physics is 60 Hz, forever** — suspension tuning depends on the tick length.
- **One contract file, everything generated.** Never hand-copy a signal list.
- **All input arbitration lives in InputRouter.**
- **Telemetry is read out of the simulation, never invented.**
- **Lamp state rides the input struct** — no local blink timer; the simulator is the
  authority.
- **Baked geometry ships, authoring content doesn't** — an export plugin strips it.
- **Trimesh collision is the exception** — ground is a heightmap shape, props get boxes or
  convex hulls.
- **No emoji in UI** — the web font has no glyphs.
- **Loading a stranger's level file is code execution** (Godot scenes embed scripts), so
  level sharing is out of scope.

More sharp edges: `CLAUDE.md`'s gotchas section, before touching wheels, bakes, or the web
export.

# Carlito, explained from scratch

A plain-language tour of how the game works, written for someone joining the project.
The detailed references are `docs/overview.md`, `docs/systems.md`, and `docs/level_kit.md`;
this file trades precision for readability.

## What is this?

Carlito is a driving sandbox that runs in the browser. You drive a car, truck, tractor,
or boat around small levels. There are no missions or scores — the point of the game is
the **signals**: while you drive, the game continuously exchanges CAN-bus-style messages
with a companion simulator (sloppyCAN/RAMN) running in the same web page. Press the
throttle in sloppyCAN and the car in Carlito accelerates; the car's real RPM, speed, GPS
and warning lamps stream back the other way. Levels exist to make those signals visible:
a steep grade makes `engine_load` climb, a hairpin makes the tires slip, a field gives
the tractor's hitch and PTO something to do.

It's built in Godot 4.7 and exported to WebAssembly. Physics runs at a locked 60 Hz with
interpolation for smooth rendering.

## The one idea that organizes everything: the contract

`contract/carlito_contract.json` is the heart of the project. It lists every signal that
crosses the game↔simulator boundary: its name, direction (`in` = simulator drives the
game, `out` = game reports telemetry), type, unit, valid range, warning threshold, and
which vehicles carry it.

Nothing else in the project hand-maintains a signal list. Instead:

- The `Contract` autoload loads and validates the JSON at startup.
- The **dashboard** builds its warning lamps and bar gauges by *walking the contract* for
  the current vehicle. Add a signal to the JSON and a lamp appears — no UI code.
- The **bridge** decides what telemetry to send by walking the contract too.
- The simulator side uses a *generated* JavaScript copy (`tools/gen_js_contract.mjs`).

This means adding or changing a signal is a one-file edit plus a regeneration step, and
the two sides can never silently disagree about what a signal means (both stamp a
contract version on every message and warn if they differ).

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
and when fresh bridge data is arriving (less than 300 ms old) the bridge wins outright.
All the rules — "brake is never throttle", "the ignition key must be on to drive", "when
the simulator is in control, its gear byte decides forward vs reverse" — live here as
pure static functions with unit tests. Vehicles never know or care where their input came
from; they just consume one normalized `VehicleInput` every physics tick.

This is why the same car works with a keyboard, a phone touchscreen, and a CAN simulator
without any vehicle code changing.

## Vehicles

`src/vehicles/base/` is a small framework:

- **VehicleSpec** (a `.tres` resource) holds *all* the driving-feel numbers: mass, wheel
  positions, torque curve, gear ratios, brake strength. A new vehicle is a new spec plus
  a scene — no new code.
- **Drivetrain** is pure math (torque, gears, real RPM computed back from wheel speed).
- **RayWheel** is a one-raycast-per-wheel suspension and tire model. It contains carefully
  tuned clamps that keep the physics stable at exactly 60 Hz — this is why the physics
  tick rate is locked and the clamps must never be weakened.
- **BaseVehicle** ties it together: reads input, runs wheels and drivetrain, publishes
  telemetry, drives the lamps and horn.

Vehicles that need extra behavior (the tractor's hitch/PTO, the boat's buoyancy) subclass
BaseVehicle through exactly **two hooks**: `_make_telemetry()` (return a bigger telemetry
object) and `_tick_extras()` (run once per tick, after everything else). They never
override the main physics loop — that keeps every vehicle's core behavior identical and
testable.

The **tractor** carries the most signals of anything in the game — twenty of them, borrowing
the names farm machinery really uses on its ISOBUS bus. There is one tractor body, and the
interesting part is what is hanging off the back of it: press E and you cycle through a
fertilizer spreader, a plough, a power harrow, a rotary mower, and nothing at all. Between a
tractor and an implement there are really only five connections — the three-point linkage that
lifts it, the drawbar that tows it, the spinning PTO shaft that drives it, a hydraulic hose,
and the data cable — and each of the four machines uses a different combination, which is the
whole reason there are four. The linkage is *solved* rather than animated (it's a four-bar
mechanism, which is why implements tip backwards as they rise), and what a machine declares
about itself decides what the bus reports: a plain plough with no data cable is bolted on and
electronically invisible, exactly like the real thing.

The signals do real work rather than lighting up lamps. Locking the differential really does
tie the rear wheels to one shaft, so the one with grip claws you out of the mud instead of the
other spinning uselessly; engaging the front axle really does drive it. The simulator can take
the steering wheel off you entirely (`guidance_curvature` — GPS auto-steer, and the best demo
in the game). And the keystone: drop the plough into the painted field and the game pushes
back on the tractor with a genuine force at the hitch. Everything you then see — the engine
bogging down, the load bar climbing, the rear wheels starting to slip — happens because the
machine was actually pulled backwards, not because three numbers were separately invented.
That's the house rule about honest telemetry, taken as far as it goes.

The **truck** family exists to show something the tractor can't: that real vehicles carry *several*
networks at once, and that the interesting question is usually where one ends and the next begins.
All four trucks share the same chassis bus, and the shared part already does real work — the air
pressure isn't a decorative bar, it's a gate, and if you drag the reservoirs down far enough the
spring brakes come on and the truck simply will not move until the compressor catches up. From
there they diverge, and the divergence is the point:

- The **garbage truck** has a *second* bus for its body, sitting behind a translator box called a
  gateway. That boundary is thick: the body network has its own profile, it can lose power and go
  dark on you, and one value — "you are going too fast to swing the arm" — is worked out on the
  chassis side and then published on the body side, which is the only value in the game that
  visibly crosses from one bus to another. Fill the hopper and the extra weight is *real* weight,
  so the axle-load bar climbs because the springs are genuinely carrying more.
- The **firetruck** is the control: identical chassis, no body network, body readouts sitting at
  zero forever. Same class of vehicle, different job — and the bus doesn't care about the job.
- The **cab-over semi** tows an actual trailer, on an actual joint, and talks to it over a bus
  whose whole vocabulary is *brakes*. That's not a simplification on our side: the real standard
  is deliberately that small, and it carries nothing at all about what kind of trailer you're
  pulling. So the four trailers (box, tipper, tanker, flatbed) are indistinguishable on the wire.
  You tell them apart by how heavy they are and how the truck behaves.
- The **North American conventional** — the long-nosed one with the hood out front — tows exactly
  the same trailers and has **no trailer bus at all**, because the connector used over there
  doesn't have the wires for one. It's the most interesting variant in the game precisely because
  of what it *doesn't* do: hook up a trailer and the "trailer connected" lamp stays dark, every
  trailer readout stays at zero, and the trailer still brakes perfectly well, because the air
  hoses were never the data cable. One lamp, sent up the power line, is everything that truck can
  say about nine metres of steel behind it.

That last one is worth sitting with, because it's the same lesson the tractor teaches with a
plough that has no data cable: **"nothing on the bus" and "nothing there" are different states**,
and a system that can't tell them apart will eventually tell you a comfortable lie.

The **train** is the same idea taken furthest. It's an electric multiple-unit consist that
runs on rails, not roads: rails are drawn with the ordinary road tool (there's a "Rail"
checkbox that gives the road a track profile instead of asphalt), and the level's rail loop
becomes the line the train rides. Instead of steering, its motion is a small 1D physics sim
— each carriage is a weight sliding along the spline, connected by spring couplers, feeling
the grade and the brakes — and the locomotive body is moved to match that sim each tick (so
the speed/acceleration readouts stay honest). You raise the pantograph to draw power (drop
it and traction cuts, like a real overhead line), open the doors only at a standstill, and
the reverser (forward/neutral/reverse) rides the same gear byte every other vehicle uses.
Its extra gauges — line voltage, motor current, brake-pipe pressure, coupler force — are
honest simple models, labelled as such, borrowing rail terminology (the descriptions credit
real rail practice) without pretending to be a real train's electronics.

On top of the *families* (car, truck, tractor, boat, bike, drone, plane, train — these are what
the contract and dashboard know about), a **VehicleCatalog** lists *variants*: individual bodies
like the taxi, the ambulance, the two semi tractor units. The garage lets you cycle through them;
the contract never sees variants, only families. Variants are usually just cosmetic, but not
always — the two semis are the same family and the same script, and one of them has a trailer bus
while the other doesn't.

**Telemetry is honest.** RPM comes from the drivetrain that actually moved the car; slip
comes from the tire model; GPS from the position. The few things a driving sim doesn't
naturally produce (fuel level, coolant temperature, battery voltage, engine load) are
simple physically-plausible models, clearly labelled as such — never random numbers.

## Levels

A level is a self-contained scene: terrain, props, spawn points, and a `LevelInfo`
resource saying which vehicles are allowed. The shell (`boot.gd`) loads a level, spawns a
vehicle, and wires up the camera, dashboard and bridge. Nothing is hardwired — levels,
vehicles and UI are independent scenes composed at runtime.

Levels are *authored* with an in-editor kit (terrain brushes, GridMap tile palettes,
prefab placement dock, vegetation scatter brushes, spline-based roads that flatten the
terrain under them). But what *ships* is a **bake**: a tool merges all the static
authoring content into a few big meshes per chunk and welds every drivable surface into
one collision body (which prevents phantom bumps at chunk seams). Each bake is stamped
with a hash of its inputs, and CI fails if a level's bake is stale — you literally cannot
ship an out-of-date bake by accident.

Water is its own system: a flat height API for the boat's buoyancy (the visual waves are
shader-only and never touch physics), plus a "you drove into the lake" respawn volume for
land vehicles.

## What you see on screen

**The game drives first.** There is no front door and no menu asking you to choose before
you know what you are choosing between: the page loads, a mountain level comes up, and you
are already in a car. That is true standalone and inside sloppyCAN — one boot path, one
first-paint cost. A link can ask for something specific (`?level=…&vehicle=…`), and
otherwise the game remembers where you were last time.

Everything else hangs off **Esc** (or the MENU button on a touchscreen), which opens a
pause overlay: RESUME, VEHICLE, LEVEL, CONTROLS, SETTINGS.

- **VEHICLE** is one screen with all three axes on it — the families down the left, that
  family's bodies as pictures in the middle, what it can tow underneath, and a single live
  3D preview on a turntable with the machine's specs (including what it speaks on the bus,
  read out of the contract). Machines this level will not spawn are still browsable and
  still preview; they just carry the reason. "No closed rail loop here" teaches you
  something about the level; a card that simply isn't there teaches nothing.
- **LEVEL** is a grid of screenshots with a description and a download weight on each —
  the city level is a 14 MB bake and you deserve to know that before you wait for it.
- **CONTROLS** is *generated*, never typed. One table (`ActionRegistry`) describes every
  bound key, and both this sheet and the touchscreen buttons are built from it, with the
  key names read live out of the input map. So a control cannot exist without being
  documented, or be documented without being reachable — which is exactly the drift that
  had left ten controls undocumented and six with no touch button before it existed.
  Controls the machine you are driving does not have are greyed with the reason rather
  than hidden.
- **SETTINGS** is currently one thing: how much instrument cluster you want (FULL,
  COMPACT, OFF, or AUTO — which quietly goes compact on a phone or when sloppyCAN is
  already showing you the numbers).

**It has to work at any size.** There is no fixed layout: one theme is rebuilt at a scale
derived from the window's short edge, and every screen sizes itself from that — card
grids reflow their column count, the tell-tale row wraps, the touchscreen button stack
wraps into another column rather than running off the bottom of a short window. (The
engine's own content scaling would have been simpler, but both of its modes resize the
*3D* render target too, and the web performance budget cannot pay for that.)

## Testing and CI

All the pure logic — drivetrain math, input arbitration, telemetry derivations, buoyancy,
terrain/road/scatter/bake math — is covered by gdUnit4 unit tests (~300 test functions).
The trick that makes this possible: anything with logic worth testing is written as a
static pure function, so tests don't need a running game.

Every push runs CI: import → tests → stale-bake check → two headless boot smokes (nothing
special is needed for this any more — the game boots straight into a level, so CI takes
exactly the path a player does) → web export. Pushes to `dev` auto-publish the dev channel
on GitHub Pages with cache-busted filenames; stable moves only when someone presses the
promote button (`docs/deploying.md`).
`tools/preflight.ps1` runs the same gates locally, and a pre-commit hook catches the most
common footguns (stale bakes, stale contract copy, editor-only type annotations that
would silently break the web build).

## House rules worth knowing (and why)

- **Physics is 60 Hz, forever.** The suspension tuning depends on the tick length;
  changing it means re-tuning every vehicle.
- **One contract file, everything generated.** Never hand-copy a signal list.
- **All input arbitration lives in InputRouter.** If you're writing an input rule
  anywhere else, stop.
- **Telemetry is read out of the simulation, never invented.**
- **Lamp state rides the input struct.** Turn signals blink because the simulator toggles
  the bit — there is deliberately no local blink timer (the simulator is the authority).
- **Baked geometry ships, authoring content doesn't.** An export plugin strips it.
- **Trimesh collision is the exception.** Ground is a heightmap shape, props get boxes or
  convex hulls.
- **No emoji in UI** — the web font has no emoji glyphs.
- **Loading a stranger's level file is code execution** (Godot scenes can embed scripts),
  so level sharing is out of scope.

Most of the sharp edges you'll hit are already written down in `CLAUDE.md`'s gotchas
section — read it before touching wheels, bakes, or the web export.

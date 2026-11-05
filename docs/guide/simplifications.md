# What the game keeps simple

<p class="lead">Every model leaves something out. This page gathers, in one place, what Carlito
approximates and what it does not model at all, so that nobody mistakes the game for more than
it is. Each idea page has its own short list; this is the whole picture.</p>

## How the game decides what to model

The game models what a vehicle's own signals would show. Wherever a number reaches sloppyCAN, it
comes from the physics that produced the motion, or from a simple model that is labelled as a
model. Nothing is invented to look right. Where the game takes a short cut, its code says so, and
says what undoing it would cost.
<!-- CLAUDE.md standing rule 3; "A COMPROMISE states what is true and what undoing it costs" -->

The short cuts fall into three kinds:

- **Simplified**: modelled, but more simply than in the real world.
- **Ideal**: modelled as a perfect version of the real thing.
- **Not modelled**: left out.

## The vehicles themselves

- **Simplified: the bodies' size.** The road vehicles are built from small, toy-proportioned
  models. Their wheelbases are short for their weight, about 1.6 m where a real saloon's is
  nearer 2.7 m, so they pitch more under braking and turn in tighter circles than full-size cars
  would. Their weights, engines, brakes and tyres are real-sized.
  <!-- docs/handling.md Pitch: "The Kenney wheelbases are toy-scale (1.58 m on suv, ~2.8 m on a real one) under real masses and COM heights"; steering.md -->
- **Simplified: the shapes.** A body's resistance to pitching and leaning comes from simple box
  shapes; only its resistance to turning is taken from measurements of real vehicles.
  <!-- docs/handling.md Inertia -->
- **Not modelled: damage.** Nothing dents, breaks, wears out or overheats.

## Tyres and the ground

- **Simplified: one grip curve.** Every tyre in the game has the same shape of grip curve. A tyre
  class, a surface and the load change only how high its peak is.
- **Simplified: soil.** Soft ground's drag is the same for every tyre, wide or narrow, and a wheel
  never sinks in or gets bogged down.
- **Not modelled: tyre wear, temperature and pressure**, and a tyre's spring up and down on road
  vehicles.
- **Not modelled: weather.** Wet roads, snow and ice are painted ground in fixed places. No rain
  falls and nothing dries.
<!-- tyres.md, surfaces.md; Surface: drag is tyre-blind (a COMPROMISE) -->

## Steering and suspension

- **Simplified: Ackermann.** Every wheeled vehicle uses full Ackermann steering.
- **Not modelled: steering feel.** No force comes back through the steering.
- **Not modelled: articulated and rear-wheel steering.**
- **Not modelled: unsprung mass and roll camber.** Wheels have no weight of their own that bounces,
  and tyres do not tilt as the body leans, which is one reason the cars understeer a little less
  than real ones.
<!-- steering.md, suspension.md, weight-transfer.md; docs/handling.md Balance "Stated shortfall: linear K" -->

## Engine, gearbox and driveline

- **Not modelled: stalling, a starter motor, turbo lag.** The engine is running whenever the key
  is at Ignition.
- **Simplified: the fuel tank.** The burn is real; the tank is scaled down so its gauge moves in a
  session, and an empty tank does not stop the engine (open question 9).
- **Not modelled: a clutch pedal.** The game works every clutch, even with manual gears.
- **Not modelled: cruise control** on any road vehicle; only the tractor's hand throttle holds a
  speed for you, through its governor.
- **Not modelled: manual gears without sloppyCAN.** The keyboard always drives an automatic.
- **Simplified: the differentials.** Each has one fixed bias ratio; none is electronically
  controlled.
<!-- engine.md, aux.md, coupling.md, gearbox.md, differentials.md -->

## Brakes and driver aids

- **Ideal: ABS and traction control.** They know the true road speed and hold each wheel exactly
  at the grip peak, with none of the pulsing of real systems.
- **Simplified: brake heat.** Each brake is one lump of metal with one temperature.
- **Simplified: truck air.** Two tanks that fill and empty; no pipes, valves or leaks.
- **Simplified: the train's brake pipe.** A displayed model; the train's brakes act at once.
<!-- driver-aids.md, brakes.md, rail.md -->

## Towing and farm work

- **Simplified: loads that move.** The tanker's liquid and the tipper's load move a centre of mass;
  there is no liquid or loose load in the simulation.
- **Simplified: a carried implement's weight.** It shifts the tractor's centre of mass but does
  not add its own resistance to turning.
- **Not modelled: draft control, crops and yield, a spreader that empties, front weights.**
- **Not modelled: coupling by hand**: no landing legs, air lines or cables.
<!-- towing.md, implements.md; docs/handling.md Inertia: implement COMPROMISE at TractorVehicle._apply_implement_mass; CLAUDE.md non-goals: crop growth, yield or farm economy -->

## Water and air

- **Simplified: buoyancy.** Four float points sized so the hull rests at its depth, not the
  volume of the hull under the water.
- **Simplified: water drag.** It grows in proportion to the speed rather than with its square,
  and a speedboat does not rise onto the plane.
- **Not modelled: real waves.** The sea is flat; the waves are drawn only.
- **Simplified: the air.** It has one density everywhere, with no change for height or weather.
- **Simplified: the wind.** The same everywhere on a level, with no shelter behind hills or
  buildings and no change with height.
- **Simplified: the plane's lift**, worked out from its speed over the ground rather than through
  the air (open question 8). No inverted flight and no spins.
- **Not modelled: sideways flight from the keys** on the drone.
<!-- floating.md, conditions.md, plane-flight.md, drone-flight.md; CLAUDE.md non-goals: real wave physics -->

## Rails

- **Simplified: the train.** Five point masses along the track, joined by springs.
- **Not modelled: wheel slip on the rails, points, signals, timetables or other trains.**
<!-- rail.md -->

## Instruments

- **Labelled models**: fuel, coolant, battery, engine load, air pressure, the boat's oil and tanks,
  the train's current and voltage, the drone's pack.
- **Ideal: position.** The GPS position is exact, except on the drone, whose receiver needs open
  sky.
- **Simplified: accelerations.** They read only the change in motion, with no gravity.
<!-- aux.md, position.md -->

## Not in the game at all

Some things are outside what Carlito sets out to be: multiplayer, an in-game level editor, a
character who walks around, crop growth or a farm economy, real wave physics, traffic, lane
markings, road junctions, and sharing levels made by others.
<!-- CLAUDE.md Non-goals -->

## Related

- [The open questions](open_questions.md): places where the code and its notes disagree, or where
  something may be a mistake rather than a choice.
- [Glossary](glossary.md): every term on this page.

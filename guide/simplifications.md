[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# What the simulator keeps simple

<p class="lead">This page gathers in one place what the simulator approximates and what it does
not model at all.</p>

## How the simulator decides what to model

The simulator models what a vehicle's own signals would show. Every number that reaches sloppyCAN
comes either from the physics that produced the motion, or from a simple model that is labelled as
a model. Nothing is invented just to look right: the rpm is the engine's real speed in the
simulation, and the slip is the tyres' real slip. Where the simulator takes a short cut, its code
says so at that spot, and says what undoing it would cost.
<!-- CLAUDE.md standing rule 3; "A COMPROMISE states what is true and its undo cost" -->

The short cuts fall into three kinds:

- **Simplified**: modelled, but more simply than in the real world.
- **Ideal**: modelled as a perfect version of the real thing, with none of its faults.
- **Not modelled**: left out.

Each teaching page lists its own short cuts in its Simplification list, under "What Carlito
simulates". This page gathers the main ones.

## The vehicles themselves

- **Simplified: the bodies' size.** The road vehicles are built from small, toy-proportioned
  models. Their wheelbases (the distance between the front and rear axles) are short for their
  weight: about 1.6 m on the saloon, where a real family saloon has nearer 2.7 m. A
  short wheelbase gives the weight less leverage against pitching, so these bodies pitch more under
  braking than full-size cars would, and turn in tighter circles. Their weights, engines, brakes
  and tyres are full-sized.
  <!-- sedan_spec.tres wheel_positions: axles at z -0.822 and +0.762, 1.58 m; docs/handling.md Pitch; Wikipedia, "Chevrolet Malibu" (the sedan's reference car), eighth generation: wheelbase "107.8 in (2,738 mm)" -->
- **Simplified: the shapes.** A body's resistance to pitching and leaning comes from simple box
  shapes. Only its resistance to turning (as seen from above) is taken from measurements of real
  vehicles.
  <!-- docs/handling.md Inertia -->
- **Not modelled: damage.** Nothing dents, breaks or wears out, and no engine overheats.

## Tyres and the ground

- **Simplified: one grip curve.** Every tyre in the simulation has the same shape of grip curve.
  A tyre class, a surface and the load change only how high its peak is, not where it sits.
- **Simplified: soil.** Soft ground holds back a wide tyre as much as a narrow one, and a wheel
  never sinks in or gets stuck.
- **Not modelled: tyre wear, temperature and pressure**, and on the road vehicles the give of the
  tyre itself, which acts as a small extra spring under the real suspension.
- **Not modelled: weather.** Wet roads, snow and ice are painted ground in fixed places. No rain
  falls and nothing dries.
<!-- tyres.md, surfaces.md; Surface: drag is tyre-blind (a COMPROMISE) -->

## Steering and suspension

- **Simplified: Ackermann.** Every wheeled vehicle uses full Ackermann steering, so the inner
  front wheel always turns exactly as far as the turn needs.
- **Not modelled: steering feel.** No force comes back through the steering, so the steering does
  not go light when the front tyres reach their limit.
- **Not modelled: articulated and rear-wheel steering.** Every vehicle steers with its front
  wheels only.
- **Not modelled: unsprung mass and roll camber.** The wheels have no weight of their own that
  bounces, and the tyres do not tilt as the body leans. That tilt is one reason a real car needs a
  little more steering as it speeds up through a bend, so the simulated cars need much less of it
  than real ones.
<!-- steering.md, suspension.md, weight-transfer.md; docs/handling.md Balance "Stated shortfall: linear K" -->

## Engine, gearbox and driveline

- **Not modelled: stalling, a starter motor, turbo lag.** The engine is running whenever the key
  is at Ignition, and its full torque is there at once, with no wait for a turbocharger.
- **Simplified: the fuel tank.** The burn is real, but the tank is scaled down so that its gauge
  moves within a session, and an empty tank does not stop the engine.
- **Not modelled: a clutch pedal.** The simulator works every clutch, even when the driver shifts
  by hand.
- **Simplified: the gearbox's insides.** Each gearbox is a list of ratios and a way of handing the
  drive from one ratio to the next. No tooth, collar, planet gear or belt is simulated.
- **Not modelled: cruise control** on the road vehicles. Only the tractor's hand throttle holds
  something steady by itself, and what it holds is an engine speed, through the governor.
- **Simplified: the differentials.** Each has one fixed bias ratio, and none is controlled by
  electronics.
<!-- engine.md, auxiliary.md, coupling.md, gearbox.md, gearbox-kinds.md, differentials.md -->

## Brakes and driver aids

- **Ideal: ABS and traction control.** They know the true road speed and hold each wheel exactly
  at the grip curve's peak, without the pulsing of real systems, which can only estimate the
  road speed from the wheels.
- **Simplified: brake heat.** Each brake is one lump of metal with one temperature.
- **Simplified: truck air.** Two tanks that fill and empty, with no pipes, valves or leaks.
<!-- driver-aids.md, brakes.md -->

## Towing and farm work

- **Simplified: loads that move.** The tanker's liquid and the tipper's load move a centre of
  mass. There is no liquid or loose load in the simulation.
- **Simplified: a carried implement's weight.** It shifts the tractor's centre of mass but does
  not add its own resistance to turning.
- **Not modelled: draft control, crops and yield, a spreader that empties, front weights.**
- **Not modelled: coupling by hand.** There are no landing legs, air lines or cables to connect.
<!-- towing.md, implements.md; docs/handling.md Inertia: implement COMPROMISE at TractorVehicle._apply_implement_mass; CLAUDE.md non-goals: crop growth, yield or farm economy -->

## Air

- **Simplified: the air.** It has one density everywhere, with no change for height or weather.
- **Simplified: the wind.** It blows the same everywhere on a level, with no shelter behind hills
  or buildings and no change with height.
<!-- resistance.md, conditions.md; VehicleMath.AIR_DENSITY; WindField: one vector per level time -->

## Instruments

- **Labelled models**: fuel, coolant, battery, engine load and air pressure.
- **Ideal: position.** The GPS position, the heading and the odometer are exact.
- **Simplified: accelerations.** They read only the change in motion, with no gravity, so a
  parked vehicle reads zero instead of 1 g.
<!-- auxiliary.md, position.md -->

## Not in the simulator at all

Some things are outside what Carlito sets out to be: multiplayer, a built-in level editor, a
character who walks around, crop growth or a farm economy, traffic, lane markings, road
junctions, and sharing levels made by others.
<!-- CLAUDE.md Non-goals -->

## Related

- [Open questions and ideas](open_questions.md): places where the code and its notes disagree, or
  where something may be a mistake rather than a choice.
- [How the simulation works](simulation.md): every parameter behind these models.
- [Glossary](glossary.md): every term on this page.

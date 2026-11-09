# The train

<p class="lead">The train is a high-speed-style electric locomotive and four wagons, about
186 tonnes in all, running on the closed loop of Level 5. It has no steering and no gearbox:
the rails choose the way, and a reverser chooses the direction.</p>

## What the train has

- An electric locomotive with constant pull, then constant power, and a railway resistance
  formula ([Trains](rail.md#pulling-tractive-effort)).
- Springy couplers with slack between the cars ([Trains](rail.md#couplers-and-slack)).
- A brake on every car, a parking brake, and a labelled brake pipe model
  ([Trains](rail.md#brakes)).
- A pantograph on an overhead wire, with motor current and line voltage models
  ([Trains](rail.md#power-from-the-wires)).
- A reverser on the gear byte, and doors that open only at a standstill
  ([Trains](rail.md#the-reverser-and-the-doors)).
- [Position and distance](position.md), and a battery voltage ([aux models](auxiliary.md)).
<!-- train.gd loco_mass 50000 + 4 x wagon_mass 34000; vehicle_catalog.gd "bullet" -->

The train ignores the wind, and none of the tyre, suspension, engine or gearbox pages apply.

## Where to drive it

Only **Level 5 - Railway**, the one level with a closed loop of track.
<!-- level_5_info allowed_vehicles includes train; train.gd needs a closed rail ("an open rail is never accepted") -->

## What you see in sloppyCAN

The train's own signals are `pantograph`, `doors`, `motor_current`, `catenary_volts`,
`brake_pipe`, `grade` and `coupler_force`. [Trains](rail.md#what-you-see-in-sloppycan) lists them.

## Related

- [Trains](rail.md): every idea on this page.
- [Glossary](glossary.md): every term on this page.

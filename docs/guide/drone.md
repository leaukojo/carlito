# The drones

<p class="lead">The drone family is one quadcopter of 5 kg in two bodies: the plain `drone` and the
more detailed `drone-mk2`, which adds a working cargo hook, a camera gimbal, lights and status
LEDs. They fly the same. Their signals follow DroneCAN, a standard for drone electronics.</p>

## The family

| Vehicle | What it adds |
| --- | --- |
| `drone-mk2` | The family's default: per-motor props, a camera gimbal, a cargo hook, a spotlight, a rangefinder beam and status LEDs, all drawn |
| `drone` | A plain build with the same flight model |
<!-- vehicle_catalog.gd: "drone-mk2" first, "same flight numbers as drone"; docs/flight.md: drone-mk2 draws per-motor props, gimbal, hook jaws, spotlight, rangefinder beam, status LEDs; drone_spec.tres mass 5 -->

## What a drone has

- Four rotors and a mixer, arming and its pre-arm checks, five flight modes, a geofence and
  failsafes ([Drone flight](drone-flight.md)).
- A battery pack with its own model: charge, voltage sag and temperature
  ([Drone flight](drone-flight.md#the-battery)).
- A GPS receiver that needs open sky, a rangefinder and a barometer
  ([Drone flight](drone-flight.md#satellites-and-sensors)).
- A small network of nodes that can be failed one by one
  ([Drone flight](drone-flight.md#the-drones-network)).
- The wind it flies through ([Wind, current and conditions](conditions.md)).

A drone has no wheels and no engine, so the tyre, brake, engine and gearbox pages do not apply.

## Where to fly it

The drone is allowed on Levels 1, 2, 3, 5 and 6, and on **Flatland**. **Level 6 - Skyport**
is its bench: landing pads at height, a slalom of masts and a canyon that hides the satellites.
<!-- *_info.tres allowed_vehicles; level_registry level_6 desc -->

## What you see in sloppyCAN

The drone publishes more signals than any other vehicle: each motor controller's speed, current,
temperature and faults, the battery, the satellites and fix, three heights, the arming state and
its reasons, the flight mode and failsafe, the node roster, the hook and the gimbal.
[Drone flight](drone-flight.md#what-you-see-in-sloppycan) lists the main ones.

## Related

- [Drone flight](drone-flight.md): every idea on this page.
- [Glossary](glossary.md): every term on this page.

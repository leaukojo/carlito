# The boats

<p class="lead">The boat family is two speedboats and a sailing dinghy. They float on four
float points, push with a propeller and steer with a rudder, all measured against the water they
sit in. Their instruments speak NMEA 2000, the marine electronics standard.</p>

## The family

| Vehicle | What it is | Weight, about | Top speed, about |
| --- | --- | --- | --- |
| `boat-speed-a` | Speedboat | 600 kg | 50 km/h |
| `boat-speed-j` | Larger speedboat | 1.4 t | 60 km/h |
| `boat-sail-a` | Sailing dinghy with a small motor | 500 kg | 12 km/h under motor |
<!-- watercraft/*_spec.tres mass; thrust_force / drag_long: 5200/360, 11000/660, 500/150 = 3.3 m/s (docs/boat.md "~5 hp outboard, 3.3 m/s top speed") -->

## What a boat has

- [Buoyancy, propeller, hull drag, rudder, trim and windage](floating.md).
- The sailing dinghy's [sail and sheet](floating.md#sailing).
- An [autopilot](floating.md#autopilot) that holds a heading, and a
  [depth sounder](floating.md#depth-and-running-aground).
- The tide on Level 6 and the wind on Level 6 and Open Sea
  ([Wind, current and conditions](conditions.md)).
- A simpler [engine](engine.md#the-simpler-engine-on-the-boat-and-the-plane) whose speed follows the
  throttle, driving forwards or in reverse.
- The [fuel, coolant, battery and engine-room models](auxiliary.md#the-boats-engine-room).

A boat has no wheels, so none of the tyre, suspension, brake or driver-aid pages apply. It slows
by easing off or going into reverse.

## Where to drive them

Boats are allowed on Levels 1 to 6 and on **Open Sea**, which is nothing but water under a
steady wind. **Level 6 - Skyport** has the tide, a buoyed channel and a sandbar where the depth
changes.
<!-- *_info.tres allowed_vehicles (not Flatland, Car Arena); docs/boat.md The level-6 playground -->

## What you see in sloppyCAN

The boats publish the most instrument signals of any vehicle: speed through the water and over
the ground, course over the ground, depth, apparent and true wind, the tide's set and drift, the
rudder and trim, the autopilot's mode and heading, oil pressure, the tanks and, on the dinghy,
the boom's angle. [Floating and boats](floating.md#what-you-see-in-sloppycan) lists them.

## Related

- [Floating and boats](floating.md): every idea on this page.
- [Glossary](glossary.md): every term on this page.

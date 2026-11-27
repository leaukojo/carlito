[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# Fuel, coolant, battery and air

<p class="lead">This page explains how fuel use follows engine load, and how the cooling, the
battery and a truck's air keep a vehicle running.</p>

<div class="badges"><span class="label">Which vehicles have this</span>
<span class="badge yes" title="Every car and van: fuel, coolant and battery">Car</span>
<span class="badge yes" title="Every truck: fuel, coolant, battery, engine load, an hour meter, and two air tanks for the brakes">Truck</span>
<span class="badge yes" title="Both tractors: fuel, coolant, battery, engine load and an hour meter">Tractor</span>
</div>

The engine and the wheels are not the whole vehicle. The engine burns fuel, which must be carried
and measured. It makes far more heat than work, and that heat must be carried away. The lamps and
the computers need electricity, and a truck's brakes need compressed air. Each of these systems has
its own reading on the dashboard. What does each reading tell the driver, and why does it move?

<figure>
<img src="img/dashboard-fuel-temperature-gauges.jpg" alt="A car's instrument panel with a large speedometer on the left, and on the right a fuel gauge running from E to F and a coolant temperature gauge running from C to H">
<figcaption>The fuel (left) and coolant temperature (right) gauges. Photo: OKJaguar, CC BY-SA 4.0, <a href="https://commons.wikimedia.org/wiki/File:Honda_Pilot_dashboard.jpg">Wikimedia Commons</a>.</figcaption>
</figure>

## Fuel

### How much is burned

![A bar for the energy in one litre of petrol burnt by a car. About 70 per cent becomes heat in the engine, which leaves through the exhaust and the radiator. About 10 per cent goes to the gears, pumps and fans. About 20 per cent reaches the wheels and moves the car.](img/fuel-energy-split.svg "Where a litre of petrol's energy goes, in mixed driving. Source: fueleconomy.gov.")

Burning fuel releases a known amount of energy for each litre, but an engine turns only part of it
into work. Most of it becomes heat, which leaves through the exhaust and the cooling system.

So how much fuel is burned depends on how much work the engine is doing, not on how far the
pedal is pressed. In words:

fuel power = (power to the wheels + power lost inside the engine) ÷ efficiency

The power lost inside the engine is its own friction: the pistons rubbing in their cylinders, the
pumps, and the air the engine must suck in and push out. The efficiency is the share of the fuel's
energy that the burning turns into push on the pistons, a little over two fifths for a petrol
engine (for example).
<!-- VehicleTelemetry FUEL_INDICATED_EFFICIENCY petrol 0.41 -->

For example, a car on a flat motorway at about 100 km/h needs about 12 kilowatts at its wheels
(about 14 at the engine, because the gears lose some), and its engine loses about 6 more to
friction. That is 20 kilowatts, and at an efficiency of 0.41, the fuel must supply 20 ÷ 0.41 =
about 49 kilowatts, which is 49,000 joules every second. A litre of petrol holds about 31 million
joules, so in an hour (3,600 seconds) the car burns 49,000 × 3,600 ÷ 31,000,000 = about 5.7 litres.
In that hour it covers 100 km, so it uses 5.7 litres per 100 km.
<!-- the sedan in sixth (widgets/fuel-burn.js): rolling 135 N + air 307 N at 27.8 m/s; friction 23 N·m at 2660 rpm; petrol 41.05 MJ/kg x 0.757 kg/L -->

This explains several things a driver notices:

- **Idling burns a little**, just enough to overcome the engine's own friction and keep it turning.
- **Coasting in gear burns nothing.** When the driver lifts off the pedal with the car in gear,
  the wheels turn the engine, so the engine computer cuts the fuel completely. Coasting in neutral
  burns more, because the engine then has to idle on its own. So, against a common belief,
  shifting to neutral to coast down a hill does not save fuel.
- **A high gear burns less than a low one at the same speed.** The wheels need the same power,
  but in the high gear the engine turns more slowly, so it loses less to friction.
- **Fast driving burns more fuel for every kilometre.** The air pushes back harder and harder as
  the speed rises (four times as hard at twice the speed), so the engine must do more work for
  each kilometre (see [Air and rolling resistance](resistance.md)). Very slow driving costs more too,
  because the engine's friction goes on for every hour the trip lasts. The cheapest speed for most
  cars is in between, usually reported at between about 55 and 80 km/h.
  <!-- Wikipedia, "Fuel economy-maximizing behaviors": "Most modern petrol vehicles cut off the fuel supply completely when coasting (over-running) in gear"; in neutral "there will still be some fuel consumption due to the engine needing to maintain idle engine speed"; the optimum "is usually reported to be between 35 and 50 mph (56 and 80 km/h)" -->
- **A hill or a heavy load burns more.** Climbing lifts the whole vehicle, and lifting takes work.
  Going down, the slope does part of the work, and the fuel use falls, down to nothing on a steep
  enough hill.

<div class="widget" data-widget="fuel-burn"></div>

<div class="widget-limits" hidden>

The car is the simulator's `sedan`, driving at a steady speed with no wind: no speeding up or
slowing down, and on a steep enough descent the brakes take whatever the engine's friction does
not. The widget picks the highest gear that keeps the engine above 1,200 rpm (the steps in the
curve at low speed are its gear changes); the simulator's own gearbox shifts by its pedal and
speed rules. The heat share stays at 59 % because
the simulator's efficiency does not change with the engine's speed or load; a real engine's does.
At a standstill the car idles in neutral.
<!-- widgets/fuel-burn.js: sedan_spec.tres, VehicleTelemetry.fuel_rate_lph -->

</div>

### The tank and the gauge

A sender in the tank measures how much fuel is left: usually a float on an arm, which rises and
falls with the fuel and moves a contact along a resistor, so the electrical resistance changes
with the level. The gauge reads it slowly, so that the fuel sloshing in a corner does not make the
needle swing. A warning lamp comes on when the level is low.

## Coolant

<!-- figure: the cooling circuit: the pump, the engine's water jacket, the thermostat, the radiator and its fan -->

An engine turns most of its fuel's energy into heat. Part of that heat leaves through the exhaust;
the coolant carries much of the rest out of the engine to the radiator, where the air flowing
through takes it away.

A cold engine warms up to its working temperature (about 90 °C), and then stays there. A
[thermostat](glossary.md#thermostat) (a valve with a pellet of wax that melts and expands when hot)
keeps the coolant inside the engine until it is warm, and then opens the way to the radiator.
When the car moves slowly and little air flows through the radiator, a fan pulls air through it.
Why keep the engine at one temperature? A cold engine wears faster and wastes fuel, and one that
is too hot can be damaged. The coolant gets warmer when the engine works hard, and a warning comes
on if it gets too hot.
<!-- Wikipedia, "Radiator (engine cooling)": "The engine temperature on modern cars is primarily controlled by a wax-pellet type of thermostat"; "Electric fans are controlled by a thermostatic switch or the engine control unit" -->

You might wonder how coolant can sit above 100 °C without boiling. Two things raise its boiling
point. The cap on the cooling system keeps the coolant under pressure, and a liquid under pressure
boils at a higher temperature. And the coolant is not plain water: it is mixed with antifreeze,
which raises its boiling point and lowers the point at which it freezes, so that it neither boils
in summer nor freezes in winter.
<!-- Wikipedia, "Radiator (engine cooling)": "the coolant is kept at higher-than-atmospheric pressure to increase its boiling point"; Wikipedia, "Engine coolant": "An antifreeze is an additive which lowers the freezing point of a water-based liquid", "Common antifreezes also increase the boiling point of the liquid" -->

The heat comes from burning fuel, so the coolant follows how much fuel the engine burns, not how
far the pedal is pressed. For example, a truck held back by its speed limiter, with the pedal
fully down, burns little fuel and stays cool.

## Battery and alternator

With the engine off, a car's battery rests at about 12.6 volts. With the engine running, the
[alternator](glossary.md#alternator) (a small generator turned by the engine through a belt)
charges it at about 14 volts, and a regulator holds that voltage whatever the engine's speed.
<!-- VehicleTelemetry BATTERY_RESTING 12.6, BATTERY_CHARGING 14.2 -->

Why is the charging voltage higher than the resting one? Current flows only from a higher voltage
to a lower one, as water flows only downhill. To push current into the battery, the alternator must
hold its side above the battery's own voltage.

While the engine runs, the alternator powers the whole vehicle, and the battery only covers what
the alternator cannot give. So, against a common belief, a car with its engine running does not
live on its battery. The battery's main jobs are to start the engine and to power things while the
engine is off. If the consumers ask for more current than the alternator can give (at idle, with
everything switched on, for example), the battery makes up the difference and the voltage sags a
little.

Which consumers count? Electrical power is the voltage times the current, so the current a lamp
draws is its power divided by the voltage. For example, a 55-watt halogen headlamp at 14 volts
draws 55 ÷ 14 = about 4 amperes, while a 5-watt tail lamp draws about 0.4. The headlamps, the
heater fans and the rear window heater are the big consumers, and the small lamps hardly count.
<!-- lamp_set.gd BULB_LOW_W 55, BULB_TAIL_W 5 (the UN ECE R37 ratings) -->

## A truck's air

A truck brakes with compressed air, kept in tanks. There are usually two circuits, each with its
own tank, so that a leak in one leaves the other working. A compressor driven by the engine fills
them, and each press of the brake pedal lets some air out into the brakes. Holding the pedal down
costs nothing more, but pumping it uses air faster than the compressor puts it back. Coupling a
trailer also takes air, to fill the trailer's own tank.

A warning comes on when the pressure is low. If it keeps falling, the
[spring brakes](brakes.md#air-and-spring-brakes) apply on their own and stop the truck, because
it is the air that holds them off.

## Engine load

Trucks and tractors report their [engine load](glossary.md#engine-load): the torque the engine is
giving, as a percentage of the most it can give at any speed. In words:

engine load = torque the engine gives ÷ the largest torque on its torque curve

For example, an engine whose best is 2,000 newton-metres, giving 500, works at 500 ÷ 2,000 = 25 %
load.

A plough, the [PTO](glossary.md#pto) driving a machine, a hill or a headwind all raise it, because
each one asks the engine for more torque to keep the vehicle going. It is never zero while the
engine runs, because even at idle the engine must give some torque to overcome its own friction.

Engine load is not the position of the pedal. A tractor's governor, for example, sets the fuel to
hold an engine speed: on the flat with nothing to pull, the pedal can be fully down while the load
stays low, and when the plough bites, the load climbs with the pedal unchanged. Fleet managers and
farmers read it to see how hard a machine has worked, and whether it is the right size for the job.

## Warning lamps

Warning lamps tell the driver about faults that the gauges do not show. Examples are the
check-engine lamp, the battery lamp (which means the alternator is not charging, not that the
battery is flat), and the red (stop) and amber (warning) lamps of trucks. The vehicle's electronic
units switch them on, often by messages on the [CAN bus](glossary.md#can-bus). In general, red
means to stop as soon as it is safe, and amber means to have the fault looked at soon.

## What Carlito simulates

The parameters the simulator uses for this, and where each is set, are listed in
[How the simulation works](simulation.md#fuel-coolant-battery-and-air):

- **Simulation-wide**:
  - [Engine efficiency](simulation.md#engine-efficiency) (`FUEL_INDICATED_EFFICIENCY`)
  - [Tank size](simulation.md#tank-size) (`FUEL_TANK_FULL_LOAD_S`)
  - [Coolant](simulation.md#coolant) (`COOLANT_AMBIENT`, `COOLANT_OPERATING`, `COOLANT_HOT`,
    `COOLANT_RATE`)
  - [Battery](simulation.md#battery) (`BATTERY_RESTING`, `BATTERY_CHARGING`,
    `BATTERY_LAMP_DROOP`)
  - [Air](simulation.md#air) (`AIR_PRESS_PRIMARY`, `AIR_PRESS_SECONDARY`)
- **Per vehicle**:
  - [Fuel](simulation.md#fuel) (`fuel_type`)

<details><summary>Simplification list</summary>

- **Simple models.** The vehicle's movement comes from its physics, but these readings come from
  short rules that behave sensibly, labelled as models. The flow of the coolant and the chemistry
  of the battery are not simulated. The fuel burn is the exception: it is read off the torque and
  speed the engine actually has.
  <!-- CLAUDE.md standing rule 3; VehicleTelemetry header; fuel_rate_lph -->
- **One efficiency per fuel.** The efficiency is the same at every engine speed and load, one for
  petrol and one for diesel.
- **A small tank.** The burn is realistic, but each tank is scaled to last a little over eight
  minutes at full power, so that the gauge visibly falls. An empty tank leaves the engine running.
  <!-- VehicleTelemetry FUEL_TANK_FULL_LOAD_S 500 s; base_vehicle.gd "an empty tank does not stop the engine" -->
- **No thermostat, radiator or fan.** The coolant moves towards a target of 90 °C at no load and
  about 108 °C at full fuel, by 2 °C a second, so it warms up in about half a minute and never
  reaches its 110 °C warning by itself. Nothing overheats or breaks.
  <!-- VehicleTelemetry COOLANT_AMBIENT 20, COOLANT_OPERATING 90, COOLANT_HOT 108; BaseVehicle COOLANT_RATE 2; contract coolant warn 110 -->
- **A battery that never runs down.** The voltage sags in proportion to the lamps lit, weighted by
  their bulbs' power, up to 0.6 volts with every lamp on, and it never falls to its 11.5-volt
  warning. The starter, the heater fans and the other consumers are not modelled.
  <!-- VehicleTelemetry.battery_volts, BATTERY_LAMP_DROOP 0.6; LampSet.load_share; contract battery warn 11.5 -->
- **No air leaks** on the trucks, apart from what the brakes and a trailer being coupled use.
- **No fault detection.** The simulation never lights a fault lamp by itself: sloppyCAN sets them.
  <!-- contract checkEngine, battery (in), red_stop, amber_warn: "Mirrored VERBATIM ... sloppyCAN is the sole authority" -->

</details>

## What you see in sloppyCAN

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `fuel` | out | % | The tank level, on a scaled-down tank. Warns below 15 %. |
| `fuel_rate` | out | L/h | The fuel burned, read off the engine's torque and speed. |
| `coolant` | out | °C | The coolant model. Warns at 110 °C. |
| `battery` | out | V | The battery's voltage. Warns below 11.5 V. |
| `engine_load` | out | % | The torque given, over the most the engine can give (Truck and tractor). |
| `air_primary`, `air_secondary` | out | bar | The two air tanks. Warn below 5 bar (Truck). |
| `engine_hours` | out | h | The engine's running time (Truck and tractor). |
| `checkEngine`, `battery` | in | flag | The check-engine and battery warning lamps, set by sloppyCAN. |
| `red_stop`, `amber_warn` | in | flag | The fault lamps, set by sloppyCAN (Truck). |
<!-- contract/carlito_contract.json: fuel (warn 15), fuel_rate, coolant (warn 110), battery (out, warn 11.5; and in), engine_load, air_primary, air_secondary (warn 5), engine_hours, checkEngine, red_stop, amber_warn -->

## Related

- [Glossary](glossary.md): every term on this page.
- [The engine](engine.md): the torque curve and the engine's friction.
- [Air and rolling resistance](resistance.md): what the engine works against on the road.
- [Brakes](brakes.md): what the truck's air is for.
- [Implements and the PTO](implements.md): the work that raises a tractor's engine load.

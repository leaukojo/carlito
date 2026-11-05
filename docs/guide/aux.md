# Fuel, coolant, battery and air

<p class="lead">A vehicle's dashboard shows more than speed: how much fuel is left, how hot the
engine is, the battery's voltage, a truck's air pressure. The game works these out with simple
models, and it says so: each one is a labelled model, not a measurement of a simulated system.</p>

<div class="badges"><span class="label">Which vehicles have this</span>
<span class="badge yes" title="Fuel, coolant and battery">Car</span>
<span class="badge yes" title="Fuel, coolant, battery and the two air tanks">Truck</span>
<span class="badge yes" title="Fuel, coolant, battery and an hour meter">Tractor</span>
<span class="badge yes" title="Fuel, coolant and battery, from a simpler throttle model">Plane</span>
<span class="badge yes" title="Fuel, coolant, battery, oil pressure and three tanks">Boat</span>
<span class="badge some" title="Its battery pack has its own model, on the drone page">Drone</span>
<span class="badge some" title="A battery voltage; its power comes from the overhead wire">Train</span>
</div>

## Why "labelled models"

Everything about how a vehicle moves is read straight out of the physics that moved it. The
auxiliary systems are different. The game does not simulate the coolant flowing through a
radiator, or the chemistry of a battery. Instead each one is a short rule that behaves sensibly,
and every signal it feeds is marked in the signal contract as a model. That way a reader always
knows which numbers are measured and which are modelled.
<!-- CLAUDE.md standing rule 3: "Aux systems (fuel/coolant/battery, engine_load, trim) are simple honest models, labelled"; VehicleTelemetry header -->

## Fuel

### How much is burned

On the cars, trucks and tractors, the fuel burned comes from the engine itself. The game knows
how much extra torque the fuel adds to the engine at its current speed, and so how much power.
Fuel holds a known amount of energy per litre, and an engine turns only part of it into work, a
little over two fifths. From those, the game works out the burn in litres per hour.
<!-- VehicleTelemetry.fuel_rate_lph; FUEL_INDICATED_EFFICIENCY petrol 0.41, diesel 0.45; FUEL_HEATING_MJ_KG, FUEL_DENSITY_KG_L -->

That simple rule gives realistic results by itself:

- Idling burns a little, the fuel needed to beat the engine's own friction: about a third of a
  litre an hour on the `sedan`, about one and a half on the `semi`.
- A fuel cut, as when coasting in gear, burns nothing.
- Driving gently in a high gear burns much less than in a low one at the same speed: the
  `sedan` at one cruising speed burns about half as much in sixth as in third.
<!-- docs/drivetrain.md Fuel: "the sedan idles at 0.34 L/h ... the semi at 1.62 L/h"; "the sedan held in D6 burns about half what it does in D3" -->

The boat and the plane use a simpler rule, because their engines carry no torque law: a small
idle burn plus an extra burn in proportion to the throttle.
<!-- VehicleTelemetry FUEL_IDLE_BURN, FUEL_LOAD_BURN (the rigid crank); BoatTelemetry.fuel_rate_model FUEL_RATE_IDLE 1.5 L/h, FUEL_RATE_LOAD 8.5 L/h -->

### The tank

The burn is realistic, but the tank is not. A real car's tank lasts hours, so a fuel gauge would
never move in a session. The game scales each tank so that it lasts a little over eight minutes
at full power, and the gauge visibly falls. The low-fuel warning is at 15 %. An empty tank does
not stop the engine.
<!-- VehicleTelemetry FUEL_TANK_FULL_LOAD_S 500 s ("COMPROMISE: the tank is a game scale"); contract fuel warn 15; see open_questions.md 9 -->

## Coolant

An engine turns most of its fuel's energy into heat, and the coolant carries it away to the
radiator. In the game the coolant starts cold, at 20 °C. With the engine running it warms
towards its working temperature, about 90 °C, and higher the harder the engine works, up to about
108 °C at full load. It changes gradually, a couple of degrees a second, and cools back to 20 °C
with the engine off. The warning is at 110 °C, which the model on its own never quite reaches.
<!-- VehicleTelemetry COOLANT_AMBIENT 20, COOLANT_OPERATING 90, COOLANT_HOT 108; BaseVehicle COOLANT_RATE 2 °C/s; contract coolant warn 110 -->

On the cars, trucks and tractors, the load that heats the coolant is the fuel's energy, not the
pedal: a governed truck holding its speed with the pedal down, but little fuel flowing, stays
cool.
<!-- VehicleTelemetry.coolant_target: "the heat the cooling rejects follows the fuel's energy, not the pedal" -->

## Battery and alternator

With the engine off, a car's battery rests at about 12.6 V. With it running, the
[alternator](glossary.md#alternator), a small generator driven by the engine, charges it at
about 14.2 V, a little less under heavy load.
<!-- VehicleTelemetry BATTERY_RESTING 12.6, BATTERY_CHARGING 14.2, battery_volts: minus 0.6 x load -->

The drone has no alternator: its battery pack has a model of its own, on the
[drone page](drone-flight.md#the-battery). The `battery` signal carries the pack's voltage there.

## A truck's air

The trucks' brakes work on compressed air, kept in two tanks. In the game the engine's compressor
fills them, each full press of the brake pedal draws some air out, and holding the pedal costs
nothing more. The second tank loses a little less per press, so the two readings drift apart,
and a fault in one is not hidden by the other. A trailer being coupled takes about 3 bar
from the first tank while it fills its own. Below 5 bar the low-air warning is due; below 3 bar the
spring brakes apply. [Brakes](brakes.md#air-and-spring-brakes) explains why.
<!-- TruckTelemetry: AIR_CHARGE_RATE 0.45 bar/s, AIR_PRESS_PRIMARY 0.70, AIR_PRESS_SECONDARY 0.55, AIR_SPAWN_BAR 7, AIR_SPRING_BRAKE_BAR 3, TRAILER_CHARGE_S 8 ("coupling costs ~3 bar of primary"); contract air_primary warn 5.0 -->

## Engine load

The trucks and the tractor publish their [engine load](glossary.md#engine-load): the torque the
engine is giving as a share of the most it can ever give. A plough's draft, a PTO, a hill or a
headwind all show in it. At idle in gear it reads a few percent, the fuel that beats the friction
and the converter's creep.
<!-- VehicleTelemetry.engine_load_pct: "delivered torque over peak torque"; docs/drivetrain.md Creep: engine_load 7-10 % at idle in gear -->

## The boat's engine room

The boats have three more models:

- **Oil pressure**: low at idle, rising to a steady working pressure as the engine speeds up,
  and zero with the key off.
- **Tanks**: fresh water drains and waste rises together while the engine runs. The third, a
  live-well for bait, stays as it is.
- **Engine hours**, as on the trucks and tractor.
<!-- BoatTelemetry OIL_PRESS_IDLE 80 kPa, OIL_PRESS_NOMINAL 350 kPa at 1.5 x idle_rpm; TANK_RATE 2 %/s; contract tank_level: "live-well ... held, not modeled" -->

## Warning lamps from sloppyCAN

Some dashboard lamps are not worked out by the game at all. The check-engine lamp, the battery
warning lamp and a truck's red and amber fault lamps are set by sloppyCAN and shown exactly as it
sends them. The game never lights them by itself.
<!-- contract checkEngine, battery (in), red_stop, amber_warn: "Mirrored VERBATIM ... sloppyCAN is the sole authority" -->

## What the game leaves out

- **No running out of fuel**: an empty tank leaves the engine running.
- **No overheating damage**, no thermostat, no radiator fan.
- **No flat battery**: the battery never runs down, and the starter is not modelled.
- **No air leaks** on the trucks, apart from what the brakes use.

## What you see in sloppyCAN

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `fuel` | out | % | The tank level, on a game-scale tank. Warns below 15 %. Car, truck, tractor, boat, plane. |
| `fuel_rate` | out | L/h | The burn, read off the engine on the wheeled vehicles. Car, truck, tractor, boat. |
| `coolant` | out | °C | The coolant model. Warns at 110 °C. Car, truck, tractor, boat, plane. |
| `battery` | out | V | The battery's voltage; on the drone, the pack's. Every vehicle. |
| `engine_load` | out | % | Truck and tractor: torque given over the most it can give. |
| `air_primary`, `air_secondary` | out | bar | Truck: the two air tanks. Warn below 5 bar. |
| `oil_press` | out | kPa | Boat: the oil pressure model. |
| `tank_level` | out | %, three values | Boat: fresh water, waste, live-well. |
| `engine_hours` | out | h | Truck, tractor, boat: the engine's running time. |
| `checkEngine`, `battery` | in | flag | The check-engine and battery warning lamps, set by sloppyCAN. |
| `red_stop`, `amber_warn` | in | flag | Truck: the fault lamps, set by sloppyCAN. |
<!-- contract/carlito_contract.json: fuel (warn 15), fuel_rate, coolant (warn 110), battery (out and in), engine_load, air_primary, air_secondary, oil_press, tank_level (count 3), engine_hours, checkEngine, red_stop, amber_warn -->

## Try it in the game

<div class="box try">
<p class="box-title">Try it in the game: warm up and burn</p>

1. Pick the `sedan` on **Flatland** with the dashboard showing (**F2**). The coolant starts at
   20 °C. Watch it climb towards 90 °C as the engine idles.
2. Drive at full throttle for a minute. The coolant rises a little higher, and the fuel gauge
   falls noticeably.
3. Lift off and coast in gear: the fuel rate reads 0 while the engine braking lasts.
4. Pick the `semi` and press the brake repeatedly while standing: the two air bars fall at
   different rates, and recover once you stop pumping.

</div>

## Related

- [The engine](engine.md): where the fuel's energy goes.
- [Brakes](brakes.md): what the truck's air is for.
- [Glossary](glossary.md): every term on this page.

[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# Position, heading and distance

<p class="lead">This page explains how a vehicle measures where it is, which way it points, how
fast and how far it goes, and how it is shaken.</p>

<div class="badges"><span class="label">Which vehicles have this</span>
<span class="badge yes" title="Every car and van: GPS position, heading, speed, odometer, accelerations, turning rate and impacts">Car</span>
<span class="badge yes" title="Every truck: all of these, plus an hour meter">Truck</span>
<span class="badge yes" title="Both tractors: all of these, plus an hour meter and a true ground speed beside the wheel speed">Tractor</span>
</div>

A driver looks out of the window to see where the car is going. The vehicle itself has no eyes,
yet its navigation shows it on a map, its speedometer shows its speed, and its airbags know when it
has hit something. Each of these comes from a sensor that measures one thing well and has its own
way of being wrong. How does a vehicle know where it is, which way it points and how far it has
gone?

## Where it is: GPS

![Three satellites at the top, each with a circle round it whose radius is its distance to the receiver. The three circles cross at one point, where the receiver is.](img/gps-circles.svg "The receiver sits where the distance circles cross (drawn flat; in space they are spheres).")

A [GPS](glossary.md#gps) receiver works out its position from the signals of satellites orbiting
about 20,000 km above the Earth. Each satellite carries a very precise clock, and keeps sending
out the time on its clock and where it is. The signal travels at the speed of light, about
300,000 km each second, so the time it takes to arrive gives the satellite's distance. For example,
a signal from a satellite straight overhead, about 20,000 km away, takes about 20,000 ÷ 300,000 =
0.07 seconds to arrive.
<!-- Wikipedia, "Global Positioning System": "Orbiting at an altitude of approximately 20,200 km" -->

Knowing its distance from one satellite, the receiver knows only that it sits somewhere on a sphere
round that satellite. A second satellite narrows this to the circle where the two spheres cross,
and a third to a point (the drawing shows the same idea flat, with circles).

Why does a receiver need four satellites, then? Because its own clock is cheap, and the timing
has to be extremely precise. Light goes 300 metres in a millionth of a second, so a receiver
clock wrong by a millionth of a second would put the receiver 300 metres out. The fourth
satellite lets the receiver work out its own clock's error as well as its position.
<!-- Wikipedia, "Global Positioning System": "at a minimum, four satellites must be in view of the receiver for it to compute four unknown quantities" (three position coordinates and the deviation of its own clock from satellite time) -->

The position comes out as a latitude (how far north or south of the equator, in degrees) and a
longitude (how far east or west of a line through Greenwich, in London). A degree of latitude is
about 111 km everywhere. A degree of longitude gets shorter away from the equator, because the
lines of longitude all meet at the poles. Near Paris, for example, a degree of longitude is only
about two thirds as long as one of latitude.
<!-- VehicleTelemetry METERS_PER_DEG_LAT 111320; cos(48.86 deg) = 0.66 -->

So a position to the metre needs many decimal places. A hundred-thousandth of a degree of
latitude (0.00001°) is 111 km ÷ 100,000 = about 1.1 metres.

<details><summary>How a navigation system carries on in a tunnel</summary>

In a tunnel, or between tall buildings, the satellite signals are blocked or bounce off walls. A
car's navigation keeps going by working out where the car must have got to from where it last
knew it was: the wheels' turning gives the distance travelled, and a [gyroscope](glossary.md#gyroscope) (see
[Acceleration and turning](#acceleration-and-turning)) gives each change of direction. Sailors
call this [dead reckoning](glossary.md#dead-reckoning). Small errors add up, so the position drifts, and it snaps back when the
satellites are seen again.

</details>

## Heading

The [heading](glossary.md#heading) is the compass direction in which the vehicle's nose points:
0° for north, 90° east, 180° south and 270° west.

The heading is not always the direction the vehicle travels. A car sliding on ice with its nose
turned a quarter of a turn to the side travels forward but points sideways, so its heading and its
direction of travel are 90° apart. A tractor working across a steep slope points a little uphill
of where it goes, because its tyres must slip slightly sideways to hold it against the slope.

How does a vehicle know its heading? A GPS receiver can tell the direction of travel from how its
position changes, but only while the vehicle moves, and that is the direction of travel, not of
the nose. An electronic compass measures the Earth's magnetic field, which points to the magnetic
north pole, not quite the same place as the north of a map (the difference depends on where you
are). A gyroscope measures each turn, as below. Real systems combine them.

## Speed

The speedometer shows how fast the vehicle goes, without a sign: driving forward and reversing at
the same pace both read the same. Other systems need the direction too, so the speed along the
vehicle can also be given as positive forwards and negative in reverse.

Most vehicles measure speed from how fast their wheels turn. That goes wrong whenever the wheels
[slip](slip.md#slip-ratio-along-the-wheel): a spinning wheel turns faster than the vehicle moves,
and a locked wheel does not turn at all while the vehicle still slides. So a tractor, whose driven
wheels always slip a little when it pulls, can also measure its true speed over the ground (with a
radar pointed at the ground, or with GPS). The difference between the two tells it how much the
wheels slip. In words:

wheel slip = (wheel speed − ground speed) ÷ wheel speed

For example, a tractor whose wheels turn as if at 10 km/h while it moves over the field at
8.5 km/h has a wheel slip of (10 − 8.5) ÷ 10 = 15 %.

A car's speedometer usually reads a little high, and that is on purpose. In Europe the law says
it may never show less than the true speed, so makers set it to read slightly over, to stay on
the safe side as the tyres wear and their size changes.
<!-- Wikipedia, "Speedometer": UN ECE Regulation 39, "The indicated speed must never be less than the actual speed", and not more than 110 percent of the true speed plus 4 km/h -->

## Distance and time

The [odometer](glossary.md#odometer) adds up the distance travelled. A car usually counts the
turns of a wheel and multiplies them by the distance one turn covers, which is the tyre's
circumference:

distance = turns of the wheel × π × the tyre's diameter

For example, a tyre 72 cm across covers 3.14 × 0.72 = about 2.26 m in one turn, so it turns about
1,000 ÷ 2.26 = 442 times in a kilometre.
<!-- sedan_spec.tres wheel_radius 0.36 -->

The odometer only counts turns; it is told once how far each turn goes. So anything that changes
the tyre's size changes the reading. A bigger tyre covers more road with each turn, so it turns
fewer times and the odometer reads short, and the speedometer, counting the same turns, reads low.
A worn tyre is a little smaller than a new one, and a spinning wheel counts turns that moved the
car nowhere.

<div class="widget" data-widget="odometer"></div>

<div class="widget-limits" hidden>

The odometer is set for a tyre 72 cm across, the size of the simulator's `sedan`'s tyres, and
counts every turn of one wheel. The wheelspin is held steady over the whole 100 m. The simulator's
own odometer does not count wheel turns (see the Simplification list below).
<!-- widgets/odometer.js: sedan_spec.tres wheel_radius 0.36 -->

</div>

The [hour meter](glossary.md#hour-meter) adds up the time the engine has run. Trucks and tractors
have one because they can work for hours without going far: a tractor driving a pump through its
[PTO](glossary.md#pto), for example, covers no distance at all, but its engine still wears. Such
machines are serviced by hours rather than by kilometres.

## Acceleration and turning

An [accelerometer](glossary.md#accelerometer) measures acceleration, along the vehicle (speeding up or braking) and across it
(cornering). Inside is a tiny mass held by springs. When the vehicle speeds up, the case has to
push the mass along with it, the springs bend, and how far they bend gives the acceleration. For
example, a car braking from 100 km/h (about 28 m/s) to a stop in 4 seconds loses 28 ÷ 4 = 7 m/s
every second, an acceleration of 7 m/s², or about 0.7 [g](glossary.md#units).

You might expect an accelerometer standing still to read zero. It does not: an accelerometer
pointing up reads 1 g on a parked car, because the ground pushes the car (and the tiny mass) up
against gravity, and that push bends the springs just as speeding up would. In free fall, with
nothing pushing on it, it reads zero. So an accelerometer cannot tell gravity from acceleration,
which is why a tilted sensor on a slope reads part of gravity as if the car were speeding up or
braking.
<!-- Wikipedia, "Accelerometer": "An accelerometer at rest relative to the Earth's surface will indicate approximately 1 g upwards"; "an accelerometer that is in free fall will measure zero acceleration" -->

A gyroscope measures the [yaw rate](glossary.md#yaw): how fast the vehicle turns, seen from above.
It is usually given in radians per second. A radian is the angle at which an arc is as long as the
circle's radius, so a full turn is 2 × π = about 6.28 radians. For example, a car that goes once
round a roundabout in 20 seconds turns at 6.28 ÷ 20 = about 0.31 radians per second (18° each
second). [Stability control](driver-aids.md#stability-control) compares this with how fast the
steering asks the car to turn.

## Impacts

A crash or a hard landing is a very short, very large acceleration. For example, a car at about
50 km/h (14 m/s) that stops in half a metre of crumpling bonnet slows at roughly 14² ÷ (2 × 0.5)
= about 200 m/s², or 20 g, far more than braking or a bump in the road ever gives. That is how a
vehicle tells a crash from a pothole: its crash sensors watch for such jolts, and fire the airbags
within a fraction of a second.

## What Carlito simulates

The parameters the simulator uses for this, and where each is set, are listed in
[How the simulation works](simulation.md#position-heading-and-distance):

- **Simulation-wide**:
  - [Map origin](simulation.md#map-origin) (`GPS_ORIGIN_LAT`, `GPS_ORIGIN_LON`)
  - [Impact threshold](simulation.md#impact-threshold) (`IMPACT_THRESHOLD`)

<details><summary>Simplification list</summary>

- **A world near Paris.** The world's origin is pinned to a spot in Paris, and metres are turned
  into degrees from there.
  <!-- VehicleTelemetry GPS_ORIGIN_LAT 48.8566, GPS_ORIGIN_LON 2.3522 -->
- **Perfect sensors.** The position and the heading are exact, with no drift, no loss of signal in
  tunnels or between buildings, and no magnetic north.
- **No curvature of the Earth.** The map is flat, which is accurate over the size of a level.
- **An odometer that cannot be fooled.** It adds up the body's own speed along its length, not the
  turns of a wheel, so tyre size and wheelspin do not change it.
  <!-- VehicleTelemetry.odo_step: |speed| x delta -->
- **No gravity in the accelerometers.** They read only the change in motion, so a parked car reads
  zero, and so does a falling one.
  <!-- VehicleTelemetry.body_accel: "Kinematic, with no gravity term, so a body at rest and one in free fall both read zero" -->
- **No memory.** The odometer and the hour meter start from zero at every respawn.
  <!-- contract engine_hours: "Reseeds to 0 on respawn, like the odometer" -->
- **A simple impact detector.** Any jolt over about 2.5 g counts. Its size is held, then shrinks
  by 40 m/s² each second, so even a short jolt stays readable for a moment.
  <!-- BaseVehicle IMPACT_THRESHOLD 25 m/s², IMPACT_DECAY 40 m/s² per s -->

</details>

## What you see in sloppyCAN

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `lat`, `lon` | out | deg | The GPS position, around the Paris origin. |
| `posX`, `posZ` | out | m | The same position in the simulator's own metres. |
| `heading` | out | deg | Where the nose points: 0 north, 90 east. |
| `speed` | out | m/s | Speed along the vehicle, negative in reverse. |
| `kmh` | out | km/h | The speedometer, always positive. |
| `wheel_speed`, `ground_speed` | out | km/h | The speed from the wheels, and the true speed over the ground (Tractor). |
| `wheel_slip` | out | % | How far `wheel_speed` runs ahead of `ground_speed`, as a share of `wheel_speed` (Tractor). |
| `odo` | out | km | Distance since the last spawn. |
| `engine_hours` | out | h | Engine running time (Truck and tractor). |
| `accLong`, `accLat` | out | m/s² | Acceleration along and across the vehicle. |
| `yaw` | out | rad/s | How fast the vehicle turns. |
| `impact` | out | m/s² | The size of the last jolt over 2.5 g, fading away. |
| `ground` | out | flag | Every wheel touching the ground. |
<!-- contract/carlito_contract.json: lat, lon, posX, posZ, heading, speed, kmh, wheel_speed, ground_speed, wheel_slip, odo, engine_hours, accLong, accLat, yaw, impact, ground; WheelDrive.fill_slip clears ground if any wheel is off the road -->

## Related

- [Glossary](glossary.md): every term on this page.
- [Slip and the grip curve](slip.md): why a wheel's turning is not the vehicle's speed.
- [ABS, traction and stability control](driver-aids.md): the systems that use the wheel speeds and
  the yaw rate.
- [Fuel, coolant, battery and air](auxiliary.md): the other readings on the dashboard.

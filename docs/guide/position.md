[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# Position, heading and distance

<p class="lead">This page explains how a vehicle measures where it is, which way it points, how
far it has gone and how it is shaken.</p>

<div class="badges"><span class="label">Which vehicles have this</span>
<span class="badge yes" title="GPS, heading, odometer, accelerations, impact">Car</span>
<span class="badge yes" title="All of these, plus an hour meter">Truck</span>
<span class="badge yes" title="All of these, plus an hour meter">Tractor</span>
</div>

A vehicle has no eyes, so how does it know where it is, how fast it goes and how far it has come?
Vehicles use sensors to follow their own movement, and share what they measure with the other
components. Each sensor measures one thing well, and each has its own way of being wrong.

## GPS: latitude and longitude

A GPS receiver works out its position from satellite signals, as a
[latitude and a longitude](glossary.md#gps). How? Each satellite sends out the time on its clock
and where it is. The signal travels at the speed of light, so the receiver can tell how long it
took to arrive, and so how far away that satellite is. Knowing its distance from several
satellites at once, the receiver can only be at one place.

A degree of latitude is about 111 km everywhere. A degree of longitude gets shorter away from the
equator, because the lines of longitude all meet at the poles (near Paris, a degree of longitude
is about two thirds as long as one of latitude).

![Three satellites at the top, each with a circle round it whose radius is its distance to the receiver. The three circles cross at one point, where the receiver is.](img/gps-circles.svg "The receiver sits where the distance circles cross (drawn flat; in space they are spheres).")

## Heading

The [heading](glossary.md#heading) is the compass direction in which the vehicle's nose points: 0°
for north, 90° east, 180° south and 270° west. This can be different from the direction of travel
(for example, when a car slides sideways). A car on ice, sliding forward with its nose turned a
quarter of a turn to the side, has a heading and a direction of travel that are far apart.

## Speed

The speedometer shows how fast the vehicle goes, without a sign. Other components may also need
the direction, so speed along the vehicle can be given as positive forwards and negative in
reverse.

Speed is often measured from the rotation of the wheels, which is wrong when they slip: a spinning
wheel turns faster than the vehicle moves, and a locked wheel does not turn at all while the
vehicle still slides. This is why tractors can also measure their true speed over the ground (with
a radar or GPS) and compare the two. The difference tells how much the wheels slip (see
[Slip and the grip curve](slip.md#slip-ratio-along-the-wheel)).

## Distance and time

- **The [odometer](glossary.md#odometer)** adds up the distance travelled. A car usually counts the
  turns of a wheel and multiplies them by the distance one turn covers. For example, a tyre that
  rolls 2 m in one turn needs 500 turns for a kilometre. A tyre of a different size therefore makes
  the odometer (and the speedometer) read wrongly.
- **The [hour meter](glossary.md#hour-meter)** adds up the time the engine has run. Trucks and
  tractors use it, because they can work for hours without moving much (a tractor driving a
  stationary pump through its PTO, for example, covers no distance at all).

## Acceleration and turning

Accelerometers measure acceleration along the vehicle (speeding up or braking) and across it
(cornering). An accelerometer is a small mass held by springs, and what it measures is how hard the
case pushes on that mass (shown by how far the springs bend). They also feel gravity: standing still, the ground holds the vehicle up,
so an accelerometer pointing up reads 1 g, and in free fall, with nothing pushing on it, it reads
zero. So an accelerometer at rest does not read zero, even though nothing moves.

A gyroscope measures the yaw rate: how fast the vehicle turns, seen from above.

## Impacts

A crash or a hard landing is a very short and very large acceleration. For example, a car at about
50 km/h (14 m/s) that stops in half a metre of crumpling has an acceleration of roughly 14² ÷
(2 × 0.5) = about 200 m/s², or 20 g, which a normal bump never reaches. Vehicles watch for such
jolts (for example, to fire the airbags).

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
- **No GPS error**: the position is exact, with no drift or loss of signal, and no tunnels or
  buildings block it.
- **No curvature of the Earth**: the map is flat, which is accurate over the size of a level.
- **No gravity in the accelerometers.** They read only the change in motion, so a parked car reads
  zero, and so does a falling one.
  <!-- VehicleTelemetry.body_accel: "Kinematic, with no gravity term, so a body at rest and one in free fall both read zero" -->
- **No memory.** The odometer and the hour meter start from zero at every respawn.
  <!-- contract engine_hours: "Reseeds to 0 on respawn, like the odometer" -->
- **A simple impact detector.** Any jolt over about 2.5 g counts, and its reading is held for a
  moment, then fades.
  <!-- BaseVehicle IMPACT_THRESHOLD 25 m/s², IMPACT_DECAY -->

</details>

## What you see in sloppyCAN

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `lat`, `lon` | out | deg | The GPS position, around the Paris origin. |
| `heading` | out | deg | Where the nose points, 0 north, 90 east. |
| `speed` | out | m/s | Speed along the vehicle, negative in reverse. |
| `kmh` | out | km/h | The speedometer, always positive. |
| `odo` | out | km | Distance since the last spawn. |
| `engine_hours` | out | h | Engine running time (Truck and tractor). |
| `accLong`, `accLat` | out | m/s² | Acceleration along and across the vehicle. |
| `yaw` | out | rad/s | How fast the vehicle turns. |
| `impact` | out | m/s² | The size of the last jolt over 2.5 g, fading away. |
| `ground` | out | flag | Every wheel touching the ground. |
<!-- contract/carlito_contract.json: lat, lon, heading, speed, kmh, odo, engine_hours, accLong, accLat, yaw, impact, ground; WheelDrive.fill_slip clears ground if any wheel is off the road -->

## Related

- [Glossary](glossary.md): every term on this page.

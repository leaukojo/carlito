# Position, heading and distance

<p class="lead">Every vehicle reports where it is, which way it points, how far it has gone and
how hard it is being shaken. These come straight from the vehicle's movement in the game, the
same way a real vehicle's sensors would see it.</p>

<div class="badges"><span class="label">Which vehicles have this</span>
<span class="badge yes" title="GPS, heading, odometer, accelerations, impact">Car</span>
<span class="badge yes" title="All of these, plus an hour meter">Truck</span>
<span class="badge yes" title="All of these, plus an hour meter">Tractor</span>
<span class="badge yes" title="All of these, plus altitude and vertical speed">Plane</span>
<span class="badge yes" title="All of these, plus an hour meter and the boat's own course and speeds">Boat</span>
<span class="badge yes" title="All of these, plus altitude and its own GPS receiver model">Drone</span>
<span class="badge yes" title="All of these">Train</span>
</div>

## GPS: latitude and longitude

The game's world is flat, measured in metres. To give a vehicle a real-looking position, the game
pins the world's origin, its zero point, to a spot in Paris, and turns metres into degrees of
[latitude and longitude](glossary.md#gps) from there. North is the same fixed direction in every
level, and east is a quarter turn to its right. A degree of latitude is about 111 km, and a degree of longitude near Paris is
about two thirds of that, so the game shrinks it to match.
<!-- VehicleTelemetry GPS_ORIGIN_LAT 48.8566, GPS_ORIGIN_LON 2.3522, METERS_PER_DEG_LAT 111320; gps_lat maps -Z to north; gps_lon "meters-per-degree shrunk by the origin latitude" -->

This position is exact: it has no error, drift or loss of signal. Only the drone has a GPS
receiver model with satellites that can be blocked ([Drone flight](drone-flight.md#satellites-and-sensors)).

## Heading

The [heading](glossary.md#heading) is the compass direction the vehicle's nose points: 0° north,
90° east, 180° south, 270° west. It is where the vehicle points, not where it travels: a car
sliding sideways or a boat carried by a current travels a different way from its heading.
<!-- VehicleTelemetry.heading_from_forward: "0 = north (-Z), 90 = east (+X)" -->

## Speed

Two speed signals are published. One is the speed along the vehicle's own length, in metres per
second, positive forwards and negative in reverse. The other is the speedometer's reading, in
km/h, always positive.
<!-- BaseVehicle._update_telemetry: telemetry.speed = linear_velocity.dot(forward), kmh = |speed| x 3.6; contract speed (m/s, signed), kmh -->

The tractor also publishes the two speeds a real tractor compares: how fast its wheels turn, and
how fast it really moves over the ground ([Tyres and slip](tyres.md#what-you-see-in-sloppycan)).

## Distance and time

- **The [odometer](glossary.md#odometer)** adds up the distance travelled, in kilometres. It counts
  backwards travel too. It starts from zero at every spawn and respawn.
- **The [hour meter](glossary.md#hour-meter)** adds up the time the engine has run with the key at
  Ignition, as trucks, tractors and boats record it. It also starts from zero at every respawn.
<!-- VehicleTelemetry.odo_step ("absolute distance travelled, in km"), hours_step; contract engine_hours: "Reseeds to 0 on respawn, like the odometer" -->

## Acceleration and turning

The game measures how fast each vehicle's movement changes, the way an accelerometer would:

- along the vehicle (speeding up or braking),
- across it (cornering),
- and, on the plane and the drone, up and down along its own up direction.

A real accelerometer also feels gravity, so it reads 1 g upwards even standing still. The game's
does not: it reads only the change in motion, so a parked car reads zero, and so does a falling
one. The readings are smoothed a little, so a single bump does not swamp them.
<!-- VehicleTelemetry.body_accel: "Kinematic, with no gravity term, so a body at rest and one in free fall both read zero"; BaseVehicle ACCEL_SMOOTH 10 /s -->

The yaw rate is how fast the vehicle turns, seen from above, in radians per second. The plane and
the drone also publish their roll and pitch rates.

## Impacts

A sudden jolt bigger than about 2.5 g, a crash or a hard landing, is recorded as an impact. The
game holds its size for a moment and lets it fade, so even a one-tick knock is visible on the
dashboard and on the bus.
<!-- BaseVehicle IMPACT_THRESHOLD 25 m/s², IMPACT_DECAY 40 m/s² per s; VehicleTelemetry.impact_gate -->

A vehicle that falls more than 20 m below sea level, off the edge of the world, is respawned.
<!-- BaseVehicle FALL_RESPAWN_Y -20 -->

## What the game leaves out

- **No GPS error** except on the drone, and no tunnels or buildings that block it.
- **No curvature of the Earth**: the map is flat, which is accurate over a game level.
- **No gravity in the accelerometers.**

## What you see in sloppyCAN

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `lat`, `lon` | out | deg | The GPS position, around the Paris origin. Every vehicle. |
| `heading` | out | deg | Where the nose points, 0 north, 90 east. |
| `speed` | out | m/s | Speed along the vehicle, negative in reverse. |
| `kmh` | out | km/h | The speedometer, always positive. |
| `odo` | out | km | Distance since the last spawn. |
| `engine_hours` | out | h | Truck, tractor, boat: engine running time. |
| `accLong`, `accLat` | out | m/s² | Acceleration along and across the vehicle. |
| `acc_vert` | out | m/s² | Plane and drone: acceleration along their up axis. |
| `yaw` | out | rad/s | How fast the vehicle turns. |
| `impact` | out | m/s² | The size of the last jolt over 2.5 g, fading away. |
| `ground` | out | flag | Car, truck, tractor, plane: every wheel touching the ground. |
| `altitude`, `vspeed` | out | m, m/s | Plane and drone: height above sea level, and climb rate. |
<!-- contract/carlito_contract.json: lat, lon, heading, speed, kmh, odo, engine_hours, accLong, accLat, acc_vert, yaw, impact, ground, altitude, vspeed; WheelDrive.fill_slip clears ground if any wheel is off the road -->

## Try it in the game

<div class="box try">
<p class="box-title">Try it in the game: a lap of the compass</p>

1. Pick any car on **Flatland**, with the dashboard showing (**F2**).
2. Drive in a slow circle. The heading climbs through 90, 180 and 270 and back to 0 as you go
   round.
3. Drive straight north for 100 m. The odometer gains 0.1 km, and the latitude grows by about a
   thousandth of a degree.
4. Brake hard: the longitudinal acceleration goes strongly negative, then back to zero as you stop.

</div>

## Related

- [Floating and boats](floating.md): the boat's course and speed over the ground.
- [Glossary](glossary.md): every term on this page.

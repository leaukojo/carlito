# Drone flight

<p class="lead">A drone has no wings, no rudder and no wheels. It flies on four spinning rotors
and steers by changing how fast each one spins. Around those rotors the game models what a real
drone carries: a flight controller, safety checks, a battery, satellites and a network that
links its parts.</p>

<div class="badges"><span class="label">Which vehicles have this</span>
<span class="badge no" title="It drives">Car</span>
<span class="badge no" title="It drives">Truck</span>
<span class="badge no" title="It drives">Tractor</span>
<span class="badge no" title="It flies on wings, on its own page">Plane</span>
<span class="badge no" title="It floats">Boat</span>
<span class="badge yes" title="The drone, drone-mk2">Drone</span>
<span class="badge no" title="It runs on rails">Train</span>
</div>

## Four rotors

Each [rotor](glossary.md#rotor) is a propeller on its own electric motor. Spinning, it pushes air
down and the air pushes the rotor up: the faster it spins, the more it lifts. In the game a
rotor's lift grows with the square of its speed, as a real propeller's does, and each motor takes
a moment to change speed. Together the four can lift about three times the drone's 5 kg.
<!-- drone_propulsion.gd: command = sqrt (thrust ~ omega²); drone.gd motor_spool_tau 0.05 s, max_thrust 150 N; drone_spec.tres mass 5 kg: 150 / 49 = 3.1 -->

![The drone seen from above with its four rotors numbered. Rotors 1 and 4 spin one way, 2 and 3 the other. Beside it: to climb, all four faster; to tilt forward, the rear pair faster; to roll right, the left pair faster; to turn, one spinning pair faster and the other slower.](img/quad-mixer.svg "The drone's four rotors. Opposite corners spin the same way, so their twisting cancels in a hover.")
<!-- drone_propulsion.gd MOTORS table -->

### The mixer

A drone steers only by changing its rotors' speeds. The part of the flight controller that turns
"climb", "tilt" and "turn" into four motor speeds is the [mixer](glossary.md#mixer).

- **To climb or descend**, all four rotors speed up or slow down together.
- **To tilt**, the rotors on one side speed up and those on the other slow down. A tilted drone's
  lift leans with it, and that leaning push moves it across the ground.
- **To turn**, it uses the rotors' own twist. Each spinning propeller twists the drone the
  opposite way, a little. Opposite corners spin the same way, so in a hover the twists cancel.
  Speed up one pair and slow the other, and the twists no longer cancel: the drone turns, while
  the total lift stays the same.
<!-- drone_propulsion.gd: quad-X mixer in thrust-fraction space; yaw = summed prop_torque_ratio N·m per N thrust; drone.gd prop_torque_ratio 0.02 -->

That last trick is weak, so a drone turns slowly: at most about one radian, under 60°, a second.
Each motor has a top speed, and the mixer does not borrow from one control to give another more:
asking for everything at once can run out of rotor.
<!-- drone.gd max_yaw_rate 1.0 rad/s; drone_propulsion.gd "per-motor clamp, no rescaling" -->

### Flying it

The drone levels itself: let go and it returns to flat. **W** and **S** tilt the nose forward and
back, up to about 32°, so it flies forward or backward. **A** and **D** turn it. **R** and **F**
climb and descend. It does not slide sideways under the keys: to go left, you turn and fly
forward.
<!-- drone.gd max_tilt_deg 32; "W and S tilt the nose forward and back (input.throttle)"; manual tilt Vector2(-throttle x max_tilt, 0); keys aircraft_up R, aircraft_down F -->

The air slows the drone a little in every direction, and it flies relative to the moving air, so
the wind carries it.
<!-- drone.gd horizontal_drag, vertical_drag; WindField: "DroneVehicle/PlaneVehicle fly drag relative to it" -->

## Arming

A drone's motors are dangerous, so they will not spin until the drone is [armed](glossary.md#arming).
Press **T**, or send sloppyCAN's `arm`. Before arming, the flight controller runs seven pre-arm
checks and refuses if any fails:

1. The drone is nearly level, within about 10°.
2. The battery has more than a quarter of its charge.
3. All four motor controllers are answering.
4. The attitude sensor is answering.
5. The climb stick is centred, so the drone does not leap on arming.
6. No failsafe is already active.
7. If the chosen flight mode needs satellites, there is a 3D fix.
<!-- drone_arming.gd PA_ATTITUDE (ARM_TILT_DEG 10), PA_BATTERY (ARM_SOC_MIN 25), PA_ESC, PA_AHRS, PA_STICK, PA_FAILSAFE, PA_GPS -->

A refused drone shows BLOCKED, and `prearm_fail` says which check failed. Once landed, it disarms
by itself after about three seconds.
<!-- drone_arming.gd arming_state DISARMED / BLOCKED / ARMED; AUTO_DISARM_S 3.0 -->

## Flight modes

Press **Z** to step through the five [flight modes](glossary.md#flight-mode), or send
`flight_mode`. The mode the drone is
actually in is published separately, because it can be overruled.

| Mode | What the sticks do |
| --- | --- |
| STABILIZE | The drone only levels itself. The climb keys add or remove lift directly. |
| ALT HOLD | The climb keys ask for a climb rate, up to 3 m/s; centred, the drone holds its height. |
| LOITER | As ALT HOLD, and it also holds its position over the ground when the tilt keys are centred. Needs satellites. |
| RTL | Return to launch: climbs to 40 m above home, flies back, and lands. Needs satellites. |
| LAND | Comes straight down at 1 m/s and stops the motors on touchdown. |
<!-- drone_modes.gd: STABILIZE, ALT_HOLD (ALT_RATE_MAX 3 m/s), LOITER, RTL (RTL_ALT 40, RTL_ARRIVE_M 3), LAND (LAND_RATE 1.0); needs_pos_fix -->

Home is where the drone armed. ALT HOLD learns a steady disturbance, such as a heavy load, and
trims for it; LOITER does not, so in a steady wind it holds a little downwind of its spot.
<!-- drone_modes.gd: "There is no position integrator (wind leaves a bounded offset) and the altitude loop's is the drone's only one" -->

### The geofence

The drone may fly up to 400 m from home and 120 m above it. Crossing either limit makes it
return home by itself. The fence is soft: the drone can overshoot it a little before it turns
back.
<!-- drone_modes.gd GEOFENCE_RADIUS 400, GEOFENCE_CEILING 120; "The fence is soft by design" -->

## Failsafes

A [failsafe](glossary.md#failsafe) is what the drone does on its own when something goes wrong. In
order of urgency:

| Failsafe | Cause | What the drone does |
| --- | --- | --- |
| MOTOR | A motor controller has dropped off the network | Lands at once. |
| BATT CRIT | Battery below 10 % | Lands where it is. |
| BATT LOW | Battery below 20 % | Returns home. |
| GEOFENCE | It crossed the fence | Returns home. |
| GPS LOST | Its mode needs satellites and the fix is gone | LOITER and RTL fall back to ALT HOLD; LAND carries on, drifting. |
<!-- drone_arming.gd failsafe_of order: FS_MOTOR > FS_BATT_CRIT (SOC_CRIT 10) > FS_BATT_LOW (SOC_LOW 20) > FS_GEOFENCE > FS_GPS_LOST; failsafe_mode -->

## The battery

The drone runs on a four-cell lithium battery pack. The game tracks how much charge is left, its
[state of charge](glossary.md#state-of-charge), from the current the motors and electronics draw.
The pack's voltage falls as it empties, but not evenly: it stays nearly flat for most of the
charge and drops quickly near the end, which is why the voltage is a poor fuel gauge and the
drone reports its charge separately. Under heavy load the voltage also sags at once, because of
the pack's internal resistance. The pack and each motor controller warm up with the current they
carry.
<!-- drone_power.gd: CELLS 4, PACK_CAPACITY_AH 10, PACK_R_INTERNAL 0.011, V = V_oc(soc) - I R; OCV curve "flat shoulder 100%-20%, then a knee"; PACK_TEMP_K, PACK_TEMP_TAU; esc_temp model -->

## Satellites and sensors

The drone's GPS needs a clear view of the sky. The game casts sixteen lines up into the sky from
the drone, spread across it. Each line that reaches open sky counts as a satellite. Fly into a
canyon or under a roof and lines are blocked, the count drops, and with fewer than four the
position fix is lost. Level 6's canyon is there to show it.
<!-- drone_sensors.gd SKY_RAYS 16, SKY_MASK_DEG 80 (10 deg elevation mask), FIX_SATS_3D 4; level_registry level_6: "a canyon that takes the satellites away" -->

It measures its height three ways, and the three deliberately do not agree:

- **Altitude**, from the GPS, against sea level.
- **Height above ground**, from a downward rangefinder beam, up to 100 m.
- **Barometric altitude**, from air pressure. The game's air pressure drifts slowly, as the
  weather would, so this height wanders a little.
<!-- drone_air_data.gd: altitude / agl / baro_alt "deliberately disagree (no fusion)"; DRIFT_PA 100, DRIFT_PERIOD 240 s; contract agl range [-1, 100] -->

## The drone's network

A real drone's parts talk over a small network, often DroneCAN. In the game the four motor
controllers, the GPS, the power monitor, the attitude sensor and the rangefinder are separate
nodes on that network. Press **Y**, or send `node_fail`, to take a node off: it stops answering,
its last readings freeze, and the drone reacts as a real one would. Losing a motor controller
lands it; losing the GPS loses the fix.
<!-- drone_bus.gd: 4 ESCs (ids 11-14) + GNSS/POWER/AHRS/RANGE (20-23); "Y key / node_fail drops one ... holds last telemetry" -->

## Cargo hook and camera

The `drone-mk2` can carry a crate on a hook, up to 4 kg, which adds its weight below the drone.
Press **1** to close the hook: it latches only if a crate is within reach. In Flatland three
crates wait beside the start while a drone is out; Level 6 has three on its apron. Its camera
gimbal can be pointed by sloppyCAN.
<!-- drone_payload.gd MAX_PAYLOAD_KG 4, CAPTURE_RANGE 1.2 m; hardpoint key 1; drone_gimbal.gd bridge-only; flatland.tscn Payloads (FamilyContent, drone) and level_6.tscn Payloads -->

## What the game leaves out

- **No sideways flight under the keys**: the keyboard tilts the drone forward and back only.
- **No propeller damage or crashes that break it**: a hard landing only bounces.
- **No real radio link or range limit** beyond the geofence.
- **No rotor wash** blowing dust or pushing on things below.

## What you see in sloppyCAN

The drone publishes more signals than any other vehicle. The main ones:

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `arm`, `armed` | in, out | flag | Asks to arm; the motors are armed. |
| `arming_state`, `prearm_fail` | out | enum, bitfield | DISARMED, BLOCKED or ARMED; which pre-arm checks failed. |
| `flight_mode`, `mode_actual` | in, out | enum | The mode asked for, and the one flown. |
| `failsafe` | out | enum | The failsafe the drone is reacting to. |
| `climb` | in | % | The climb command. |
| `rotor_rpm`, `esc_rpm` | out | rev/min | The rotors' mean speed, and each one's. |
| `esc_current`, `esc_temp` | out | A, °C | Each motor controller's current and temperature. |
| `soc`, `battery`, `pack_current`, `pack_temp` | out | %, V, A, °C | The battery. |
| `sats`, `fix_type`, `hdop` | out | count, enum, DOP | Satellites in view, the fix, and how good it is. |
| `agl`, `altitude`, `baro_alt` | out | m | The three heights. |
| `home_dist` | out | m | Distance from home, flat over the ground. |
| `node_fail`, `node_online`, `node_health` | in, out | bitfield, code | Take nodes off the network; which are answering. |
| `hardpoint_cmd`, `hardpoint_state`, `payload_weight` | in, out | flag, N | The cargo hook. |
| `gimbal_pitch`, `gimbal_yaw` | in | deg | Point the camera. |
| `pitch`, `roll`, `roll_rate`, `pitch_rate`, `yaw` | out | deg, rad/s | The drone's attitude and how fast it is turning. |
<!-- contract/carlito_contract.json drone signals: arm, armed, arming_state, prearm_fail, flight_mode, mode_actual, failsafe, climb, rotor_rpm, esc_rpm, esc_current, esc_temp, soc, battery, pack_current, pack_temp, sats, fix_type, hdop, agl, altitude, baro_alt, home_dist, node_fail, node_online, node_health, hardpoint_cmd, hardpoint_state, payload_weight, gimbal_pitch, gimbal_yaw, pitch, roll, roll_rate, pitch_rate, yaw -->

## Try it in the game

<div class="box try">
<p class="box-title">Try it in the game: lose the satellites</p>

1. Pick the `drone-mk2` on **Level 6 - Skyport**. Press **T** to arm and **R** to climb.
2. Press **Z** until the mode is LOITER, and let go: the drone holds its spot.
3. Fly down into the canyon. Watch the satellite count on the dashboard fall. Below four, the fix
   is lost: the GPS LOST failsafe drops the drone from LOITER to ALT HOLD. It keeps its height
   but starts to drift.
4. Climb back out, and press **Y** once. That takes the first motor controller off the network:
   the MOTOR failsafe lands the drone at once.

</div>

## Related

- [Wind, current and conditions](conditions.md): the wind the drone flies through.
- [Glossary](glossary.md): every term on this page.

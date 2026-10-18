# Plane & drone (flight)

- Protocols are flavors: plane `canaerospace` (`elevator`/`flaps`/`beacon`/`strobe` in;
  `altitude`/`vspeed`/`flaps_actual` out), drone `dronecan` (`climb`/`arm`/`node_fail`/
  `flight_mode`/`led`/`hardpoint_cmd`/`gimbal_pitch`/`gimbal_yaw` in; `altitude`/`vspeed`/
  `rotor_rpm`/`armed` + ESC/pack/node/GNSS/mode/hardpoint/gimbal/air-data blocks out). Both
  share `pitch`/`roll` and the IMU triple (`roll_rate`/`pitch_rate`/`acc_vert`), free
  (`BaseVehicle` already computes all three).
- The plane and the plain `drone` are primitive low-poly builds; `drone-mk2` (family
  default) is Blender-modelled (`tools/gen_drone_model.py`): per-motor props/wash discs, a
  gimbal following `gimbal_*_actual`, hook jaws, a spotlight on the `lights` ladder,
  rangefinder beam, status LEDs.

## Drone subsystems

Rationale and the fence: `src/vehicles/drone/CLAUDE.md`. `DroneVehicle`
(`src/vehicles/drone/`): zero wheels, never forks `_physics_process` — everything runs in
`_tick_extras` (measure, judge, decide, act), a context
`WheelDrive`/`TowHost`/`RefuseBody`/`TrainSim` share no shape for. Battery-electric, no
rpm/gear/fuel/coolant. Each of `drone_propulsion` / `drone_bus` / `drone_power` /
`drone_sensors` / `drone_modes` / `drone_arming` / `drone_payload` / `drone_gimbal` /
`drone_air_data` is a pure-static-function file with its own test suite. Four body laws stay
on the vehicle: `lift_thrust`, `heading_frame`, `level_target_up`, `align_torque`.

| File | Owns |
| --- | --- |
| `drone_propulsion.gd` | quad-X mixer in thrust-fraction space, command = sqrt (`thrust ~ ω²`); yaw = summed `prop_torque_ratio` N·m per N thrust; per-motor clamp, no rescaling; `MOTORS` (array → `esc_index`) pinned to `drone.tscn` by test; `rotor_rpm` = mean `esc_rpm` |
| `drone_bus.gd` | DroneCAN roster (`uavcan.protocol.NodeStatus`), 4 ESCs (ids 11-14) + GNSS/POWER/AHRS/RANGE (20-23); Y key / `node_fail` drops one, drops out of `node_online`, holds last telemetry, health derived |
| `drone_power.gd` | DroneCAN `power.BatteryInfo`, replaces the shared `battery` model: `V = V_oc(soc) - I * R_internal`; `pack_current` sums four `esc_current` + avionics draw; `soc`/`pack_temp` |
| `drone_sensors.gd` | `sats` sixteen-ray golden-angle spiral (`SKY_MASK_DEG` mask); `fix_type` = DroneCAN `Fix2.status`; `hdop`; `agl` one ray, `-1` invalid; masks `Layers.SOLID`, omits `Containment` |
| `drone_modes.gd` | STABILIZE/ALT_HOLD/LOITER/RTL/LAND, Z key or `flight_mode`, read back as `mode_actual`; altitude cascade + PD position; geofence 400 m / 120 m ceiling latches RTL |
| `drone_arming.gd` | seven pre-arm checks in `prearm_fail`; `arming_state` DISARMED/BLOCKED/ARMED; arm = rising edge, disarm = refused level in flight |
| `drone_payload.gd` | cargo hook mass/COM change; `hardpoint_cmd` closes only with a `CargoPayload` in reach else `hardpoint_state` false; `payload_weight` = mass×gravity N (`uavcan.equipment.hardpoint.Status`'s unit) |
| `drone_gimbal.gd` | writes the `HoodCam` marker transform, no camera code; bridge-only (`retarder`/`led` precedent), degrees; `gimbal_*_actual` chases at a finite slew |
| `drone_air_data.gd` | `altitude`/`agl`/`baro_alt` deliberately disagree (no fusion): standard-day subscale vs drifting sea-level pressure, position error ∝ airspeed² |

Six stateful sub-objects (plain `RefCounted`s the vehicle owns and ticks, the `WheelDrive`
pattern) hold what the static files cannot: `DroneMotors` (rotors, `_omega`, ESC temps, wash
discs), `DroneSensorSuite` (sky pattern, `agl`, the shared ray query), `DroneHook` (Hardpoint
marker, crate, latch, jaws), `DroneGimbalMount` (HoodCam marker, angles, stops), `DronePack`
(`soc`, pack temperature), `DroneIndicators` (status LEDs, rangefinder beam). A drawn part hangs
off the object owning its state and is optional (`drone.tscn` has none of `drone-mk2`'s). The
flight controller and arming state machine are not extractable: ~18 values cross stage
boundaries.

Payloads are level nodes at the level root, never under `AuthoringRoot`. Wind
(`src/levels/base/wind_field.gd`): base flow + seeded gusts, horizontal only, `test_wind.gd`
pinned.

## Drone: the cluster

- `ST_GROUND` is family-specific: drone's `DroneSensors.landed_now` (AGL close, |vspeed|
  low, collective ≤ hover, `LANDED_DEBOUNCE`); boat's `BoatVehicle.aground_now` (mean probe
  depth < `AGROUND_SHALLOW_FRAC` of `float_depth`); `VehicleTelemetry.with_status_bit`
  stamps either over the packed word. IMU triple (`roll_rate`/`pitch_rate` beside `yaw`,
  `acc_vert` beside `accLong`/`accLat` — DroneCAN `ahrs.Solution`'s
  `angular_velocity`/`linear_acceleration`) is unflavored, off the rigid body in
  `BaseVehicle._update_telemetry`.
- Attitude indicator (`src/ui/attitude_indicator.gd`) owns `pitch`/`roll` (boat/plane too)
  via `Dashboard.WIDGET_SIGNALS`. Node strip generates from `node_health`; `led` (packed
  u32) drives arm-tip LEDs directly, no lamp; buzzer is `BeepCommand`.

## Plane

`PlaneVehicle` (`src/vehicles/plane/`): three RayWheels (steered nose wheel, two mains),
base handles ground roll. `_tick_extras`: prop thrust (drivetrain rpm × throttle), lift with
a stall fade, drag, control torques scaling with airspeed. Steer = roll+yaw; elevator =
pitch; flaps slew toward the request. Force terms are pure statics through `VehicleMath`
dampers, tested `tests/test_plane.gd` / `tests/test_drone.gd`.

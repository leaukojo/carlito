# Drone — rules

Tour, split table, sub-objects: `docs/vehicles.md` § Drone subsystems. Shared vehicle rules:
`src/vehicles/CLAUDE.md`. Derivations sit at their site (`drone.gd` @exports, `drone_modes.gd`,
`drone_bus.gd`).

## Split and tick order

- `drone.gd` keeps the airframe math (`lift_thrust`, `heading_frame`, `level_target_up`,
  `align_torque`), the `@export` tuning and `_tick_extras`. The rest is pure statics plus six
  `RefCounted` sub-objects.
- Tick order, stated once and load-bearing: sensors, hook, fix debounce, arming, modes, demands,
  mixer/motors, pack, gimbal, landed predicate (bottom), indicators (last). Measure, then decide,
  then act. `_pack.soc` and `_landed` are read one tick late on purpose.
- The MASS WRITE stays on the vehicle (`_apply_carried_mass`); `DroneHook.tick` returns "latch
  changed". One `lift_thrust` formula serves the empty and the loaded quad.
- The debounces (`_fix_hold`, `_landed_hold`) and `_ahrs_node` stay on the vehicle: they are
  decisions, the sensor suite measures.
- Tuning knobs stay `@export`s on `drone.tscn` and are passed in (`max_thrust`, `motor_spool_tau`,
  `prop_torque_ratio`); a copy on a sub-object is a second home.

## The fence: `tests/test_drone_vehicle.gd`

- The only coverage of `drone.gd`'s orchestration. It ticks a REAL `DroneVehicle`
  (`_update_telemetry` then `_tick_extras`, 1/60) and asserts published telemetry and public
  properties only, never a private field.
- Await one physics frame after each added body, then write the pose: before the space steps, every
  ray misses (`agl` -1) and LAND / auto-disarm are silently unreachable.

## Measuring

- `tools/measure_drone.tscn` is a dev report (always exits 0). Re-run after touching a `drone.tscn`
  `@export`, `DronePower` pack constants or the mixer; a divergence from the header arithmetic is a
  finding.
- It drives via `InputRouter.set_touch_source`, never `Input.action_press` (autoloads tick first,
  so a pressed edge is a frame stale and lost). It drops and re-raises the arm switch each pass
  (arming is a rising edge).
- The translate figure is taken at the time cap (the pass cannot run longer without crossing
  `GEOFENCE_RADIUS`): read it with the `residual` line or don't quote it. Yaw divergence integrates
  the published `yaw` rate, never `heading`.

## Mixer and bus

- `MOTORS` is the `esc_index` map and the sign table, pinned to `drone.tscn` by `test_drone`. The
  mixer clamps per motor with no rescaling and no compensation: a saturated or dead motor loses
  authority. `drone_propulsion.gd` reads nothing back from `DroneVehicle`; keep it so.
- `max_attitude_torque` / `max_yaw_torque` are pinned arithmetic (`drone.gd`); never inflate
  `prop_torque_ratio` for yaw snap (rule 3). A yaw demand past the hover ceiling climbs.
- `drone_bus.gd` declares the roster once; the array index is the bit index, not the node id. Its
  two copies (contract `node_health` count, `DRONE_NODES` in `src/input/subsystem_counts.gd`, which
  the router's Y walk in `cycles.gd` reads) are pinned by `test_drone_bus`.
- `node_fail` is an input mirrored verbatim; the local Y latch clears via
  `InputRouter.reset_vehicle_cycles`, a bridge-sent mask survives.
- An offline ESC's command is zeroed after the mix, never `_omega` and never compensated.
- A dropped node holds its last telemetry: write the per-ESC arrays element-wise (a fresh array
  zeroes it); gate POWER's four writes on `DroneBus.is_online` while `_pack.step` keeps integrating.
- `rotor_rpm` (mean of published `esc_rpm`) and `pack_current` (true draw) disagree after a drop by
  design; do not "fix" either.
- Health is derived (`DroneBus.health_of`), never echoed; ERROR is unreachable and a test says so.

## Flight modes

- `DroneModes.resolve_mode` is the sole mode decider; nothing re-derives one. The mode reads the
  debounced fix (`held_fix_ok`), published `sats`/`fix_type`/`hdop` stay raw (rule 3).
- LAND's touchdown cut zeroes all four demands AND the integrator (`mix_quad_x` clamps the sum per
  motor; a one-motor-output integrator must not wind up).
- Autonomous output never exceeds a human's: the collective ceiling is `_auto_collective_max`
  (`lift_thrust` at stick +1, no second formula); tilt is limited as a vector to `max_tilt_deg`;
  every mode feeds the one `level_target_up` -> `align_torque` -> `limit_length` chain. Yaw stays
  manual.
- One integrator (the altitude loop's); the position PD has none, so wind leaves a bounded offset.
- The geofence is soft (400 m / 120 m above home), an accepted compromise (`GEOFENCE_*`).
- `_fence_rtl` and `_rtl_landing` are released by the pilot's mode change, disarm or respawn, never
  by `_reset_controllers` (it runs on the mode change they cause). `_fence_answered` carries a
  cancel past the same-tick re-latch (`test_drone_vehicle.test_the_geofence_commands_rtl_and_the_mode_key_cancels_it_from_outside`).
- `rtl_landing_latch` takes the RESOLVED mode, never the request.
- The mode key (Z) and Y are cleared by `register_vehicle` / `reset_vehicle_cycles` (global keys).
- `mode_actual` carries an enum and no range; `home_dist` is the last generated bar row two columns
  hold: see `Dashboard.BAR_ROWS_MAX` before giving another drone signal a range.

## Cargo hook, gimbal, baro

- `hardpoint_cmd` closes only with a `CargoPayload` in the capture ray; release is unconditional,
  never gated or timed. `DroneHook._await_release` needs the command LOW once after `reset()`.
- `MAX_PAYLOAD_KG` is a capture refusal in `DroneHook._find`, not a mass truncation. Flight laws
  read the live `mass`, never `spec.mass`; the hook ticks above arming so every controller sees it.
- Payloads are level nodes at the level root, never under `AuthoringRoot` (rule 1).
- Gimbal commands are bridge-only; the mount's stops come from `gimbal_pitch` / `gimbal_yaw`'s
  contract ranges, so travel and signal range cannot diverge.
- Never fuse the three heights (`altitude`, `agl`, `baro_alt`): the barometer exists to disagree. It
  is ungated by the roster (no baro node; adding one changes `node_health`'s count).

## Arming

- `armed` is latched (`drone_arming.gd`), which makes refusal possible. Arming is an edge,
  disarming a level, and a disarm is refused in flight.
- The key and an empty pack are the master switch, not checks: `arming_state` reads DISARMED.
- A failsafe forces its mode only through `resolve_mode`'s `forced` argument; `DroneModes.auto_rank`
  lets overrides only escalate. A failsafe is not a latch: it clears with its cause.
- `prearm_fail` publishes 0 while armed and renders nowhere (a bitfield has no range or enum).
- `SOC_LOW` is the contract's `soc` warn (`test_drone_arming`); `ARM_SOC_MIN` sits above it.

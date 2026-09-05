# Drone — gotchas & hard-won rules

Descriptive tour: `docs/vehicles.md` § Plane & drone (flight).

## How the drone is split, and where the line falls

`drone.gd` owns the AIRFRAME — the flight math the mode ladder is built on (`lift_thrust`,
`heading_frame`, `level_target_up`, `align_torque`), the `@export` tuning, `_apply_carried_mass`,
and the `_tick_extras` ORDERING that four headers call load-bearing. Everything else is either a
pure-static module (`DroneProp`, `DroneModes`, `DroneArming`, `DroneSensors`, `DronePower`,
`DronePayload`, `DroneGimbal`, `DroneBus`, `DroneAirData`) or one of five stateful sub-objects —
plain `RefCounted`s owned and ticked by the vehicle, the `WheelDrive` pattern:

| object | owns | calls |
| --- | --- | --- |
| `DroneMotors` | rotors, offsets, the two measured arms, `_omega`, ESC temps, the contract warn | `DroneProp`, `DroneBus` |
| `DroneSensorSuite` | sky pattern + mask + cursor, `agl`, the shared ray query, GNSS/RANGE indices | `DroneSensors`, `DroneBus` |
| `DroneHook` | the Hardpoint marker, the crate, the latch | `DronePayload` |
| `DroneGimbalMount` | the HoodCam marker, both angles, the contract-read stops | `DroneGimbal` |
| `DronePack` | `soc`, pack temperature | `DronePower` |

Four boundaries that must not move:

- The MASS WRITE stays on the vehicle. `_apply_carried_mass` writes `mass`/`center_of_mass` onto
  the RigidBody3D and re-derives `_inertia` and BOTH collectives through the same `lift_thrust`
  calls the empty aircraft used, so `DroneHook.tick` RETURNS "the latch changed" instead of
  applying anything — there must be no second formula for a loaded quad.
- The two debounces stay off the sensor suite. `_pos_fix`/`_fix_hold` step above the arming block
  (so the pre-arm GPS check and the mode refusal read one answer) and `_landed_hold` runs at the
  very bottom (it needs a collective demand the tick has not produced yet). They are DECISIONS;
  the suite measures. `_ahrs_node` stays on the vehicle too — the arming snapshot reads it.
- The tuning knobs stay `@export`s on `drone.tscn` and are PASSED IN: `max_thrust`,
  `motor_spool_tau` and `prop_torque_ratio` reach `DroneMotors` as arguments, the way
  `WheelDrive.tick` takes the spec. A knob copied onto a sub-object is a second home, and a second
  home is how two numbers stop agreeing (`gen_boat_variants`' lesson).
- `DronePack.soc` is read one tick late by the arming gate, deliberately: the pack integrates at
  the bottom once the currents are known — 16 ms on a ten-minute discharge, against deciding on a
  number the tick has not produced.

The flight controller and the arming state machine were not extracted; see the rejected list in
`../CLAUDE.md`.

Judge `drone.gd` by its CODE line count, not its file length: ~58 % of it is comment, leaving
~300 code lines and 30 private fields.

## The fence: `tests/test_drone_vehicle.gd`

This suite is the only coverage `drone.gd`'s orchestration has. The other nine drone suites
exercise the pure modules' statics, and `tools/measure_drone.tscn` is a dev report that always
exits 0.

- It ticks a REAL `DroneVehicle`: scripted pose/velocity, then `_update_telemetry` followed by
  `_tick_extras`, the two calls `BaseVehicle._physics_process` makes, at 1/60.
- It asserts on PUBLISHED TELEMETRY and PUBLIC body properties, never a private field. That is
  what let the five sub-objects come out from under it without a test edit — a suite that reached
  for `_soc` would have to be rewritten by the refactor it is fencing.
- The rig awaits exactly ONE physics frame, at setup. A body added to the tree is not in the SPACE
  STATE until the space has stepped once, so a rig that queried immediately gets an empty raycast
  from every sensor — `agl` of -1 over a floor that is plainly there, with the landed predicate,
  LAND and the auto-disarm all silently unreachable. The pose is written AFTER that frame.

## Measuring the drone

- The drone gets its own tool, `tools/measure_drone.tscn`, because `measure_vehicles` cannot touch
  it: `_wheel_driven_variants` skips every chassis with no driven axle. No arguments; five passes
  on a flat strip in still air, ~55 s, always exits 0. Re-run it after touching any `@export` on
  `drone.tscn`, `DronePower`'s pack constants or the mixer — every number it prints is one the
  drone/power headers state arithmetic for, so a divergence is a finding.
  - It drives the craft as an INPUT SOURCE (`InputRouter.set_touch_source`), not through
    `Input.action_press`. Arming and the node-failure walk are per-frame edges, and autoloads tick
    BEFORE scene nodes, so an action pressed from a tool's `_physics_process` is a frame stale
    when InputRouter reads it and the edge is silently lost. Any future tool pressing a toggle key
    has the same problem and the same answer.
  - Each pass drops the arm switch and raises it again: arming is a rising edge with every pre-arm
    check passing, so a switch left up across a respawn spends its edge on a tick where `PA_STICK`
    still refuses, and the run then flies as an unpowered brick and prints a plausible zero rather
    than failing.
  - `get_physics_process_delta_time()` returns 0 in `_ready`, before the node has ticked once;
    `1.0 / Engine.physics_ticks_per_second` is the one to latch.
  - The translate figure is taken AT THE TIME CAP, not at terminal speed — the `measure_vehicles`
    "top (settled)" trap, and the pass cannot run longer without crossing `GEOFENCE_RADIUS`. The
    `residual` line beside it (ground speed still being gained when the clock stopped) says how
    far off it is; read the two together or don't quote the number.
  - Yaw divergence is INTEGRATED off the published `yaw` RATE, never differenced off `heading`: a
    quad on three motors tumbles, and a compass heading off a tumbling body swings and wraps.

## Mixer and bus roster

- The propulsion chain (demand → commands → spooled speeds → thrust/current/temp/rpm) lives in
  `drone_propulsion.gd` (`DroneProp`) — a sibling file, not shared cross-family, since nothing in
  it reads back into `DroneVehicle`; keep it that way. `DroneVehicle` keeps only the body's own
  math (`lift_thrust`, `heading_frame`, `level_target_up`, `align_torque`) that the mode ladder is
  built on. A prior attempt to extract just "the ESC laws" was abandoned: `esc_current_a` sits on
  `motor_thrust`, which sits on `MOTORS` — the chain doesn't cut smaller than this.
- `MOTORS` is the DroneCAN `esc_index` mapping AND
  the sign table, derived from where `drone.tscn` puts each rotor; `test_drone` pins the two
  against each other — signs AND lever magnitudes, so a rotor moved in the scene fails CI whether
  it inverts a control axis or quietly rescales every constant below. Those constants are
  round-tripped through the mixer (demand → motors → summed N·m), so they are pinned arithmetic.
  The controllers produce DEMANDS in thrust-fraction units and the mixer clamps each motor to
  [0, 1] with no rescaling and no compensation — a saturated or dead motor simply loses authority,
  which is what the node failures need. Three consequences before touching a knob:
  - `max_attitude_torque` = 20 N·m is not a taste value, it is the airframe's ceiling. Roll torque
    is `arm_x * max_thrust * demand` and hover spends `m*g/max_thrust` = 0.327 of the range, so
    0.327 × 0.407 × 150 = 20.0 N·m is exactly what a hovering quad can make.
  - Yaw is prop drag, and it is ~1 N·m. `prop_torque_ratio` (0.02 m, what a 0.44 m prop really
    makes) is the only source; `max_yaw_rate` and `yaw_gain` are tuned to suit. Inflating the ratio
    to get more snap is an arcade fudge under rule 3 — and a quad that cannot hold yaw on three
    motors is correct behaviour.
  - A yaw demand past the hover ceiling turns a yaw into a CLIMB: it pins the falling pair at zero
    while the rising pair is still climbing the `w²` curve, so total thrust goes *up*. That is why
    `max_yaw_torque` is that ceiling rounded to a whole newton-metre.
- The drone's bus is a ROSTER, and `drone_bus.gd` is the one place it is declared. Eight nodes
  (four ESCs, GNSS, POWER, AHRS, RANGE), and the array INDEX is the bit index in `node_fail` /
  `node_online` — not the DroneCAN node id, which is only what sloppyCAN addresses frames with.
  `esc_fault` is the one signal in a different bit space (esc_index), which coincides today only
  because the ESCs sit first. Three copies cannot read the roster and are pinned to it by
  `test_drone_bus` instead: the contract's `node_health` count, `InputRouter.NODE_FAIL_COUNT`, and
  `InputRouter.cycle_node_fail` (a named static fn precisely so the pin can CALL it). Growing the
  roster is one edit here and three CI failures telling you where the others are.
  - `node_fail` is an INPUT and rides `VehicleInput`, mirrored verbatim from sloppyCAN like the
    lamp bits (absent = 0 = healthy). The Y key is an InputRouter-owned cycle (the `_pto` pattern).
    It is a bench SWITCH rather than damage, so respawn does not clear it — press Y again. A new
    body does (`InputRouter.register_vehicle`): the roster belongs to the airframe, and Y is bound
    globally, so a press on a car would otherwise follow you into a drone.
  - An offline ESC is zeroed AFTER the mix (`DroneBus.gate_commands`), never compensated: the
    controllers still ask for the roll/pitch/yaw they wanted and one motor does not answer, so the
    loss is asymmetric. Zeroing the COMMAND rather than `_omega` is deliberate — the prop spools
    down and makes decaying lift on the way.
  - A dropped node HOLDS its last telemetry and must never be zeroed. The three per-ESC arrays on
    `DroneTelemetry` ARE the last-published store, so `DroneVehicle` writes them ELEMENT-WISE and
    skips an offline ESC; reassigning a whole fresh array silently zeroes it. `respawn()` clears
    them explicitly, the accel-history rule.
  - `rotor_rpm` and `pack_current` deliberately DISAGREE once a node drops, and neither is a bug.
    `rotor_rpm` averages the PUBLISHED `esc_rpm`, so a stale element keeps counting toward it —
    what a listener reading four messages computes, and what the contract defines it as;
    `pack_current` is measured at the pack, so it follows the TRUE draw and falls, keeping `soc`
    from draining for a motor that is not turning. Do not "fix" either into agreement.
  - Health is derived (`DroneBus.health_of`), never echoed from the input: offline → CRITICAL, an
    ESC over its `esc_temp` warn → WARNING, offline dominates. ERROR is unreachable and a test says
    so. `node_health` carries neither an `enum` nor a `range`: `count` > 1 with an `enum` is
    parse-rejected, and a `range` would put eight bars plus a caption on the generated-bar path. So
    all three node signals render only through the node strip, the `esc_fault` route.

## Flight modes

- The drone's mode ladder is `drone_modes.gd`, and `resolve_mode` is the ONE place a mode is
  decided. STABILIZE / ALT_HOLD / LOITER / RTL / LAND, requested by the contract's `flight_mode`
  and read back as `mode_actual` — the two disagreeing is the reading, not a bug, and everything
  that can make them differ is in that fn: disarmed or an unknown byte is STABILIZE, a latched
  fence breach commands RTL, LOITER/RTL without a 3D fix fall back to ALT_HOLD, an RTL on its
  landing leg reads LAND. Nothing else may re-derive a mode — the vehicle resolves, latches the
  landing leg off that answer, and resolves again rather than assigning LAND itself.
  - A measurement is raw; a decision is debounced. `sats` turns over four of sixteen sky rays a
    tick, so the raw `fix_type` crosses the four-satellite line in both directions within a few
    ticks at the edge of a shed — fed straight into `resolve_mode` that is a mode change per tick,
    each re-seating the hold targets, i.e. a position hold that walks. The published
    `sats`/`fix_type`/`hdop` stay raw (rule 3 owns them); the MODE reads `has_pos_fix` →
    `fix_hold_step` → `held_fix_ok`, a change that has stood for `FIX_DEBOUNCE` (1 s, symmetric).
  - LAND's touchdown cut is ALL FOUR DEMANDS, not just the collective. `mix_quad_x` clamps the SUM
    per motor, so a zero collective with an attitude demand on top still drives two motors and a
    craft landed on a slope sits there fighting the ground. The cut zeroes collective, roll, pitch,
    yaw and the integrator (one whose output reaches no motor must not wind up, or `keep_trim`
    hands the wind-up to the next mode).
  - The climb axis means two different things, and that IS the ladder's content: in STABILIZE a
    thrust TRIM, everywhere else a climb RATE. Same for the tilt stick in LOITER — deflected, the
    pilot flies and the anchor follows the craft, so releasing holds where you let go.
  - No autonomous output may exceed what a human can command, and both ceilings are DERIVED rather
    than typed. The collective is clamped to `_auto_collective_max` — `lift_thrust` run with the
    stick at +1, the same call the manual path makes, so there is no second copy of the formula.
    Its floor is 0 rather than the human's minimum, because LAND cutting the motors is *below* the
    envelope, not beyond it. Tilt is limited as a VECTOR to `max_tilt_deg`, so a diagonal cannot
    make 45 degrees out of two 32-degree axes, and every mode feeds the SAME `level_target_up` →
    `align_torque` → `limit_length(max_attitude_torque)` chain the stick does. Yaw stays manual in
    every mode, RTL included — no real FC takes the yaw stick.
  - `level_target_up` takes a Vector2 (x about the heading's right axis, y about its forward axis)
    and is ONE rotation about the combined axis, which makes the total lean exactly
    `tilt.length()`. `heading_frame` is the single definition of "which way is right", so the tilt
    target and the position error's projection cannot disagree — a split there flies the craft away
    from the point it is holding.
  - The sensors run before the control laws in `_tick_extras`, and the ordering is load-bearing:
    `fix_type` is what refuses a LOITER. Measure, then decide, then act. The one exception is the
    landed predicate, which needs the collective DEMAND and runs at the bottom — LAND cuts the
    motors on LAST tick's `t.ground`, 16 ms after a 0.5 s debounce.
  - The position controller is a PD with no integrator, so it holds a bounded OFFSET into wind and
    that is correct. The altitude loop's is the drone's only integrator; do not add a second.
  - Home is where the craft ARMED, and while disarmed it tracks the craft — so there is no "no home
    yet" case, `home_dist` reads 0 on the ground and the fence cannot breach before takeoff. No
    level node, no authoring. A respawn re-latches it.
  - The geofence is SOFT: 400 m horizontally and 120 m ABOVE HOME, and it COMMANDS rather than
    stops (`WorldBounds` is still the hard wall). 120 m is the real EU/US recreational ceiling;
    400 m is chosen against the 2000 m map, because ArduPilot's own 150 m default would turn
    ordinary exploring into a permanent RTL. `home_dist`'s contract range top IS that radius,
    pinned by test, so the bar fills as the fence approaches — a SCALE and not a clamp: the
    fence's RTL is refusable, so the published number really can pass 400.
  - Two latches, and they are what stop an override chattering against its own cause. `_fence_rtl`
    and `_rtl_landing` are pure fns (`fence_latch`, `rtl_landing_latch`) released by the PILOT
    changing the requested mode, by disarming and by a respawn — deliberately NOT by
    `_reset_controllers`, which runs on the very mode change they produce.
    - The mode key cancels a fence RTL from anywhere, and that costs a third bit of state: the
      vehicle clears `_fence_rtl` on a mode change and calls `fence_latch` on the SAME tick, so on
      its own the release re-latches instantly while the craft is still in breach.
      `_fence_answered` (`DroneModes.fence_answered`) carries the cancel past that tick — set to
      the latch it just cleared, held while the craft stays outside, spent on re-entry or a
      disarm. So the fence commands once per EXIT, ArduPilot's rule; flying home never releases
      the latch by itself. Pinned by
      `test_drone_vehicle.test_the_geofence_commands_rtl_and_the_mode_key_cancels_it_from_outside`
      and `test_drone_modes.test_an_answered_fence_breach_holds_until_the_craft_is_back_inside`.
    - `rtl_landing_latch` takes the RESOLVED mode, never the request, and that is why it is a fn
      with an argument. Keyed off the request, a craft near home with an RTL selected but *refused*
      for want of a fix latches anyway; fly 500 m out, restore the receiver, and the first tick
      with a fix reads LAND and puts the aircraft down where it stands.
    - A mode change carries the climb-rate trim between two cascade modes (`uses_cascade` —
      everything but STABILIZE): same aircraft, same air, same loop on either side of an
      ALT_HOLD → LOITER switch, so dumping it buys a bobble. Arming and respawn always dump it.
  - The mode key is Z. The cycle is InputRouter-owned (the `_pto` pattern) and, like `_node_fail`,
    is CLEARED by `register_vehicle` — Z is bound globally, and a drone that spawned already flying
    itself home because the key was pressed in a car is worse than one that spawns hand-flown.
  - `mode_actual` carries an `enum` and no `range` (the `node_health` reasoning), so it lands on
    the state-chip path beside FIX. `home_dist` is the drone's last generated bar row that two
    columns hold — there is no headroom left; see the note at `Dashboard.BAR_ROWS_MAX` before
    giving another drone signal a range.

## Cargo hook, gimbal, air data

- The drone's CARGO HOOK is a real mass change, and `drone_payload.gd` is the law behind it.
  `hardpoint_cmd` closes the latch only with a `CargoPayload` inside the capture ray's reach, so
  commanding HOLD over open ground leaves `hardpoint_state` false — the `arm`/`armed` relationship
  again. Releasing needs no condition and no timer: the failure you must never have is a load you
  cannot drop.
  - `_apply_carried_mass` is where a payload is FELT, called on the two latch edges only. It writes
    `mass` and `center_of_mass` onto the RigidBody3D and re-derives `_inertia`,
    `_hover_collective` and `_auto_collective_max` through the same `lift_thrust` calls the empty
    aircraft used. Every flight-law read of the mass is the live `mass`, NOT `spec.mass`; only
    `_base_mass` holds the spec's.
  - The hook ticks above the arming block: the pre-arm attitude check and every controller are
    sized against the mass, so latching later flies one tick of a loaded aircraft on an empty
    aircraft's numbers.
  - The payloads are LEVEL nodes at the level ROOT, never under `AuthoringRoot` — everything there
    is a bake input welded into static per-chunk geometry (rule 1), and scenery cannot be lifted.
    `gen_skyport.gd`'s `_build_payloads` owns them for level 6, with its own re-run cleanup
    separate from `OWNED_NODES`. A carried crate stops colliding (a frozen kinematic body accepts
    no force back, so a collider could shove the world and never be shoved) — a decided compromise,
    written down in `cargo_payload.gd`.
- The gimbal costs no camera code, because `ChaseCamera.HOOD` composes the `HoodCam` marker's WHOLE
  local transform; every other vehicle authors an identity basis and is unaffected. `DroneVehicle`
  writes a slew-limited basis onto its marker each tick. The two commands are bridge-only — the
  `retarder` / `led` rule — and the mount's stops come off `gimbal_pitch` / `gimbal_yaw`'s own
  contract ranges at `_ready` (the `_esc_temp_warn` precedent), so the travel and the signal range
  cannot become two numbers.
- The barometer exists to DISAGREE with `altitude` and `agl` (`drone_air_data.gd`), and the two
  labelled models that make the gap are the whole content: a fixed standard-day subscale against a
  drifting sea-level pressure (the standing offset), and a static port that under-reads with the
  square of airspeed relative to the air (position error), which is what makes the gap MOVE in
  level 6's wind. Never correct one of the three heights toward another. It is ungated by the node
  roster on purpose: there is no barometer node, and adding one would change the contract's
  `node_health` count.

## Arming

- `armed` is LATCHED, and `drone_arming.gd` is the state machine behind it — not
  `arm and key == IGNITION` recomputed every tick, which is what makes a refusal possible at all.
  Three signals sit beside it: `arming_state` (DISARMED / BLOCKED / ARMED — BLOCKED is *asked and
  refused*, as against *nobody asked*), `prearm_fail` (a u16, one bit per check) and `failsafe`
  (one enum, most severe wins).
  - Arming is an edge, disarming is a level. `arm` is a LATCHED switch, so arming on the level
    would make the auto-disarm meaningless — the craft would stop its motors three seconds after
    landing and re-arm on the next tick under a switch nobody moved. A disarm is REFUSED in flight
    (gated on the same landed predicate `ST_GROUND` publishes); the instruction lands when the
    craft does.
  - The key and an empty pack are the MASTER SWITCH, not checks: both cut instantly and
    unconditionally, and `arming_state` reads DISARMED rather than BLOCKED without them — an
    unpowered FC is not refusing anything, it is absent.
  - A failsafe forces its mode through `resolve_mode`'s `forced` argument and nowhere else, so one
    fn still decides a mode. `DroneModes.auto_rank` (LAND > RTL > everything) is the single
    statement of which override is more urgent, used by the fence AND the failsafe — so a forced
    mode can only ESCALATE and a low pack cannot pull a craft out of a landing.
  - A failsafe is not a latch. Pressing Z releases `_fence_rtl` and `_rtl_landing`; it cannot
    dismiss a flat pack or a dead motor, which clear when their cause does (Y to restore the node,
    respawn for a fresh pack).
  - `prearm_fail` publishes 0 while armed, and that is not a gap: a flying craft leans past ten
    degrees constantly, so live bits would light through every manoeuvre, and a real FC stops
    running pre-arm checks the moment it arms. It carries no range and no enum (a bitfield's values
    are combinations), so like `esc_fault` and `node_online` it renders nowhere on the cluster;
    `arming_state` and `failsafe` DO land as generated chips (enum + flavor, the `mode_actual`
    path).
  - The arming block sits between the sensors and the modes in `_tick_extras`, and the order is
    load-bearing both ways: it reads this tick's attitude, fix and pack, and the mode resolve reads
    this tick's `armed` and forced mode. Its two backward reads (`_soc`, `_landed`) are deliberate
    one-tick holds with the same justification LAND's motor cut has.
  - `SOC_LOW` **is** the contract's `soc` warn, pinned by test: the bar has to turn danger exactly
    when the aircraft decides to come home. `ARM_SOC_MIN` sits deliberately above it — arming at
    the failsafe threshold is taking off already inside one.

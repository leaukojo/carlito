# Challenge ideas

Challenges teach automotive systems and CAN bus. The player drives **over the bridge only** —
keyboard and touch are locked out — and is assumed to bring their own tooling for sending
frames to sloppyCAN (a script, a replay tool, or frames by hand). A good challenge is one
where the answer is in a signal, not in driving skill: a par time, an entry-speed gate or an
invisible hazard usually stops "just drive slowly" from being a solution. **A par goes only where
time is the point** — where a crawl would otherwise solve it (7, 9, 14, 15). Everywhere else the
geometry or a gate closes the crawl and the challenge carries no par: a failing timer the lesson
does not need only punishes a player reading signals slowly.

Numbered per vehicle, easiest first. Boat is provisional. § Wire facts says which signals a frame
can drive and which only a sloppyCAN panel can.

## Wire facts the catalogue depends on

- **Gear byte 0 is "no gear opinion"**, not neutral: with accel above 0 the gearbox engages D1 and
  auto-shifts (`InputRouter.arbitrate_bridge`). Only an exact byte (1-6, 255) is a manual gearbox.
  A challenge that teaches gears carries the manual-gear constraint, which fails the attempt while
  `VehicleInput.gear_auto` is set and the vehicle is moving. The same rule means the engine cannot
  be revved standing still over the bridge.
- **The handbrake does not hold a car against the throttle**: it holds only below ~25-30 % accel,
  and an absent `handbrake` is off. Above that it drags, which a par time catches. **This is true
  only of the design invariant checked by the spec-level hierarchy test, not of a genuinely locked
  wheel at runtime.** A locked wheel's rpm is clamped to idle regardless of throttle (no clutch —
  `Drivetrain.wheel_engine_rpm`), so a car held by the handbrake never revs past idle and never
  breaks free at any throttle, including 100 % held indefinitely — confirmed by a Phase 2 spike.
  See `docs/TODO.md` § A locked handbrake never releases.
- **Resolution on the wire** (sloppyCAN's frame map): `posX` / `posZ` are whole metres, `odo` is
  1 m, `heading` 0.1 deg, `speed` 0.01 m/s, `lat` / `lon` 1e-7 deg (about 1 cm). Precise position
  is GPS; posX/posZ are too coarse for parking or a hill-start rollback.
- **Lat/lon is equirectangular around Paris** (`vehicle_telemetry.gd`):
  `lat = 48.8566 + (-z) / 111320`, `lon = 2.3522 + x / (111320 * cos(48.8566 deg))`.
- **Turn bits blink at the source.** A lamp is lit only while its bit is set, so a "steady"
  check accepts a bit seen on through the checkpoint window rather than one held high.
- **Coupling has no signal**: it is the E key (a lay at walking pace). Truck 1 is the one
  challenge that whitelists it.
- **sloppyCAN sources every tractor and truck "in" signal.** Where a real carrier could be
  verified, a frame drives the signal, whether it arrives on the wire, from sloppyCAN's TX
  scheduler or through `carlito-bridge.html`. The owning panel drives it too, and a panel edit
  takes it back:
  - `hitch_pos` / `pto` / `pto_mode`: ISO 11783-7 PGN 65090 Hitch and PTO commands. Byte 2 is the
    rear hitch at 0.4 %/bit, 7.5 the rear PTO engage, 8.5 the rear PTO mode (00 = 540,
    01 = 1000). `pto` is the truck's too.
  - `guidance_curvature`: PGN 44288 Guidance System command, addressed to the TECU (0xF0) or
    global. Bytes 1-2 carry 0.25 km^-1/bit at offset -8032, clamped to +-127. It counts only while
    3.1 reads 01 "intended to steer"; 00 lets go of the wheel.
  - `scv_flow`: PGN 65072 Auxiliary valve 0 command. Byte 1 is 0.4 %/bit while byte 3's state is
    1 (extend); block, retract and float (0/2/3) close the gate, and any other state is ignored.
  - `body_cmd`: CANopen RPDO1 of body node 0x10 (COB-ID 0x210), byte 0 = the enum. It is held
    only while it keeps arriving (500 ms deadline), so a lift needs a periodic send.
  - The ISO 11783-7 commands expire 300 ms after their last frame and fall back to the panel value.
  - Panel-only, so a challenge that needs one is played from sloppyCAN's panels: `diff_lock` and
    `fwd_drive` (tractor dashboard), `retarder` (truck dashboard), and `trailer_ebs_fault` /
    `trailer_abs_lamp` (J1939 tab, four-state like the DM1 lamps).
  - The drone's `led` / `hardpoint_cmd` / `gimbal_*` also decode from frames (DroneCAN 1081 / 1070
    / 1040 from any node but the FC, node 1), and so do the boat's `nav_mode` / `heading_cmd`
    (127237 from any address but 1). `arm`, `flight_mode`, `climb`, `beep`, `node_fail` and
    `sheet` stay panel-only.
- **Wire resolution of the flavored signals a goal quotes**, read off sloppyCAN's packers:
  - `pto_rpm`: 0.125 rev/min per bit (RPTO).
  - `engine_load`: 1 %/bit (EEC2).
  - `axle_load`: 0.5 kg/bit, and only on request (PGN 65258 VW answers a PGN 59904 request, from
    Axle - Drive #1).
  - `agl`: float16 in DroneCAN range_sensor.Measurement, so about 0.06 m steps above 64 m. A -1
    reading goes out as "undefined", not as zero.
  - `home_dist`: **no frame at all**. DroneCAN has no message for it, so it is only a readout in
    sloppyCAN's DroneCAN tab.
  - The contract's own types are finer than all of these: `axle_load` f32 kg 0-20000 with its warn
    at 11500 (the EU 11.5 t drive-axle limit), `pto_rpm` u16 0-1200, `engine_load` u8 %, `agl` f32 m
    -1..100, and `home_dist` f32 m 0-400. `home_dist` is not clamped to that 400 m geofence radius.

## Car

1. **Start up.** Drive a straight road to the finish line. Accel alone does nothing: throttle is
   forced to 0 unless `key` is Ignition (the game says so with an IGNITION OFF notice). The
   manual-gear constraint means the player also sends a real gear byte (D1) rather than relying on
   byte 0. No par: a handbrake left on holds the car outright (§ Wire facts), so nothing drags.
2. **Easy turns.** A wide, winding road to the finish. Wide shoulders forgive a wrong `steer`
   value, so the player can tune left/right on the way and learn that `steer` is a percentage
   whose effect tapers with speed (watch `yaw`). No way to lose: it is the tutorial.
3. **Stop in the box (lit).** Pass an entry gate above a set speed, then brake to a halt fully
   inside a marked zone (every wheel contact inside). The gate is what stops a crawl into the box.
   Teaches braking distance against `speed`. Measured (`sedan-sports`, full brake, flat full-grip
   strip): 8.3 m from 40 km/h, 17.8 m from 60 km/h, 30.5 m from 80 km/h — roughly v², so the box
   needs generous margin past the stop distance at the low end of whatever entry speed is chosen.
4. **Signal your turns (steady).** A course with marked corners; `turnL` / `turnR` must be on
   through a window before each corner and off after it. Easy, and introduces the lamp bits.
5. **Lights.** A pitch-black level (no sun, zero ambient, black sky — the headlights are the only
   light source). The player finds the lamp frame, brings `lights` to LOW or HIGH, then drives a
   narrow causeway. Falling off the edge respawns with a warning.
6. **Stop in the box (blind).** Listed straight after 3: lit, 3 is easy by eye, so it only earns
   its place as the setup for this one. Heavy fog, not dark. Challenge 3 with the box **unmarked** —
   headlights would reveal a painted one. The distance from the start is given, so the player
   stops on `odo`. `odo` is 1 m on the wire, so the box is at least a car length plus 2 m; lat/lon
   is the precise alternative for a player who finds it.
7. **Hard turns.** Same idea as 2, but the outside of every corner is a drop. The steering angle
   has to be right before the turn, so the player plans `steer` against speed. A par time closes
   the crawl, which would otherwise work because the steering keeps the most lock at low speed.
8. **Signal your turns (blinking).** Challenge 4, but a steady bit fails. There is no blink timer
   in the game — a lamp flashes only because its bit is toggled — so the player toggles `turnL` /
   `turnR` like an indicator relay. Anything from 1.0 to 2.0 Hz passes (90 ± 30 flashes a minute,
   the UN R6/R48 band), counted from the lamp edges. Trivial with a script, fiddly by hand.
9. **Steep ramp.** With a gear byte the gearbox takes the exact gear and never shifts on its own.
   The ramp is tuned so D6 lugs to a crawl and D1 sits on the rev limiter: the player shifts on
   `rpm` (the manual-mode / AMT idea). Manual-gear constraint (byte 0 would auto-shift up the
   ramp) and a par time (D1 on the limiter still climbs, slowly). Measured (`sedan-sports`): D6
   starts losing the climb around 5-6° (peaks ~2.4 m/s at 4°, stalls/rolls back by 6°); D1 climbs
   solidly through at least 15° and is still net-positive around 20° (readings above 20° got noisy
   from launch-transient wheelspin and need a cleaner method). Tune the ramp around 5-8° for the
   "D6 stalls, D1 still climbs" contrast — not much past ~15° or D1 stalls too.
10. **Speed trap.** Hold 50 ±2 km/h through a long zone. The player builds their own cruise
    control from `speed` — a first taste of a feedback loop. Uses an ungoverned car: the van,
    pickup, pickup-flat and ambulance carry a `speed_limit`.
11. **Reverse park.** Gear R (255), then reverse into a bay and stop with the heading inside a
    tolerance, which is what forces a reverse entry. `lat` / `lon` / `heading` tell the player
    where the car sits relative to the bay; `posX` / `posZ` are whole metres and too coarse.
12. **Rock out of a ditch.** The car starts in a pit too steep to drive out of directly. The
    player alternates D1 and R in time with the sign of `speed` to build momentum. Physics-model
    check: nothing clamps momentum between D1/R transitions (wheel spin is semi-implicit, not a
    hard clamp on road reaction — `src/vehicles/CLAUDE.md`), so momentum-rocking should work; the
    actual pit grade still needs a real geometry pass in the authoring phase.
13. **Hill start.** Stop on a ramp for a few seconds, then pull away with less than 10 cm of
    rollback, measured by the game. On the wire the player watches the sign of `speed` and
    `accLong` (posX/posZ cannot show 10 cm). Holding the brake and releasing once `accLong` goes
    positive is the scripted solution; holding the handbrake while raising accel past its ~25 %
    hold is the real-world one, and both pass. Measured handbrake-only rollback (`sedan-sports`):
    11 cm @5°, 21 cm @10°, 32 cm @15°, 43 cm @20° — already past the 10 cm bar at the shallowest
    grade tested. **The handbrake-then-accel method does not work at all as designed**: a genuinely
    locked wheel never revs past idle regardless of throttle, so the handbrake never actually
    releases under power (see the wire-fact note above and `docs/TODO.md`). Only the brake-pedal
    method is real today, so the challenge is authored for it alone (the rollback goal cannot tell
    the two apart; only the hint changes) until the drivetrain is fixed.
14. **Cornering budget.** Take a curve under a par time without `accLat` exceeding a comfort
    limit. Too slow fails the clock, too fast fails the limit: a closed loop on `accLat`.
15. **Ice patch.** An invisible low-grip patch on a course with a par time. It is a low-grip splat
    channel painted **under the road deck**: a conformed road reads the splat beneath it, so the
    patch cannot be seen. `slip` is the only warning; the player eases off accel when it spikes,
    building a traction control of their own. A Phase 2 spike (`sedan-sports`) did not land a
    clean grip threshold: full-throttle launches read `slip` 10-13 regardless of grip (launch
    wheelspin dominates), and a gentler cruise-then-steer pass still gave noisy, non-monotonic
    readings across grip 0.2-1.0 (0.85-10.1). Needs a steady-speed, moderate-steer, no-launch
    methodology before a threshold can be tuned.
16. **Open loop vs closed loop.** The player records their frames on a course, then replays them.
    Each attempt starts from a slightly shifted spawn (a seeded offset), so the replay drifts off
    the road. Finishing requires steering from `lat` / `lon` / `heading` feedback instead of a
    fixed frame sequence.
17. **Blind circle.** Heavy fog on flat featureless ground. The player drives a given circle
    (centre in lat/lon, radius in metres) and passes by completing one lap — 360 deg swept about
    the centre — without leaving an invisible ring. Teaches lat/lon-to-metres conversion and
    steering on a position error.
18. **Blind slalom.** Heavy fog. Cone coordinates are given as a list; the player passes within a
    set distance of each, in order, on GPS alone. The follow-up to 17: a sequence of targets
    instead of one shape.

## Truck

1. **Couple and deliver.** The `semi` spawns bobtail (the `semi-conventional` has no ISO 7638 data
   pair, so it never publishes `trailer_connected`). The player couples the trailer with E — the
   one local key a challenge allows, because coupling has no signal — confirms
   `trailer_connected`, then stops the full rig in the box under a par time. The catch is the air:
   coupling costs AIR1 about 3 bar and a trailer coupled by driving starts with empty reservoirs
   (8 s to charge), so braking hard before `air_primary` recovers reaches the 3 bar spring-brake
   gate and locks the rear axle.
2. **Tipping refused.** On the garbage truck, `body_cmd` does nothing. The player reads
   `body_bus` / `body_inhibit` to find the interlock — the body network needs the engine running
   and the chassis PTO on, speed at or below walking pace (1.4 m/s), and the handbrake applied —
   then completes a lift/dump cycle. `body_inhibit` is one bit for all three, so `body_bus` is the
   clue to the PTO term. A frame-sent lift holds only while its RPDO keeps arriving (§ Wire facts).
3. **Weighbridge.** Follow-up to 2 on the same truck. Each completed DUMP cycle adds 12.5 % to
   `hopper_load` (625 kg of real mass, confirmed in `refuse_body.gd:25-27`). The player counts
   cycles while watching `axle_load` (the rear axle), landing inside a target band under the
   11.5 t limit, then drives onto the scale. Only a respawn empties the hopper, so overshooting
   costs the run. Measured rear `axle_load` at rest (handbrake, engine+PTO on): empty 4792 kg,
   then per completed cycle 5177 / 5556 / 5932 / 6307 / 6683 / 7058 / 7435 / 7812 kg at 8/8 full —
   only ~60 % of each 625 kg lands on the rear axle (~377 kg/cycle). **The 11.5 t limit is never
   actually reached** even at a full hopper, so the target band has to sit well below full (e.g.
   5.9-6.7 t, cycles 3-5) rather than being framed as "don't blow through 11.5 t."
4. **Trailer ABS.** On the `semi` with a laden trailer, pass an entry gate above a set speed, then
   stop in the box. `trailer_abs` must never come on — it fires when a trailer wheel really slips
   past the ABS threshold (`TRAILER_ABS_SLIP = 0.30`, the trailer's own worst wheel slip,
   `truck_telemetry.gd:38`) — so the player modulates `brake` against it. Measured: a full-brake
   stop from 40/60/80 km/h (8.1 m / 1.70 s, 18.0 m / 2.40 s, 31.8 m / 3.12 s) trips `trailer_abs`
   at **every** speed tested — a hard stop always fires it. The entry gate's real job is forcing a
   real speed rather than a crawl; passing needs a modulated brake application, not any particular
   entry speed.

## Tractor

1. **PTO speed.** Run the implement at its rated shaft speed: select `pto_mode` 1000, engage
   `pto`, and hold `pto_rpm` inside 950-1050 while working. There is no engagement-order
   interlock (`pto_state` is the request with the key at Ignition, and `pto_mode` only picks the
   gearbox ratio), so the lesson is the ratio: the shaft turns 1000 only near the rated 2200 engine
   rpm, which the player holds with gear and ground speed under the manual-gear constraint.
2. **Mud.** The tractor is stuck in a mud patch with one side firmer than the other. The player
   reads `wheel_slip` and engages `diff_lock` and/or `fwd_drive` to drive out. The split grip is
   deliberate: on uniform mud both rear wheels slip alike and the diff lock does nothing, while
   MFWD helps on any mud. Confirmed in `wheel_drive.gd`: drive is `axle_torque / _driven_count`
   per driven wheel, a genuine open differential (`:109`), so a low-grip rear wheel spins while the
   high-grip side gets no extra torque; `diff_lock` (`:129-139`) pins both rear wheels to a shared
   `Drivetrain.locked_axle_omega` so the gripping wheel actually pulls; `fwd_drive` (`:78-81`) sets
   `w.driven = input.fwd_drive or gd.driven_front` each tick, adding front drive independent of the
   split-grip case, so it helps on uniform low grip too.
3. **Plough.** Plough across a field while keeping `engine_load` inside a band, adjusting
   `hitch_pos` (working depth) as the draft changes. The draft changes because the Field (channel
   4) weight varies across the field. The plough is in the soil only for about the bottom tenth of
   the hitch stroke (`hitch_pos` 0-10 %, confirmed by `draft_depth01` in `tractor_telemetry.gd:77-80`
   — 0.57 m ball travel, 0.055 m tool depth), so `draft_force` reads nearly on/off; and
   `engine_load` is not monotone in draft (it rises toward the torque peak and falls past it — it
   is delivered torque over peak torque, per `src/vehicles/CLAUDE.md`, peak around 1600 rpm).
   `draft_newtons` (`tractor_telemetry.gd:91-96`) is rated draft (12 kN) × depth01 × soil01 (from
   `channel_weight_at` on splat channel 4) × a speed ramp to 2 m/s.
4. **Auto-steer.** Follow a curved crop row by sending `guidance_curvature` instead of `steer` —
   commanding curvature, not wheel angle, the way ISOBUS guidance does. Confirmed the mapping is
   `steer = clampf(curvature / 127.0, -1, 1)` (`bridge_source.gd:97-98`, so 127 1/km full lock =
   7.9 m radius), a **fixed** mapping independent of speed — but `steer` then goes through the
   tractor's speed-tapered rack (`min_steer_frac = 0.55`, linear taper from standstill), so
   commanded curvature only matches driven radius near zero speed; at any working speed the taper
   shrinks the actual wheel angle, so driven radius grows past the commanded one as speed rises.
   This is analytic, not yet confirmed with a runtime circle-drive at 2/8/15 km/h — still needs
   that measurement (and a fix if it's off) before this challenge is authored, per the prerequisite
   already noted in the plan.

## Drone

1. **Arming.** Get the drone armed. `arming_state` and `prearm_fail` say what is blocking it. The
   checks: key at Ignition (without it the state reads DISARMED, not BLOCKED), a rising edge on
   `arm`, pitch and roll within 10 deg, charge at least 25 %, every ESC and the AHRS node online,
   `climb` centred, no failsafe, and a 3D fix only if LOITER or RTL is selected. No way to lose.
2. **LED colour.** Set `led` to a given colour. The value is packed RGB565 in the low 16 bits, so
   it is an encoding lesson. Checked on the input, since `led` has no telemetry echo.
3. **Gimbal target.** Point the camera at a marker with `gimbal_pitch` (-90..30) / `gimbal_yaw`
   (-120..120), confirmed on the `_actual` readbacks.
4. **Payload drop.** Pick up cargo (confirmed by `payload_weight`), fly it to a zone, and release
   it with `hardpoint_cmd`. The hook only closes with a payload inside its capture reach.
5. **Terrain following.** Hold a constant height above ground over hills. Done right, `agl`
   stays flat while `baro_alt` rises and falls with the terrain, so the player learns the two
   measure different things. `agl` reads up to 100 m and -1 means no return. Confirmed structural,
   not just typical: `agl` is a straight-down raycast against level collision
   (`drone_sensors.gd:162-171`); `baro_alt` is derived from a simulated static-pressure column
   referenced to a fixed QNH subscale, i.e. sea-level-relative, with its own drift and position
   error (`drone_air_data.gd:1-73`, doc comment at `:7-8`: "Deliberately disagrees with altitude
   (GPS) and agl... Never correct one height toward another"). Since one tracks terrain and the
   other tracks a fixed reference, divergence over hills is guaranteed by the model, not something
   that needs a flight to prove.
6. **Home by distance.** Heavy fog. Return and land using only `home_dist`, the horizontal
   distance to where the drone armed. RTL and LOITER fail the attempt: RTL would fly home and
   land by itself.

## Boat (provisional)

1. **Autopilot to a buoy.** Heavy fog. Reach a buoy by setting `nav_mode` and `heading_cmd`
   instead of steering by hand. `nav_mode_actual` must stay HEADING HOLD for the run; a hand on
   the helm drops it to STANDBY.
2. **Hold a course in a current.** A cross current (`current_set` / `current_drift`) pushes the
   boat sideways; the player holds a track by steering off `cog` rather than `heading` (crab
   angle).
3. **Shallow channel.** Heavy fog. Get through a winding channel using only `depth`. Needs a sea
   level above the shared 1 m, or `depth` reads a constant.
4. **Tack upwind.** Reach a buoy upwind with the sailboat (`boat-sail-a`), trimming `sheet`
   against `awa`.

## What the set needs

- **CAN-only lock.** Keyboard and touch ignored, including the N key and the pause menu's TIME
  button (either would undo a dark level). The attachment key E is locked too, except in Truck 1.
- **Constraints beside goals**: par times and entry-speed gates as fail conditions, the
  manual-gear constraint, a flag that must never be set, a mode that must never be entered.
- **Finish / fail zones** with a message, and respawn with a warning.
- **A short briefing** per challenge, quoting wire resolution where a goal depends on it.
- **Visibility** needs no new rendering: pitch black is level lighting with no sun, zero ambient
  and a black sky; blind is heavy fog on the level's own environment, tuned so the vehicle stays
  visible at chase-camera distance. Blind challenges also need targets that are invisible by
  construction (ring, cones, buoy, an unmarked box). Inputs for tuning (desk-read, not yet tuned
  by eye — that step needs the user, per Phase 8): chase camera follow distance is 6.0 m
  (`chase_camera.gd:18`); the car's actual runtime headlight beams (from `LampSet`, not the static
  `.tscn` values) are LOW range 32 m / energy 7.5, HIGH range 90 m / energy 14.0 (`lamp_set.gd`
  `HEAD_RANGE`/`HEAD_ENERGY`).

## Parked

- **Long descent (truck).** Keeping speed with `retarder` to save the air does not work as a
  lesson. The reservoirs charge at 0.45 bar/s and draw 1.10 bar/s times the pedal, so any pedal
  up to about 41 % never drains them, and 40 % pedal out-brakes any drivable grade. Without a
  brake-temperature model the retarder buys nothing the service brake cannot. Adding that model
  (an honest aux model under rule 3) is what would unpark it.
- **Trailer EBS fault.** `trailer_ebs_fault` is a lamp the game never sets — a fault injected
  from the bus. Without sloppyCAN injecting frames on its own, the player would only be sending
  it to themselves.
- **Diagnose the status bits.** Needs another ECU on the bus pre-loading a wrong frame
  (handbrake on, key stuck at On) that the player must find from the `status` word — also a
  sloppyCAN-side injection.

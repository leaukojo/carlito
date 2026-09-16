# Challenge ideas

Challenges teach automotive systems and CAN bus. The player drives **over the bridge only** —
keyboard and touch are locked out — and is assumed to bring their own tooling for sending
frames to sloppyCAN (a script, a replay tool, or frames by hand). A good challenge is one
where the answer is in a signal, not in driving skill: a par time, an entry-speed gate or an
invisible hazard usually stops "just drive slowly" from being a solution. **A par goes only where
time is the point** — where a crawl or a lazy gear would otherwise solve it (7, 14, 15).
Everywhere else the geometry or a gate closes the crawl and the challenge carries no par: a failing
timer the lesson does not need only punishes a player reading signals slowly.

Numbered per vehicle. A number is an id that code comments quote, not the play order
(`ChallengeRegistry.DEFS` is that), and a parked idea leaves its number unused. Boat is
provisional. § Wire facts says which signals a frame can drive and which only a sloppyCAN panel
can.

## Wire facts the catalogue depends on

- **Every challenge declares its gearbox** (`ChallengeDef.transmission`, shown on the briefing).
  AUTOMATIC, the default, reads the gear byte as a PRND lever: 255 reverses, 1-6 and 0 drive
  forward and the gearbox picks the gear, so the engine cannot be revved standing still. MANUAL
  takes the byte exactly and 0 is neutral; it belongs only where choosing the gear is the lesson
  (Car 7 manual gearbox).
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
   gearbox is AUTOMATIC, so the key and accel are the whole lesson; gears are Car 7's. No par: a
   handbrake left on holds the car outright (§ Wire facts), so nothing drags.
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
   narrow causeway. Falling off the edge respawns with a warning. Estimated, not measured by eye
   (headless has no renderer): with Godot's inverse-square SpotLight3D falloff, HIGH (energy 14.0)
   matches LOW's (7.5) brightness at LOW's own 32 m range out to `32 * sqrt(14/7.5)` ≈ 44 m, then
   fades to black by its 90 m cutoff — HIGH throws usefully to ~40-45 m, not the full 90 m. LOW's
   wide 44° half-angle cone (11° pitch down) floods the near foreground; HIGH's narrower 38° cone
   (1.5° pitch, nearly level) throws further and lights less of the shoulder up close. A ~5-6 m
   causeway sits inside LOW's cone at the distances that matter (10-20 m ahead) and a ~120-150 m
   length keeps the whole run within HIGH's ~40-45 m usable reach one rolling window at a time on
   LOW, or mostly in view at once on HIGH — either beam suffices, per the catalogue's "LOW or
   HIGH". This still needs the user's eye on a real deployed build to confirm the cones actually
   read as bright enough against the black sky. Authored as `car_lights` on the arena's gravel
   causeway (6 m paved): lights LOW or HIGH first, then a finish where the S ends, still over the
   water, and a `Water` fall box over the lagoon under the deck. A detour round the lagoon onto
   the causeway's far end is left open, since it is longer and just as dark. Measured with the
   scripted-bridge driver: PASS on LOW at 30 km/h (19.0 s); with lights OFF the attempt never
   passes; swerving off the deck RESETs.
6. **Stop in the box (blind).** Listed straight after 3, the pair just before the blind stadium:
   lit, 3 is easy by eye, so it only earns its place as the setup for this one. Fog at
   0.2, thicker than the other FOG challenges' 0.12, not dark. Challenge 3 with **no markers at
   all** — headlights would reveal a painted box, and a gate line or post seen through the fog
   says where to brake, which made it trivial. The distance from the start is given, so the
   player stops on `odo`. `odo` is 1 m on the wire, so the box is at least a car length plus 2 m;
   lat/lon is the precise alternative for a player who finds it.
7. **Manual gearbox.** Car 1's road and finish again, on a MANUAL gearbox with a par, so the
   player shifts on `rpm`. Authored as `car_manual_gearbox` on Car 1's course. Measured with a
   scripted-bridge driver (full throttle from the first tick, `--fixed-fps 60`): D1 alone 16.2 s
   (on its ~50 km/h limiter from 4 s), D2 alone from rest 12.6 s, D1 then D2 12.0 s; shifting up
   at 6700 rpm (reaching D4 by the line) with 0 / 0.5 / 1.0 s in neutral per shift, 10.4 / 11.0 /
   11.4 s. **Par 11.5 s**: every one-gear run and the D1-D2 run fail, a full upshift sequence
   passes with up to about 1 s per shift.
8. **Hazard lights.** Flash the hazards for 5 s; anything from 1.0 to 2.0 Hz passes (90 ± 30
   flashes a minute, the UN R6/R48 band). There is no hazard signal of its own: a hazard is
   `turnL` and `turnR` toggled together, in phase, the same as RAMN 0x1BB carries them, so the
   player is really building an indicator relay for both sides at once — a lamp lights only
   while its bit is set, and `LampFlashHoldGoal` fails a lamp flashing alone as readily as a
   steady one. Measured (`sedan-sports`): PASS flashing both sides in phase at 1.5 Hz (5.67 s to
   the 5 s hold), FAIL flashing the left side alone ("no synced flash for 1.07 s").
10. **Speed trap.** Hold 58 to 62 km/h through a 160 m zone. The player builds their own cruise
    control from `speed` — a first taste of a feedback loop. The sedan's own gear limiters sit
    either side of the band, so pinning a gear cannot pass it: measured (`sedan-sports`,
    full throttle) D1 settles at 50.1 km/h and D2 at 77.5 km/h, both FAIL in the trap. A feedback
    controller (`accel = k * (60 - kmh)`) PASSes at 60 km/h, 18.3 s through the trap.
11. **Reverse park.** Gear R (255), then reverse into a bay and stop with the heading inside a
    tolerance, which is what forces a reverse entry. `lat` / `lon` / `heading` tell the player
    where the car sits relative to the bay; `posX` / `posZ` are whole metres and too coarse.
    Measured footprint (`sedan-sports`, visual AABB in body-local space, chassis + wheel meshes
    only — GPUParticles3D dust carries its own oversized travel AABB and is excluded): 1.56 m
    wide x 3.06 m long x 1.53 m tall; wheelbase 1.58 m, track 1.14 m. Proposed bay: an interior
    clear ~2.4 m wide x ~4.6 m long (about 0.4-0.8 m of margin per side/end over the footprint),
    with a heading tolerance of ±20° around the bearing that points back out toward the aisle —
    both `heading` (0.1°) and `lat`/`lon` (~1 cm) resolve that easily. A forward (nose-in) entry
    ends up facing the opposite way, ~180° off the required "nose out" bearing — far outside any
    tolerance narrower than 90°, so it cannot pass from the aisle. Paint has no collision, so a
    car could still loop round and drive in nose first through the bay's back line; a `Behind`
    fail zone over the ground behind the bay closes that. Authored as `car_reverse_park`: the bay
    is painted 2.4 x 4.6 m on the apron's north edge, and its zone is that bay inset by the body's
    overhang past the wheel contacts (the goal tests contacts), heading 180 ± 20°. Measured:
    reversing in along an arc PASSes (17.4 s); nosing in from the aisle stops in the bay facing
    north and never passes.
12. **Rock out of a ditch.** The car starts in a pit too steep to drive out of directly. The
    player alternates D1 and R in time with the sign of `speed` to build momentum. Physics-model
    check: nothing clamps momentum between D1/R transitions (wheel spin is semi-implicit, not a
    hard clamp on road reaction — `src/vehicles/CLAUDE.md`), so momentum-rocking should work; the
    actual pit grade still needs a real geometry pass in the authoring phase. **No grade found
    where rocking clearly beats a single D1 run**, on a symmetric V pit (HeightmapTerrain, flat
    floor a few metres each side of the apex, walls climbing at a constant grade beyond it).
    Two findings stood in the way: (1) D1 in gear holds position via the no-clutch idle-creep
    floor (`src/vehicles/CLAUDE.md`) rather than rolling back when a climb stalls, so triggering a
    D1/R alternation off the sign of `speed` (as a player watching the wire would) never fires —
    the car just sits. (2) Timing the alternation instead (a fixed 1.4 s D1/R square wave, like
    pumping the pedal) did no better than a single D1 run at the same grade, and often worse: a
    single D1 run with a short flat run-up already climbs most of a 30-50° wall (2.4-3.5 m of a
    3.5-8.6 m wall at 30-55°) in one attempt, so there is little room left for rocking to add.
    Car 12 is parked rather than forced, per the catalogue's own allowance for "no grade found".
14. **Perfect turns** (`car_corner_budget`). Take a curve under a par time without `accLat` exceeding a comfort
    limit. Too slow fails the clock, too fast fails the limit: a closed loop on `accLat`.
15. **Ice patch.** An invisible low-grip patch on a course with a par time. It is a low-grip splat
    channel painted **under the road deck**: a conformed road reads the splat beneath it, so the
    patch cannot be seen. `slip` is the only warning; the player eases off accel when it spikes,
    building a traction control of their own. A Phase 2 spike (`sedan-sports`) did not land a
    clean grip threshold: full-throttle launches read `slip` 10-13 regardless of grip (launch
    wheelspin dominates), and a gentler cruise-then-steer pass still gave noisy, non-monotonic
    readings across grip 0.2-1.0 (0.85-10.1). Needs a steady-speed, moderate-steer, no-launch
    methodology before a threshold can be tuned. That methodology (`sedan-sports`, D1, full
    throttle in a straight line to ~45 km/h, THEN a held moderate steer at reduced throttle
    through a bend, `slip` sampled only during the bend) gives a clean, monotonic sweep: grip 1.0
    (asphalt) baseline `slip` max 0.14 / mean 0.04; grip 0.6 spikes to max 2.54 / mean 0.75 (about
    18x baseline) while the car stays controllable and in the 40-50 km/h band; grip <= 0.5 spins
    the car out (`speed` goes negative mid-bend) with `slip` maxing past 9.7. Grip ~0.5-0.6 reads
    as the patch value: a clear multi-x spike over baseline without a guaranteed spin-out.
    **Built but unregistered: no par window at grip 0.55.** `car_ice_patch` (the arena's ice
    road, R 35 m over 70°, Ice under the bend only) was measured with a pure-pursuit driver and
    `slip` read only on the bend. Held speeds of 30 / 40 / 50 km/h PASS in 11.3 / 9.3 / 8.4 s
    with bend `slip` 0.01 / 0.03 / 0.06, which is never a spike. 55 km/h reads 0.34 and runs wide
    off the paved finish, and auto gear at full throttle enters at about 70 km/h, reads 0.58 and
    leaves the road. D1 flat out (about 50 km/h) PASSes in 8.5 s at 0.20. So the fastest run
    that passes never needs to read `slip`, and no par can fail a driver who ignores it. The spike
    comes only a few km/h before the car is lost, and launch wheelspin reads 0.6-4 up to about
    45 km/h, which drowns a player's slip-triggered lift before the bend. Re-gripping the channel
    is a scaffold edit and a re-bake; whether that, or a different lesson on the same road, is
    worth it is open.
17. **Blind stadium.** Heavy fog on flat featureless ground. The player drives a stadium track —
    two straights joined by two semicircles, given as the two end centres A and B in lat/lon plus
    a radius — and passes by completing one lap without leaving an invisible band around segment
    AB. A circle is solved by holding one steering angle; the stadium's curvature changes along
    the way, so the error term stays one formula (`distance(P, segment AB) - R`) but a constant
    steering angle can no longer hold it. `ZoneShape`'s RING gained `half_length`, stretching the
    annulus into a stadium (0 keeps the circle); `RingLapGoal` needed no change, since the band
    still never contains the centre and a single loop around it still nets exactly 360 deg
    regardless of the loop's shape. Measured (`sedan-sports`, straights 40 m, R 15 m, band 12-18 m):
    a driver steering on the lat/lon error (a pure-pursuit target on the ideal R-radius offset
    curve, one heading gain) PASSes in 32.4 s; one constant steering angle picked to fit the 15 m
    caps (about -16 deg, the closest a spawn-facing survives) FAILs by leaving the band in 7.8 s,
    on the straight right after the spawn.

## Truck

1. **Couple and deliver.** The `semi` spawns bobtail (the `semi-conventional` has no ISO 7638 data
   pair, so it never publishes `trailer_connected`). The player couples the trailer with E — the
   one local key a challenge allows, because coupling has no signal — confirms
   `trailer_connected`, then stops the full rig in the box under a par time. The catch is the air:
   coupling costs AIR1 about 3 bar and a trailer coupled by driving starts with empty reservoirs
   (8 s to charge), so braking hard before `air_primary` recovers reaches the 3 bar spring-brake
   gate and locks the rear axle. Authored as `truck_couple_deliver` on flatland (no separate
   island — courses are runtime overlays and need no bake); measured PASS coupling then stopping
   in the box at 17.97 s (par 35 s), FAIL never coupling (times out on par, `trailer_connected`
   stays 0 the whole run).
2. **Tipping refused.** On the garbage truck, `body_cmd` does nothing. The player reads
   `body_bus` / `body_inhibit` to find the interlock — the body network needs the engine running
   and the chassis PTO on, speed at or below walking pace (1.4 m/s), and the handbrake applied —
   then completes a lift/dump cycle. `body_inhibit` is one bit for all three, so `body_bus` is the
   clue to the PTO term. A frame-sent lift holds only while its RPDO keeps arriving (§ Wire facts).
   Authored as `truck_tipping_refused` (`garbage-truck`, flatland); measured PASS completing one
   cycle at 4.40 s, FAIL never engaging PTO/handbrake (the interlock refuses; hopper never rises).
3. **Weighbridge.** Follow-up to 2 on the same truck. Each completed DUMP cycle adds 12.5 % to
   `hopper_load` (625 kg of real mass, confirmed in `refuse_body.gd:25-27`). The player counts
   cycles while watching `axle_load` (the rear axle), landing inside a target band under the
   11.5 t limit, then drives onto the scale. Only a respawn empties the hopper, so overshooting
   costs the run. Measured rear `axle_load` at rest (handbrake, engine+PTO on): empty 4792 kg,
   then per completed cycle 5177 / 5556 / 5932 / 6307 / 6683 / 7058 / 7435 / 7812 kg at 8/8 full —
   only ~60 % of each 625 kg lands on the rear axle (~377 kg/cycle). **The 11.5 t limit is never
   actually reached** even at a full hopper, so the target band has to sit well below full (e.g.
   5.9-6.7 t, cycles 3-5) rather than being framed as "don't blow through 11.5 t." Authored as
   `truck_weighbridge` (`garbage-truck`, flatland, `SignalReachGoal(axle_load, 5900..6700,
   zone=Scale)`); measured PASS landing at 6142 kg after four cycles then holding on the scale at
   20.98 s, FAIL driving onto the scale empty (~4802 kg, under the band, indefinitely).
4. **Trailer ABS.** On the `semi` with a laden trailer, pass an entry gate above a set speed, then
   stop in the box. `trailer_abs` must never come on — it fires when a trailer wheel really slips
   past the ABS threshold (`TRAILER_ABS_SLIP = 0.30`, the trailer's own worst wheel slip,
   `truck_telemetry.gd:38`) — so the player modulates `brake` against it. Measured: a full-brake
   stop from 40/60/80 km/h (8.1 m / 1.70 s, 18.0 m / 2.40 s, 31.8 m / 3.12 s) trips `trailer_abs`
   at **every** speed tested — a hard stop always fires it. The entry gate's real job is forcing a
   real speed rather than a crawl; passing needs a modulated brake application, not any particular
   entry speed. Authored as `truck_trailer_abs` (`semi` + the laden box trailer attached from
   spawn, `SignalBandGoal(kmh, low=50, zone=Gate)` then `StopInZoneGoal(Box)`,
   `ForbiddenValueConstraint(trailer_abs, [1])`). Measuring the pass found the SHAPE of the brake
   input matters as much as its magnitude: a stepped brake percentage — even a light one, even
   well after a launch's own transient has settled — trips `trailer_abs` almost immediately at any
   speed from ~40 to ~50 km/h; only a brake ramped smoothly from 0 over several seconds avoided the
   trip, and even that loses the last few km/h to the same lock unless released to a coast under
   about 12 km/h. Measured PASS crossing the gate at ~51 km/h and creeping to a stop with a ramped-
   then-coasted brake at 92.50 s (no par: the gate and the constraint close the crawl), FAIL
   crossing the gate then braking hard, tripping `trailer_abs` at 18.03 s. The box is 240 m long to
   leave room for this, well past the plan's own estimate.

## Tractor

1. **PTO speed.** Run the implement at its rated shaft speed: select `pto_mode` 1000, engage
   `pto`, and hold `pto_rpm` inside 950-1050 while working. There is no engagement-order
   interlock (`pto_state` is the request with the key at Ignition, and `pto_mode` only picks the
   gearbox ratio), so the lesson is the ratio: the shaft turns 1000 only near the rated 2200 engine
   rpm, which the player holds with gear and ground speed on a MANUAL gearbox.
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
   commanding curvature, not wheel angle, the way ISOBUS guidance does. **Fixed in Phase 11**:
   `VehicleInput.guidance_curvature` now carries the raw signed curvature (1/km) through
   arbitration (presence-gated like `heading_cmd`/`rudder`, `GUIDANCE_CURVATURE_NONE` the
   sentinel — 0 is dead-straight and a real command), and `WheelDrive.tick` derives the wheel
   angle directly off the tractor's own wheelbase (`angle = atan(wheelbase * curvature / 1000)`,
   clamped to `max_steer_deg` only) instead of going through `steer` and the speed-tapered rack.
   `steer` itself is unchanged (still `clampf(curvature / 127.0, -1, 1)` for dashboard/telemetry
   and every other consumer) — only the tractor's own wheel angle now bypasses the taper.
   Measured (a scripted-bridge driver holding a fixed curvature of 20 1/km — 50 m radius — at
   2/8/15 km/h on flatland, reading `|telemetry.speed / telemetry.yaw|` once settled): **before**
   the fix, radius sat at 18.6 / 17.1 / 18.6 m at 2/8/15 km/h (the wire's 127 1/km "full lock"
   badly under-states the tractor's real ~4 m minimum radius, so any curvature under it steers
   tighter than commanded); **after**, 60.7 / 51.9 / 51.6 m — accurate to within a few percent at
   8 and 15 km/h, noisier (about 20% high) at 2 km/h where the yaw signal is small. Tractor 4
   (`tractor_auto_steer`) is authored on this fix.

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
- **Constraints beside goals**: par times and entry-speed gates as fail conditions, a flag that
  must never be set, a mode that must never be entered.
- **A gearbox per challenge**: AUTOMATIC unless choosing the gear is the lesson.
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

- **Blind slalom (car).** Removed from the set (debfbbb); kept as an idea. It was the follow-up
  to the blind circle: cone coordinates given as a list, passed in order on GPS alone. Car 17's
  slot became the blind stadium instead.
- **Hard turns (car).** Removed from the set; its slot 7 became the manual gearbox. The ridge road
  it drove (L L R at R 18 / 15 / 20 m, cliffs both sides) is still in `car_arena`, used by no
  course; bringing it back is a def plus its course and fall-volume builder from
  git history. What it measured: on a 7 m road corners want R >= 15 m (at R 12 m the sedan runs
  wide at any speed); a steep edge of a few metres already reads as a fall; a pure-pursuit driver
  passed at 20-45 km/h (29.1-15.3 s) and ran off the R 20 m corner from 50 km/h, so its par was
  22 s.
- **Hill start (car).** Removed from the set, along with its rollback goal (git history). Only
  the brake-pedal method works: a locked handbrake wheel never revs past idle, so the
  handbrake never releases under power (§ Wire facts). Measured: brake held, then brake off and
  full throttle in the same tick rolls back 0.1-0.3 cm at 10-20 deg; the handbrake alone rolls
  back 11 cm at 5 deg, over a 10 cm bar at every grade tried.
- **Steep ramp (car).** Removed from the set; Car 7 carries the gear lesson. It drove the ridge
  road's 8 deg ramp on a MANUAL gearbox with a 10 s par. Measured (`sedan-sports`, full throttle,
  exact gear): D1 5.5 s, D2 5.9 s, D3 8.6 s; D4-D6 ran past the par. At 7-8 deg D6 settles to a
  ~9 km/h crawl at idle rpm (the no-clutch idle-creep floor) while D1 climbs on its ~49 km/h
  limiter; D6 loses the climb from about 5-6 deg, D1 still climbs at 15-20 deg.
- **Open loop vs closed loop (car).** Removed from the set. A seeded spawn jitter was meant to
  make a replayed frame log drift off the hard-turns road; at 2.5 m / 12 deg, 3 of 10 replays
  still passed, short of the 8-of-10 aim.
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

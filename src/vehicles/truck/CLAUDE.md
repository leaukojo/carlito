# Truck & trailers — gotchas & hard-won rules

Descriptive tour: `docs/heavy_vehicles.md`. `TowHost`, `TowedBody`, `Articulation` and the
two-body housekeeping are shared and live in `src/vehicles/base/` — rules in
`src/vehicles/CLAUDE.md` § Towing. What is in this folder is only what this family has.

## Brakes, retarder, air

- A brake TORQUE goes through RayWheel's brake path; a kinematic LOCK may be written after the
  tick. The truck needs both. The retarder is driveline behaviour, so it follows the
  diff-lock/MFWD pattern: math on `Drivetrain`, applied by `BaseVehicle` into the driven wheels'
  `brake_t`, gated by `spec.retarder_equipped`. Not a `_tick_extras` job — applied as its own
  `move_toward` after the wheels have ticked it over-corrects on tick one, throwing the driven
  axle to slip 1.0 at 8 m/s².
  - Quote the retarder's strength as arithmetic, never as a remembered measurement: flat-road
    retardation is `frac * brake_torque * rear_wheels / (wheel_radius * mass)`. `test_truck`
    asserts a 0.9–1.6 m/s² band per shipped spec.
  - The floor is 0.9 and not 1.0 because on a grip-derived truck the arithmetic collapses:
    substituting `brake_torque = BRAKE_GRIP_FRAC * mu_long * m * g * r / 4` cancels mass and
    radius, so a two-driven-wheel truck retards at
    `RETARDER_MAX_FRAC * BRAKE_GRIP_FRAC * mu_long * g / 2` = 0.93 m/s² whatever it weighs. Only a
    0.215–0.219 fraction would reach 1.0, and above that the hand-built units (1.46 m/s² at 0.20)
    break the 1.6 ceiling. So the floor moved and `RETARDER_MAX_FRAC` 0.20 did not.
  - The band's 1.6 m/s² top caps `brake_torque`, which is why the tractor units peak well below
    what a real 32 t artic makes. It no longer caps peak ENGINE torque: that hierarchy runs against
    transmissible drive.
  - `_lock_rear_diff` is not a counter-example: averaging two omegas and pinning omega to 0 are
    kinematic writes that can only remove energy. A torque is not.
- The retarder's anti-lock rule is a SLIP limit, never a force limit. `RETARDER_SLIP_TARGET` caps
  the one-tick spin change so the axle cannot be driven past 0.10 slip. A cap at μ·N·r looks
  equivalent and is not: it bounds the *saturated* road torque, which a locked wheel is already
  making, so it permits a full skid. Real hardware agrees — SPN 520 rides ERC1, the EBS interface,
  because a driveline brake has no wheel-by-wheel modulation of its own. The axle settles well
  under a third of the cap, so it is a backstop that makes a rating edit fail visibly, not the
  operating point; `test_truck` pins that margin off the spec's own grip curve and static
  rear-axle load, so it needs no re-measuring when the brake changes.
- Air pressure is a GATE, not a bar. Two reservoirs (`TruckTelemetry.air_step`, one pure function
  used twice with different draw rates) charge only while running. Below `AIR_SPRING_BRAKE_BAR`
  (3) on either circuit the spring brakes apply and the rear `omega` is pinned to 0 — a mechanical
  lock, so a full-throttle standing start genuinely cannot move (a brake torque would not do:
  first-gear drive torque exceeds `brake_torque` here). The contract's `warn` (5) is deliberately
  higher, so there is a band to stop in. The gate reads the minimum of the two circuits, which is
  what makes a dual circuit more than one signal published twice.
  - `Drivetrain` reads drive-wheel omega, so with the rears pinned the tach falls to idle however
    far the throttle is pressed. That IS the engine lugging against the brakes — don't "fix" it
    with a throttle cut, a second model of the same thing.
  - No ramp, accepted: losing the air while rolling locks the rear axle in one tick, so slip goes
    to 1 and the friction circle takes the rear lateral grip with it. Real spring brakes are held
    off by air, so this is honest, and it is why the `warn` sits 2 bar above the gate.
  - The gate does NOT zero `retarder_state`: that torque entered `brake_t` earlier in the same tick
    and RayWheel integrated it, so it really ran. Zeroing it would make the signal an echo of the
    gate instead of a read of the driveline.
  - The draw is pedal position and nothing else — not the handbrake (a real spring brake spends air
    being RELEASED), not the spring brakes applying, not speed or load. Extra terms would be ones
    nothing on the dashboard could distinguish.

## Truck telemetry

- `axle_load` is summed `RayWheel.suspension_force` over the rear axle, in kg — a weight, never a
  mass lookup, so weight transfer and a laden body move it as consequences. `retarder_state`
  likewise reads `BaseVehicle.retarder_torque_applied`, the `diff_lock_state` rule. SPN 520's
  negative convention is documented in the contract `desc`, not encoded: a `[-100, 0]` range would
  fill the generated bar backwards.

## The refuse body

- The garbage truck's refuse body is a second network and `RefuseBody` is the whole of it — CiA
  422 body signals reaching the J1939 chassis across a CiA 413 gateway. Pure logic, no nodes.
  - Silent regen trap: `gen_kenney_vehicles.gd` rebuilds the entire `Model` subtree from the GLB
    every run, so a rig node added under `Model` is wiped by the next regen while the run still
    prints success. `TruckVehicle._find_rig` finds `Model/arm` and `Model/body/trash` by name and
    poses them from code — add no scene nodes under `Model`.
  - The geometry IS the declaration: no `arm` mesh means no body unit, which is why the firetruck
    publishes honest zeros on all five body signals with an unchanged cluster.
  - `body_pos` is written onto the arm and then read back off it (`arm_angle_rad` →
    `_arm.rotation.x` → `arm_pos_pct`), the `ball_lift()` discipline. `ARM_STOW_DEG` /
    `ARM_DUMP_DEG` are measured by DRIVING: the arm's origin is its own AABB min corner rather than
    a hinge line, so the stowed end sits below the authored pose and `arm_pos_pct` must never
    hardcode 0 as the bottom. `trash` is the pile in the hopper; its authored pose is a full
    hopper, and empty is one pile-height lower (read off `mesh.get_aabb()`, never a constant).
  - `hopper_load` touches the chassis through `mass` and nothing else; `axle_load` and
    `engine_load` report the payload as consequences. Never add a laden term to either.
    `center_of_mass` stays on the spec — a load that shifts the balance is the tanker's content.
    - The two report it unequally. `axle_load` is summed suspension force, so the payload lands on
      it the next tick; `engine_load` reaches it only through the rpm the drivetrain sags to, so it
      answers under throttle and on a grade, and a loaded truck holding a steady speed on the flat
      reads the same load as an empty one. `axle_load` is the bar to watch after a dump cycle.
  - The interlock is the content: `is_inhibited` takes chassis state (road speed, parking brake,
    and `bus_up`, which carries the PTO) and publishes its result on the body network. It freezes
    the arm where it stands rather than driving it home — losing the PTO mid-lift leaves the arm
    up. `Idle` and `Lower` both stow, deliberately, and an unknown command byte lands there too, so
    the bus fallback is the safe pose.
    - A down bus inhibits, so `body_inhibit` is true through the whole of normal driving, which
      would light INHIB beside a BODY BUS lamp already saying it. Fixed on the dashboard, which
      suppresses the lamp while BODY BUS is dark. Never quieten it by dropping the `bus` term from
      `is_inhibited` — the interlock would then claim an unpowered body may swing its arm.
  - `body_cmd` is an InputRouter-owned cycle (`_body_cmd`, X key) exactly like `_pto`/`_lights`,
    riding `VehicleInput` — not the `boot.gd`/`cycle_implement()` shell duck-type, which never
    reaches `VehicleInput`. The `merge_local` line is required, not tidiness: that dict is built
    explicitly, so a missing key silently drops the keyboard edge while a touch source is
    registered.
  - Ceiling, so it is not rediscovered: the rig is a front loader — no separable tailgate, no body
    raise, no compaction blade, so no packer cycle, and respawn is the only way to empty the hopper
    (cargo goes, meters like `odo`/`engine_hours` stay).

## The fifth wheel, mass ratios, axle loads

- The semi's fifth wheel is a real Jolt joint between two RigidBody3Ds, and it holds: a
  `Generic6DOFJoint3D` built in code at the scene's `Kingpin` marker, linear X/Y/Z limited to
  `lower == upper == 0` (how a 6DOF joint says *locked*), yaw free to the jackknife stop, pitch
  ±15°, roll ±1.5°. The kinematic fallback (`Articulation.jackknife_step` + `pose_at_angle`) stays
  written and tested but unused; its cost is being deaf to trailer-side forces.
  - Roll is deliberately ±1.5° and not 0: a hair of compliance lets the solver settle instead of
    fighting the road every tick.
  - The pitch limit must cover the steepest grade the rig can climb, never bound it. On its stop
    the two bodies are RIGID, so at a break of slope 24 t of still-level trailer picks the climbing
    tractor's drive axle up and the rig has no traction — which reads as "the truck cannot pull the
    trailer up a slope" and is neither power nor grip. Sized by measurement: a sharp break onto the
    25 % grade the drivetrain can climb swings the joint −9.0° to +12.8°, so 15° clears it (and
    matches a real plate's ±12-15°). Check the articulation before touching a spec.
  - The rig rests ~5.9° nose-up on flat ground, an open bug and not the joint's doing: the
    tractor's kingpin rides 1.306 m over the road on its springs while every trailer is authored
    against a 1.05 m plate, so it permanently spends a fifth of the pitch travel. Fixing it means
    moving the shared coupling datum (`FifthWheel.KINGPIN_LOCAL.y` and every trailer's authored
    ground), so it is deliberately a separate change.
  - The YAW limit is a labelled model of trailer-against-cab contact, not a property of the plate,
    and it cannot be collision: the plate and the trailer's nose overlap while coupled, so
    `exclude_nodes_from_collision` must stay at its default true or the two bodies fight for the
    same space. Without it the rig folds to 130° and swings the trailer through where the cab is.
    `Articulation.JACKKNIFE_MAX_DEG` (75°) is the one constant the joint AND the fallback use.
- Tested mass ratio: 8 t tractor : 24 t box (3:1) shipped, 8 t : 25 t verified. Raising a trailer's
  mass past 3:1 is a re-tune needing re-verification, not a free number — `test_trailer` pins the
  ratio and the travel fraction, so it fails instead of shipping a rig on its bump stops.
  - The plate share is 27 % on every trailer, and on a 4x2 it is the traction budget. A real van
    semi-trailer puts 25-30 % of its weight on the fifth wheel; below that a fifth of the trailer
    is not helping the one driven axle grip, and the symptom is "it still struggles to climb" — the
    rig is grip-limited, not power-limited. Set by `center_of_mass.z` against the bogie centre.
    Moving it means re-deriving the bogie load, THAT trailer's `spring_rate` (weight onto the plate
    is weight off the bogie), its load-apportioned brakes, and the tractor's own rear spring rate.
  - Every trailer spec's `spring_rate` and `brake_torque` are sized off the load its own bogie
    carries, never copied: the springs land all four at the same fraction of static travel despite
    a 10 t spread, and the brakes come from one formula (the tractor's `brake_torque` scaled by
    per-wheel load), so every trailer brakes at the same fraction of what it carries as the unit
    pulling it — move the tractor's and all four need re-evaluating. `handbrake_torque` follows the
    same apportioning at a flat quarter of each trailer's service brake, landing every rig on the
    same ~25 % holding grade. That is where a rig's parking brake lives: with 0 there, 32 t held by
    the tractor's two driven wheels runs away on any real slope.
  - A jointed body's RayWheel clamps are sized ~25 % loose: every one-tick clamp scales with
    `corner_mass = spec.mass / wheel_count`, but the bogie only carries `1 − kingpin_share` of the
    mass. No clamp was touched and none should be — the fix, if it ever measures, is the spec's own
    numbers. The tractor errs the safe way round (its rear carries the plate load, so its
    `corner_mass` is understated).
- Neither new spec may ride its bump stops, and the shipped Kenney trucks DO (rear static
  26.3 kN/wheel against a spring that maxes at 20.8 kN). So the semi and the flatbed are sized from
  the load each axle actually carries, which for the semi's rear is its own weight PLUS the plate
  load. `RayWheel` has one spring rate per vehicle, so this is a compromise between a light steer
  axle and a heavy drive axle.
- A cab-over tractor unit is front-heavy bobtail (`center_of_mass.z = -0.15`, 52 % on the steer
  axle) — cab and engine both sit over it, which is why real bobtails lock up so easily. Coupled,
  the plate's load lands 90 % on the drive axle. Driving found this: further back, the coupled
  steer axle carried 20 % and both front wheels left the road under throttle in a corner.

## Trailer authoring, pulling away

- Trailer authoring: origin AT THE KINGPIN, ground at y = -1.05 — the implements' "origin on the
  lower pin line" convention, so the coupling datum is the origin and the coupled pose is one
  transform multiply. Wheel visuals live under `Wheels` in `spec.wheel_positions` order
  (`test_trailer` counts them against the spec; a mismatch is otherwise an invisible wheel). The
  trailer's `spec` is a plain `VehicleSpec` because that is what RayWheel consumes; its
  drivetrain/steering fields are unused, but its LAMP paths are live.
  - A semi-trailer is a GOOSENECK, structural rather than decorative: nothing of it may hang below
    the coupling plane over the tractor. The front 1.35 m is a raised neck whose underside is the
    bolster plate, and the frame and deck step down behind the tractor's tail. Authored flat, the
    deck and both frame rails run straight through the tractor's frame rails, mudguards and fifth
    wheel.
  - Two boxes that TOUCH on a face plane z-fight; two that overlap never do. Stack coupling
    surfaces with a 2 cm gap and let a trailer's own parts interpenetrate freely. Same-body faces
    that merely rest on each other (plank on rail, foot under leg) are fine — those pairs face
    opposite ways, so back-face culling settles them.
    - The rule is swept, not remembered (`test_no_two_boxes_share_a_face_plane_and_a_facing`):
      every axis-aligned BoxMesh pair in the semi and all four trailers, on all three axes, failing
      on a shared plane with a shared FACING over a patch ≥ 2 cm. All five scenes are at 0. When
      the sweep fails, move the DETAIL part proud or inset by 1-3 cm rather than shaving the panel
      it sits on; where two segments of one wall meet, BUTT them exactly.
  - The gooseneck rule bites each new trailer somewhere different: the box's floor is two panels
    because one flat floor ran through the fifth wheel; the tanker's barrel starts behind the neck
    with a pump cabinet on it, because a barrel high enough to clear the bogie wheels still has its
    underside below the coupling plane; the tipper's body starts further back and leaves the
    gooseneck exposed.
  - The swing-clearance rule is geometry, not taste: every point ahead of the kingpin sweeps a
    circle of radius `sqrt(x² + z²)` that must fit inside the kingpin-to-cab distance (1.15 m), or
    the rig cannot turn. `test_trailer` sweeps every BoxMesh CORNER of every trailer, recursively
    and through nested transforms, rather than trusting a node name or an axis-aligned formula —
    the frontmost part has changed once already, and the tipper's body lives under a rotating
    pivot. All four land on the gooseneck at 1.015 m; tipping only moves the body further from the
    cab.
- A rig pulls away on IDLE torque, and that is the drivetrain, not the joint. There is no clutch or
  converter model, so torque at rest is `torque_curve(idle) * throttle` and nothing about peak
  torque or gearing helps until it is already rolling. Fix startability at the LOW END of the
  torque curve, never by reaching for the peak (which the retarder/brake chain caps anyway). The
  tractor units hold 975 Nm at idle, 65 % of their 1500 peak. Part throttle still only creeps —
  correct for a laden artic, not a missing launch model.

## The ISO 11992 trailer bus

- The ISO 11992 trailer bus is five signals (table in `docs/heavy_vehicles.md`), and there is
  deliberately no `trailer_type`: ISO 11992 publishes no body type, and which trailer is on the
  back shows through MASS and through which tractor-side signals it moves. Don't add one.
  - `trailer_connected` is a CLAIM, not "something is on the fifth wheel": coupled AND
    `spec.trailer_bus_equipped` (the ISO 7638 data pair). False with a trailer physically attached
    is a real shipped state — the third state `implement_connected` teaches, and the whole of what
    `semi-conventional` is. A unit without the
    pair still tows and still brakes the trailer: the pneumatic lines are not the data pair, so
    `tick_towed` runs either way and only the publishing goes dark.
  - The two READ signals are read AFTER `tick_towed`, and the ordering is load-bearing.
    `trailer_axle_load` is `axle_load_kg(bogie_suspension_force())` — the same function the drive
    axle uses — and `trailer_abs` is the trailer's worst RayWheel slip past `TRAILER_ABS_SLIP`.
    `TruckVehicle` clears the whole bus every tick (`clear_trailer_bus`), so bobtail and every
    non-towing truck publish real zeros and `SemiTractor` only ever overwrites.
  - `trailer_brake_demand` reports the blend the trailer really brakes with. It takes
    `retarder_state` (what ran) not the request, so it inherits the speed fade; the retarder's
    share is `Drivetrain.RETARDER_MAX_FRAC`.
  - A coupled trailer draws air through the chassis' own reservoir model rather than beside it:
    `air_step` has an `aux01` second consumer (clamped separately from the pedal, then summed) and
    `SemiTractor._aux_air_draw` fills the trailer's reservoirs over `TRAILER_CHARGE_S`. Coupling
    costs AIR1 3 bar, past the low-pressure warn but not past the spring-brake gate — a brake
    application while it charges is what reaches the gate, and that is the designed catch-out.
    Spawn and respawn start the trailer CHARGED; every coupling made by driving starts empty.

## Tractor-unit variants, coupled lamps

- Two tractor units, one script, and the difference is a flag. `semi.tscn` (European cab-over) and
  `conventional.tscn` (North American bonneted) both run `SemiTractor` with their own spec; nothing
  about the tow, the joint, the trailers or the brakes differs. `trailer_bus_equipped` is true on
  one and false on the other, and that is the entire variant — SAE J2497 / PLC4TRUCKS puts trailer
  ABS on the POWER line because the connector over there has no data pair, so `trailer_abs_lamp`
  (flavor `j2497`, mirrored verbatim like the DM1 bits) is the whole North American trailer
  protocol. Both specs are hand-authored with no generator baseline, so the flag has to be right in
  the `.tres` or it is simply absent — and `false` is written out explicitly on the conventional,
  because a flag this load-bearing being *absent* and being *missing* must not look the same in a
  diff.
  - The conventional's drivetrain/brake/suspension/tyre block is `semi_spec.tres`'s verbatim,
    deliberately: `test_truck` walks catalog → scene → spec across the whole truck family, so
    sharing the numbers makes all of it hold by construction. Only geometry and the one flag
    differ; re-tuning one unit means re-checking the other.
  - A tractor-unit variant may not move the coupling plane. Every trailer in `TrailerCatalog` is
    authored with its ground at y = −1.05 against a plate top at y = 1.05, so the `Kingpin`
    marker's Y is shared geometry — change it and every trailer floats or buries. Its Z is free,
    but the kingpin-to-rearmost-cab-structure gap is not: the trailers' gooseneck swings on
    1.015 m, so the conventional's sleeper sits at exactly the cab-over's 1.15 m and `test_truck`
    pins it against that gap rather than a literal. A sleeper moved back is a rig that cannot turn.
  - A longer wheelbase gives the plate load a shorter lever on the steer axle, so the coupled
    conventional keeps more front axle load than the cab-over and is the forgiving one to reverse.
- A coupled rig lights at both ends, and it takes a second `LampSet`, not a second resolve root.
  `LampSet.setup(vehicle, spec)` already takes its resolve root as an argument, so `TowedBody` owns
  a `LampSet` of its own built from lamp paths on the TRAILER's spec, and `SemiTractor` drives it
  each tick (`apply_lamps`) from the lamp bits already on `VehicleInput`. Teaching the tractor's
  set a second root is wrong: one set would own nodes in two bodies with two lifetimes, and a
  trailer is dropped and freed on every E press. As it stands the materials are
  `material_override`s on the trailer's own meshes, so a drop takes them with it.
  - No contract change, and there must not be one — a trailer stop lamp is the same `brake_lamp`
    bit shown at the other end of the vehicle. No signal, no side channel, no local timer.
  - The trailers' `head_lamp_paths` stay EMPTY (no headlamps, no beam), so `lights` only ever picks
    the rear tier and the markers. `test_trailer` pins that, pins every declared path resolving to
    a `MeshInstance3D` in its own scene — `LampSet` tolerates a missing node silently, which is a
    dark trailer with nothing to say so — and pins one indicator lighting without the other.
  - The indicator is a lens of its own (`TurnLensL/R`, amber, stacked under the tail lamp on the
    same stay), because these lenses are hand-authored: the Kenney bodies' `TURN_FRAC` split costs
    the same four scene edits and only makes the stop lamp narrower. All four trailers share the
    rear-lamp geometry exactly.

## The four trailers

- Four trailers, not one new signal (roster and masses in `docs/heavy_vehicles.md` § Four
  trailers). What tells them apart is MASS, what they plug into the towing unit, and which
  tractor-side signals they move; ISO 11992 carries nothing about the body, so adding a signal to
  the `iso11992` flavor for a trailer is the mistake the set exists to make visible. `test_trailer`
  sweeps the catalog for unique masses the way `test_implement_catalog` sweeps device classes.
  - What a trailer CONSUMES is declared in code (`TowedBody.consumers()`, a `Consumer` bitmask —
    the `ImplementBase` rule), and the gating is `TowHost.tick_towing`, never the subclass: a towed
    body is never trusted to ignore drive or flow it never plugged in. Only the tipper declares
    anything (PTO | HYDRAULIC), and hydraulics imply the PTO that turns the pump — pinned.
  - The box declares nothing and that is its lesson, written into `box.gd`: on the trailer bus it
    is indistinguishable from the flatbed, on the tractor's signals it is a different vehicle. A
    test asserts the two declare identical consumers, so a future edit that tells them apart on the
    bus fails.
  - Both load models move a real `center_of_mass` (`set_load_offset_z`) and nothing else;
    `trailer_axle_load` and `axle_load` move as consequences. Never add a tipper or tanker term to
    either. `kingpin_share()` stays SPEC-based (it sizes the springs); `live_kingpin_share()` is
    the one that moves.
    - `set_load_offset_z` forces `CENTER_OF_MASS_MODE_CUSTOM` itself. RigidBody3D rejects the write
      in any other mode with an engine error rather than a wrong number, and the tests step these
      bodies without ever running `_ready`.
  - The tanker's surge is a labelled model, not fluid dynamics — one number chasing the trailer's
    own longitudinal acceleration with a lag, and the lag is the whole model. It declares no
    consumers: a surge is the payload, not a function.
  - The tipper's interlock is chassis state evaluated by the TRACTOR
    (`TowedBody.body_raise_allowed`, the crossing `RefuseBody.is_inhibited` makes; described in
    `docs/heavy_vehicles.md`). It refuses the raise
    direction only, clamped against `body_pos01()`, so rolling away with the body up HOLDS it
    rather than commanding it down onto whatever is under it, and no PTO freezes the body where it
    stands — a lost drive is not a retraction.
  - The tipper's valve command is `1.0 - input.hitch_request` — InputRouter's existing hitch toggle
    (the I key, and the touch TIP button) read in its TRANSPORT sense rather than as a height:
    `hitch_request` 1 is the transport pose, which for a mounted implement is raised and for a
    tipping body is DOWN. Hence the rig spawns with the body stowed under the toggle's
    `_hitch_up = true` default. No new input owner, no new signal — and `scv_flow` was deliberately
    not reused, because it is an `isobus` signal and this is a J1939 truck.
  - Every trailer control has a touch twin, offered by CAPABILITY rather than by family.
    `SemiTractor.attachment_controls()` answers off the same `TowedBody.consumers()` the gating
    reads, so a button cannot claim a connection the machine does not have, and `boot.gd` re-asks
    after every E press because cycling swaps a driven trailer for an undriven one without changing
    the body. `TractorVehicle.attachment_controls()` answers the same hook off the implement's own
    `ImplementBase.connections()` — one duck-type, both towing machines, and neither the shell nor
    the overlay learns what a trailer or an implement is. Its `lift` is unconditionally true where
    the semi's is a declaration: the three-point linkage is tractor anatomy, so it raises and lowers
    with nothing hanging on it.
  - The coupling refusal and the reactive fit check are described in `docs/heavy_vehicles.md`
    § Four trailers. What must not be undone here: a press that DROPS a trailer is never refused
    (both `cycle_implement`s ask whether the NEXT entry is a coupling before they ask about the
    speed — refusing anyway makes bobtail unreachable above walking pace); the fit check's contact
    test is exact rather than a threshold, because a semi-trailer stands on RayWheels and touches
    nothing at all in normal towing; and the predictive `collide_shape` version must not come back
    — the query returns the contacts it finds FIRST rather than the deepest, so no threshold both
    passes a grazed kerb and catches a hillside. `test_trailer` pins the assumption (no trailer may
    carry a wheel CollisionShape) and pins that contact monitoring is on, because that failure mode
    is silent. `TowedBody.collision_probes()` survives as an AUTHORING accessor with no runtime
    caller.
  - The spawn coupling is a plain countdown (`SPAWN_COUPLE_TICKS`), not a condition — a condition
    can fail to come true. Grounded-for-N-ticks leaves a rig driven off its marker at once, or
    spawned on rough ground, waiting for a quiet moment that never arrives and running bobtail
    forever. A counter always finishes, and the reactive fit check deals with a bad pose after the
    fact.
    - Same shape of mistake: the wait must never `return` early out of `_tick_extras`, which skips
      `tick_towed` — a trailer coupled with E *during* the wait then hangs off the joint with dead
      wheels. A trailer that exists is ticked, unconditionally.
  - A dropped trailer leaves the tree in the same call; only its memory is deferred. `queue_free`
    alone flushes at the END OF THE FRAME and physics steps run before that, so between a swap and
    the flush the level holds two trailers, both jointed to this tractor, interpenetrating at the
    same coupled pose — an enormous separation impulse. So `TowHost.uncouple` `remove_child`s both
    bodies first. Except from `_exit_tree` (`uncouple(false)`): `remove_child` fails outright while
    a parent is mid-removal, and nothing is coupling during teardown anyway.
  - The garage freezes and hovers its vehicle, so it must freeze the trailer too
    (`set_display_frozen`, duck-typed by `garage.gd` and handed straight to `TowHost`): the trailer
    is a separate RigidBody3D, so without this it is the one thing in the room still obeying
    gravity. The same flag exempts the rig from the fit check — a display rig must never decide it
    does not fit and put its own trailer down.
  - The tipper's tip-body collision is two authored poses and one swap, never a posed shape. A
    `CollisionShape3D` re-transformed every tick rebuilds the compound and re-derives the inertia
    tensor at 60 Hz, on the one body that is also writing its own `center_of_mass` — two churning
    physics properties on a jointed body is how a rig starts buzzing. So `tipper.tscn` authors
    `CollisionTipBody` (lowered) and `CollisionTipBodyRaised` (the same `BoxShape3D` swept
    `TIP_MAX_DEG` about the hinge), and `tipper.gd._swap_collision()` enables exactly one,
    switching at mid-travel with `RAISED_ON`/`RAISED_OFF` hysteresis so a spool parked on the
    threshold cannot dither the rebuild. The raised box is not optional: the interlock refuses the
    raise direction only, so driving away with the body in the air is a real pose that has to hit
    the bridge it looks like it should hit. Nothing interpolates between the two.
- E on the semi cycles its TRAILER, through the same duck-typed `cycle_implement()` the tractor
  uses: box → tipper → tanker → flatbed → bobtail. `TrailerCatalog` owns the order with `BOBTAIL` a
  real entry in it, not a special case wrapped around it, and bobtail is LAST so one press drops
  the trailer and the next picks it back up (`test_trailer` pins that, and that only the last entry
  wraps). The box is FIRST, so the rig spawns on the 3:1 mass ratio.
  - E and V are separate axes. They shared V once, and V then meant different things on different
    vehicles — and the tractor, one body so it could never hand back, was a dead end you could only
    leave through the garage. With E owning attachments, `cycle_implement()` is an unconditional
    `-> void` on both vehicles and nothing arbitrates.

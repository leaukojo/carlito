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
    asserts a 0.7–1.6 m/s² band per shipped spec.
  - **The band's floor tracks the TYRE, because the retarder is a fraction of a grip-derived
    brake.** Substituting `brake_torque = BRAKE_GRIP_FRAC * mu_long * m * g * r / 4` cancels mass
    and radius, so a two-driven-wheel truck retards at
    `RETARDER_MAX_FRAC * BRAKE_GRIP_FRAC * mu_long * g / 2` = 0.745 m/s² at the family's truck tyre
    (mu_long 0.80), whatever it weighs — hence the 0.7 floor. Raising `RETARDER_MAX_FRAC` to hold a
    higher figure is the wrong lever: it decouples an auxiliary brake from the grip it acts
    through, and the 1.6 ceiling then forces the hand-built units' `brake_torque` down, which
    re-derives all four trailers. The CEILING is unmoved for the mirror reason — those units'
    10500 Nm brake is fixed rather than grip-derived, so they sit at 1.46 m/s² at any mu.
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
  - The rig rests ~0.4° tractor nose-up / ~0.1° trailer nose-down on the flat, kingpin ~1.18 m over
    the road (`measure_semi_launch`'s P5 standstill; its P1 "static pose" is sampled 2 s after the
    spawn drop, still settling). That is the rear axle at 40 % travel against the steer axle's 32 %,
    on the rear's own `spring_rate_rear` (sized for the coupled drive corner, so a bobtail rides
    a few tenths nose-DOWN). The coupling datum (`KINGPIN_LOCAL.y`, the trailers' −1.05 ground)
    cannot level the tractor on its own — it only sets the trailer's own pitch.
  - The rear DAMPER follows the same per-axle logic as the spring: `damper_bump_rear` /
    `damper_rebound_rear` are set explicitly (24700 / 28800 on both tractor units) rather than left
    at `GroundDriveSpec`'s sqrt(rate-ratio) fallback, because that fallback preserves the FRONT's
    damping ratio at the BOBTAIL corner mass, not the coupled one. Sized for the coupled rear
    corner (~3.5-4.7 t depending which trailer is on the back) they hold zeta 0.30-0.40 laden and
    read ~0.5 (over-damped) bobtail — an unladen truck skating over bumps rather than pitch-rocking
    is the honest bobtail feel. `tests/test_trailer.gd` pins the laden band against the flatbed.
  - **Both wheelbases are sized by the LAUNCH, not by the silhouette.** The trailer's inertial
    pull at the ~1.05 m kingpin is a lever on the steer axle, and a short unit loses it: measured,
    a 2.1 m wheelbase lifted BOTH steer wheels clear of the road (0 N) through gear 1's
    peak-torque window (~1 s), bottomed the rear springs solid and put the joint on its 15° stop,
    which drives as "it drags on its rear wheels". The shipped 3.6 m (cab-over) and 4.4 m
    (conventional) hold ≥ 8.5 kN on the steer axle and under 4° of pitch — the floor across all
    four trailers and both units, worst on the cab-over pulling the flatbed (8512 N). It came down
    from 8.6 kN when the COM went up: a higher centre of mass is more launch transfer off the
    front, which is the point of the height and the reason this is the number to re-read after
    one moves. Shortening either wheelbase is a re-measure with `tools/measure_semi_launch.tscn`,
    never a styling edit.
  - The plate carries **Coulomb yaw friction** (`CouplingProfile.yaw_friction_nm`, 2000 N*m on the
    fifth wheel, 0 on the drawbar — a pin in an eye is nearly free), applied by
    `TowHost._apply_yaw_friction` as a torque pair about the chassis' up axis against the RELATIVE
    yaw rate. Besides tyre lateral grip it is the only thing damping trailer sway. Never a spring
    toward zero angle (that is a plate that steers), and never the joint's own angular motor:
    Jolt's 6DOF motor is a velocity TARGET, not friction, and it fights the yaw limit. One-tick
    clamped against a box-footprint yaw inertia proxy (`TowedBody.yaw_inertia`), which on any
    shipped trailer binds only below ~1e-4 rad/s — the anti-buzz floor, not part of the feel.
  - The YAW limit is a labelled model of trailer-against-cab contact, not a property of the plate,
    and it cannot be collision: the plate and the trailer's nose overlap while coupled, so
    `exclude_nodes_from_collision` must stay at its default true or the two bodies fight for the
    same space. Without it the rig folds to 130° and swings the trailer through where the cab is.
    `Articulation.JACKKNIFE_MAX_DEG` (75°) is the one constant the joint AND the fallback use.
- Tested mass ratio: 8 t tractor : 24 t box (3:1) shipped, 8 t : 25 t verified. Raising a trailer's
  mass past 3:1 is a re-tune needing re-verification, not a free number — `test_trailer` pins the
  ratio and the travel fraction, so it fails instead of shipping a rig on its bump stops.
  - The plate share (`kingpin_share`, pinned to a 25-30 % band in `test_trailer`) is the same on
    every trailer, and on a 4x2 it is the traction budget. A real van semi-trailer puts 25-30 % of
    its weight on the fifth wheel; below that a fifth of the trailer
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
  load, at the rear's own `spring_rate_rear` (`GroundDriveSpec`) rather than the steer axle's rate.
- A cab-over tractor unit is front-heavy bobtail (`center_of_mass.z = -0.92`, cab and engine both
  sitting over the steer axle, which is why real bobtails lock up so easily) and its coupled plate
  load lands mostly on the drive axle; the conventional shares the same shape on its own geometry.
  Both units' bobtail and coupled shares, and the coupled steer axle's own floor, are pinned in
  `test_trailer` (semi_spec.tres / conventional_spec.tres headers carry the formulas). Driving
  found the bias: further back, the coupled steer axle carried about a fifth of the rig's weight
  and both front wheels left the road under throttle in a corner — the floor `test_trailer` holds
  today is well clear of that fifth.
- **COM HEIGHTS AND ROLLOVER.** Every body in the family carries its centre of mass at roughly its
  real height, and that is the whole point: a laden rig leans, transfers load onto the steer axle
  under launch, and rolls over if you take a roundabout too fast.
  - Tractor units `center_of_mass.y` 0.90 = ~1.03 m over the road (the chassis origin rides 0.13 m
    up coupled; `measure_semi_launch`'s P5 prints `kingpin over road`, minus `KINGPIN_LOCAL.y`
    1.05, is how to read it back). Kenney `truck` family `com_y` 0.75. Trailers, over the road:
    box 1.60, tanker 1.50, tipper 1.30 parked, flatbed 0.90 — each derived in its own spec header.
  - `rollover_g = half_track / com_height` is the static tip-over threshold on a flat road, and a
    body ROLLS BEFORE IT SLIDES when that sits below its tyre mu (`mu_lat` 0.75 across the family):
    box 0.45, tanker 0.48, tipper 0.55, flatbed 0.80, bobtail unit 0.66. So everything but the
    flatbed and the bobtail is roll-first laden, which is the real machine and is lethal in real
    life. `BaseVehicle.is_overturned()` and the F3 overlay are how the driver finds out, and
    there is no auto-reset — they press R.
  - `measure_semi_launch`'s P7 (`trailer=` picks which one) PROVES the rollover but does not rank
    the trailers: a full-lock step at 40 km/h is past every threshold in the list, so all four roll
    at 0.84-0.94 g of measured lateral with the trailer through 71° and the tractor dragged to 68°
    — under the 70° latch, so the report reads "tractor no, trailer YES". Ranking them wants a
    lower entry speed or a ramped lock, which P7 does not have.
  - **THE NARROW TRACK IS THE COMPROMISE, NOT THE HEIGHT.** The wheel stations are x ±0.72 (steer
    axle and trailer bogie) and ±0.62 (drive axle) — a 1.44 m track where a real artic runs ~2.0 m
    — so every threshold above reads ~25 % lower than the real vehicle's. Widening it means moving
    every wheel station AND the visual wheels authored beside them (`Wheels` in each trailer
    `.tscn`, counted by `test_trailer`) on two tractor units and four trailers: a model change, not
    a number. **Never buy the threshold back by lowering a COM** — the levers are
    `GroundDriveSpec.anti_roll_rate` (0 on both units today) and `mu_lat`, the same order phase 3
    settled for the car family.
  - The joint's ±1.5° roll stop now carries a real overturning moment: a laden box past its 0.45 g
    takes the tractor over with it. The stop's solver overshoot went from ~0.08° to ~0.6° (2.09°
    measured mid-rollover) with it — expected while tonnes of trailer hang off the plate, and the
    number to re-read when a trailer's height or mass moves again.
  - **The speed taper was checked and deliberately NOT tightened.** `min_steer_frac` 0.21 x 24 deg
    leaves 5.0° of lock at the 25 m/s floor, and at 80 km/h that is ~1.2 g of steady-state demand
    against a 0.45 g laden threshold — so yes, a driver who asks for full lock at motorway speed
    rolls the rig. Tapering that away needs ~1.7° (`min_steer_frac` ~0.07), a rack that will not
    steer, and the tyre saturates at ~2.4° there anyway: the rollover comes from asking for more
    than the tyre can hold, which is the real failure mode. The notice and R are the answer, not a
    nannying rack.

## Trailer authoring, pulling away

- Trailer authoring: origin AT THE KINGPIN, ground at y = -1.05 — the implements' "origin on the
  lower pin line" convention, so the coupling datum is the origin and the coupled pose is one
  transform multiply. Wheel visuals live under `Wheels` in `spec.wheel_positions` order
  (`test_trailer` counts them against the spec; a mismatch is otherwise an invisible wheel). The
  trailer's `spec` is a plain `VehicleSpec` because that is what RayWheel consumes; its
  drivetrain/steering fields are unused, but its LAMP paths are live.
  - A semi-trailer is a GOOSENECK, structural rather than decorative: nothing of it may hang below
    the coupling plane over the tractor. The front 2.75 m is a raised neck whose underside is the
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
    gooseneck exposed, and its neck stops at that bulkhead rather than running on to the step-down,
    because a neck carried under a body whose floor is below the coupling plane stands up through
    it. The tanker's barrel is the family's one stated compromise (tanker.tscn's header).
  - The swing-clearance rule is geometry, not taste: every point ahead of the kingpin sweeps a
    circle of radius `sqrt(x² + z²)` that must fit inside the kingpin-to-cab distance (1.85 m), or
    the rig cannot turn. `test_trailer` sweeps every BoxMesh CORNER of every trailer, recursively
    and through nested transforms, rather than trusting a node name or an axis-aligned formula —
    which part is frontmost is not stable, and the tipper's body lives under a rotating pivot.
    All four land on the gooseneck at 1.50 m (1.49 on the box, whose neck is 1.88 wide); tipping
    only moves the body further from the cab.
- A rig pulls away on LOW-END torque, and that is the drivetrain, not the joint. Torque at rest is
  `torque_curve(converter_free_rpm) * throttle`, and the converter only revs to 1325 (a quarter of
  the way up the band), so nothing about peak torque or gearing helps until it is already rolling.
  Fix startability at the LOW END of the torque curve, never by reaching for the peak (which the
  retarder/brake chain caps anyway). The tractor units hold 975 Nm at idle and 1337 at stall,
  65-89 % of their 1500 peak. Part throttle still only creeps — correct for a laden artic, not a
  missing launch model.

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
    - And it reports the LAGGED application, not the tractor's blend: the trailer's chambers
      travel their whole stroke in `TowedBody.BRAKE_APPLY_S` (0.35 s) and vent in
      `BRAKE_RELEASE_S` (0.5 s), a rate limit so the blend stays the ceiling. That lag is what
      makes a rig push on the first application — the tractor dips, the trailer catches up a beat
      later. The HANDBRAKE is deliberately not lagged: spring brakes are a mechanical lock applied
      BY the loss of air, not a chamber being filled.
  - A coupled trailer draws air through the chassis' own reservoir model rather than beside it:
    `air_step` has an `aux01` second consumer (clamped separately from the pedal, then summed) and
    `SemiTractor._aux_air_draw` fills the trailer's reservoirs over `TRAILER_CHARGE_S`. Coupling
    costs AIR1 3 bar, past the low-pressure warn but not past the spring-brake gate — a brake
    application while it charges is what reaches the gate, and that is the designed catch-out.
    Spawn and respawn start the trailer CHARGED; every coupling made by driving starts empty.
    Measured (`measure_semi_launch`, both units): the draw runs the full 8 s whatever the pedal
    does, and the scripted stop-then-recouple sequence DOES reach the gate — AIR1 bottoms at
    2.92 bar in P6 and the rears pin for ~0.4 s (25 ticks on the cab-over, 21 on the
    conventional), seconds after the brake release, mid-throttle. The whole margin here is a TENTH
    OF A BAR, so a few hundred ms of extra pedal spends it — which is exactly what a truck tyre
    costs, mu_long 0.80 making that stop 0.3 s longer than a car tyre would. So a heavy stop
    followed straight away by a recouple really cannot be driven away from until the reservoir
    recovers, and any future change to stopping distance lands back here. Kept as designed — it is
    the catch-out the 2 bar band between `warn` and the gate exists to telegraph — and it never
    fires from spawn pressure without a recouple. No lamp for it — the notice below is the tell.
    The gate announces itself once per application through `GameState.notice`
    (`TruckVehicle.SPRING_BRAKE_NOTICE`), latched on the edge (`TruckTelemetry.spring_brake_notice_edge`)
    so it fires once and re-arms only once the gate releases — no lamp, no timer beyond the notice's
    own dwell.

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
    1.50 m, and `test_truck` pins EACH unit's own gap against that computed worst swing plus a
    margin, not one unit against the other's. A sleeper moved back is a rig that cannot turn.
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
    a `MeshInstance3D` in its own scene, and pins one indicator lighting without the other.
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
  - Both load models move a real `center_of_mass` (`set_load_offset`) and nothing else;
    `trailer_axle_load` and `axle_load` move as consequences. Never add a tipper or tanker term to
    either. `kingpin_share()` stays SPEC-based (it sizes the springs); `live_kingpin_share()` is
    the one that moves, and it is a Z question — the height term below leaves it alone.
    - `set_load_offset` forces `CENTER_OF_MASS_MODE_CUSTOM` itself. RigidBody3D rejects the write
      in any other mode with an engine error rather than a wrong number, and the tests step these
      bodies without ever running `_ready`.
    - The tipper moves Y as well as Z, because a load cannot stay at parked height under a floor
      that has lifted 42°: `TIP_COM_RISE_Y` 1.50 is derived from the same rotation about the rear
      hinge that `TIP_COM_SHIFT_Z` 0.90 implies (the derivation is in `tipper.gd`). It puts the
      raised body's load 2.80 m over the road, a 0.26 g rollover threshold — so driving away with
      the body up, which the interlock deliberately allows, now rolls the rig. The tanker's surge
      stays Z-only; a lateral slosh term is out of scope.
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
  - E and V are separate axes: V is always the body cycle, E always the attachment. One key for
    both means a key that does different things on different vehicles, and on a one-body machine
    a dead end you can only leave through the garage. With E owning attachments,
    `cycle_implement()` is an unconditional `-> void` on both vehicles and nothing arbitrates.

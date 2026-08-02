# Vehicles — gotchas & hard-won rules

Loaded when working under `src/vehicles/`. Project-wide rules stay in the root `CLAUDE.md`
(physics tick is **60 Hz + interpolation, locked**; vehicles consume one normalized
`VehicleInput` from `InputRouter`; telemetry is read out of the sim that produced the motion).

- **Changed a spec's gearing, mass, tires or wheel positions? Re-measure it** with
  `godot --headless --path . res://tools/measure_vehicles.tscn -- <variant>` (or `all`,
  which is minutes — background it). It reports 0-100 / quarter / settled top speed with the
  gear it lands in, flags ratios the vehicle can never reach, and runs a zero-steer
  straight-line tracking pass that catches a chassis that pulls. Dev tool, never CI, always
  exits 0. Details and the `Engine.time_scale` trap: `docs/systems.md` § Measuring a vehicle.
- **The free-body vehicles (boat, drone, plane) share `VehicleMath`** — `damped_force` /
  `clamped_damper` (the one-tick clamp in 1D and 3D), `yaw_torque`, `inertia_of`,
  `pitch_deg`, `roll_deg`. These were duplicated verbatim across the three and tested three
  times over; put a new shared free-body helper there rather than in a fourth copy.
- 60 Hz stability lives in `RayWheel`'s clamps (damper ≤ one-tick reversal, suspension
  force cap, low-speed slip floors + one-tick lateral force cap) plus the semi-implicit
  **spin** step in `_integrate_spin`, and the boat's probe clamps (derived spring k, one-tick
  damper, total force cap, `damped_force` for drag).
  **Don't remove or weaken any clamp; don't raise the tick.**
- **Wheel spin is integrated semi-implicitly, and must NOT become a clamp on the road
  reaction.** Tire force is huge next to the wheel's own inertia (`I / r²` ≈ 31 kg-equivalent
  on the tractor vs 1000 kg of corner mass), so an explicit step over-corrects and `omega`
  rings at the tick rate — invisible until `wheel_speed` / `wheel_slip` publish it. The fix is
  to divide the NET torque by `1 + reaction_stiffness` (the linearized backward-Euler step),
  not to cap the reaction term. Capping it leaves `drive_torque − cap` pushing at equilibrium,
  which walks the wheel to a steady slip the driveline never paid for: **measured** against a
  480 Hz reference run, a cap gave +20 % top speed on the car and +41 % on the tractor, while
  the semi-implicit step lands within ~2 % of the reference at 60 Hz with the ringing gone. It
  errs slightly SLOW in the transient (over-damped, because the stiffness estimate is a secant
  slope) — that is the correct direction for a stability device. `test_wheel_spin` pins the
  equilibrium invariant, the no-overshoot rule and the relax-as-delta-shrinks property.
- **The tractor's draft force is the only force a subclass puts on a wheeled chassis**, and it
  is deliberately ONE force: rated draft x depth x soil x speed ramp, applied at the hitch point
  from `_tick_extras`. `engine_load` / rpm sag / `wheel_slip` are then consequences of it — never
  add a draft term to any of them (that is the rule-3 fiction the force exists to avoid).
  - **The 60 Hz margin is the SPEED RAMP, not the one-tick cap.** Below `DRAFT_SPEED_REF` the
    model is exactly a linear damper (`F = -k*v`, `k = rated / DRAFT_SPEED_REF`), and an explicit
    damper is stable while `k*dt/m < 2` — at 12 kN on 4 t that is 0.025, and the feedback is
    negative so it cannot ring. The `damped_force`-shaped cap behind it is unreachable until the
    rating passes ~480 kN, and it bounds only the LINEAR impulse (the force lands ~1.3 m behind
    the centre of mass). `test_tractor` pins the damper margin against the shipped rating, so
    raising `draft_max_force` into the regime that needs an angular bound fails CI instead of
    shipping. Keep the ramp: a *constant* rearward force would shove a standing tractor out of
    the furrow.
  - **Working depth belongs to the IMPLEMENT** (`ImplementBase.tool_depth()`, measured off its
    own scene: plough shares 0.055 m, harrow tines 0.02 m), and the LIFT comes from
    `ThreePointHitch.ball_lift()` off the four-bar solve — so the picture and the number cannot
    disagree, per machine. One shared depth had the harrow reporting draft with its tines 35 mm
    in the air. Know before tuning: the balls travel 0.57 m, so a 0.055 m tool is in the soil for
    only the bottom **tenth** of the hitch stroke and `draft_force` reads near-binary. That is
    geometry — the lever for a wider depth sweep is the implement's authored reach, not the draft
    model.
  - "In soil" is splat channel 4 under the hitch point through
    `HeightmapTerrain.channel_weight_at` + `RayWheel.terrain_at` — the wheels' own cached-Image,
    nearest-surface-in-reach rule, so a plough over a bridge finds no soil.
  - The force is applied BELOW the centre of mass (hitch y ~ 0.21, com y = 0.35), so its own
    moment is nose-DOWN; the net nose-up, rear-loaded weight transfer comes from the tire drive
    reaction answering it at ground level. Don't "correct" the offset to chase the pitch.
  - `_tick_extras` poses the linkage BEFORE reading it for draft. Sizing the force from
    `ball_lift()` after `set_hitch` would be a tick stale; the ordering is load-bearing.
- **A brake TORQUE goes through RayWheel's brake path; a kinematic LOCK may be written after
  the tick. The truck needs both, and mixing them up cost a day.** The retarder is driveline
  behaviour, so it follows the diff-lock/MFWD pattern exactly — math on `Drivetrain`, applied by
  `BaseVehicle` into the driven wheels' `brake_t`, gated by `spec.retarder_equipped`. It is NOT
  a `_tick_extras` job: applied as its own `move_toward` after the wheels had ticked, it
  over-corrected on tick one, threw the driven axle to slip **1.0** and pulled **8 m/s²** —
  the "explicit step over-corrects" failure the wheel-spin note above describes. In the brake
  path the same model is stable at **1.33 m/s²** (garbage truck) to **1.42** (firetruck),
  settling at 0.024–0.029 slip.
  - **Quote the retarder's strength as ARITHMETIC, never as a remembered measurement** — the
    docs once claimed 1.3 m/s² while `RETARDER_MAX_FRAC` could only make 0.20. Flat-road
    retardation is `frac * brake_torque * rear_wheels / (wheel_radius * mass)` and nothing
    else: 0.20 of the garbage truck's 9583 Nm gives 1.33 m/s² at 8000 kg, and of the tractor
    units' 10500 Nm, 1.46. `test_truck` asserts that band per shipped spec.
  - **Consequence — the ceiling on the whole truck family's power:** the 1.6 m/s² top of the
    band caps `brake_torque` at 11520, and `brake > peak drive` then caps peak ENGINE torque at
    `4 * brake_torque / (gear1 * final * efficiency)`. That is why the tractor units peak at
    1500 Nm and not the 2300-2800 a real 32 t artic makes. Going higher is not a spec edit: it
    means the retarder stops being quotable as a fraction of the service brake.
  - `_lock_rear_diff` is not a counter-example: averaging two omegas and pinning omega to 0 are
    **kinematic** writes that can only remove energy. A torque is not.
- **The retarder's anti-lock rule is a SLIP limit, never a force limit.** `RETARDER_SLIP_TARGET`
  caps the one-tick spin change so the axle cannot be driven past 0.10 slip. A cap at μ·N·r
  looks equivalent and is not: it bounds the *saturated* road torque, which a locked wheel is
  already making, so it permits a full skid. This mirrors real hardware — SPN 520 rides ERC1,
  the EBS interface, because a driveline brake has no wheel-by-wheel modulation of its own.
  At the shipped rating the axle settles at **0.024–0.029** slip, under a third of the cap, so
  the cap is a backstop that makes a rating edit fail visibly, not the operating point.
  `test_truck` pins that margin off the spec's own grip curve and static rear-axle load.
- **Air pressure is a GATE, not a bar.** Two reservoirs (`TruckTelemetry.air_step`, one pure
  function used twice with different draw rates) charge only while running. Below
  `AIR_SPRING_BRAKE_BAR` (3) on **either** circuit the spring brakes apply and the rear `omega`
  is pinned to 0 — a mechanical lock, so a full-throttle standing start genuinely cannot move
  (a large brake torque would not do: first-gear drive torque exceeds `brake_torque` here).
  The contract's `warn` (5) is deliberately HIGHER — that is the low-pressure warning, so there
  is a band to stop in. The gate reads the **minimum** of the two circuits, which is the only
  thing that makes a dual circuit more than one signal published twice.
  - Consequence that looks wrong until you think about it: `Drivetrain` reads drive-wheel omega,
    so with the rears pinned the tach falls to idle however far the throttle is pressed. That IS
    the engine lugging against the brakes — don't "fix" it with a throttle cut, which would be a
    second model of the same thing.
  - **There is no ramp, and that is accepted:** losing the air while rolling locks the rear axle
    in one tick, so slip goes to 1 and the friction circle takes the rear lateral grip with it.
    Real spring brakes are held OFF by air and a supply failure applies them fully, so this is
    honest — and it is why the `warn` sits a whole 2 bar above the gate. Don't soften it into a
    gradual torque; a torque cannot hold this truck at all, which is why it is a pin.
  - **The gate does NOT zero `retarder_state`.** The retarder torque entered `brake_t` earlier in
    the same tick and RayWheel integrated it, so it really ran; the pin supersedes it rather than
    retracting it. Zeroing the signal would make it an echo of the gate instead of a read of the
    driveline — the `diff_lock_state` rule backwards.
  - The draw is **pedal position and nothing else** — not the handbrake (a real spring brake
    spends air being RELEASED), not the spring brakes applying, not speed or load. Recorded as a
    decision in `air_step`: extra terms nothing on the dashboard could distinguish.
- **`axle_load` is summed `RayWheel.suspension_force` over the rear axle, in kg** — a weight,
  never a mass lookup, so weight transfer and (later) a laden body move it as consequences.
  `retarder_state` likewise reads `BaseVehicle.retarder_torque_applied`, the `diff_lock_state`
  rule. SPN 520's negative convention is documented in the contract `desc`, not encoded: a
  `[-100, 0]` range would fill the generated bar backwards.
- **The garbage truck's refuse body is a SECOND NETWORK, and `RefuseBody` is the whole of it** —
  CiA 422 ("CleANopen") body signals reaching the J1939 chassis across a CiA 413 gateway. Pure
  logic, no nodes, so the state machine and the interlock are tested rather than described.
  - **SILENT REGEN TRAP.** `gen_kenney_vehicles.gd` rebuilds the entire `Model` subtree from the
    GLB every run, so a rig node added under `Model` is wiped by the next regen *while the run
    still prints success*. `TruckVehicle._find_rig` therefore finds `Model/arm` and
    `Model/body/trash` **by name** and poses them from code — **add no scene nodes under `Model`.**
  - **The geometry IS the declaration.** No `arm` mesh means no body unit, which is why the
    firetruck publishes honest zeros on all five body signals with an unchanged cluster. The
    implement rule (declared in CODE, never exported data) at its strongest: a `VehicleSpec` flag
    could claim a refuse body on a truck with nothing to show it.
  - `body_pos` is **written onto the arm and then read back off it** (`arm_angle_rad` →
    `_arm.rotation.x` → `arm_pos_pct`) — the `ball_lift()` discipline, so the number and the picture
    cannot disagree. **`ARM_STOW_DEG` / `ARM_DUMP_DEG` are both measured by DRIVING:** the arm's
    origin is its own AABB min corner rather than a hinge line, so it sweeps a wide arc about a
    corner of itself and −155° carried it **through** the cab. Shipped travel is roughly half
    that, and the stowed end sits 5° BELOW the authored pose (20° put the forks through the road)
    — so stowed is *not* the authored rotation of zero, and `arm_pos_pct` must never hardcode 0 as
    the bottom. `trash` is the pile in the hopper — its **authored** pose is a full hopper, and
    empty is one pile-height lower (read off `mesh.get_aabb()`, never a constant).
  - **`hopper_load` touches the chassis through `mass` and nothing else.** `axle_load` and
    `engine_load` then report the payload as consequences — the draft-force discipline. Never add a
    laden term to either. `center_of_mass` stays on the spec; a load that shifts the balance is the
    tanker's content.
    - **The two report it UNEQUALLY, and expecting otherwise reads as a bug.** `axle_load` is summed
      suspension force, so the payload lands on it the next tick. `engine_load` reaches it only
      through the rpm the drivetrain sags to, so it answers **under throttle and on a grade** — a
      loaded truck holding a steady speed on the flat reads the same load as an empty one (and per
      the non-monotone note below it can read *lower*). `axle_load` is the bar to watch after a dump
      cycle; verifying the coupling on `engine_load` means accelerating or climbing.
  - The interlock is the content: `is_inhibited` takes **chassis** state (road speed, parking brake,
    and `bus_up`, which carries the PTO) and its result is published on the **body** network. It
    **freezes the arm where it stands** rather than driving it home — losing the PTO mid-lift leaves
    the arm up, which is what happens. `Idle` and `Lower` both stow, deliberately, and an unknown
    command byte lands there too, so the bus fallback is the safe pose.
    - **A down bus inhibits, so `body_inhibit` is true through the whole of normal driving** (PTO
      out), which would light INHIB beside a BODY BUS lamp already saying it — over a refuse round,
      lit-with-the-bus-dark is 44 % of ticks and the informative case only 20 %. Fixed **on the
      dashboard**, which suppresses the lamp while BODY BUS is dark. Never quieten it by dropping
      the `bus` term from `is_inhibited` — the interlock would then claim an unpowered body may
      swing its arm, and the published signal has to stay the honest one.
  - `body_cmd` is an **InputRouter-owned cycle** (`_body_cmd`, X key) exactly like `_pto`/`_lights`,
    riding `VehicleInput`. Not the `boot.gd`/`cycle_implement()` shell duck-type — that shape never
    reaches `VehicleInput`. The `merge_local` line is **required**, not tidiness: that dict is built
    explicitly, so a missing key silently drops the keyboard edge while a touch source is registered.
  - Ceiling, so it is not rediscovered: the rig is a **front loader** — no separable tailgate, no
    body raise, no compaction blade, so no packer cycle, and **respawn is the only way to empty the
    hopper** (cargo goes, meters like `odo`/`engine_hours` stay).
- **The semi's fifth wheel is a REAL Jolt joint between two RigidBody3Ds, and it holds.** A
  `Generic6DOFJoint3D` built in code at the scene's `Kingpin` marker: linear X/Y/Z limited to
  `lower == upper == 0` (that is how a 6DOF joint says *locked*), yaw free to the jackknife stop,
  pitch ±15°, roll ±1.5°. **Measured by driving:** the kingpin-to-plate distance holds at
  **0.0000 m** settled, under a 24 kN push with a 40 kNm yaw torque, and through cornering at the
  articulation stop; its worst excursion is **11 mm** during a jackknife at 19 km/h, and **13 mm**
  when the tractor alone is teleported 60 m and drags the trailer bodily after it. The fallback
  (`Articulation.jackknife_step` + `pose_at_angle`) was **not taken** — written and tested so that
  taking it stays a decision; its cost is being deaf to trailer-side forces.
  - **Roll is deliberately ±1.5° and not 0**: a hair of compliance lets the solver settle instead
    of fighting the road every tick.
  - **THE PITCH LIMIT MUST COVER THE STEEPEST GRADE THE RIG CAN CLIMB, NEVER BOUND IT.** It shipped
    at ±8° on the theory that the limit stopped the trailer levering the tractor's rear off the
    road; it does the opposite. On its stop the two bodies are RIGID, so at a break of slope 24 t
    of still-level trailer picks the climbing tractor's drive axle up and the rig has no traction —
    reported as "the truck cannot pull the trailer up a slope", diagnosed as neither power nor grip.
    Sized by measurement: a sharp break onto the 25 % grade the drivetrain can climb swings the
    joint **-9.0° to +12.8°**, so 15° clears it (and matches a real plate's ±12-15°). Raising
    engine torque against this symptom does nothing — **check the articulation before touching a
    spec.**
  - **The rig rests ~5.9° nose-up on FLAT ground, and that is an open bug**, not the joint's doing:
    the tractor's kingpin rides 1.306 m over the road on its springs while every trailer is authored
    against a 1.05 m plate. It permanently spends a fifth of the pitch travel and it is why ±8° had
    only ~2° of headroom. Fixing it means moving the shared coupling datum (`KINGPIN_LOCAL.y` and
    every trailer's authored ground), so it is deliberately a separate change.
  - **The YAW limit is a labelled model of trailer-against-cab contact, not a property of the
    plate**, and it cannot be collision: the plate and the trailer's nose overlap while coupled, so
    `exclude_nodes_from_collision` must stay at its default true or the two bodies fight for the
    same space. Driving without it folded the rig to **130°** and swung the trailer through where
    the cab is. `Articulation.JACKKNIFE_MAX_DEG` (75°) is the one constant the joint AND the
    fallback use, so they cannot disagree.
- **Tested mass ratio: 8 t tractor : 24 t box (3:1) SHIPPED, and 8 t : 25 t verified** by
  re-speccing live. **Raising a trailer's mass past 3:1 is a re-tune needing re-verification, not a
  free number** — `test_trailer` pins both the ratio and the travel fraction each case uses, so it
  fails instead of shipping a rig on its bump stops. Re-measured behind all four trailers on level
  4 (full throttle 3 s, then a full brake application): the **kingpin holds to 0.0000–0.0003 m**,
  trailer bogies peak at **37–39 %** of travel and the semi's rear at **34–53 %**, and
  `trailer_axle_load` reads **11 461 kg (flatbed) → 19 766 kg (box)**. No clamp touched, tick
  unchanged. (Those axle loads predate the 27 % plate-share correction below and now read lower.)
  - **THE PLATE SHARE IS 27 % ON EVERY TRAILER, AND ON A 4x2 IT IS THE TRACTION BUDGET.** A real van
    semi-trailer puts 25-30 % of its weight on the fifth wheel; these shipped at 19-22 %, a fifth of
    the trailer simply not helping the one driven axle grip. Symptom was "it still struggles to
    climb" after the fifth-wheel pitch fix, and the diagnosis order is the lesson: the rig is
    **grip-limited, not power-limited**. Set by `center_of_mass.z` = 3.98 against the 5.45 m bogie
    centre. Moving it means re-deriving the bogie load, THAT trailer's `spring_rate` (weight onto
    the plate is weight off the bogie — the springs came DOWN), its load-apportioned brakes, and
    the tractor's own rear spring rate.
  - **Every trailer spec's `spring_rate` is sized off the load ITS OWN bogie carries**, not copied:
    145 000 / 197 000 / 218 000 / 249 000 N/m land all four at the same **36 %** of static travel
    despite a 10 t spread. Same for `brake_torque`, from one formula —
    `10500 * (per-trailer-wheel kN / 26.5 kN per tractor wheel)` — so every trailer brakes at the
    same fraction of what it carries as the unit pulling it; the reference is the TRACTOR's own
    `brake_torque`, so moving that means re-evaluating all four rather than leaving them behind.
    `handbrake_torque` follows the same load-apportioning at a flat quarter of each trailer's own
    service brake, which lands every rig on the same ~25 % holding grade. **That is where a rig's
    parking brake lives** — the trailers shipped with 0 at first, and 32 t held by the tractor's two
    driven wheels ran away on any real slope. Copying either number between trailers
    is how one ends up on its stops or over-braking into a jackknife.
  - **A jointed body's RayWheel clamps are sized ~25 % loose.** Every one-tick clamp scales with
    `corner_mass = spec.mass / wheel_count` (2333 kg on the flatbed), but the bogie only carries
    `1 − kingpin_share` of the mass — 1867 kg — because the rest is on the plate, so the caps allow
    ~25 % more force than the body they bound. No clamp was touched and none should be: the fix, if
    it ever measures, is the spec's own numbers. The tractor errs the safe way round (its rear
    carries the plate load, so its `corner_mass` is UNDERstated and its caps are tighter than
    needed).
- **Neither new spec may ride its bump stops, and the shipped Kenney trucks DO** (rear static
  26.3 kN/wheel against a spring that maxes at 0.32 × 65000 = 20.8 kN). So the semi is 240000 N/m
  and the flatbed 145000 — sized from the load each axle actually carries, which for the semi's rear
  is its own weight PLUS the plate load. `RayWheel` has one spring rate per vehicle, so this is a
  compromise between a light steer axle and a heavy drive axle.
- **A cab-over tractor unit is FRONT-heavy bobtail** (`center_of_mass.z = -0.15`, 52 % on the steer
  axle) — cab and engine both sit over it, which is also why real bobtails lock up so easily.
  Coupled, the plate's load lands 90 % on the drive axle. Driving found
  this: at `z = +0.10` the coupled steer axle carried **20 %** and both front wheels left the road
  under throttle in a corner, i.e. the rig lost its steering exactly when it needed it.
- **Two-body housekeeping, all of it load-bearing:**
  - The trailer is a child of the semi's **parent** (the level), never of the semi — a dynamic
    RigidBody3D under another body gets the parent transform applied on top of the one the physics
    server writes. `SemiTractor._exit_tree` frees it, or a variant swap leaves it in the road.
  - It couples on the **first physics tick**, not in `_ready`: `Level._spawn_vehicle` assigns
    `global_transform` / `spawn_transform` AFTER `add_child`, so `_ready` has nowhere to put it.
    Same shape as the `_terrains_found` guard.
  - Coupling **matches the trailer's velocity at the kingpin before the joint exists**, treating the
    rig as one body for that instant. Measured: re-coupling at 36.7 km/h costs 2 km/h and produces
    no gap at all; without it the solver is handed 14 t with the whole road speed as relative
    velocity.
  - Respawn **re-lays and stops** the trailer (the train's lesson) and resets its wheels — a
    RayWheel keeping last tick's compression across a teleport reports the jump as a suspension
    spike, which is this body's equivalent of the accel history the base clears. Verified from a
    75° jackknife at 18 km/h: the rig comes back at 0.3° and 0.3 km/h.
  - `get_camera_exclude_bodies` includes the trailer's RID (the train precedent) and
    `get_camera_framing` returns a longer, higher frame for the ~8.9 m combination.
- **Trailer authoring: origin AT THE KINGPIN, ground at y = -1.05** — the implements' "origin on the
  lower pin line" convention in the same shape, so the coupling datum is the origin and the coupled
  pose is one transform multiply. Wheel visuals live under `Wheels` in **`spec.wheel_positions`
  order** (`test_trailer` counts them against the spec, because a mismatch is otherwise an invisible
  wheel). The trailer's `spec` is a plain `VehicleSpec` because that is what RayWheel consumes; its
  drivetrain/steering/lamp fields are unused.
  - **A semi-trailer is a GOOSENECK, and that is structural rather than decorative: NOTHING of it
    may hang below the coupling plane over the tractor.** The front 1.35 m is a raised neck whose
    underside is the bolster plate, and the frame and deck step down behind the tractor's tail.
    Authored flat instead — one deck height end to end, 0.46 m below the plate — the deck and both
    frame rails ran straight through the tractor's frame rails, mudguards and fifth wheel. A real
    trailer has this shape for exactly this reason.
  - **Two boxes that TOUCH on a face plane z-fight; two that overlap never do.** The reported bug was
    the trailer's bolster plate and the tractor's fifth wheel authored into the same 0.95-1.05 slab,
    which flickered as one white slab. Stack coupling surfaces with a **2 cm gap** and let a
    trailer's own parts interpenetrate freely (the implements do). Same-body faces that merely rest on
    each other (plank on rail, foot under leg) are fine — those pairs face opposite ways, so
    back-face culling settles them.
    - **The rule is SWEPT, not remembered** (`test_no_two_boxes_share_a_face_plane_and_a_facing`):
      every axis-aligned BoxMesh pair in the semi and all four trailers, on all three axes, failing
      on a shared plane with a shared FACING (both minima or both maxima) over a patch ≥ 2 cm. The
      first pass shipped **56 such pairs in the box alone** (its rave and its side wall both ending
      at x = ±0.96, flickering as a 5.4 m stripe down each side); all five scenes are now at 0.
      **When the sweep fails, move the DETAIL part proud or inset by 1-3 cm** ("a lamp is a fitting,
      not an inlay") rather than shaving the panel it sits on; where two segments of one wall meet,
      BUTT them exactly (zero overlap → the faces point at each other → culling settles it).
  - **The gooseneck rule bites each new trailer somewhere different, and always the same way:**
    the box's floor is TWO panels (neck-top at y 0.25, deck at −0.16) because one flat floor ran
    through the tractor's fifth wheel; the tanker's barrel starts at z 1.05 with a pump cabinet on
    the gooseneck instead, because a 0.85 m barrel high enough to clear the bogie wheels still has
    its underside 0.19 m BELOW the coupling plane; the tipper's body starts at z 1.10 and leaves
    the gooseneck exposed, which is what a real bulk tipper looks like anyway.
  - The swing-clearance rule is geometry, not taste: every point ahead of the kingpin sweeps a
    circle of radius `sqrt(x² + z²)` that must fit inside the kingpin-to-cab distance (1.15 m), or
    the rig cannot turn. `test_trailer` sweeps **every BoxMesh CORNER of every trailer**,
    recursively and through nested transforms, rather than trusting a node name or an
    axis-aligned formula — the frontmost part has already changed once (the neck took over from
    the headboard), and the tipper's body lives under a rotating pivot. All four trailers land on
    the gooseneck at **1.015 m**; tipping only ever moves the body further from the cab.
- **A rig pulls away on IDLE torque, and that is the drivetrain, not the joint.** There is no clutch
  or converter model, so torque at rest is `torque_curve(idle) * throttle` and nothing about peak
  torque or gearing helps until it is already rolling. **Fix startability at the LOW END of the
  torque curve, never by reaching for the peak** (which the retarder/brake chain above caps
  anyway). The tractor units hold **975 Nm at idle, 65 % of their 1500 peak**, the shape of a real
  truck diesel; the first pass had 520 (a car curve scaled up) and a 32 t rig could not start on a
  grade. Part throttle still only creeps — correct for a laden artic, not a missing launch model.
- **The ISO 11992 trailer bus is FIVE signals, and how few that is IS the content.** Part 2 is the
  application layer for brakes and running gear only, so the whole boundary is a coupling claim,
  the demand out (EBS11), the ABS state back (EBS21), an axle load, and one injected fault in —
  against the body network next door, a whole second bus behind a gateway. **There is deliberately
  no `trailer_type`**: ISO 11992 publishes no body type, and which trailer is on the back shows
  through MASS and through which tractor-side signals it moves. Don't add one.
  - **`trailer_connected` is a CLAIM, not "something is on the fifth wheel"**: coupled AND
    `spec.trailer_bus_equipped` (the ISO 7638 data pair). False with a trailer physically attached
    is a real SHIPPED state — attached steel and bus silence, the third state `implement_connected`
    teaches — and it is the whole of what `semi-conventional` is. A unit without the pair still
    tows and still **brakes** the trailer: the pneumatic lines are not the data pair, so
    `tick_towed` runs either way and only the publishing goes dark.
  - **The two READ signals are read AFTER `tick_towed`, and the ordering is load-bearing.**
    `trailer_axle_load` is `axle_load_kg(bogie_suspension_force())` — the *same* function the drive
    axle uses, not a second model — and `trailer_abs` is the trailer's worst RayWheel slip past
    `TRAILER_ABS_SLIP`. Publishing before the trailer's wheels integrate would ship last tick's
    numbers. `TruckVehicle` clears the whole bus every tick (`clear_trailer_bus`), so bobtail and
    every non-towing truck publish real zeros and `SemiTractor` only ever *overwrites*.
  - **`trailer_brake_demand` is a report of the blend, and the blend is what the trailer really
    brakes with.** It takes `retarder_state` (what ran) not the request, so it inherits the speed
    fade; the retarder's share is `Drivetrain.RETARDER_MAX_FRAC` — arithmetic, not taste: the
    retarder at full is that fraction of the tractor's brake torque, so it asks the trailer for the
    same fraction of the trailer's.
  - **A coupled trailer DRAWS AIR, through the chassis' own reservoir model rather than beside it.**
    `air_step` gained an `aux01` second consumer (clamped separately from the pedal, then summed —
    two independent taps on one reservoir), and `SemiTractor._aux_air_draw` fills the trailer's
    reservoirs over `TRAILER_CHARGE_S`. Coupling costs AIR1 3 bar, which is past the low-pressure
    warn but **not** past the spring-brake gate — a brake application while it charges is what
    reaches the gate, and that is the designed catch-out. Spawn and respawn start the trailer
    CHARGED (the rig has stood coupled); every coupling made by driving starts empty.
- **TWO TRACTOR UNITS, ONE SCRIPT, AND THE DIFFERENCE IS A FLAG.** `semi.tscn` (European cab-over)
  and `conventional.tscn` (North American bonneted) both run `SemiTractor` with their own spec;
  nothing about the tow, the joint, the trailers or the brakes differs. `trailer_bus_equipped` is
  true on one and false on the other, and **that is the entire variant** — SAE J2497 / PLC4TRUCKS
  puts trailer ABS on the POWER line because the connector over there has no data pair to run a
  bus on, so `trailer_abs_lamp` (flavor `j2497`, mirrored verbatim like the DM1 bits) is the whole
  North American trailer protocol. Both specs are HAND-AUTHORED with no generator baseline behind
  them, so the flag has to be right in the `.tres` or it is simply absent — and `false` is written
  out explicitly on the conventional, because a flag this load-bearing being *absent* and being
  *missing* must not look the same in a diff.
  - **The conventional's drivetrain/brake/suspension/tyre block is `semi_spec.tres`'s VERBATIM,
    deliberately.** `test_truck` walks catalog → scene → spec across the whole truck family (the
    retarder band, brake > peak drive > handbrake, the slip-cap backstop margin, the
    loaded-suspension cap), so sharing the numbers makes all of it hold by construction. Only
    geometry and the one flag differ; re-tuning one unit means re-checking the other.
  - **A tractor-unit variant MAY NOT MOVE THE COUPLING PLANE.** Every trailer in `TrailerCatalog`
    is authored with its ground at y = −1.05 against a plate top at y = 1.05, so the `Kingpin`
    marker's Y is shared geometry — change it and every trailer floats or buries. Its Z is free
    (0.75 cab-over, 0.85 conventional), but the **kingpin-to-rearmost-cab-structure gap is not**:
    the trailers' gooseneck swings on 1.015 m, so the conventional's sleeper sits at exactly the
    cab-over's 1.15 m and `test_truck` pins it against that gap rather than a literal. A sleeper
    moved back is a rig that cannot turn.
  - A longer wheelbase is the honest upside of the silhouette: 3.00 m against 2.10 m gives the
    plate load a shorter lever on the steer axle, so the coupled conventional keeps **more** front
    axle load than the cab-over (41/59 against 43/57) and is the forgiving one to reverse.
- **Trailer marker lamps are static, unlit meshes.** `LampSet` resolves the spec's NodePaths from
  the vehicle root and the trailer is a separate body, so driving them needs either a cross-body
  path or a side channel — and the lamp rule forbids the side channel. Recorded as a gap.
- **FOUR TRAILERS, NOT ONE NEW SIGNAL — that is the content, not a shortfall.** Box (24 t),
  tipper (19 t), tanker (21 t), flatbed (14 t). What tells them apart is MASS, what they plug into
  the towing unit, and which TRACTOR-side signals they move; ISO 11992 carries nothing about the
  body, so adding a signal to the `iso11992` flavor for a trailer is the mistake the set exists to
  make visible. `test_trailer` sweeps the catalog for unique masses (the only thing on the wire
  that distinguishes them) the way `test_implement_catalog` sweeps device classes.
  - **What a trailer CONSUMES is declared in CODE** (`TowedBody.consumers()`, a `Consumer` bitmask
    — the `ImplementBase` rule), and **the gating is `SemiTractor._drive_trailer_body`, never the
    subclass**: a towed body is never trusted to ignore drive or flow it never plugged in. Only the
    tipper declares anything (PTO | HYDRAULIC), and hydraulics imply the PTO that turns the pump —
    pinned, the shape of draft-relevant-implies-a-depth.
  - **The box declares NOTHING and that IS its lesson**, written into `box.gd`: on the trailer bus
    it is indistinguishable from the flatbed, on the tractor's signals it is a different vehicle.
    A test asserts the two declare identical consumers, so a future edit that tells them apart on
    the bus fails.
  - **Both load models move a REAL `center_of_mass` (`set_load_offset_z`) and nothing else.**
    `trailer_axle_load` and `axle_load` then move as consequences — never add a tipper or tanker
    term to either (the draft-force / `hopper_load` discipline). Measured on the tipper:
    `axle_load` 7671 → 4969 kg, `trailer_axle_load` 15 063 → 18 103 kg over one tip. Note
    `kingpin_share()` stays SPEC-based (it sizes the springs); `live_kingpin_share()` is the one
    that moves.
    - `set_load_offset_z` forces `CENTER_OF_MASS_MODE_CUSTOM` itself. RigidBody3D **rejects** the
      write in any other mode with an engine error rather than a wrong number, and the tests step
      these bodies without ever running `_ready`.
  - **The tanker's surge is a LABELLED MODEL, not fluid dynamics** — one number chasing the
    trailer's own longitudinal acceleration with a lag, and the lag is the whole model. Real wave
    physics is a non-goal, the same rule that governs the boat's water. It declares no consumers:
    a surge is the payload, not a function.
  - **The tipper's interlock is CHASSIS state evaluated by the TRACTOR** —
    `TowedBody.body_raise_allowed(speed, parking_brake)`, the crossing `RefuseBody.is_inhibited`
    makes. Deliberately STRICTER than the refuse arm (which works at walking pace): a raised body
    is four metres of leverage, so it wants a genuine standstill. It refuses the **raise direction
    only**, clamped against `body_pos01()`, so rolling away with the body up HOLDS it rather than
    commanding it down onto whatever is under it. **No PTO freezes the body where it stands** — a
    lost drive is not a retraction. ISO 25200 / CiA 408 are declared as a naming reference in
    `tipper.gd` and NOT implemented.
  - **The tipper's valve command is `1.0 - input.hitch_request`** — InputRouter's existing hitch
    toggle (**the I key**, and the touch TIP button; H is the horn) read in its TRANSPORT sense
    rather than as a height: `hitch_request` 1 is the transport pose, which for a mounted implement
    is raised and for a tipping body is DOWN. Hence the rig spawns with the body stowed under the
    toggle's `_hitch_up = true` default. No new input owner, no new signal — and `scv_flow` was
    deliberately NOT reused, because it is an `isobus` signal and this is a J1939 truck.
  - **Every trailer control has a touch twin** (the web build is a first-class target): E is
    ATTACH, P is **PTO**, I is **TIP**, and the handbrake the interlock wants is HAND. PTO/TIP are
    offered by CAPABILITY, not by family — `SemiTractor.attachment_controls()` answers off the same
    `TowedBody.consumers()` the gating reads, so a button cannot claim a connection the machine
    does not have, and boot.gd re-asks after every E press because cycling swaps a driven trailer
    for an undriven one without changing the body. Unlike ATTACH they ARE bridge-hidden: `pto` and
    `hitch_pos` are contract IN signals, so sloppyCAN owns them while it drives.
    - **`TractorVehicle.attachment_controls()` answers the same hook**, off the implement's own
      `ImplementBase.connections()` — one duck-type, both towing machines, and neither the shell
      nor the overlay learns what a trailer or an implement is. Its `lift` is unconditionally true
      where the semi's is a declaration: the three-point linkage is tractor ANATOMY, so it raises
      and lowers with nothing hanging on it and `hitch_pos` is a real signal on a bare tractor.
  - **COUPLING REFUSES ON ONE THING — THE RIG MOVING — AND THE FIT CHECK IS REACTIVE.**
    `cycle_implement` requires a standstill (`COUPLE_SPEED_MS`, the same figure as
    `TowedBody.RAISE_SPEED_MS`) and says so with a `GameState.notice`; coupling at speed lays the
    trailer at a pose the tractor has already left, which read as "it refuses even though there is
    room". Nothing else is decided in advance: `_set_trailer` couples, and
    `_watch_fresh_coupling` then asks the engine, for `COUPLE_WATCH_TICKS` afterwards, whether the
    trailer's **body** is touching anything (`TowedBody.body_is_colliding` ->
    `get_colliding_bodies`); if it is, the trailer is taken away again with a `GameState.notice`.
    The signal is EXACT rather than a threshold because **a semi-trailer stands on RayWheels, which
    are raycasts and not shapes, so its collision body touches nothing at all in normal towing** —
    and the tractor is excluded by the fifth-wheel joint. One body contact right after a coupling
    means it was laid inside the world. `test_trailer` pins the assumption (no trailer may carry a
    wheel CollisionShape, or the rig would unhitch itself on the road) and pins that contact
    monitoring is on, because that failure mode is SILENT: no error, no contacts, every coupling
    accepted forever.
    - **The predictive version is gone and should not come back.** It was a `collide_shape` sweep
      of the candidate's own authored shapes at the coupled pose, with a penetration-depth
      threshold (`COUPLE_CLEARANCE`) and a contact budget. It failed both ways: the query returns
      the contacts it finds FIRST rather than the deepest, so it waved buried trailers through, and
      any threshold generous enough not to refuse a bogie grazing a kerb missed a hillside. A
      refusal also left `_trailer_id` untouched, so E did *nothing* and bobtail became unreachable.
      Coupling and then LOOKING is simpler and better informed.
    - `TowedBody.collision_probes()` survives as an AUTHORING accessor with no runtime caller —
      `test_trailer` uses it to assert each trailer's authored collision clears the ground and does
      not reach forward into the tractor, which is a real invariant of the scenes.
  - **THE SPAWN COUPLING IS A PLAIN COUNTDOWN (`SPAWN_COUPLE_TICKS`), NOT A CONDITION.** All it
    buys is the moment the chassis has risen on its own springs: on tick one the body is still
    exactly where the marker put it, so the coupled pose 5.45 m behind measures **0.160 m into the
    terrain on EVERY heightmap level**. It used to be "every wheel grounded for N CONSECUTIVE
    ticks", and that was the bug — **a condition can fail to come true.** Drive off the marker at
    once, or spawn on ground rough enough that something is always in the air, and the rig waits
    for a quiet moment that never arrives and runs bobtail forever. A counter always finishes, and
    the reactive check above deals with a bad pose after the fact.
    - Same shape of mistake: the wait must never `return` early out of `_tick_extras`. It did,
      which skipped `tick_towed` — so a trailer coupled with E *during* the wait hung off the joint
      with DEAD WHEELS: no suspension, no brakes, sinking into the ground. A trailer that exists is
      ticked, unconditionally.
  - **A DROPPED TRAILER LEAVES THE TREE IN THE SAME CALL; only its memory is deferred.**
    `queue_free` alone flushes at the END OF THE FRAME and physics steps run before that, so
    between a swap and the flush the level held **two** trailers, both jointed to this tractor,
    interpenetrating at the same coupled pose — an enormous separation impulse that threw the new
    one. So `_drop_trailer` `remove_child`s both bodies first.
    **Except from `_exit_tree`** (`_drop_trailer(false)`): `remove_child` fails outright while a
    parent is mid-removal ("Parent node is busy setting up children"), and nothing is coupling
    during teardown anyway.
  - **THE GARAGE FREEZES AND HOVERS ITS VEHICLE, SO IT MUST FREEZE THE TRAILER TOO**
    (`SemiTractor.set_display_frozen`, duck-typed by `garage.gd`). The showroom pins the body
    `FREEZE_MODE_KINEMATIC` 2.5 m off the floor so the orbit camera can look underneath — and the
    trailer is a SEPARATE RigidBody3D, so without this it is the one thing in the room still obeying
    gravity: 24 t hanging off the fifth wheel with no ground under its wheels, swinging on the joint
    (measured: kingpin **2.0 m** off the plate, 43 rad/s). That was "the trailer jumps around in the
    garage"; swapping trailers looked like a cure only because it re-laid the coupled pose. The same
    flag EXEMPTS the rig from the fit check above — the showroom hovers it on purpose, and a display
    rig must never decide it does not fit and put its own trailer down.
  - **The tipper's tip-body collision is authored for the LOWERED pose and does not follow the
    tip.** A `CollisionShape3D` re-transformed every tick rebuilds the compound and re-derives the
    inertia tensor at 60 Hz, on the one body that is also writing its own `center_of_mass` — two
    churning physics properties on a jointed body is how a rig starts buzzing. The body only rises
    parked, so nothing drives into the raised pose.
- **E on the semi cycles its TRAILER**, through the same duck-typed `cycle_implement()` the tractor
  uses: box → tipper → tanker → flatbed → bobtail. `TrailerCatalog` owns the order with `BOBTAIL` a
  real entry in it, not a special case wrapped around it, and bobtail is LAST so one press drops the
  trailer and the next picks it back up (`test_trailer` pins that, and that only the last entry
  wraps). The box is FIRST, so the rig spawns on the 3:1 mass ratio rather than a corner of it.
  - **E and V are separate axes, and the split is what keeps the hook simple.** They shared V once
    (the vehicle answered whether it had CONSUMED the press and `boot.gd` fell through to the body
    cycle when it had not). It worked, but V then meant different things on different vehicles, and
    the tractor — one body, so it could never hand back — was a dead end you could only leave
    through the garage. With E owning attachments, `cycle_implement()` is an unconditional
    `-> void` wrapping cycle on both vehicles and nothing arbitrates.
- `engine_load_pct` and `hours_step` live on **VehicleTelemetry**, not TractorTelemetry:
  `engine_load` (SPN 92) and `engine_hours` (SPN 247) are shared tractor/truck signals, so the
  model is one, not two.
  - **`pto_load` is the one term ADDED to a signal rather than emerging from the sim** — literally
    `load_frac += pto_load` (0.35 on both the tractor and the truck) while the PTO is engaged. The
    PTO costs no real engine torque, so the rpm does not sag and nothing else moves with it: a
    knowingly-cheap parasitic model, kept because one model beats two (the truck's chassis PTO
    reuses the tractor's). Know the shape before reading anything into `engine_load` on a PTO
    machine; if it is ever promoted to a real driveline drag, this is the term that GOES, not a
    second one added beside it. Contrast `hopper_load` (mass only, consequences downstream).
- **What an implement DECLARES is load-bearing, not documentation** — and it is declared in
  CODE, never exported data, so a scene edit cannot claim a connection the machine does not
  have. `Connection.ISOBUS_DATA` decides whether `implement_connected` / `implement_type`
  report a claim at all (a mechanical-only plough is attached steel and bus silence — the third
  state those two signals exist to distinguish); `PTO` / `SCV` decide whether drive and flow
  reach it, and **the gating lives in `ThreePointHitch`, not the subclass** — an implement is
  never trusted to ignore drive it never plugged in. Device classes must be unique across the
  catalog (`test_implement_catalog` asserts it) or `implement_type` cannot tell two machines
  apart, and draft-relevant implies a positive `tool_depth()`.
- **Implements are VISUAL ONLY**: no CollisionShape, no joint, no RigidBody anywhere in the
  subtree (nor in `ThreePointHitch`, which is tractor anatomy and stays whole with nothing
  attached). They are children of the chassis body, so they ride along for free. Authoring
  convention: **authored in the LOWERED pose with the origin on the lower pin line, where
  ground is y = −0.21** (the balls sit 0.21 m up fully lowered, 0.78 m raised); geometry lives
  in the `.tscn` and is *measured* off it (depths, gate strokes, shut poses), never duplicated
  as constants. New implement = instance `implements/headstock.tscn` rather than redrawing pins.
- **`spin_from_pto`'s `ratio` is COSMETIC and deliberately « 1.** 540 rev/min is nine turns a
  second, which at 60 fps aliases into a slow backwards crawl — the exact failure for a part
  whose whole job is making `pto_rpm` legible. Gear the *rendering* down; the published rpm
  stays the honest drivetrain number. Axis is per machine (harrow rotor transverse, mower and
  spreader discs vertical, the tractor's own stub about local Z).
- **`wheel_speed` reads the REAR axle only**, not "every driven wheel": the driven set changes
  when MFWD engages, so the latter would step the signal at the moment you engage the front
  axle with nothing about the motion having changed. The rear axle is also the one that digs
  in, so it is the axle `wheel_slip` should measure.
- **`pto_mode` 540/1000 are SHAFT speeds through a gearbox ratio off `PTO_RATED_RPM`** — the
  engine is never asked to run at a different speed for them. `test_tractor` pins the shipped
  gearing against the spec's redline so a redline edit cannot silently push `pto_rpm` into the
  contract clamp; an unknown byte falls back to 540.
- **Detached / absent-function signals publish a real 0 / false every tick, never a gap** —
  that is what keeps the cluster the same shape across implement swaps (and the dashboard
  pairs each request lamp with its state lamp, so "commanded but not engaged" is readable).
- **E cycles the tractor's IMPLEMENT (V is the body cycle, always), and the shell finds it by
  duck-typing** `cycle_implement()`. Keep it that way: `boot.gd` and `VehicleCatalog` must not
  learn that implements exist, and the tractor keeps exactly one catalog entry. `ImplementCatalog`
  owns the cycle order with DETACHED as a real entry in it, not a special case wrapped around it.
  The touch overlay's ATTACH button is the same hook — `boot.gd` duck-types the vehicle and hands
  `TouchControls.set_attachment_available()` a bool, so the overlay hides it where nothing tows
  without learning what an attachment is. It cannot be family-gated like PANTO or FLAPS: within
  `truck`, the semi tows and the garbage truck does not.
- **`guidance_curvature` overrides `steer`, and the arbitration lives ONLY in
  `InputRouter.arbitrate_bridge`** — same precedent as the boat's `rudder`, with the same
  presence rule: `bridge_source.gd` includes the key only when sloppyCAN actually sent it,
  because a commanded dead-straight 0 is a real auto-steer command and not an absence. No
  vehicle code knows it was steered externally. `scv_flow` has no local key at all (a spool
  valve has no keyboard analogue) and is gated by `running` like the PTO — the pump is
  engine-driven.
- `engine_load` is **not monotone in draft**, and that is honest rather than a bug: it is
  delivered torque over peak torque, so a sag toward the 1600 rpm torque peak raises it and a sag
  past the peak lowers it. Verify a draft pass above peak-torque rpm or the load bar will move
  the "wrong" way.
- `ChaseCamera` follows `get_global_transform_interpolated()` — never `global_transform`
  in `_process`; it stutters at the locked 60 Hz tick.
- Feel tuning is data-only (`*_spec.tres`); keep the hierarchy test green (brake > peak
  drive > handbrake; handbrake holds only below ~30% throttle). Drift comes from
  `handbrake_grip` (rear grip cut), not brake torque — the hierarchy test caps
  `handbrake_torque` too low to lock the rears.
- Vehicle subclasses use ONLY the two seams (`_make_telemetry()`, `_tick_extras()` — run
  last so drivetrain RPM + telemetry motion are current). Never fork `_physics_process`.
- BaseVehicle is zero-wheel-safe (boat spec: empty `wheel_positions`; keep its 6
  `gear_ratios` — `auto_shift` indexes up to byte 6).
- **The equal `axle_torque / driven_count` split IS an open differential** — equal torque to
  both half-shafts is the open diff's torque law, and the low-grip wheel spinning up is what
  the sim already does (the drivetrain reads the MEAN driven omega, so a spinning wheel drags
  rpm up and engine torque off the curve). Do not "fix" it into a per-wheel traction cap. The
  LOCK is the part that needed code: a locked diff is one rigid shaft, so
  `BaseVehicle._lock_rear_diff` pulls the rear pair onto `Drivetrain.locked_axle_omega` AFTER
  they integrate — sharing a spin speed makes them share a slip ratio, so the wheel with grip
  makes the bigger force. Averaging only shrinks the spread, so it needs no clamp of its own.
- `engine_load` is normalized against `Drivetrain.peak_torque(spec)` — the peak of the whole
  curve — **never** against the torque available at the current rpm. That denominator cancels
  exactly to throttle (`engine_torque(rpm) * throttle / engine_torque(rpm)`) and turns the
  signal into a second pedal-position readout that nothing but the pedal can move. Normalized
  against the peak it is rpm-aware, which is the only reason a real load (lugging, a PTO
  implement, a plough's draft) can show up in it — rpm sags honestly, and this follows.
- Vehicle-specific DRIVELINE behaviour is gated by a `VehicleSpec` flag defaulting **off**,
  never by a third BaseVehicle seam: `rear_diff_lockable` / `front_axle_engageable` are true
  only on the tractor's spec, so `VehicleInput.diff_lock` / `fwd_drive` are inert everywhere
  else — the same "other vehicles ignore it" contract the hitch/PTO fields have.
  Consequence: `w.driven` is **not** fixed at `_ready` for the tractor; MFWD rewrites the
  front wheels each tick, ahead of the driven-count loop so the split and the drivetrain's
  `drive_omega` both see this tick's axles.
- **A spec flag is only real on the spec the shipped SCENE loads.** The drivable tractor is
  `kenney/tractor-kenney.tscn` → `kenney/tractor-kenney_spec.tres`. This has bitten once:
  consolidating to one tractor body left `tractor/tractor_spec.tres` behind as an orphan, the
  driveline flags were added to the orphan, and diff lock and MFWD were dead in-game while the
  suite stayed green — the test had preloaded the same orphan by path. `test_tractor` now walks
  catalog → scene → spec instead of naming a file, and every Kenney-generated flag must ALSO live
  in `gen_kenney_vehicles.gd`'s family baseline or the next regen wipes it.
- The train (`src/vehicles/train/`) is a real BaseVehicle subclass like the boat: empty
  `wheel_positions`, the 6 `gear_ratios` kept (the reverser N/D/R rides the gear byte). It
  never forks `_physics_process` — it uses only the two seams. Locomotion is a 1D consist
  sim (`TrainSim`) on the level's rail curve; the loco is driven **kinematically**
  (`gravity_scale = 0`, the sim writes `global_transform` + linear/angular velocity each
  tick so `_update_telemetry` still reads honest motion — no derived fictions). Wagons are
  `AnimatableBody3D` followers posed by `TrainPlacement`. Aux systems (motor current,
  catenary sag, brake pipe) are honest labelled models in `TrainTelemetry`, not circuits.
  `TrainSim`'s coupler/brake clamps are 60 Hz stability — **don't weaken them**. Respawn
  re-lays the consist at `s = 0` via `_sim.setup(...)` (velocity-zeroing alone leaves it
  halted where it drifted). It self-places on a closed rail in `_ready` and ignores
  `VehicleSpawn` markers — see the rails note in `kit/CLAUDE.md` for the shared
  `find_closed_rail` walk.
- Contract signals key on the vehicle **family** (`signals_for_vehicle` looks up `"train"`,
  not the variant `"bullet"`): any pre-spawn fallback that has only a variant name must map
  it through `VehicleCatalog.family_of(...)` first, or the dashboard/bridge get an empty
  cluster. This bit `dashboard.bind()` and `level_baker.validate_spawns` — both now map.
- RayWheel is single-radius: the tractor's big-rear/small-front wheels are visual only
  (`wheel_visual_radius`/`_rear` + `RayWheel.visual_lift`, which keeps an over/undersized
  visual meeting the ground). Wheel scenes are radius-NORMALIZED (model scaled to radius 1);
  BaseVehicle scales each instance. Per-instance tweaks (scale, the right-side flip) ride the
  visual's CHILDREN — RayWheel overwrites the root transform every tick.
- Kenney lamp placement is **measured, never guessed**: a lens is not a named node (each
  vehicle is one merged mesh on a shared colormap atlas), so `gen_kenney_vehicles.gd`
  samples the atlas at every triangle's UV centroid and unions welded same-shade triangles
  into lens clusters (amber = front, red = rear). Each end's lens is then SPLIT along its
  width — inboard 65% = head/brake lamp, outboard 35% = turn indicator, since the kit paints
  no indicator of its own. The run prints a per-variant lens report; `fallback` means that
  end has no painted lamp (race, race-future, tractor-shovel, and every tractor rear) and
  the old body-box formula placed it — a guess, so `_fallback_lamp_y` overrides its HEIGHT per
  variant where driving showed the box centre wrong (the tractor's rear, whose body is mostly
  open frame between the big wheels — pinned at 1.22, and the model changing once already moved
  the box centre out from under it). Correct a fallback lamp THERE, never in the `.tscn`:
  `Lamps` is generator-owned, so a scene edit is wiped by the next regen. Filter candidates
  BEFORE merging or a lens fuses into a same-hue body panel (the firetruck is red all over).
- Kenney vehicle **hand-authored anatomy is preserved across regens, by whitelist**:
  `gen_kenney_vehicles.gd` writes only `Model` + `Lamps` (`GENERATED_CHILDREN`) and transplants
  every other direct child of the existing scene (`_existing_children`) — the hand-tuned
  `CollisionLower`/`CollisionUpper` box pair, and the tractor's `ThreePointHitch` instance. A
  whitelist of what the generator OWNS, never a list of what to save, so a hand-added node
  survives by default instead of vanishing by omission — the hitch (and every implement with it)
  was once silently dropped by a regen while the run still printed success. Only a brand-new
  variant with no scene yet gets a generated convex hull. Extras are **reparented** out of an
  instance loaded with `GEN_EDIT_STATE_INSTANCE`, not duplicated: `duplicate()` loses the
  scene-instance state, so `pack()` writes the instanced scene's own properties back out and the
  hitch lands carrying a `script=` that pins the vehicle scene to today's hitch script. Adding a
  new generated child means adding its name to `GENERATED_CHILDREN`, or the old one is
  transplanted alongside the new one. To reset a variant's collision to the auto hull, delete its
  collision nodes from the .tscn first, then regen.
- Turning a right-side wheel around is `Basis(Vector3.RIGHT, PI)`, **not** `Basis(UP, PI)`:
  in the wheel-root frame RayWheel builds, local Y is the AXLE, so a yaw just spins the wheel
  about its own axis and changes nothing visible. Verify rim direction by rendering both
  sides, never by reasoning about the basis.
- Splat-channel grip (`HeightmapTerrain.channel_grip` → `grip_at()`, sampled by RayWheel
  per contact) reads **cached decoded splat Images** — never `get_image()`/decompress
  per tick (the heightmap is cached the same way at runtime, for the surface test below;
  in-editor it still decodes per call so an external PNG edit shows up). The multiplier
  rides `mu_long`/`mu_lat`; the 60 Hz clamps stay untouched. Three rules that are easy to
  undo by accident: `grip_at` **pow-sharpens weights with the material's `blend_sharpness`
  exactly like the splat shader** (raw weights give every painted patch an invisible
  low-grip apron, and normalization alone makes a faint trace read as full effect);
  `channel_grip` is **clamped to [0, 1] on read** (>1 breaks the tuned brake > drive
  hierarchy, <0 inverts friction and skips the friction circle); and the wheel picks the
  terrain whose **surface is nearest the contact** within `RayWheel.SURFACE_GRIP_REACH`,
  never XZ alone — otherwise a bridge or ramp inherits the ice painted under it.
- Corollary: roads/tiles conformed onto terrain DO read the splat under the deck, so an
  unpainted road grips like grass (0.8), not asphalt (1.0). Fix is authoring, not code:
  RoadPath's **Paint splat under road** button and the palette dock's **Paint splat under
  tiles** button (`kit/helpers/splat_paint.gd`, tested) paint under the deck (roads:
  the PROFILE's `splat_channel` — asphalt/city 6, gravel 7; tiles: 6; paint is
  destructive AND additive — profile swaps don't repaint, repaints don't erase),
  biased to UNDERCOVER (paved width − 1 m inset for ribbons; actual mesh faces + 1 px
  8-neighbor erosion for tiles) so the paint never peeks past the deck — don't "fix" the
  inset/erosion to widen coverage. Bridges need nothing and are skipped on purpose: out
  of grip reach = neutral 1.0 = asphalt.

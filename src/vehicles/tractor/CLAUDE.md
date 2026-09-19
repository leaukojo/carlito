# Tractor & implements — gotchas & hard-won rules

Descriptive tour: `docs/heavy_vehicles.md`. `TowHost`, `TowedBody`, `Articulation` and the
two-body housekeeping are shared and live in `src/vehicles/base/` — rules in
`src/vehicles/CLAUDE.md` § Towing. What is in this folder is only what this family has.

- The tractor's draft force is the only force a subclass puts on a wheeled chassis, and it is
  deliberately ONE force: rated draft × depth × soil × speed ramp, applied at the hitch point from
  `_tick_extras`. `engine_load` / rpm sag / `wheel_slip` are consequences of it — never add a
  draft term to any of them (the rule-3 fiction the force exists to avoid).
  - The 60 Hz margin is the SPEED RAMP, not the one-tick cap. Below `DRAFT_SPEED_REF` the model is
    exactly a linear damper (`F = -k*v`, `k = rated / DRAFT_SPEED_REF`), stable while
    `k*dt/m < 2` — at 12 kN on the ballasted 5.5 t body that is 0.018 (was 0.025 at 4 t; R2's
    added mass only widens the margin), and the feedback is negative so it cannot ring.
    The `damped_force`-shaped cap behind it is unreachable until the rating passes ~480 kN and
    bounds only the LINEAR impulse. `test_tractor` pins the damper margin against the shipped
    rating, so raising `draft_max_force` into the regime that needs an angular bound fails CI.
    Keep the ramp: a *constant* rearward force would shove a standing tractor out of the furrow.
  - Working depth belongs to the IMPLEMENT (`ImplementBase.tool_depth()`, measured off its own
    scene), and the LIFT comes from `ThreePointHitch.ball_lift()` off the four-bar solve, so the
    picture and the number cannot disagree per machine. One shared depth had the harrow reporting
    draft with its tines 35 mm in the air. Know before tuning: the balls travel 0.57 m, so a
    0.055 m tool is in the soil for only the bottom tenth of the hitch stroke and `draft_force`
    reads near-binary. That is geometry — the lever for a wider depth sweep is the implement's
    authored reach, not the draft model.
  - "In soil" is splat channel 4 under the hitch point through
    `HeightmapTerrain.channel_weight_at` + `RayWheel.terrain_at` — the wheels' own cached-Image,
    nearest-surface-in-reach rule, so a plough over a bridge finds no soil. Channel 4 is
    "Field", NOT Dirt, and Auto-splat wipes it — `src/levels/CLAUDE.md`.
  - The force is applied BELOW the centre of mass, so its own moment is nose-DOWN; the net
    nose-up, rear-loaded weight transfer comes from the tire drive reaction answering it at ground
    level. Don't "correct" the offset to chase the pitch.
  - `_tick_extras` poses the linkage BEFORE reading it for draft. Sizing the force from
    `ball_lift()` after `set_hitch` would be a tick stale; the ordering is load-bearing.
- **Suspension IS the tyres, on purpose.** Shipped 260 kN/m front / 300 kN/m rear (2.57 Hz on
  the 1 t front corner, against a sedan's ~1.3 Hz), `rest_length` 0.12 m, `damper_bump`/
  `damper_rebound` 13/16 kN·s/m (ratio ~0.40-0.50 — a tyre has little hysteresis, but this
  models the whole axle). Static sag 3.8 cm sits at 31% of the 0.12 m travel, the same
  sag/travel fraction band the truck family targets. A real tractor rides on tyre compliance
  alone and jolts; stiff numbers and short travel are the picture, not a softening target.
  `_wheel_positions` re-derives the anchor Y (`WHEEL_RADIUS + rest_length - static_comp`), so
  the chassis origin still sits at ground level at equilibrium — only the wheel anchor moved
  (0.57 m -> 0.44 m). The implement/hitch geometry (`tool_depth()`, `ball_lift()`) is measured
  off its own scene, never off ride height, so it did not move with it.
- **Traction is ballast, never the torque curve.** Gear-1 wheel force outran rear-axle grip
  3.4x at the original 4 t / 50-50 split. Shipped `mass` 5500 / `front_weight` 0.38 (rear axle
  3.4 t, 33 kN at mu 1.0) drops the ratio to ~2.0 — real tractors solve exactly this with ballast
  weights and liquid-filled tyres, not a smaller first gear. The torque curve and `final_drive`
  stay untouched: idle torque is what pulls a drawbar trailer away from a standstill
  (`truck/CLAUDE.md` § Pulling away, the same law), so trimming it to match grip would break that.
  `brake_torque` / `handbrake_torque` / the draft 60 Hz margin are all recipe-derived from
  `mass`, so the regen re-derives them for free; the drawbar trailer's nose-weight fraction (12%
  of the TRAILER) is untouched. Top speed in 6th is rpm-bound, so ballast doesn't move it — only
  acceleration and the governor-droop grade climb do. MFWD still shares the one physics radius
  (a lead-ratio model would be wind-up, not feel); engaging the front axle now adds 38% of
  static weight's worth of grip at the moment draft calls for it, the honest reason the button
  exists.
- **The COM rides at 0.91 m over the road**, written as `com_y_frac` 0.35 of the body's own AABB
  top (2.60 m on the scaled body) rather than as a metre figure, so the `scale` above can move
  without silently flattening the machine again. Against the 0.70 m mean half-track that is a
  rollover threshold of ~0.78 g under lug mu 1.0 — the tractor TIPS before it slides on a side
  slope, which is the real machine and what a field edge teaches. The drawbar's +/-25 deg roll
  limit is what keeps a rutted trailer from levering it over; do not narrow it toward the fifth
  wheel's 1.5 deg.
  - **The COM height does not enter the steady-draft pitch balance.** At rated draft the body is
    in equilibrium: the drag at the hitch and the tyre reaction at ground level form a couple of
    F x h_hitch, so the transfer off the front axle is 12 kN x ~0.35 m / 2.115 m wheelbase =
    ~2.0 kN against a 20.5 kN static front (0.38 of 5.5 t) — the front keeps ~90 %, nowhere near
    a wheelie. What the raised COM changes is the TRANSIENT: the same 12 kN arriving as
    acceleration now has a 0.91 m arm. If a future rating unloads the front past ~70 %, the lever
    is the ballast split (`front_weight`), never the height back down.

- **The body ships at `scale` 1.35** (`gen_kenney_vehicles.VARIANTS`, multiplied into `KIT_SCALE`
  inside `_analyze`): 2.99 x 2.17 m on a 2.12 m wheelbase, so the 5.5 t spec (R2's ballast) sits
  on something the size of a tractor. Nothing about the level bounds that factor — the field fence leaves a 13 m
  gap — what bounds it is everything the scale does NOT reach: the linkage, the four implements
  and the 1.90 m farm tipper, which read one size class small behind it. Taking them up too is
  a separate job (`HitchLinkage`'s constants, six scenes, and the quoted 0.57 m stroke /
  0.055 m plough depth), not a follow-up this one left half done.
  - The **physics** radius stays 0.36 on both axles and must: RayWheel is single-radius, and
    `wheel_radius` is also `Drivetrain.road_radius`, so gear selection and the 40 km/h road gear
    ride on it. Only the VISUAL radii followed the body (0.66 rear / 0.44 front, with the tread
    half-widths, or the flush-X rule stops landing on the scaled station). The honest cost: the
    rear visual stands 0.30 m proud of its contact, so on a kerb the drawn tyre clips before
    the physics one does. Acceptable on a field machine.
  - The rear tyre is at its **ceiling** at 0.66 m: the tread is the surface `test_three_point_hitch`
    measures every implement against, and the spreader's hopper corner starts sweeping it just
    past 0.67 m. Growing it further means moving that hopper. A wider tyre eats its own growth
    inboard under the flush-X rule, so `wheel_x_out` 0.064 pushes both axles back out until the gap
    between the rears is where it was — the track came out ~5% wider, roll stiffness a tractor can
    have and nothing else.
  - Ride height needs no compensation at any scale, rate or `rest_length`: `_wheel_positions`
    derives the anchor Y from `WHEEL_RADIUS + rest_length - static_comp`, never off the model, so
    the chassis origin sits at ground level at spring equilibrium by construction.
  - The datum that holds the implements is the **lower-pin height over the road**, so the linkage
    keeps it whatever the body does. `ThreePointHitch` and `Drawbar` hang at **z = +0.3935** on
    the tractor scene — the offset that lands the hitch housing's back face on the hull's rear
    face — each still authored in its own frame. So a chassis coordinate is a scene coordinate
    plus 0.3935 (`Drawbar.PIN_LOCAL` 1.9935 against `Pin`'s 1.60), and `test_drawbar_trailer` /
    `test_three_point_hitch` compose the two rather than trusting either alone.
  - `test_three_point_hitch` models the rear tyre as the CYLINDER it is drawn as, not a box: at
    0.6075 m the box's corner region is where the spreader's hopper skirt legitimately passes.
- The tractor tows, and the towed thing is not an implement — `src/vehicles/tractor/drawbar.gd`
  + `trailers/farm_tipper.{gd,tscn}`. An implement is a VISUAL Node3D riding the chassis; the
  trailer is a second RigidBody3D on a real `Generic6DOFJoint3D`, and `ImplementCatalog` carries
  BOTH kinds in one E cycle. Rules that are easy to undo:
  - `ImplementCatalog.TOWED` is what routes an id, because `TractorVehicle._set_implement` has to
    pick a coupler BEFORE it instances anything. It is data and would rot silently, so
    `test_drawbar_trailer` sweeps it against each machine's own `connections()`. A new towed entry
    means both, or the test says so.
  - The datum is 0.40 m and must never be the semi's −1.05, which is a fifth-wheel PLATE height.
    The trailer is authored origin at the drawbar eye, ground at y = −0.40, against
    `Drawbar.PIN_LOCAL` which the runtime reads off the scene's `Pin` marker.
  - The pin is fixed, not swinging, and that is a decision: a swinging bar moves the hole while the
    joint stays anchored at a chassis-local point — the picture and the number disagreeing, the one
    thing `ball_lift()` and `body_pos` are both written to avoid.
  - Roll is the axis that makes it a drawbar: ±25°, against the fifth wheel's ±1.5°. A plate under
    a locked kingpin holds the trailer's roll to the tractor's; an eye on a pin does not, so a rut
    under one trailer wheel does not lever the tractor over. Pitch is ±20° under the fifth
    wheel's cover-the-grade rule. Yaw is `Drawbar.SWING_MAX_DEG` (90°) and
    **not** `Articulation.JACKKNIFE_MAX_DEG` — that 75° is a model of a semi against a CAB. 90 is
    derived: up to it nothing behind the eye reaches forward of the pin's own z-plane.
    `test_drawbar_trailer` sweeps every BoxMesh corner against the tyres and the chassis boxes.
  - A drawbar carries a nose weight (12 %), not a share (the plate's 27 %), so the tractor gets
    much less help gripping — and the road tipper's load-walk fraction is wrong here: a plate
    starts with a quarter and a pin with a tenth, so the same walk takes the nose weight past zero
    and leaves the trailer on its bogie alone. Size `TIP_COM_SHIFT_Z` by what it must LEAVE on the
    pin.
  - The tip runs off the SCV and declares no PTO, the whole difference from the truck's tipping
    semi-trailer: a truck has no hydraulic remotes so something must turn a pump ON the trailer,
    and a tractor already carries the pump. Same job, one fewer connection.
  - It declares in two vocabularies and they must agree: `consumers()` (TowedBody's, what `Drawbar`
    gates `set_valve` on) and `connections()` (ImplementBase's, what `TractorVehicle` publishes and
    offers buttons from). `test_drawbar_trailer` pins SCV ⟺ HYDRAULIC.
  - It claims NO bus address, and that is content rather than an omission: all four implements
    claim one, so this is the first shipped machine in the "attached steel, electronic silence"
    third state `implement_connected` / `implement_type` exist to distinguish. Giving it a device
    class would mean a contract bump to invent electronics a farm trailer does not have.
  - The coupling is `TowHost`, the same class the semi's fifth wheel is, so every rule in the truck
    section's two-body checklist is this machine's rule too, by construction rather than by copy.
    `Drawbar` is the pin's geometry plus a `CouplingProfile`; `TractorVehicle` keeps only the brake
    demand, the spool source, the catalog, its dual-vocabulary bridge and the camera framing.
  - The `Drawbar` instance is a direct child of the tractor scene ROOT, never under `Model`:
    `gen_kenney_vehicles.gd` rebuilds `Model`/`Lamps` from the GLB every run while still printing
    success (the `kenney/CLAUDE.md` whitelist rule).
  - Level 1's tractor spawn has scenery close behind it, so the first E there is refused by the
    reactive fit check with a notice. Pull forward a length; that is the check working.
  - A towed body that is never TICKED keeps its authored wheel-root transforms — a frozen display
    rig, i.e. the selector card and the garage. `farm_tipper.tscn` therefore authors its `Wheels/*`
    roots at their hubs; the four semi-trailers do not, and their cards show all six wheels stacked
    at the kingpin. Cheap to copy if anyone re-shoots them.

- What an implement DECLARES is load-bearing, not documentation, and it is declared in CODE, never
  exported data, so a scene edit cannot claim a connection the machine does not have.
  `Connection.ISOBUS_DATA` decides whether `implement_connected` / `implement_type` report a claim
  at all (a mechanical-only plough is attached steel and bus silence); `PTO` / `SCV` decide whether
  drive and flow reach it, and the gating lives in `ThreePointHitch`, not the subclass. Device
  classes must be unique across the catalog (`test_implement_catalog` asserts it) or
  `implement_type` cannot tell two machines apart, and draft-relevant implies a positive
  `tool_depth()`.
- Implements are VISUAL ONLY: no CollisionShape, no joint, no RigidBody anywhere in the subtree
  (nor in `ThreePointHitch`, which is tractor anatomy and stays whole with nothing attached). They
  are children of the chassis body, so they ride along for free. Authoring convention: authored in
  the LOWERED pose with the origin on the lower pin line, where ground is y = −0.21; geometry lives
  in the `.tscn` and is *measured* off it (depths, gate strokes, shut poses), never duplicated as
  constants. New implement = instance `implements/headstock.tscn` rather than redrawing pins.
  Every pivot's meshes fold into one `MergedMesh` (`StaticMeshMerge`, originals hidden): a script
  that moves one leaf MESH must list it in `static_merge_skip()`, and geometry sweeps skip merged nodes.
- `spin_from_pto`'s `ratio` is COSMETIC and deliberately « 1. 540 rev/min is nine turns a second,
  which at 60 fps aliases into a slow backwards crawl — the exact failure for a part whose whole
  job is making `pto_rpm` legible. Gear the *rendering* down; the published rpm stays the honest
  drivetrain number. Axis is per machine.
- `wheel_speed` reads the REAR axle only, not "every driven wheel": the driven set changes when
  MFWD engages, so the latter would step the signal at the moment you engage the front axle with
  nothing about the motion having changed. The rear axle is also the one that digs in, so it is the
  axle `wheel_slip` should measure.
- `pto_mode` 540/1000 are SHAFT speeds through a gearbox ratio off `PTO_RATED_RPM` — the engine is
  never asked to run at a different speed for them. `test_tractor` pins the shipped gearing against
  the spec's redline so a redline edit cannot silently push `pto_rpm` into the contract clamp; an
  unknown byte falls back to 540.
- Detached / absent-function signals publish a real 0 / false every tick, never a gap — that is
  what keeps the cluster the same shape across implement swaps.
- E cycles the tractor's ATTACHMENT (V is the body cycle, always), and the shell finds it by
  duck-typing `cycle_implement()`. Keep it that way: `boot.gd` and `VehicleCatalog` must not learn
  that implements exist, and the tractor keeps exactly one catalog entry. `ImplementCatalog` owns
  the cycle order with DETACHED as a real entry in it — and the DRAWBAR TRAILER as another, which
  is why `is_towed()` exists. **`first()` must stay a three-point implement**: the tractor spawns
  on it,
  and `measure_vehicles` reports its force figures against `spec.mass`, so a towed `first()` would
  silently measure a ~15.5 t combination against the 5.5 t tractor number — the `-- semi` trap. The touch
  overlay's ATTACH button is the same hook. It cannot be family-gated like PANTO or FLAPS: within
  `truck`, the semi tows and the garbage truck does not.
- `guidance_curvature` overrides `steer` in `InputRouter.arbitrate_bridge` only (presence rule:
  `src/input/CLAUDE.md`). **`scv_flow` has a local key (Q)**:
  it is the drawbar trailer's ONLY control, and with no key that is ten tonnes you can tow and
  brake but never tip. Owner is `InputRouter._scv`, the `_pto` pattern, and it is binary — both
  consumers slew internally, so a toggle gives the bridge's visible ramp without inventing a
  keyboard axis. It is still gated by `running` like the PTO (the pump is engine-driven). The
  truck's `retarder` stays keyless: it refines a pedal that already works.
- `engine_load` is not monotone in draft, and that is honest rather than a bug: it is delivered
  torque over peak torque, so a sag toward the 1600 rpm torque peak raises it and a sag past the
  peak lowers it. Verify a draft pass above peak-torque rpm or the load bar will move the "wrong"
  way.

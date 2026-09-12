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
    `k*dt/m < 2` — at 12 kN on 4 t that is 0.025, and the feedback is negative so it cannot ring.
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
    under one trailer wheel does not lever the tractor over. Pitch is ±20° under the same
    cover-the-grade rule the semi's ±8° failure taught. Yaw is `Drawbar.SWING_MAX_DEG` (90°) and
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
    success. This already ate the three-point hitch once.
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
  silently measure a 14 t combination against a 4 t number — the `-- semi` trap. The touch
  overlay's ATTACH button is the same hook. It cannot be family-gated like PANTO or FLAPS: within
  `truck`, the semi tows and the garbage truck does not.
- `guidance_curvature` overrides `steer`, and the arbitration lives ONLY in
  `InputRouter.arbitrate_bridge` — same precedent as the boat's `rudder`, with the same presence
  rule: `bridge_source.gd` includes the key only when sloppyCAN actually sent it, because a
  commanded dead-straight 0 is a real auto-steer command and not an absence. No vehicle code knows
  it was steered externally. **`scv_flow` has a local key (Q)**, reversing its bridge-only start:
  it is the drawbar trailer's ONLY control, and with no key that is ten tonnes you can tow and
  brake but never tip. Owner is `InputRouter._scv`, the `_pto` pattern, and it is binary — both
  consumers slew internally, so a toggle gives the bridge's visible ramp without inventing a
  keyboard axis. It is still gated by `running` like the PTO (the pump is engine-driven). The
  truck's `retarder` stays keyless: it refines a pedal that already works.
- `engine_load` is not monotone in draft, and that is honest rather than a bug: it is delivered
  torque over peak torque, so a sag toward the 1600 rpm torque peak raises it and a sag past the
  peak lowers it. Verify a draft pass above peak-torque rpm or the load bar will move the "wrong"
  way.

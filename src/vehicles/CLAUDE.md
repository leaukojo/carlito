# Vehicles — gotchas & hard-won rules

True of EVERY vehicle. Family rules are nested: `drone/CLAUDE.md`, `train/CLAUDE.md`,
`truck/CLAUDE.md` (trailers), `tractor/CLAUDE.md` (implements). Descriptive tour:
`docs/vehicles.md`, and `docs/heavy_vehicles.md` for truck / trailer / tractor.

## The two seams, and what `BaseVehicle` does not do

- Subclasses use ONLY the two seams (`_make_telemetry()`, `_tick_extras()` — run last so
  drivetrain RPM + telemetry motion are current). Never fork `_physics_process`.
- Every family earns its `BaseVehicle` subclass, because a method's ABSENCE on the base is
  behaviour. `boot.gd` sets `caps["tows"] = v.has_method("cycle_implement")`,
  `debug_overlay.gd` gates `artic` on `has_method("articulation")`, and
  `vehicle_select.gd:_show_preview` guards on `set_attachment` then reads `attachment_ids()`
  / `current_attachment()` unguarded. Hoisting the attachment axis onto the base gives every
  car an ATTACH button, an `artic` readout and a preview that wipes the remembered implement
  — whatever `TractorVehicle` and `SemiTractor` share must be a plain owned object they each
  forward to.
  - Before deleting a `has_method` guard, check the RECEIVER's static type, not just whether
    `BaseVehicle` defines the method. Of ~30 sites only `boot.gd:_capabilities`'
    `has_method("vehicle_capabilities")` was removable. `chase_camera.gd`'s two look dead and
    are not (`@export var target: Node3D`, plus a live `elif target is PhysicsBody3D`
    fallback), nor does `tow_host.gd`'s `has_method(&"respawn")`, which reaches a
    statically-`RigidBody3D` `_chassis()` by a `get_parent()` walk.
  - The other three subclasses stand on their own terms. The boat's buoyancy has one consumer
    (`WaterSurface` is named by no vehicle but `boat.gd`), so a `HullBuoyancy` would retire
    nothing — `BoatTelemetry`, the trim slew, the aground debounce and the `respawn` override
    stay. The tractor's `_tick_extras` ORDER is its content: pose the linkage, read it back,
    tow, draft, each step reading what the last wrote this tick. Every telemetry subclass
    keeps fields of its own, down to `PlaneTelemetry.flaps_actual`; a field hoists to the base
    only when it is family-agnostic body state (rule 4: `pitch`/`roll`/`altitude`/`vspeed`).
- There is no `FreeBodyDrive` and must not be. The three drag models share no shape: the boat
  is body-axis anisotropic (`drag_long` / `drag_lat` / `drag_yaw`, the lateral term at
  `keel_offset` so the hull heels), the plane isotropic on one coefficient plus a flap bonus,
  the drone WORLD-horizontal split from WORLD-vertical with the vertical gated on the motors
  turning — a common model is the rule-3 fiction. Force application differs too (four hull
  probes / a capped lift-stall curve / four per-rotor `apply_force`), the `@export` blocks are
  anatomy already beside their machine and overridden per scene, and `BaseVehicle` runs no
  buoyancy loop, stall curve or rotor mixer for anybody. Shared instead: `VehicleMath`,
  `BaseVehicle._gravity`, and the attitude/height telemetry `BaseVehicle._update_telemetry`
  writes off the body basis.
- Extract only where two sites are IDENTICAL, never merely analogous. The truck/train/drone/
  fuel "reservoir" bars look like one system and share no arithmetic.
  `VehicleTelemetry.engine_load_pct(..., pto_on, pto_load)` is the counterexample: one
  implementation tractor and truck call identically.
- `BaseVehicle._level_root()` is the one level lookup — a `carlito_level` group lookup
  filtered by `is_ancestor_of`, falling back to the outermost ancestor below the tree root so
  a test rig finds a terrain that is a SIBLING of the vehicle's parent. `_find_grip_terrains`
  and `TrainVehicle._find_rail` call it; a third world query calls it rather than copying it,
  and do not build a `LevelEnvironment` seam over them. Before adding a walk, check whether a
  collision layer already answers the question — `Layers.SOLID` omits `Containment`, which
  retired the drone's sensor-exclusion walk. `WindField.at` keeps its own lookup: static,
  standalone-tested, and returning `ZERO` for a node not under a level is its contract.
  - `_grip_terrains` is collected on the first physics tick and reused (`tractor._soil_at` is
    the second consumer). `BoatVehicle` collects its `WaterSurface` list the same one-shot way
    but keeps `contains_xz` per tick — that is what changes as the boat moves.
- Rejected, so they stop being re-proposed (beside the aux-model one under the four
  reservoirs):
  - `VehicleSpec.air_drive` / `.water_drive` sub-resources. `plane.tscn` and `drone.tscn`
    override none of their node `@export`s, so the node is already the single home; the boat's
    second home is `gen_boat_variants.gd`'s `VARIANTS` / `BOAT_BASE`, and a generated
    sub-resource is that home renamed. The multi-home problem needed a test instead:
    `tests/test_boat_variants.gd` pins the three shipped `.tscn`/`.tres` against the recipe
    (the `ef5b043` class of bug). An omitted `.tscn` line is not drift — Godot drops a property
    equal to its script default, so the suite compares effective values.
  - A polymorphic `spec.drive`: retires none of the ~11 null guards, adds a downcast to each,
    and renames a property across 31 `.tres` and ~30 read sites.
  - Splitting `Drivetrain` into gear selection + wheel-derived rpm. The gearbox is
    load-bearing on every family (direction latch, status bits, the train's `gear`); only the
    engine half is inert.
  - Extracting `DroneVehicle._tick_extras`, in either form: ~18 values cross stage boundaries,
    so a split needs a context object that does not exist or ~25 more member fields, and a
    `DroneFlightController` / `DroneArmingState` pair does not escape it — `armed` alone is
    read by the vertical-damper gate, the mode resolve, the demand block and the telemetry
    block. What DID extract is the five leaf subsystems (`DroneMotors`, `DroneSensorSuite`,
    `DroneHook`, `DroneGimbalMount`, `DronePack`): 51 private fields to 30, no ordering moved.
    See `drone/CLAUDE.md`.
  - Merging `TowedBody.Consumer` with `ImplementBase.Connection` — refused twice on the terms
    under Towing; both vocabularies cost ~10 lines in `farm_tipper.gd` and one test.

## What a `VehicleSpec` declares

- The ground drive is OPTIONAL and the boat / drone / train declare none, so `BaseVehicle`
  builds them no `WheelDrive` and everything outside the wheeled path reads it through
  `drive != null` or the forwarding getters. Keep their 6 `gear_ratios`: `auto_shift` walks
  toward byte 6 and `ratio_for_byte` INDEXES the array, so a short gearbox is an out-of-range
  read (both shift fns guard with `mini(TOP_GEAR, gear_ratios.size())`, but the boat still
  walks its box on road speed and publishes the gear byte in `status`).
- `com_z = 0` is not 50/50 — it is wherever Kenney put the body origin, which across the
  eighteen generated bodies lands anywhere from 36/64 to 61/39. Invisible while a car is
  all-wheel drive, decisive the moment a variant drives ONE axle. Declare `front_weight` (the
  fraction on the front axle) in the recipe and let `_com_z` measure it against that body's
  own axle line; reach for a raw `com_z` only where the body was hand-tuned by driving (the
  garbage truck). A spec with neither is not balanced, it is unexamined.
- `min_steer_frac` is not the setting; the degrees it leaves are. It multiplies each body's
  OWN `max_steer_deg`, so the same fraction on a truck's 22 deg rack and an open-wheeler's 40
  is two different cars — decide the absolute lock, then divide. Every wheeled vehicle
  declares a pair. The whole lock (`max_steer_deg`, `min_steer_frac`, `steer_falloff_speed`)
  lives on `GroundDriveSpec` and bodies with no steered wheel (train, boats, drone) omit it;
  `steer_speed` stays on `VehicleSpec` because it slews a rudder and a drone's yaw too.
  `WheelDrive` is the only reader of the three.
  - The taper is linear from a STANDSTILL, so lock lost at any two speeds is in the ratio of
    those speeds: halving it at road speed takes an eighth of it at a quarter of that. Hence
    the tractor's 0.55 rather than the 0.35 the road end alone would want — its working life is
    8-12 km/h headland turns. Check a slow body's WORKING speed.
  - The rack never limits a corner on any body: at each vehicle's own limiter the floor still
    asks 2.6-19x more lateral force than its `mu_lat` can hold. A falloff failing this check
    is too aggressive.
- Vehicle-specific DRIVELINE behaviour is gated by a `VehicleSpec` flag defaulting off, never
  by a third seam: `rear_diff_lockable` / `front_axle_engageable` are true only on the
  tractor's spec, so `VehicleInput.diff_lock` / `fwd_drive` are inert everywhere else — the
  same "other vehicles ignore it" contract the hitch/PTO fields have. Consequence: `w.driven`
  is not fixed at `_ready` for the tractor; MFWD rewrites the front wheels each tick, ahead of
  the driven-count loop, so the split and `drive_omega` both see this tick's axles.
- A spec flag is only real on the spec the shipped SCENE loads — `kenney/tractor-kenney.tscn`
  → `kenney/tractor-kenney_spec.tres`. An orphan spec once took the driveline flags, so diff
  lock and MFWD were dead in-game while the suite stayed green against that same orphan.
  `test_tractor` now walks catalog → scene → spec instead of naming a file, and every
  Kenney-generated flag must ALSO live in `gen_kenney_vehicles.gd`'s family baseline or the
  next regen wipes it.
- `has_engine` is decoration and only decoration: it gates the `Gears` / `Redline` /
  `Peak torque` readouts on the garage wall (`garage.gd`) and the `Gears / Redline` line on
  the selector card (`vehicle_select.gd:_spec_text`), and no physics. `Drivetrain` runs for
  every family, because the gear byte is the direction latch `InputRouter.arbitrate_local`
  reads and the source of `ST_REVERSE` / `ST_NEUTRAL`. False on `drone_spec.tres` and
  `train_spec.tres` only; the boat keeps the default, since an outdrive really does have
  forward, neutral and reverse. Declared rather than inferred from `ground_drive == null`.
  - Accepted compromise: the wheel-less bodies run an engine model nothing can observe. With
    no `WheelDrive` the drive omega is 0, so the limiter can never fire, `applied_throttle`
    collapses to `|throttle|` and the smoothed `rpm` reaches no contract. Inert: the TORQUE
    CURVE, the redline, and (boat and drone, which publish no `gear`) which of D1–D6 the box
    lands in. The GEARBOX is not. Undoing it is the `Drivetrain` split rejected above;
    `has_engine` keeps the inert half off the garage wall and the selector card.
- A feel change edited into a generated scene must be edited into its recipe in the same
  commit — the generator is the source, the scene is output. `ef5b043` folded the removed
  `physics/3d/default_linear_damp` into the three boats' `.tscn` drag coefficients and left
  `tools/gen_boat_variants.gd` short by each hull's own `mass * 0.1`, so the documented regen
  path silently gave every boat ~20 % more top speed and a slacker keel.
  - `tests/test_boat_variants.gd` (the three watercraft) and `tests/test_kenney_variants.gd`
    (the eighteen Kenney bodies) hold both generators. A failure there is never fixed in the
    `.tres`: fold the driven value into the recipe and re-run the generator, because the
    derivations downstream move too and until they do the shipped spec is internally
    inconsistent. From one hand-edit (`91509c2`): `race`'s grip went to mu 1.35/1.40 while
    `brake_torque` stayed sized for 1.2 (905 against the derivation's 1019), and
    `suv-luxury`'s `torque_mul` went to 1.54 while `handbrake_torque` stayed sized for 1.10.
  - The Kenney suite re-derives rather than transcribes, so it tests the recipe and not the
    output: the brakes via `_derive_brakes` on a copy of the shipped spec, the torque curve by
    scaling the baseline, and `drag_area` / `com_z` / the four wheel stations by re-running
    `_analyze` over the variant's own GLB (~0.3 s for all eighteen). That catches a model
    re-import nobody re-ran the generator for.
- Feel tuning is data-only (`*_spec.tres`); keep the hierarchy test green (brake >
  transmissible drive > handbrake; handbrake holds only below ~30% throttle). Drift comes from
  `handbrake_grip` (rear grip cut), not brake torque — the hierarchy test caps
  `handbrake_torque` too low to lock the rears.

## Drivetrain and brakes

- The rev limiter judges `wheel_engine_rpm` (unclamped), never `Drivetrain.rpm`: the published
  rpm lerps toward an already-redline-clamped target, and in IEEE double that lerp's fixed
  point sits just below the target, so `>= redline_rpm` against it is dead code.
  `wheel_engine_rpm` (raw, what the wheels impose on a clutch-less crank) drives
  `limiter_cut`; `rpm_from_wheel` (its clamp) drives the needle and the `rpm` bridge signal.
  - The cut rides `applied_throttle` beside the governor's, so engine_load / fuel / coolant
    see it for free. `engine_torque` is the curve and nothing else.
  - A curve may end nonzero, and 20 of the 26 shipped specs do — the limiter is what stops the
    engine. The six ending at `(redline, 0)` (the five 3200-rpm heavies and `tractor-kenney`)
    are belt-and-braces and the right shape for a governed diesel, whose top gear is governed
    rather than drag-limited. Restoring tails there would move shipped, driven-and-tuned top
    speeds for nothing; settled, not open.
  - A hard cut, deliberately. Any fade band wide enough to see would eat real torque below the
    redline, and `sedan-sports` settles only ~110 rpm under its.
  - The limiter shows up at the launch, not only at the top end: `process` reads the SPINNING
    drive wheels' mean omega while auto-shift decides on ROAD speed, so a car spinning its
    wheels in first holds gear 1 with the crank past the redline and the fuel cut — about a
    second to 100 on the heavy, wheel-spinning bodies, all of it in the 0-50 split. If a launch
    feels lazy, the lever is the LAUNCH (grip, gear 1, `shift_up_rpm`), not the limiter.
- The plane is single-speed by construction, true by accident of two numbers:
  `plane_spec.tres` ships `shift_up_rpm` 6000 against `redline_rpm` 5400, and `auto_shift`
  judges the redline-clamped `rpm_from_wheel`, so the box never leaves gear 1. The published
  `gear` byte is a constant 1 in D, honest for a fixed-pitch light aircraft; dropping the shift
  point to 5000 would hand it a working gearbox and change a published wire signal for nothing
  physical. `tests/test_plane.gd` pins both halves; the six `gear_ratios` stay.
- A road-speed governor can strand the gearbox, and auto-shift cannot fix itself:
  `spec.speed_limit_kmh` cuts fuel while auto-shift decides on RPM, so a limit below the road
  speed of the next upshift means the taller gear never engages. `Drivetrain.governed_upshift`
  is the fix — against the limiter, take the tallest gear that still turns the engine above
  `shift_down_rpm`, and that guard is what stops it lugging a slow-governed vehicle. Declaring
  a new limit means re-measuring that variant and checking for the gear-N-of-6 note.
  - The gear-selection scale is `Drivetrain.road_radius`, DECLARED — not a wheel field reached
    for. Auto-shift and `governed_upshift` both decide on `ground_speed / road_radius`, the one
    wheel number a wheel-less body needs: the boat and the train walk a gearbox and publish the
    gear byte in `status`. `_init` copies it off the ground drive's `wheel_radius` or takes
    `DEFAULT_ROAD_RADIUS`, which let the wheel fields leave `VehicleSpec` without moving
    anyone's shift points. `governed_upshift` is static, so it takes the radius as
    `p_road_radius` — a parameter named `road_radius` shadows the field, and shadows are errors
    here.
- The equal `axle_torque / driven_count` split IS an open differential, and the low-grip wheel
  spinning up is what the sim already does (the drivetrain reads the MEAN driven omega, so a
  spinning wheel drags rpm up and engine torque off the curve). Do not "fix" it into a
  per-wheel traction cap. The LOCK is the part that needed code: a locked diff is one rigid
  shaft, so `WheelDrive._lock_rear_diff` pulls the rear pair onto
  `Drivetrain.locked_axle_omega` AFTER they integrate — a shared spin speed means a shared slip
  ratio, so the wheel with grip makes the bigger force. Averaging only shrinks the spread, so
  it needs no clamp of its own.
  - Consequence: an open diff caps an AWD car at its LIGHTEST driven wheel, so an AWD body
    wants a ~50/50 weight split in this model — a rear bias measured a full second of 0-100 on
    `race-future`. A torque-biasing centre diff would be a real feature, not a fix. Re-measure
    the PAIR before quoting any gap.
- Every Kenney `brake_torque` comes from the TYRE, not the gearbox:
  `gen_kenney_vehicles.BRAKE_GRIP_FRAC` (0.95) times the static per-wheel grip torque on all
  four baselines, one derivation with no per-family knob. It collapses to "full pedal asks for
  `0.95 * mu_long * g`" whatever the body weighs. Past the tyre ceiling RayWheel's slip tyre is
  saturated, so an over-sized brake buys nothing but a wheel lock with no steering under
  braking.
  - The hierarchy is `brake > TRANSMISSIBLE drive`, i.e. against
    `min(peak drive, driven_wheels * mu_long * N * r)` and not raw gearbox output —
    `brake > peak drive` and `brake <= grip` cannot both hold on a body geared deeper than its
    tyres. Authoritative statement:
    `test_vehicle_catalog.test_kenney_specs_keep_force_hierarchy` (the "§6" name older comments
    use is inherited from a spec document, not a live rule). Two-driven-wheel bodies clear it
    by 1.9x; an AWD body whose engine saturates all four is the only shape that cannot.
  - `OVER_BRAKED` is empty, but keep the shape in mind — four driven wheels on a close-ratio
    first put the hierarchy floor over the tyre by construction, unfixable with any brake
    number. The lever is gear 1 or torque, and shortening gear 1 costs nothing measurable,
    since a deep first on a traction-limited body is spun away rather than delivered.
    Re-derive the ceiling per body. It sweeps only the generated Kenney specs: the hand-built
    semis are not grip-derived, since grip-deriving them would drop `brake_torque` far enough
    to take the retarder with it.
  - This decoupling is what makes the car gearbox's deep first and the tractor's crawler free:
    a deep first costs a bigger HANDBRAKE (`launch_25`) and nothing else.

## Wheels, suspension and the 60 Hz tick

- 60 Hz stability lives in `RayWheel`'s clamps (damper ≤ one-tick reversal, suspension force
  cap, low-speed slip floors + one-tick lateral force cap) plus the semi-implicit **spin** step
  in `_integrate_spin`, and the boat's probe clamps (derived spring k, one-tick damper, total
  force cap, `damped_force` for drag). Don't remove or weaken any clamp; don't raise the tick.
- Suspension force acts along the CONTACT NORMAL (`hit.normal`), never the chassis' up axis.
  Pushing along the body's own up tips part of the vertical load into the direction of travel
  whenever the chassis sits nose-up or nose-down, so a body thrusts itself along (or drags
  itself back) with its own springs — hundreds of newtons. The term vanishes on flat ground.
  - Resistance and the drivetrain are both measured innocent; stop re-suspecting them.
    Resistance applies what the spec's `0.5*rho*Cd*A*v^2 + crr*N` owes to within a newton, and
    summed tire force matches `axle_torque / r` to within two.
  - `measure_vehicles`' `balance` line is the regression check: `tyres - resistance + rake`
    closes on the body's own measured acceleration to a newton or two; if it stops closing
    there is a NEW force unaccounted for. `Wheel.force_long` and `Wheel.contact_normal` are
    diagnostic fields the tool sums — nothing in the sim reads either. `rake` is not an
    artefact term: on a grade the contact normal genuinely tilts with the slope, so it should
    read ~0 N only on the flat.
  - Trailers get this for free: `towed_body.gd` never repeated the force, since
    `bogie_suspension_force()` sums the same `Wheel` objects.
- Wheel spin is integrated semi-implicitly, and must NOT become a clamp on the road reaction.
  Tire force is huge next to the wheel's own inertia (`I / r²` ≈ 31 kg-equivalent on the
  tractor against 1000 kg of corner mass), so an explicit step over-corrects and `omega` rings
  at the tick rate, invisible until `wheel_speed` / `wheel_slip` publish it. Divide the NET
  torque by `1 + reaction_stiffness` (the linearized backward-Euler step); do not cap the
  reaction term, which leaves `drive_torque − cap` pushing at equilibrium and walks the wheel
  to a steady slip the driveline never paid for. Against a 480 Hz reference a cap gave +20 %
  top speed on the car and +41 % on the tractor, while the semi-implicit step lands within
  ~2 % at 60 Hz, erring slightly SLOW in the transient — the correct direction for a stability
  device. `test_wheel_spin` pins the equilibrium invariant, the no-overshoot rule and the
  relax-as-delta-shrinks property.
- RayWheel is single-radius: the tractor's big-rear/small-front wheels are visual only
  (`wheel_visual_radius`/`_rear` + `RayWheel.visual_lift`, which keeps an over/undersized
  visual meeting the ground). Wheel scenes are radius-NORMALIZED (model scaled to radius 1);
  BaseVehicle scales each instance. Per-instance tweaks (scale, the right-side flip) ride the
  visual's CHILDREN — RayWheel overwrites the root transform every tick.
- Turning a right-side wheel around is `Basis(Vector3.RIGHT, PI)`, **not** `Basis(UP, PI)`: in
  the wheel-root frame RayWheel builds, local Y is the AXLE, so a yaw just spins the wheel
  about its own axis and changes nothing visible. Verify rim direction by rendering both sides,
  never by reasoning about the basis.
- `ChaseCamera` follows `get_global_transform_interpolated()` — never `global_transform` in
  `_process`; it stutters at the locked 60 Hz tick.
- Splat-channel grip (`HeightmapTerrain.channel_grip` → `grip_at()`, sampled by RayWheel per
  contact) reads cached decoded splat Images — never `get_image()`/decompress per tick
  (in-editor it still decodes per call so an external PNG edit shows up). The multiplier rides
  `mu_long`/`mu_lat`; the 60 Hz clamps stay untouched. Three rules that are easy to undo by
  accident: `grip_at` pow-sharpens weights with the material's `blend_sharpness` exactly like
  the splat shader (raw weights give every painted patch an invisible low-grip apron, and
  normalization alone makes a faint trace read as full effect); `channel_grip` is clamped to
  [0, 1] on read (>1 breaks the tuned brake > drive hierarchy, <0 inverts friction and skips
  the friction circle); and the wheel picks the terrain whose surface is nearest the contact
  within `RayWheel.SURFACE_GRIP_REACH`, never XZ alone, or a bridge inherits the ice painted
  under it.
- Corollary: roads/tiles conformed onto terrain DO read the splat under the deck, so an
  unpainted road grips like grass (0.8), not asphalt (1.0). Fix is authoring, not code:
  RoadPath's **Paint splat under road** button and the palette dock's **Paint splat under
  tiles** button (`kit/helpers/splat_paint.gd`, tested) paint under the deck (roads: the
  PROFILE's `splat_channel` — asphalt/city 6, gravel 7; tiles: 6; paint is destructive AND
  additive — profile swaps don't repaint, repaints don't erase), biased to UNDERCOVER so the
  paint never peeks past the deck — don't "fix" the inset/erosion to widen coverage. Bridges
  need nothing and are skipped on purpose: out of grip reach = neutral 1.0 = asphalt.

## Drag and downforce

- Drag is DECLARED, never inherited. Every chassis sits on `DAMP_MODE_REPLACE` at 0, so
  nothing rides `physics/3d/default_linear_damp` — a wheeled vehicle's resistance is its GROUND
  DRIVE's `drag_area` (aero) plus its `rolling_resistance` (`crr * N`, with N read off the
  SPRINGS, not `mass * g`), applied by `WheelDrive._apply_resistance` and by
  `TowedBody.tick_towed`. Neither term reads the mass: the engine default was an acceleration,
  so a 24 t trailer on an 8 t tractor quadrupled the rig's drag. Consequences —
  - A towed body is not a `BaseVehicle`, so a new towed/attached rigid body means a new
    resistance call.
  - A trailer's `drag_area` is a MARGINAL, in-the-wake figure (0.25-0.60 m² against 2.4 m² of
    real frontal area), not its own silhouette. Set it to the silhouette and a coupled rig is
    over-braked again, just more politely.
  - The Kenney bodies' Cd*A is derived, not typed: `gen_kenney_vehicles` takes
    `cd * FRONTAL_FILL * w * h` off each body's measured AABB, so a per-variant edit belongs in
    that recipe. Hand-authored specs (semi, conventional, trailers) carry the number inline
    with the reasoning in the `.tres` header.
  - The free bodies declare NEITHER term and must not: the boat/drone/plane run their own drag,
    each having absorbed its exact `mass * 0.1` share of the removed engine default into its
    own coefficient. `test_vehicle_catalog` sweeps both directions.
- Downforce is a FORCE through the springs, never a grip multiplier. The ground drive's
  `downforce_area` (Cl*A, applied down the body's own up axis by `WheelDrive._apply_downforce`)
  is declared by the two open-wheelers and nothing else. It compresses the suspension, RayWheel
  reads the bigger normal load, and grip follows on its own — so it pays ride height and
  rolling resistance, which a `mu_lat` multiplier would not. Two rules ride on that: a body
  declaring it must declare `drag_area` too (a wing with no drag is grip for free), and `cl` is
  budgeted by the SUSPENSION TRAVEL — static load plus the wing at top speed has to stay under
  `spring_rate * rest_length`, or the ray bottoms and the chassis is dragged through the
  ground. `test_vehicle_catalog` fails both. A wing moves top speed as well as cornering, so
  re-measure after changing it.

## `VehicleMath` and the free-body vehicles

- The free-body vehicles (boat, drone, plane) share `VehicleMath` — `damped_force` /
  `clamped_damper` (the one-tick clamp in 1D and 3D), `air_damper`, `flow_authority`,
  `yaw_torque`, `inertia_of`, `pitch_deg`, `roll_deg`. Put a new shared free-body helper there
  rather than in a fourth copy.
  - `air_damper` is the DRAG path and never an angular one: `clamped_damper` on `vel - wind`,
    with an optional axis mask for a body whose axes carry different coefficients (the drone's
    horizontal against its vertical). In still air the relative velocity IS the velocity, the
    equivalence `test_wind.gd` pins and why every coefficient kept its meaning when wind
    arrived. An angular velocity has no air to be relative to, so the drone's attitude damper
    and the boat's `drag_yaw` stay raw `clamped_damper` / `damped_force`.
  - `flow_authority` is one curve, and the prop wash is the only thing that tells the two
    apart. No flow over a surface = no control; hull/air speed gives flow, and a propeller
    gives some from a standstill so a boat can turn out of a dock.
    `BoatVehicle.rudder_authority` and `PlaneVehicle.control_authority` are one-line forwards
    keeping their own names and figures (the tail sits outside the prop stream, so the plane
    declares no wash).

## Towing

- All three shared coupling classes live in `base/` and none of them is a truck thing:
  `tow_host.gd`, `towed_body.gd`, `articulation.gd` and `coupling_profile.gd`, beside each
  other. `base/tow_host.gd` itself depends on `TowedBody` and `Articulation`
  (`var trailer: TowedBody`, `COUPLE_SPEED_MS := TowedBody.RAISE_SPEED_MS`), as do
  `tractor/drawbar.gd` and `tractor/trailers/farm_tipper.gd`, so keeping them in `truck/` had
  `base/` depending on a family folder. What stays in `truck/` is what only the truck has:
  `fifth_wheel.gd` (a profile) and the four semi-trailers. `flatbed.tscn` names `towed_body.gd`
  by PATH with no `uid=`, so a future move has to hand-edit it or the scene silently fails to
  load.
- The towing side is `TowHost` and the tractor's drawbar is the same class: a coupler node on
  the chassis (`src/vehicles/base/tow_host.gd`) owning the datum, the joint, the gates and
  every item of two-body housekeeping below, with `FifthWheel` and `Drawbar` each a
  `CouplingProfile` and nothing more. Do not fix a towing bug on one machine — there is one
  implementation, and the list of what legitimately stays on the vehicle is in
  `docs/heavy_vehicles.md` § The drawbar. Do not let `TowHost` grow a `trailer_type`-shaped
  accessor either: which body is on the back shows through mass and through what it declares.
- The E cycle's refusal is `TowHost.may_cycle_to`, static and taking `is_coupled` / `is_towed` as a
  Callable — the attachment axis cannot hoist onto `BaseVehicle`; a null coupler never refuses.
- `TowedBody.Consumer` and `ImplementBase.Connection` are two different sets, not two names for
  one; the merge has been proposed and refused three times, and the cross-reference now sits at
  both enum declarations. Checked term by term:
  - `Consumer` is `{PTO, HYDRAULIC}` and has no data-bus member on purpose: ISO 11992 belongs
    to the TOWING unit's ISO 7638 pair (`VehicleSpec.trailer_bus_equipped`) and carries nothing
    about the body. One enum hands a semi-trailer an `ISOBUS_DATA` and a `THREE_POINT` it
    cannot have — the exact claim `truck/CLAUDE.md` § The four trailers exists to make visible.
  - The two `PTO`s are different shafts (a truck's chassis PTO turning a pump ON the trailer
    vs. a tractor's stub shaft driving an implement), and `HYDRAULIC` / `SCV` are different
    plumbing (a valve on the towing unit vs. a spool on the tractor's own pump). `FarmTipper`
    declaring `HYDRAULIC` without `Consumer.PTO` is that difference stated.
  - The bridge is ~10 lines (`FarmTipper.connections()` + `device_class()`) and merging the
    enum would not remove it. `TractorVehicle`'s `has_method` guard survives either way,
    because `ImplementBase` (a visual `Node3D`) and `TowedBody` (a `RigidBody3D`) share no base
    class and must not.
  - One catalog does not survive either: `ImplementCatalog.TOWED` is a routing table read
    before anything is instanced, and `TrailerCatalog` has nothing to route.
  - Nor are the two `attachment_controls()` two copies: the semi's `lift` is
    `Consumer.HYDRAULIC` (the tipping body), the tractor's is unconditionally true (the linkage
    is anatomy and works empty). Two answers, one hook.
- Two-body housekeeping, all of it load-bearing:
  - The trailer is a child of the towing unit's **parent** (the level), never of the unit — a
    dynamic RigidBody3D under another body gets the parent transform applied on top of the one
    the physics server writes. `TowHost._exit_tree` frees it, or a variant swap leaves it in
    the road.
  - It couples on the **first physics tick**, not in `_ready`: `Level._spawn_vehicle` assigns
    `global_transform` / `spawn_transform` AFTER `add_child`, so `_ready` has nowhere to put it.
  - Coupling **matches the trailer's velocity at the kingpin before the joint exists**,
    treating the rig as one body for that instant. Without it the solver is handed 14 t with
    the whole road speed as relative velocity.
  - Respawn **re-lays and stops** the trailer (the train's lesson) and resets its wheels — a
    RayWheel keeping last tick's compression across a teleport reports the jump as a suspension
    spike, this body's equivalent of the accel history the base clears.
  - `get_camera_exclude_bodies` includes the trailer's RID (the train precedent) and
    `get_camera_framing` returns a longer, higher frame for the combination.

## Telemetry and the bridge cluster

- Telemetry reads `Drivetrain.applied_throttle`, never `input.throttle`. A governed or
  rev-limited vehicle is holding the pedal flat while the engine is being cut (that field
  carries BOTH cuts), so `engine_load` and the fuel / coolant / battery `load_frac` off the
  driver's request would report a load the engine is not making — standing rule 3. The one
  deliberate exception is the contract's own `throttle` signal, which IS the pedal.
- `engine_load` is normalized against `Drivetrain.peak_torque(spec)` — the peak of the whole
  curve — never against the torque available at the current rpm, which cancels exactly to
  throttle and turns the signal into a second pedal-position readout. Against the peak it is
  rpm-aware, the only reason a real load (lugging, a PTO implement, a plough's draft) can show
  up in it.
- The four "reservoirs" are four different models and must not be unified, however alike the
  bars look. `TruckTelemetry.air_step` integrates a DEMAND FRACTION against fixed charge/draw
  rates and charges and drains in the same tick; `TrainTelemetry.brake_pipe_step` is a
  `move_toward` toward a TARGET the brake lever picks, with asymmetric rates;
  `DronePower.soc_step` coulomb-counts a MEASURED current against a rated capacity and feeds an
  OCV curve and a thermal lag; `fuel_step` is a monotonic drain off a load fraction. A target
  chaser cannot express "charging while being drawn down" and an integrator cannot express
  "settles where the lever puts it". Two of them also GATE (the truck's spring brakes pin the
  rear `omega`, the drone refuses to arm) and two gate nothing.
  - The PTO is the mirror image and is already shared: `VehicleTelemetry.engine_load_pct`'s
    parasitic term is one implementation the tractor and the truck call identically, because
    ISO 11783 is built on J1939 and SPN 92 is the same signal on both. What stays per family is
    what the shaft DRIVES. `pto_load` is exported on each vehicle rather than hoisted for the
    same reason a capability is: a machine's anatomy is declared beside the machine.
- `speed_limit` is the one telemetry field that is CONFIGURED rather than measured, and the
  only one set outside the tick: `BaseVehicle._ready` copies `spec.speed_limit_kmh` into it
  once (respawn never rebuilds telemetry) and the base `to_bridge_dict` carries it. It sits on
  the base, since the car family has no telemetry subclass to put it on — so every vehicle has
  the field, and the dashboard gates the LIM readout on the CONTRACT (`_has_speed_limit`), not
  on an `engine_hours`-style `t.get(...)` duck-type that would have printed LIM on the boat.
  Consequence: declaring a new `speed_limit_kmh` is a contract-visible fact as well as the
  re-measure trigger the strand-the-gearbox note describes, and the value must be a whole km/h
  in [0, 250] — `test_vehicle_catalog` fails it, because SPN 74 is one byte at 1 km/h per bit.
- `engine_load_pct` and `hours_step` live on **VehicleTelemetry**, not TractorTelemetry:
  `engine_load` (SPN 92) and `engine_hours` (SPN 247) are shared tractor/truck signals, so the
  model is one, not two.
  - `pto_load` is the one term ADDED to a signal rather than emerging from the sim — literally
    `load_frac += pto_load` while the PTO is engaged. The PTO costs no real engine torque, so
    the rpm does not sag and nothing else moves with it: a knowingly-cheap parasitic model,
    kept because one model beats two. Know the shape before reading anything into `engine_load`
    on a PTO machine; if it is ever promoted to a real driveline drag, this is the term that
    GOES, not a second one added beside it. Contrast `hopper_load` (mass only, consequences
    downstream).
- Contract signals key on the vehicle **family** (`signals_for_vehicle` looks up `"train"`, not
  the variant `"bullet"`): any pre-spawn fallback that has only a variant name must map it
  through `VehicleCatalog.family_of(...)` first, or the dashboard/bridge get an empty cluster.
  `dashboard.bind()` and `level_baker.validate_spawns` are the two that must.

## Kenney bodies

Detail in `src/vehicles/kenney/CLAUDE.md`.

## Measuring and the tracking gate

- **Changed a spec's gearing, mass, tires or wheel positions? Re-measure it** with
  `godot --headless --path . res://tools/measure_vehicles.tscn -- <variant>` (or `all`,
  which is minutes — background it). It reports 0-100 / quarter / settled top speed with the
  gear it lands in, flags ratios the vehicle can never reach, and runs a zero-steer
  straight-line tracking pass that catches a chassis that pulls. Dev tool, never CI, always
  exits 0 (`track strict` is the CI gate). Flags after the seconds cap: `coast`, `track`,
  `strict`. Details and the `Engine.time_scale` trap: `docs/vehicles.md` § Measuring a vehicle.
  - "top (settled)" can be the TIME CAP: the tool stops a pass at the cap and prints whatever
    it had reached, in the wording it uses for a real settle, so a slow vehicle reports a
    number that is simply too low. Sanity-check any top speed against the power balance —
    engine kW at the reported rpm versus `0.5*rho*Cd*A*v^3 + crr*m*g*v` — and re-run the slow
    ones at a longer cap. A change that improves ACCELERATION raises the reported top speed of
    a capped vehicle without touching anything that sets top speed, which reads as a physics
    mystery.
  - `tractor-kenney` gets no tracking pass and that is correct: the pass latches its ideal line
    at 60 km/h to skip the launch transient, and a 40 km/h farm tractor never gets there. It
    prints `never reached 60 km/h, skipped`. Any vehicle geared below 60 is in the same
    position — check its steering by driving.
  - `-- semi` measures the coupled 32 t rig, not a bobtail tractor: `TowHost`'s spawn countdown
    couples `TrailerCatalog.first()` unconditionally, so there is no way to measure a solo
    tractor unit from the command line. Two consequences: the force column reads against all-up
    mass where the two differ, and a towing variant measured solo does not reproduce its figure
    from an `all` sweep — the countdown couples against whatever state the previous vehicle
    left, so the launch transient is not bit-reproducible across run contexts (top speed, gear
    and rpm are stable; 0-50 / quarter / `tyres` / `rake` move in the third digit). A
    regression diff has to compare runs of the SAME SHAPE.

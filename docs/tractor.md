# Tractor & implements

The tractor publishes its implement's state on ISOBUS (ISO 11783), the J1939 child. Towing is
shared with the semis (`TowHost`, `TowedBody`: `docs/truck.md` § TowHost, cycling and mass); the
framework and the other families: `docs/vehicles.md`; shared plumbing: `docs/systems.md`. Rules:
`src/vehicles/tractor/CLAUDE.md` — this doc is the tour and the derivations.

## Tractor, implement & ISOBUS

**Twenty ISOBUS signals (8 in, 12 out), all `flavor: "isobus"`**, the widest cluster in the
game (names: the contract). It also publishes the unflavored `engine_hours`,
the truck's `j1939` `axle_load` (lifting an implement moves its weight onto the rear axle) and
`gear_ratio` (§ The CVT tractor).

- One body, two gearboxes, five swappable attachments on two connections. `V` cycles the
  gearbox: `kenney/tractor-kenney.tscn`'s powershift (the default) and `kenney/tractor-cvt.tscn`'s
  CVT (§ The CVT tractor), the same body and recipe otherwise. `E` cycles the attachment — spreader → plough →
  power harrow → mower → drawbar tipping trailer → detached — each teaching one of the five
  real tractor↔implement connections (three-point linkage, drawbar, PTO, SCV hydraulic
  remote, ISOBUS data). Absent functions publish a real zero, never a gap.
- Spawn: raised, PTO off, implement attached; respawn re-raises but keeps the implement.
  `engine_load` is a modeled honest value (`engine_load_pct`), the rest read straight out of the sim.

### The signals that change how it drives

- `diff_lock` locks the rear pair onto one shaft speed: an unbounded `Differential` coupling in
  `WheelDrive._couple_differentials`. `fwd_drive` is MFWD: it rewrites the front wheels'
  `driven` flag each tick, and while engaged the spec's `centre_diff_rigid` ties the front axle's
  mean speed to the rear's, a geared transfer with no centre diff. Both requests gate on
  `GroundDriveSpec` flags (`rear_diff_lockable`, `front_axle_engageable`), which are true only on
  the tractor's spec. Both axles stay open inside, so 2WD with the lock off is still the open
  rear diff. The transfer runs the kinematic ratio, `r_rear / r_front` = 1.5 (`WheelDrive`'s shaft
  frame). Rejected: a lead past the kinematic ratio; with exact radii it is straight-line wind-up,
  not feel.
- `wheel_speed`/`ground_speed`/`wheel_slip` are the signature ISO pair and its difference:
  wheel-based is the mean spin of the rear axle × tire radius; ground-based is chassis
  forward velocity; `wheel_slip` is how far the first runs ahead of the second (unsigned,
  J1939 SPN 1858, floored at low speed).
- `pto_mode` is a gearbox selection, not an engine speed: 540/1000 are shaft speeds off
  `PTO_RATED_RPM` (**2043**, the 6175R's 1950 of its 2100 rated, on the curve's 2200;
  `docs/sources.md` § Governor); an unknown byte falls back to 540.
- `hand_throttle` is the all-speed governor's second lever (`docs/drivetrain.md` § The pedal map):
  the higher of it and the pedal sets the engine speed, and it never pulls away alone. Local keys
  `-` / `=` step it 10 %, `0` sets the PTO preset (`TractorTelemetry.pto_hand_throttle`, the
  governor on `PTO_RATED_RPM`) or clears it; owner `InputRouter._hand_throttle`, the `_pto`
  pattern, kept through a respawn. `engine_hours` is an hour meter, range-less, on the readout
  line beside ODO.
- `guidance_curvature` is auto-steer (the boat's `rudder` precedent): present, it overrides
  `steer`, arbitrated only in `InputRouter.arbitrate_bridge`. `bridge_source.gd` maps the
  contract's ±127 1/km onto the ±1 steer channel; 0 is a real held command, not an absence.
- `scv_flow` is a hydraulic remote reaching the spreader's hopper gate ram
  (`ThreePointHitch.set_scv`) and the tipping trailer's ram (`Drawbar.set_scv`);
  engine-driven, so a stopped engine means no flow. Local key `Q` (owner `InputRouter._scv`,
  the `_pto` pattern) — binary, not proportional; the truck's `retarder` stays keyless.

### Draft, hitch, linkage

- Draft is a real force: with a draft-relevant implement (plough, power harrow) down in the
  ploughable field, `TractorVehicle._apply_draft` puts a rearward force at the hitch point
  (`TractorTelemetry.draft_newtons`): the implement's own rating × working depth × soil × ASABE
  D497's speed factor at the hitch's speed (`ImplementBase.draft_rating` / `draft_shape`, held at
  the top of its speed range) × a fade to 0 below `DRAFT_V_CRAWL`. `draft_max_force`, the 100 % end
  of `draft_force`, is the plough's rating. The level's light bands paint soil 0.5; D497's
  coarse-to-medium texture ratio is 0.64.
  `engine_load`, rpm sag and `wheel_slip` move as consequences. Lift comes from
  `ThreePointHitch.ball_lift()`; working depth is the implement's own
  (`ImplementBase.tool_depth` — plough 0.25 m, harrow tines 0.10 m). "In soil" is
  `Surface.FIELD`, in whichever channel a level paints it (`HeightmapTerrain.surface_weight_at`).
- `ThreePointHitch` (`src/vehicles/tractor/three_point_hitch.{gd,tscn}`) is tractor anatomy,
  whole with nothing attached. `HitchLinkage` (pure math, tested) solves the side view as a
  four-bar — implement pitch and rockshaft arm angle fall out of a circle-circle
  intersection, why implements tip back as they lift.
- Draft 60 Hz margin: below `DRAFT_V_CRAWL` the draft is a linear damper on the hitch point's
  speed, which meets the effective mass `m_eff` (the body plus the pitch the hitch's arm turns,
  `TractorVehicle.hitch_effective_mass`), stable while `k*dt/m_eff < 2`
  (`test_the_shipped_draft_keeps_the_60hz_damper_margin_on_the_hitch` holds it under 0.5). The
  one-tick cap behind it, `m_eff · |v_hitch| / dt`, bounds the angular impulse with the linear one.
- Weight: the linkage's carried share of an implement folds into the chassis' live mass and COM
  (`TractorVehicle._apply_implement_mass`, `VehicleMath.carried_com`). At the bottom stop the
  ground carries `ground_share()` (depth wheel, roller, tail wheel), handed to the linkage across
  `support_lift()` (`ImplementBase.carried01`); the spreader never touches, so attaching it, not
  lifting it, moves its load. Raised, the harrow takes the front under John Deere's ballasting
  minimum, ≥ 20 % of total weight on the front axle, and the plough to its edge: reported, not
  enforced; that is what front weights fix. `measure_vehicles -- tractor-kenney 20 hitch`, parked,
  per-axle kg off the springs (every reading within 1.1 % of the statics `m e / L`):

  | Implement | Front / rear, bottom stop | Front / rear, raised | Front share, raised |
  |---|---|---|---|
  | none | 2656 / 4344 | | 37.9 % |
  | Plough | 1952 / 5634 | 1614 / 6286 | 20.4 % |
  | Power harrow | 2441 / 4869 | 1638 / 6912 | 19.2 % |
  | Rotary mower | 2328 / 5024 | 2101 / 5519 | 27.6 % |
  | Spreader, full | 2050 / 5853 | 2176 / 5726 | 27.5 % |

  Carried full, the spreader barely moves the handling: the full-lock circle and the step-steer yaw
  rates stay within a few percent of bare, the yaw index read off the tensor 1.06 against 0.96. The
  light front shows as no extra understeer in the linear range (`20 circle`, `20 step`, with and
  without `trailer=spreader`).
  Held on full soil (`20 plough`), the measured draft sits on D497 at each speed held, to 0.0 %.
  The harrow holds each of the pass's speeds, open or locked. The plough holds the slowest at 16 %
  slip either way. With the diff open, pushed on to the reference speed on a floored pedal, it
  peels: the lighter right rear (2709 of 5789 kg, under the plough's left-of-centre mass) passes
  the grip peak and runs away at 122 % slip while the left turns at 9 %, the open diff giving the
  left no more torque than the spinning right; it settles near half the reference speed in D1,
  49 % slip. An open diff already under the peak at the reference speed stays there: the peel is
  the falling side of the grip curve, reached by a heavy foot. Locked, it holds the reference
  speed in D1 at 10 %, both rears at Fx/Fz ~0.5 under the peak; past it D1's governed top holds
  it there. Floored from rest, open, it peels (~50-60 %), its lugged D7 taking D1 in two shifts.
  Ramped in as a driver does, the diff locked as tractor_plough's hint asks (`20 plough course`),
  the course's reference-speed run reads `engine_load` 63 % on full soil and 43 % on the light
  bands, inside tractor_plough's 25-70 %; at part pedal the PI driver's governed box shifts
  through D1-D6 in the Row, its load spiking on the shift ticks. The lug's grip in soil (0.60 of asphalt, `ag_lug.tres`) is an estimate, and D497's
  own traction at the slip peak is lower still (0.49): an open-diff 2WD tractor ploughing is
  traction-limited, and the diff lock or MFWD is the answer, as a ploughing driver engages it.
  Not modelled: draft control (the Ferguson hitch), a spreader that empties, a composite inertia
  declaration, front ballast as an attachment, a start gear that reads draft, skid drag.
- The PTO is real load: a driven implement declares its shaft power
  (`ImplementBase.pto_power_kw`; the harrow's off its trials' torques in D497's form, by speed,
  tine depth and soil; the mower's D497 cutting figure with its deck down; the spreader's disc an
  estimate; `docs/sources.md` § PTO power), and the tractor puts it on the crank as a constant
  torque at `PTO_RATED_RPM` (`TractorTelemetry.pto_load_nm`, `Drivetrain.accessory_torque`). It
  acts only with the PTO in, the key on and an implement declaring `Connection.PTO`: the plough
  with the PTO in reads as out (`20 plough course` byte-identical either way). `engine_load` and
  the rpm sag carry it, never a term of their own. The harrow on full soil (`20 plough
  trailer=harrow`, then with `pto`): parked lowered, `engine_load` 9 % rises to 24 % at idle;
  held at the pass's three speeds, 36 / 41 / 61 % rise to 51 / 63 / 89 % (the PI driver's governed
  box holds them in higher gears with the PTO's load). Floored from rest with the PTO in, the rig is
  power-bound in D7 on the curve's tail over rated speed, its road speed short of the upshift point,
  where with the PTO out it takes D7>D6>D11.
- The governor holds the PTO (`20 plough governor`: the hand throttle at the PTO preset, 540, a
  fixed D2 on the pedal's go request; `docs/drivetrain.md` § The pedal map). Parked in N the shaft
  turns 540; the harrow lowered at rest pulls it to 533. Working raised it turns 535-536;
  lowered, the draft and the harrow's PTO power come on together and the crank settles in about a
  second, 3.4 % under the 2043 setting: the shaft 521 rpm, `engine_load` 55 %. The plough, with no
  PTO and its full draft, settles 3.2 % under: 522 rpm, 53 %. Both inside the 7 % droop (the `droop`
  gate's 504.7 rpm).
- Ground support is drawn, not simulated: `ThreePointHitch` keeps two poses. Physics (ball lift,
  hitch point, implement COM) reads the commanded solve on flat ground; the drawn pose floats the
  implement up until its `support_points()` meet the ground under them
  (`HitchLinkage.float_pos`, one ray per point while lowered), as a linkage in float does. A float
  moves no weight or draft depth, and a dip under the support leaves the implement on its stop.
  The drawn pose chases that contact through a critically damped follower, stiff into the ground
  and soft out of it (`ThreePointHitch.FLOAT_OMEGA_UP` / `_DOWN`): copied tick by tick, the
  implement jumped every facet of the 8-bit heightmap and landed on its stop dead.
- Ballast: gear-1 wheel force at `Drivetrain.launch_target_rpm` is about 1.5x the rear grip at 7 t /
  `front_weight` 0.38 (about 3.4x unballasted at 4 t 50/50). Top
  speed in D16 is rpm-bound, so ballast moves only acceleration and grade climb.
- Launch: a powershift's, not a car's, in its start gear (`ShiftPolicy.start_gear`, up to
  `start_gear_max` D7). A powershift's start gear is a driver preset, higher for an empty run and
  lower with a load; here the box picks it as an AMT picks its own from gross weight and grade
  (`docs/drivetrain.md` § The shift policy): the highest gear whose launch drive (the curve at the
  launch line on the pedal's fuel) beats the grade's pull plus the rolling and soil resistance on the
  whole rig by `ShiftPolicy.START_RESERVE` (2, an estimate), and whose floored launch locks within
  `START_SLIP_S` on the rig's mass. Picked at full pedal while the tractor stands, it
  steps down through the launch to what the driver's pedal holds (a pedal of 0.6 with the tipper on
  8 % takes D4, then D2 at once), and down again by ratio (`ShiftPolicy.start_step_down`) if the
  launch has not moved after the ramp and a dwell. Computed picks (`test_tractor`): D7 empty on the
  flat or on flat mud; D6 with the tipper on the flat, D4 on 10 %; D1 with the tipper on mud, and on
  the 26 % mud climb.
- The pack's capacity ramps to its rating over `launch_engage_s` while the controller slips
  it toward the launch line, which holds a floored start near the grip peak (with the whole rating
  on the first tick the rears flash to heavy slip and the front axle unloads almost entirely); while
  the ramp is short of the engine's torque the crank flares over the line. The
  close onto the wheels, like each shift, is a handover over `shift_handover_s`, the clutch passing
  the pedal's torque plus the flare's inertia (`docs/drivetrain.md` § The shift's handover), never
  the rating: closed at
  the rating, a held D7 poured the flare into the wheels in a tick (a spike of g, the front axle
  unloaded), and a held D4 flashed its rears into slip.
- Flat strip (`measure_vehicles -- tractor-kenney 40 trace`):
  - bobtail: D7, a clean close carrying the engine's torque, then three floored skip-shifts,
    D7>D12, D12>D15 and D15>D16, each gear held past the trace's dwell floor; rear slip low (~0.10), the front axle
    kept loaded; D7>D12 and D12>D15 ring past their `front axle` gate (`docs/handling.md` § Pitch);
  - with the farm tipper: D6, then D10, D12, D13, D14, D15 and D16, each held longer.
- Standing starts: `docs/vehicle_measurements.md` § Gradeability, `docs/drivetrain.md` § Hill hold; with the tipper on 10 %
  asphalt it picks D4 (`measure_grade -- tractor-kenney rollback tipper` times how soon it moves).
- Reverse is the bus's single R byte, at ~D7's ratio (3.9); its top speed follows from that ratio and the governor.
- Steady draft does not involve COM height: drag at the hitch and tyre reaction at ground form a
  couple of `F × h_hitch`, a few kN off the static front load. The COM (`com_y_frac`, an estimate)
  matters for transients and rollover. **The front axle is a beam on a pivot** (`GroundDriveSpec.
  front_axle_swing_deg`, `docs/sources.md`): inside its stop the fronts share their load freely
  (no front roll moment or damping), so the body rolls on the rears and the pivot, then on all four
  at the stop; `BalanceModel` lifts the rear inner on that triangle. Its threshold sits under the
  lugs' slide: a fast turn tips and overturns the tractor before it slides
  (`docs/vehicle_measurements.md` § Cornering), and over bumps the beam keeps four wheels down.
- Body `scale` 1.6465 (3.64 × 2.65 m, the 6R 150's 2.58 m wheelbase), on its drawn tyres.
  Suspension is the tyres: 330 / 420 kN/m, `rest_length` 0.12 m, ~33 / 42 % static sag.

### The CVT tractor

`tractor-cvt` is the same tractor on a power-split CVT of the ZF Eccom class, which John Deere fits
as AutoPowr: four mechanical ranges changed synchronously as it drives, with no power interruption
(Renius & Resch, ASAE Lecture 29, 2005; the ranges' speeds and every figure below: `docs/sources.md`
§ CVT). Through this body's gearing its top range reaches the road-speed limit well under rated
speed, the overdrive Renius asks of a CVT. `Drivetrain.is_cvt` gates it; `gear_ratios` stays empty.

- **The ratio is drivetrain state** (`Drivetrain.cvt_i`), chosen by the controller before the spin
  solve and solved in it as the gear, at the overall speed ratio `k = i / final_drive` rather than
  its inverse (`_solve_cvt`): the reflected `J k²` moves with it, and what a ratio change takes from
  the crank's inertia is carried in the step. The coupling is locked in D and R, open with the key
  off and in N or P; the hydrostatic relief (`cvt_max_axle_torque`, `mass g r`: peak gross traction
  about the ballasted weight) is its only slip, and the powershift's brakes hold it.
- **The controller** (`Drivetrain.cvt_ratio_step`):
  - The engine runs the all-speed governor at the driver's demand while the hand throttle is set or
    the PTO engaged; in pedal mode, engine-speed management (`Drivetrain.cvt_managed_setting`,
    Deere's automatic mode) lowers it in proportion to the load (the power asked over the limit
    speed's), from the setting whose full-fuel end is the limit speed to `CVT_LIGHT_LOAD_SHARE` of
    rated, never under what the top ratio needs for the command nor past the pedal's own setting,
    and falling no faster than the ratio can follow (`cvt_setting_step`).
  - The foot pedal commands ground speed, its share of the road-speed limit (`CVT_REVERSE_KMH`
    back). A CVT governs road speed through its ratio, so its fuel takes no road-speed fade: a speed
    hold off the crank would read the fade as overload and pull the box down to its limit speed.
  - `cvt_accel_ms2` (JCB's "high" band) moves a ground-speed reference; the ratio turns the crank's
    speed into it, so a crank that droops or lifts moves no ground speed. Pressure cut-off: never a
    step past the wheels' own ratio read at the reference's crank speed, so only lagging wheels trip it.
  - Limit-load control: under the governor line's full-fuel end (never over peak power) the ratio
    gives way over `CVT_LOAD_TAU_S`: the crank holds its speed, the ground speed gives.
  - The hand throttle never pulls away alone; the foot brake stops it (AutoPowr's AutoClutch).
- **Active standstill** at a ratio of 0 is the park pawl's path at the relief
  (`Drivetrain.standstill_hold`, `WheelDrive.standstill_lock`): the transmission holds its output,
  with the lock's stiction, so this variant needs no brake hold and retires the STANDSTILL
  COMPROMISE (`GroundDriveSpec.hill_hold`) on itself. Every stop ends there, on the brake or with
  the pedal up: the redline bound on the ratio binds only past one step of its rate, so the ratio
  reaches 0 as the wheels stop, and a direction change sweeps it through 0 the same way. Like the pawl, it
  holds only under `WheelDrive.PAWL_ENGAGE_SPEED`: brakes that lock the wheels at speed bring the
  ratio to 0 with the crank at idle (the anti-stall bound), the wheels stay the brakes' alone, and
  the ratio re-synchronises to them once they turn. `measure_grade -- tractor-cvt rollback` (and
  `tipper`) reads the hold against the powershift's brake hold.
- **The bus:** `gear` publishes the engaged range, D1-D4 (a bridge byte caps it; `CVT_RANGE_HYSTERESIS`
  keeps a ratio held on a boundary from chattering it); `gear_ratio` (J1939 SPN 526, sloppyCAN's
  ETC2) the live ratio inverted, `GEAR_RATIO_MAX` at standstill. The efficiency is the powershift's
  at each range's lock-up, less the variator's loss on the hydrostatic share
  (`Drivetrain.cvt_efficiency`).
- **Measured:** floored from rest (`measure_vehicles -- tractor-cvt 40 trace`) it pulls away with no
  clutch and no step, the bytes stepping D1 to D4, the crank on its governor line over its limit
  speed, and the front-axle gate passes; the trace reports ranges, ratio and crank in place of the
  shift gates, which judge a stepped box's shifts. The governor's hold (`20 plough governor`, the
  pedal commanding the stepped run's working speed in range 2) keeps the shaft inside the droop
  as the harrow's or the plough's draft comes on, as the powershift does; the ground speed drops by
  the drive tyres' slip. Tables: `docs/vehicle_measurements.md` (`doc=accel`, `doc=cruise`,
  `doc=grade`).

### What an implement declares

`ImplementBase` (`implement_base.gd`, the declarations and why they are code: its comments)
declares connections, device class, A-frame, draft, mass and support points; implements are
visual only (no CollisionShape, no joint). The declared connections are load-bearing:
`ISOBUS_DATA` decides whether `implement_connected`/ `implement_type` report anything; `PTO`/`SCV`
decide whether drive/flow reach the machine. Attach/detach is a logical address claim —
`ImplementCatalog` holds the cycle order with DETACHED a real entry; `E` cycles it via duck-typed
`cycle_implement()`.

### The four implements

`src/vehicles/tractor/implements/`, each a different connection set and a device class no
other machine may share (`test_implement_catalog`):

| Implement, drawn class | Connections | `implement_type` | Draft depth | Moving part |
|---|---|---|---|---|
| Plough, 4 × 14" | three-point, bus | 2 tillage | 0.25 m | gauge wheel arm swings on lift |
| Power harrow, 3.0 m | + PTO | 3 secondary tillage | 0.10 m | tine rotor, transverse axis |
| Rotary mower, 7 ft | + PTO | 9 forage | none | rotor, vertical axis |
| Fertilizer spreader, ~800 L | + PTO, SCV | 5 fertilizer | none | disc + `scv_flow` hopper gate |
| *Fifth entry, not an implement:* drawbar tipping trailer (§ The drawbar) | drawbar, SCV | 0 none (no bus claim) | none | tipping body + tailgate on one ram |

Their masses, ground shares and draft ratings: `docs/sources.md`.

Each is authored lowered with the origin on the lower pin line (ground y = −0.21). Shared
A-frame: `implements/headstock.tscn`. PTO-driven visuals go through
`ImplementBase.spin_from_pto`, whose `ratio` is cosmetic (540 rev/min would alias at 60
fps); the published `pto_rpm` stays honest. Level 1's centre is the ISOBUS farm playground:
painted field (soil for `draft_force`, with two light sandy-loam bands at half soil so
`engine_load` moves along a pass), mud wallow (`diff_lock`), haul ramp (`fwd_drive`), implement
yard. See `docs/level_kit.md`.

## The drawbar: the connection that only pulls

The fifth cycle entry is not an implement. `farm_tipper.tscn` is a 10 t towed body on a real
`Generic6DOFJoint3D`, standing on its own unmodified `RayWheel`s, the same `TowedBody` the
semi-trailers use. The tractor side is the same `TowHost` the semi's fifth wheel is:
`Drawbar` (`src/vehicles/tractor/drawbar.{gd,tscn}`) is a `TowHost` carrying a drawbar
`CouplingProfile` and the pin's own geometry, nothing else. Rationale: `tractor/CLAUDE.md`.

- A drawbar only pulls: with the trailer hitched, `I` still raises/lowers the empty
  three-point linkage and `hitch_pos_actual` still reports the whole stroke; `draft_force`
  reads a clean zero.
- The two couplings are the same code, not two implementations. What stays on the vehicle:
  the brake demand (semi foot brake or roll stability, never its retarder; tractor plain pedal); the
  spool source (`input.scv_flow` gated on `running` here, `1.0 - input.hitch_request` on the
  truck); the attachment catalog; the semi's ISO 11992 publish and trailer air draw; camera
  framing.

### Pin, datum, profile

- Pin, datum and the joint's three stops differ from a fifth wheel: `drawbar.gd`'s constants and
  their reasons. Datum 0.40 m, not the semi's 1.05 m plate; trailer origin at the drawbar eye,
  ground at y = −0.40.
- A drawbar carries a nose weight, not a share: 12% against the fifth wheel's 27%.
- **Laden on 10 % mud the rig is traction-bound.** That is `measure_grade -- tractor-kenney rollback
  grade=10 mud mfwd tipper verbose`: it first moves 0.1 m forward only after several seconds, the same from any
  start gear and with or without the hold.
  - What it asks: the 17 t combination needs the grade pull plus mud's 0.2 drag on the whole
    load (weight x (grade + 0.2)).
  - What it has: the MFWD tractor's 8.2 t (7 t plus the 1.2 t nose) grips less than that at the
    peak. Floored, all four tyres spin at a slip ratio well past the peak and carry less still.
  - The tipper's own brake is off shortly after the start, and its tyres carry nothing. The
    drawbar pulls its grade share plus its share of the drag.
  - The rig crawls instead of standing, because the drag's per-tick cap
    (`RayWheel.surface_drag_force`, a 60 Hz clamp) shrinks with speed.

### Tipping, collision, refusal

- Tip runs off the SCV, not a PTO (the truck's tipping semi-trailer declares `Consumer.PTO`
  because a truck has no hydraulic remotes; a tractor already carries the pump). Raise
  interlock is `TowedBody.body_raise_allowed` unchanged.
- Collision for the raised body is two authored poses and one swap, with hysteresis
  (re-transforming a `CollisionShape3D` at 60 Hz would rebuild the compound/inertia tensor
  on a body already writing its own centre of mass).
- `E` refuses only for a press that hitches (the tractor moving); dropping the trailer lays
  nothing. Level 1's first `E` at the tractor spawn is refused by the fit check (scenery close
  behind): that is the check working; pull forward.

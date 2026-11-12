# 2026-11-10: unit 1, COMPROMISE triage

Started at 6b10e43. All 72 mentions read (45 in `src kit tools tests`, 27 in `docs`), each
against the code it labels.

## Sorted

**Design choice: label dropped, the text says it is a choice.**

- `base_vehicle.gd` empty tank keeps the engine running. No refuel path exists, so stopping
  would strand the player.
- `vehicle_telemetry.gd` `FUEL_TANK_FULL_LOAD_S` game-scale tank (and its echoes:
  `tank_litres`, `test_telemetry.gd`, `docs/drivetrain.md` § fuel, `docs/guide/auxiliary.md`
  source comment). Wanted: "a real tank never visibly moves in a session".
- `drone_modes.gd` soft geofence (and the `docs/guide/drone-flight.md` source comment). The
  section header is "the soft geofence"; a breach latching RTL is the design.
- `rail_track.gd` one rail loop per level. A level-format limit, nothing in the sim is wrong.
  Whole-line comment in a bake-hashed file: `strip_gd_comments` drops it from the hash.
- `docs/making_a_level.md` § 8 sculpt-drift tolerance: "a guarantee nothing consumes".
- `docs/vehicles.md` § Rejected designs, the unsplit `Drivetrain`: the cost of a kept design.

**Not a compromise: an estimate.**

- Rear roll steer 0.10 (`gen_kenney_vehicles.gd` TRUCK_BASE, `semi_spec.tres`,
  `conventional_spec.tres`). `docs/sources.md` § Roll steer grades it "the sign sourced; the
  figure an estimate": an unsourced parameter, not a sim knowingly wrong.

**Not a compromise: an engine limit already closed.**

- `wheel.gd` `_contact_query`: "`cast_motion` bisects to 1/256 ... `settled_drop` closes it".
  The comment itself says the gap is closed; what is left (`settled_drop`: "exact on a face, to
  first order over the step at an edge") is stated there without a label.

**Code debt.**

- `tools/road_gen.gd` header: RoadPath's `_conform_terrain` / `_paint_splat`
  (`kit/helpers/road_path.gd` 417-598) repeat `road_gen.footprint` / `conform` / `paint`
  (sampling at `adaptive_offsets`, the deck strip, the normalisation). Size L (kit cannot load
  `tools/`, the shared core needs a kit home, `road_path.gd` is a level dependency so every
  level with a road re-stales, and the editor buttons need the user's check). Queued; relabelled
  "Code debt".

**Real: label stays (states what is true; undo cost stated unless noted).**

`surface.gd` tyre-blind drag (cost in `docs/sources.md` § Surfaces) · `drivetrain.gd`
`lockup_holds` (+ `launch_target_rpm` echo, test echo) · `drivetrain.gd` `cvt_efficiency`
(undo cost not stated: unit 2) · `ground_drive_spec.gd` STANDSTILL hold ·
`stability_control.gd` `roll_retardation` (feeds only `brake_light_request`; the exact sum
crosses into `TowHost` for a lamp threshold, not worth queueing) · `torque_converter.gd`
`IDLE_CAPACITY` · `vehicle_telemetry.gd` rigid crank burn · `wheel.gd` `brake_settled_spin`
(undo cost not stated: unit 3) · `wheel.gd` `corner_mass` kingpin · `wheel.gd` rolling
resistance as a force · `wheel_drive.gd` `set_esc_mass`, retarder cap, one-pass couplings ·
`mower.gd` (non-goal: crop) · `three_point_hitch.gd` float pose · `tractor.gd` implement
inertia · `train.gd` pipe lag · `semi_spec.tres` `cornering_peak_load` 0 · `tanker.tscn`
barrel over the tail (breaks the gooseneck rule in `truck/CLAUDE.md`, cost stated) ·
`kit/CLAUDE.md` colormap (md5 `451b163d...` on all three copies, 12 KB each) ·
`gen_kenney_vehicles.gd` `SIDE_CP_FRAC`, `free_rev_limit_rpm` (a real limiter, but it also
masks the petrol map's part-pedal free rev), harrow sag, e16 span, 38 deg lock,
`hatchback-sports` converter, `suv` grip bonus (+ two echoes) · `measure_grade.gd` joint
residual (checked on 4.7.1: `ClassDB` lists no applied-force or impulse getter on
`Generic6DOFJoint3D` or `PhysicsServer3D`) · `tc_pedal.gd` `bite_pending`.

**Needs the user: proposal 1.**

- `drivetrain.gd` `drive_inhibit` "engages at any speed, where a real auto-neutral waits for
  the vehicle to stop". The code fix is one speed gate in `truck.gd`, so "costly" is false; but
  `truck.gd` says the spring brakes are "not sized to out-hold the engine", so the gate would
  let a held throttle drive through an air loss. Label left until decided.

## Seen, outside the unit

- Run-on lines from a lost `\` continuation (valid GDScript, cosmetic): `truck.gd:115`,
  `tests/test_telemetry.gd:178` and `:187`. For units 6 and 19.

## Commits

- 56728ba: the six design choices relabelled, with their doc and test echoes.
- 2a7392d: the trucks' rear roll steer 0.10 labelled an estimate (three sites).
- 36b3e7b: the wheel sweep's 1/256 step labelled an engine limit.
- c6686e0: `road_gen.gd`'s RoadPath duplicate labelled code debt.

Checks: `check_docs` clean, `check_bakes` 7 fresh / 0 stale (the `rail_track.gd` edit is a
whole-line comment), full suite 2417 cases, 0 failures. Counts after: 34 in
`src kit tools tests`, 22 in `docs`.

## Deferred

- The RoadPath / `road_gen` fold (L): Queue line 1 in `summary.md`.
- `drive_inhibit`: proposal 1, decided by the user the same day: keep the behaviour, relabel
  it a design choice (`drivetrain.gd`, `docs/truck.md`). Counts after: 33 and 21.
- Undo cost missing on two real labels (`cvt_efficiency`, `brake_settled_spin`): to their
  unit reviews (2 and 3), where the code is read in depth.


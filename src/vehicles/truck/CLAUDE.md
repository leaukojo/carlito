# Truck & trailers — rules

Tour, signal tables, derivations: `docs/heavy_vehicles.md`. `TowHost`, `TowedBody`, `Articulation`
are shared in `src/vehicles/base/` (`src/vehicles/CLAUDE.md` § Towing); only truck-family rules live here.

## Brakes, retarder, air

- The retarder is a brake torque on the driven wheels, added inside `WheelDrive`'s wheel tick so
  `RayWheel` integrates it semi-implicitly. Never a post-tick `move_toward` (over-corrects on tick
  one, slip 1.0). A kinematic LOCK (spring-brake pin) may be written after the tick.
- Quote retarder strength as arithmetic (`docs/heavy_vehicles.md` § Air, retarder, axle load), never
  a remembered measurement. Guard: `test_truck` pins 0.7-1.6 m/s² per shipped spec.
  The floor tracks the tyre, so never raise `RETARDER_MAX_FRAC` to hold a figure.
- Anti-lock is a SLIP limit (`RETARDER_SLIP_TARGET`), never a force cap at mu*N*r: a locked wheel
  already makes that torque. Guard: `test_the_retarder_can_never_skid_the_driven_axle`.
- Air is a GATE, not a bar: below `AIR_SPRING_BRAKE_BAR` on either circuit the rear `omega` is pinned
  to 0 (a lock; first-gear drive torque beats `brake_torque`). `warn` stays above the gate.
- The tach falling to idle at the gate is correct (lugging); no throttle cut. The gate does not
  zero `retarder_state` (it ran). The draw is pedal position only. Losing air has no ramp (accepted).
- Recouple after a heavy stop can reach the gate (margin ~0.1 bar): `docs/to_investigate.md`.

## Telemetry

- `axle_load` is summed `RayWheel.suspension_force` in kg, never a mass lookup. SPN 520's negative
  sign lives in the contract `desc`; a `[-100, 0]` range fills the bar backwards.

## Refuse body

- Add no scene nodes under `Model`: `gen_kenney_vehicles.gd` wipes it each regen and
  `TruckVehicle._find_rig` finds `Model/arm` and `Model/body/trash` by name. No `arm` mesh = no body
  (the firetruck publishes zeros).
- `arm_pos_pct` / trash empty height are read off the geometry (`ARM_STOW_DEG`/`ARM_DUMP_DEG` are
  measured by driving; the arm origin is its AABB corner), never 0 or a constant.
- `hopper_load` reaches the chassis only through `mass`; never add a laden term to `axle_load` or
  `engine_load`. `center_of_mass` stays on the spec.
- `is_inhibited` keeps its `bus` term; the dashboard (not the interlock) hides INHIB while BODY BUS
  is dark. The interlock freezes the arm, never drives it home.
- `body_cmd` is an `InputRouter` cycle riding `VehicleInput`; the `merge_local` line is required or
  a touch source drops the keyboard edge.

## Fifth wheel, mass, axle loads

- Joint limits: roll ±1.5° not 0 (compliance lets the solver settle); pitch must COVER the steepest
  break of slope, never bound it (on its stop the bodies are rigid and the drive axle lifts);
  `exclude_nodes_from_collision` stays true; yaw stop is `Articulation.JACKKNIFE_MAX_DEG`, one
  constant for joint and fallback.
- Yaw friction is Coulomb (`TowHost._apply_yaw_friction`), never a spring toward zero or the joint's
  angular motor (a velocity target, it fights the stop).
- Wheelbase or COM change = re-run `tools/measure_semi_launch.tscn` (steer-axle load through launch,
  `docs/heavy_vehicles.md` § Truck sizing).
- Rear dampers (`damper_*_rear`) are explicit per spec; the fallback sizes for the bobtail corner.
- Mass: trailer:tractor <= 3:1 (`test_the_heaviest_trailer_holds_the_verified_mass_ratio`);
  `kingpin_share` 0.25-0.30 on every trailer (`test_every_trailer_puts_a_realistic_load_on_the_fifth_wheel`).
  Moving the share re-derives that trailer's bogie `spring_rate`, brakes, and the tractor's rear spring.
- Trailer `spring_rate` / `brake_torque` are sized off its own bogie load, never copied.
- `corner_mass` is `mass / wheel_count`: a trailer's clamps run ~25 % loose (its bogie carries only
  `1 - kingpin_share`), the tractor's run tight (plate load not in its `corner_mass`). Fix in the
  spec numbers, never the clamps.
- Coupled steer-axle share has a floor (`test_a_coupled_tractor_keeps_enough_steer_load_to_steer`).

## Rollover

- COM sits at real height; never lower a COM to buy a rollover threshold back. Levers:
  `GroundDriveSpec.anti_roll_rate` (0 today), `mu_lat`. Thresholds: `docs/heavy_vehicles.md` § Truck sizing.
- Narrow track (1.44 m) and the speed-taper steer lock are reopened: `docs/to_investigate.md`.

## Trailer authoring, pulling away

- Trailer origin at the kingpin, ground at y = -1.05; `Wheels` children in `spec.wheel_positions`
  order (`test_every_trailer_is_a_towed_body_with_its_wheels_authored_to_match_its_spec`).
- Gooseneck: nothing may hang below the coupling plane over the tractor.
- Boxes that TOUCH on a face plane z-fight; leave 2 cm or overlap. Guard:
  `test_no_two_boxes_share_a_face_plane_and_a_facing` (fix by moving the detail part, not the panel).
- Swing clearance: every BoxMesh corner fits inside the kingpin-to-cab gap; swept by
  `test_every_trailer_clears_the_cab_all_the_way_round`.
- Pull-away is decided by torque at `Drivetrain.converter_free_rpm`, never the peak: fix startability
  at the low end of the curve.

## ISO 11992 trailer bus

- `trailer_connected` = coupled AND `spec.trailer_bus_equipped`; the pneumatics
  still run without it.
- The two READ signals are read AFTER `tick_towed`; `clear_trailer_bus` runs each tick.
- `trailer_brake_demand` reports `retarder_state` (what ran), lagged by `TowedBody.BRAKE_APPLY_S` /
  `BRAKE_RELEASE_S`. The handbrake is unlagged (spring brakes apply by loss of air).
- A coupled trailer draws air through `air_step`'s `aux01`; spawn starts it charged, a driven coupling
  starts empty. The gate notice latches on `spring_brake_notice_edge`.

## Tractor-unit variants, lamps

- Variants differ by a `VehicleSpec` flag; absent = false, so an editor save may drop
  `trailer_bus_equipped` from the conventional (`test_the_trailer_bus_flag_is_opposite_on_the_two_shipped_units`).
- The conventional shares `semi_spec.tres`'s drivetrain/brake/suspension/tyre block; retune both.
- `Kingpin` Y is frozen (every trailer is authored against it); Z is free but each unit's gap is pinned
  (`test_each_tractor_unit_clears_the_trailers_worst_swing`).
- A trailer owns its own `LampSet` (`TowedBody.apply_lamps`), never a second resolve root on the
  tractor's. No contract change. `head_lamp_paths` stay empty (`test_trailer` pins lamps).

## Four trailers

- No per-trailer signal. Consumers are declared in code (`TowedBody.consumers()`); gating is in
  `TowHost.tick_towing`, never the subclass. Box and flatbed declare identically (pinned); hydraulics
  imply PTO.
- Load models move `center_of_mass` only (`set_load_offset`, which forces custom COM mode).
  `kingpin_share()` stays spec-based; `live_kingpin_share()` moves.
- Tipper valve is `1.0 - input.hitch_request`, not `scv_flow` (an `isobus` signal). Its raise
  interlock is chassis state (`TowedBody.body_raise_allowed`), refusing the raise direction only.
- Tipper collision is two authored poses plus a swap with hysteresis, never a posed shape.
- Controls are offered by capability (`attachment_controls()`); a press that DROPS a trailer is never
  refused; the fit check is exact contact, never a predictive `collide_shape`.
- Spawn coupling is a countdown (`SPAWN_COUPLE_TICKS`); never `return` before `tick_towed`.
- `TowHost.uncouple` `remove_child`s both bodies, except from `_exit_tree`, which calls
  `uncouple(false)` (`remove_child` fails while the parent is mid-removal).
- Garage freezes the trailer via `set_display_frozen`.
- `TrailerCatalog` order: box first (3:1 spawn), bobtail last and a real entry
  (`test_the_trailer_cycle_wraps_and_ends_on_bobtail`).

## Rejected — do not re-propose

- A packer cycle or tailgate on the refuse rig (front loader; respawn empties the hopper).
- A lateral tanker slosh term.

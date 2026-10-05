# 04 — Brakes, handbrake, retarder: size them from hardware

Shared context: `00_README.md`. Root cause 3 (ratings derived from other ratings). Size:
medium-large. Do brief 03 first, or no parking figure is meaningful.

## Summary

Brake strength is derived from the tyre (full pedal = 0.95 x the tyre's static grip), the
handbrake from launch torque (it must slip at ~30 % throttle), and the retarder from the service
brake (20 % of it). Real hardware is rated on its own: brakes out-torque both the tyre and the
engine in first gear. Seven consequences, most of them patched:

1. Full pedal asks only 0.95 x `mu_long` g overall: the brake hardware has no capacity beyond the
   static tyre. Wheels reach lock or ABS only where the per-axle split over-asks one axle
   (**measured**, `docs/vehicles.md` § Braking: ABS acts at full pedal on every ABS body tested
   and already at 60 % on `garbage-truck` and the semi; `race`, without ABS, skids 0.40 s).
2. First-gear drive at converter stall beats the driven axle's brake: 3.4-4.4x on the
   rear-driven heavies (**measured**), 1.3x on the tractor, and ~2.4x on a rear-drive car
   (**computed** for `police`: rear axle brake 1144 x 4 x 0.284 = 1.30 kNm against
   192.8 Nm x 4.5 x 4.0 x 0.9 = 3.12 kNm). So both pedals held creep the vehicle; settled in the
   input layer by `InputRouter.brake_override`.
3. Truck spring brakes are a kinematic `omega = 0` write, because no brake torque could hold the
   truck.
4. The handbrake cannot lock the rear wheels, so the drift is faked by cutting rear side grip
   (`handbrake_grip`).
5. Most cars cannot park on a legal grade.
6. The semi's service brake is bounded by the retarder test.
7. `race-future`'s first gear was lengthened (3.2 -> 2.375) to satisfy the brake-vs-tyre test.

## Where it lives

Derivation, `tools/gen_kenney_vehicles.gd`:
- `BRAKE_GRIP_FRAC = 0.95` (~line 52).
- `_derive_brakes` (~line 661): `brake_torque = ceil(max(0.95 * m*g/wheels * mu_long * r,
  hierarchy floor))`; `handbrake_torque = 0.75 * (torque at idle rpm * 0.25 * gear 1 ratio *
  final_drive * efficiency)` per rear wheel, so the pair is 1.5x the 25 %-throttle launch torque.
  `_front_brake_share` splits the foot brake by each axle's load-transferred grip (sound: keep it
  as proportioning).
- `race-future`'s gear 1 was lengthened (3.2 -> 2.375) so its engine stops saturating all four
  tyres and the brake rule holds: the history is in the `OVER_BRAKED` comment
  (`tests/test_vehicle_catalog.gd`) and the `_derive_brakes` header; the cap's arithmetic is in
  the `VARIANTS` comment.

Tests that pin today's philosophy:
- `test_vehicle_catalog.test_kenney_specs_keep_force_hierarchy`: brake > transmissible drive
  (`min(peak drive, driven wheels * mu_long * N * r)`); handbrake between the 25 % and 50 %
  idle-rpm launch torques.
- `test_vehicle_catalog.test_no_kenney_spec_brakes_harder_than_its_tyres_except_the_listed_ones`
  and its `OVER_BRAKED` ratchet ("anything past that is a lock, not a stop").
- `test_drivetrain.test_car_spec_brake_stronger_than_accel_stronger_than_handbrake`.
- `test_kenney_variants.test_brakes_are_what_the_generator_derives_from_the_tyre`.
- `test_truck.test_every_truck_spec_keeps_the_force_hierarchy_with_the_retarder_added` (covers
  the semis).
- `test_trailer.test_every_semi_trailer_brakes_at_one_fraction_of_its_own_wheel_load`.
- `test_drawbar_trailer.test_the_brake_is_inside_its_own_tyres_and_apportioned_to_the_tractors`.
- `test_input_arbitration.test_the_router_cuts_the_throttle_once_a_braked_body_creeps`.
- `test_truck.test_spring_brakes_apply_below_the_cut_in`.

Rules (`src/vehicles/CLAUDE.md` § Drivetrain and brakes): hierarchy "brake > TRANSMISSIBLE drive
> handbrake"; "Drift comes from `handbrake_grip`, never handbrake torque"; "Kenney `brake_torque`
derives from the tyre … with no per-family knob"; "fix gear 1 or torque, never the brake"; "The
tyre class (`mu_long` / `mu_lat`) is the root of everything brake-shaped: brake, retarder rating,
hierarchy floor, taper margin." Also:
- `src/input/CLAUDE.md`: "Both pedals held: `brake_override` … never a bigger brake".
- Truck CLAUDE.md § Brakes, retarder, air: "A kinematic LOCK (spring-brake pin) may be written
  after the tick"; "never raise `RETARDER_MAX_FRAC` to hold a figure"; air is a gate, not a bar.

Runtime:
- `WheelDrive.tick` (`src/vehicles/base/wheel_drive.gd`, ~lines 193-201): handbrake torque on the
  rears, `lat_grip_scale = lerp(1, handbrake_grip, handbrake)`, ABS off on a rear wheel while the
  handbrake is held. `GroundDriveSpec.handbrake_grip` doc: "arcade drift knob since
  handbrake_torque alone can't lock the rears" (CAR_BASE 0.45, race bodies 0.5, heavies 1.0).
- `TruckVehicle._apply_spring_brakes` (`src/vehicles/truck/truck.gd`): "first-gear drive torque
  exceeds brake_torque, so no torque could hold the truck".
- `InputRouter.brake_override` (`src/input/input_router.gd`); `docs/vehicles.md` § Both pedals
  (**measured**): gear-1 drive at converter stall vs driven-axle brake, `delivery` 20.9 vs
  4.8 kNm, `garbage-truck` 23.5 vs 7.0, tractor 23.7 vs 18.4; 6-17 m of creep in 10 s without the
  override.
- `InputRouter.locked_idle`: a bridge-only rig with no live bridge is parked with key Lock and
  handbrake 1.0. The RAMN gear byte has no P. Because `handbrake_grip` applies whatever the speed,
  a car parked on its handbrake also keeps only 45 % of its rear side grip (worse cross-slope
  creep, brief 03); removing `handbrake_grip` fixes that too.
- `src/vehicles/truck/semi_spec.tres` header: "brake_torque 10500 IS NOT GRIP-DERIVED …
  retarder_rating is a FRACTION of it, so 0.20 * B * 2 / 0.36 / 8000 must stay under 1.6 m/s^2
  (B < 11520)"; "handbrake_torque 4800 is pinned by construction" by the 25-50 % window.
- `Drivetrain.RETARDER_MAX_FRAC = 0.20` of `brake_torque` per driven wheel; band pinned by
  `test_truck.test_the_retarder_is_worth_feeling_on_every_shipped_truck` (0.7-1.6 m/s^2).
- Trailers: service brake "load-apportioned", handbrake = a quarter of the trailer's own service
  brake; the rig's parking brake lives on the trailer (trailer spec headers).

## Why it matters

- Real service brakes have more torque than the tyre can use at full pedal; a non-ABS car locks
  its wheels, which is what ABS exists for. Real brakes also hold a converter automatic at full
  throttle in gear 1: that is how a converter stall-speed test is done. The derivation conflates
  "what the hardware can make" with "what full pedal should ask for".
- Handbrake grade capacity, rear handbrake only (**computed** from mass, `handbrake_torque` and
  r = 0.36, ignoring creep):

  | Body | Holds up to |
  | --- | --- |
  | `van` | 10 % |
  | `pickup`, `pickup-flat`, `suv` | 11-12 % |
  | `taxi` | 13 % |
  | `sedan` | 14 % |
  | `police` | 15.5 % |
  | `suv-luxury` | 16 % |
  | `garbage-truck` | 18.5 % |
  | `sedan-sports`, `hatchback-sports`, `firetruck` | 19-20 % |
  | others (`race*`, heavy vans, tractor, semi bobtail) | 25 % and up |

  Coupled to the 24 t box trailer, the semi plus the trailer's spring brakes hold ~24 %
  (**computed**), which still passes.

  UN R13-H (cars and light vans) asks the parking brake to hold the laden vehicle on 20 %; UN R13
  (heavy goods vehicles) on 18 %. The planner should confirm the figures. Level 2's road averages
  16.4 %.
- With a handbrake that can lock the rears, the drift comes for free: RayWheel's combined-slip
  tyre already makes a locked wheel lose its side force ("A locked wheel's slip is almost all
  longitudinal: its force opposes the slide and it stops steering", `combined_slip_force`).
- The spring-brake lock bypasses the brake path (spin step, ABS rules) and relies on brief 03 to
  actually hold.

Note on intent: the handbrake's current sizing has a purpose ("holds only below ~30 % throttle":
you can drive off with it on). In reality a FWD car drives through a rear handbrake easily
(undriven axle); a RWD car mostly cannot. The planner should ask what behaviour the user wants.

`brake_override` is a real car feature (brake-throttle override). It can stay as a modelled
feature; what changes is that physics no longer needs it.

## What it would retire or re-examine

`handbrake_grip`; the kinematic spring-brake lock; `brake_override` as a necessity; the
`OVER_BRAKED` ratchet and "never a bigger brake"; `race-future`'s gear 1 (a gearing choice made
for a brake test); the semi brake bound; the hierarchy test and its CLAUDE.md rule.

## Constraints

- The brake goes through the semi-implicit spin step (`* spin_compliance`), never a
  `move_toward` after it (`src/vehicles/CLAUDE.md`; `test_wheel_spin` § brakes).
- ABS caps the foot brake and retarder at `RayWheel.ABS_SLIP`; a handbrake or spring brake is a
  mechanical hold no ABS modulates. Keep.
- Pedal feel: deceleration per pedal travel is linear to 0.95 x `mu_long` g at full pedal today
  (~1.0 g on the cars, ~0.76 g on the trucks). With more
  capacity the pedal-to-torque map is a decision (linear to the new capacity, so full pedal locks
  or hits ABS; or progressive). The `docs/vehicles.md` § Braking table (30 / 60 / 100 % pedal) is
  regenerated with `measure_vehicles -- doc=braking`.
- The truck air gate (spring brakes below `TruckTelemetry.AIR_SPRING_BRAKE_BAR`) and its notices
  stay; only the mechanism (lock vs torque) changes. Truck CLAUDE.md § Brakes, retarder, air.
- Tractor: rear-only brakes that engage MFWD (`brake_engages_front_axle`), no ABS. Keep
  (`test_tractor.test_the_foot_brake_engages_the_front_axle_and_brakes_only_the_rears`).
- Trailer brake lag (`TowedBody.BRAKE_APPLY_S` / `BRAKE_RELEASE_S`), trailer ABS and
  `trailer_brake_demand` reporting stay. Trailer `brake_torque` stays sized from its own bogie
  load (truck CLAUDE.md) unless the planner restates that rule too.
- Kenney changes via recipe + regen; the semi, conventional, trailer and farm-tipper specs by
  hand, header derivations rewritten.
- Brief 12 (user-swappable tyres) depends on this: today a tyre (mu) change silently re-derives
  the brake hardware.

## Done

- Each body declares brake hardware independent of its tyre: per-axle service brake, handbrake,
  retarder rating (its own figure: driveline torque or power), each sized to a real class with the
  derivation stated.
- Full foot brake can lock the wheels of a non-ABS body; ABS bodies hold the peak.
- The foot brake holds each body against full throttle in gear 1 at converter stall without
  `brake_override` (which may remain as a feature).
- With brief 03 done, each laden body parks on its handbrake on at least 20 % (cars and light
  vans) / 18 % (heavy goods vehicles); the handbrake can lock the rears at speed and the drift
  comes from the lock
  (`handbrake_grip` removed, or 1.0 everywhere).
- Truck spring brakes act as a brake torque, or the remaining lock is justified.
- Tests state the new hierarchy; `docs/vehicles.md` (§ Both pedals, § Braking, § Physics
  derivations) and `src/vehicles/CLAUDE.md` § Drivetrain and brakes rewritten.

## Open decisions (user)

- Pedal map: linear or progressive.
- What the handbrake does under throttle on RWD bodies.
- Whether `brake_override` stays, and for which families.
- Whether a park state (P / parking pawl) is wanted: the RAMN gear byte has none, so it would be a
  contract change.

## Related

Brief 03 (hold), 05 (its coupling model may add converter torque multiplication, which raises
gear-1 drive at stall: re-check the hierarchy then), 12.

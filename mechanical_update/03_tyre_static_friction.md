# 03 — Tyre static friction: held vehicles creep

Shared context: `00_README.md`. Root cause 2 (no static friction). Size: medium.

## Summary

Below 1.5 m/s the tyre force is proportional to sliding speed: the tyre behaves like a damper,
not like friction. A wheel locked by a brake therefore holds a slope only by sliding slowly, so
braked and parked vehicles creep down grades (and sideways on a cross-slope). Two existing
mechanisms work around the same gap.

## What happens

`src/vehicles/base/wheel.gd`, `RayWheel.tick`:
- Slip ratio and lateral slip share one denominator, `max(|v_long|, LOW_SPEED_FLOOR)` with
  `LOW_SPEED_FLOOR = 1.5` m/s (~line 14, ~lines 259-265).
- On the grip curve's linear rise (peak at slip 0.12) the force is
  `budget * slip_velocity / (0.12 * 1.5)`: linear in sliding speed, zero at zero speed.
- A brake holds `omega` at 0 (`_integrate_spin`, `move_toward` toward 0), so the locked tyre
  resists a slope only once the contact slides.
- Each axis is capped at the force that cancels its slip velocity in one tick (~lines 267-272).
  The comment says the lateral cap "kills parked-car jitter".

Mechanisms on the same gap:
- `TowedBody._size_lateral_caps` (`src/vehicles/base/towed_body.gd`): tightens trailers' lateral
  cap because "the tyres' explicit lateral stiffness at a standstill overruns the tick and the rig
  rings left/right off float noise" (marked COMPROMISE, towed bodies only). It is one of the 60 Hz
  clamps listed in `src/vehicles/CLAUDE.md` § The 60 Hz tick.
- Truck spring brakes pin rear `omega` to 0 (`TruckVehicle._apply_spring_brakes`); the tyre then
  creeps exactly like a braked one.

Made worse by: `handbrake_grip`. `WheelDrive.tick` applies
`lat_grip_scale = lerp(1, handbrake_grip, handbrake)` to the rear wheels whatever the speed, so a
car parked on its handbrake (including a rig parked by `InputRouter.locked_idle`) keeps only 45 %
of its rear side grip, which worsens cross-slope creep. Brief 04 removes `handbrake_grip`.

Not this gap: the tractor's draft speed ramp (`TractorTelemetry.DRAFT_SPEED_REF`). Its comment
blames a shove at a standstill, but `draft_newtons` already opposes travel, is 0 at rest and is
one-tick capped; its real job is the 60 Hz angular margin (brief 11).

In-repo precedent: the train already models the hold honestly. `TrainSim.brake_step`
(`src/vehicles/train/train_sim.gd`) applies the brake as Coulomb friction that "holds the car at
rest when the other forces (a grade) are within that, so a parked train does not creep" (tested:
`test_train.test_a_braked_train_holds_at_rest_on_a_grade`).

## Symptoms (computed, not measured)

- `sedan`, all four wheels braked, 10 % grade: equilibrium creep ~2 cm/s (~1 m/min; the one-tick
  cap binds slightly on the loaded fronts); 30 % grade ~5 cm/s.
- `sedan` on the handbrake alone (rear axle, ~40 % of the load): ~4 cm/s (~2.5 m/min) on 10 %.
- Same mechanism sideways on a cross-slope, for every body, trailers included.
- Where it bites: parking on level 2 (road mean grade 16.4 %), hill starts, a bridge-only
  challenge rig parked by `InputRouter.locked_idle` when the bridge drops, a semi parked on a
  grade.
- How to observe: no tool measures a held vehicle over time today (`measure_grade` holds the brake
  only for its 1.5 s settle, `SETTLE_S`, then releases it). Park on a level-2 slope and watch the
  position, or add a hold pass to a measure tool (the planner's call).

## Approaches used in vehicle sims (the planner chooses)

- **Contact anchor / bristle spring:** below a slip-speed threshold, remember the contact point
  and pull toward it with a spring-damper capped by the friction budget; release to sliding when
  the cap is exceeded.
- **Tyre relaxation length:** a first-order lag on slip with a length constant. Standard in
  Pacejka-style sims, gives finite stiffness at zero speed and removes low-speed ringing; needs its
  own 60 Hz stability check.
- **Coulomb hold like the train's:** if every other force along an axis is within the friction
  budget, zero the contact's velocity on that axis (in the one-tick-cap form).

Whatever the choice, the force stays inside the friction ellipse (`combined_slip_force`) and
inside the 60 Hz one-tick clamps.

## Constraints

- 60 Hz clamps stay; any new force path is one-tick clamped (`src/vehicles/CLAUDE.md` § The 60 Hz
  tick).
- The spin step reads the tyre's reaction torque and derives `reaction_stiffness` from it; a
  low-speed force change feeds that step. ABS and TC caps (`abs_spin_room`, `tcs_spin_room`) treat
  "near a standstill, where the floor lets it stop: a stopped vehicle must still be held" — keep
  them consistent.
- Launches start at zero speed: a static state must release cleanly into sliding, with no launch
  regression. Re-measure `measure_vehicles -- doc=accel`, `measure_grade -- doc=grade`,
  `measure_rough -- doc=rough`, and the CI gates (`measure_vehicles -- all 45 track strict`,
  `measure_semi_launch -- <unit> strict` on both tractor units).
- Trailers tick through `TowedBody.tick_towed` with the same RayWheel; the semi and drawbar
  couplings must not start buzzing (`test_tow_host`
  `test_a_coupled_rig_standing_still_stays_mirror_symmetric`).
- Painted-surface drag (`RayWheel.surface_drag_force`) is already Coulomb-style with a one-tick
  cap and 0 at rest; stay consistent with it.

## Done

- A vehicle held by its foot brake, handbrake or spring brakes, on a grade within its brake and
  grip capacity, stays at rest (no measurable creep over a minute), longitudinally and laterally.
- Past capacity it slides at the friction limit, not as a slow viscous creep.
- No new jitter at rest; launch, stop and tracking figures unchanged within noise.
- A test in the spirit of the train's hold test.

## Open decisions

- Which approach.
- The trailer lateral cap is a 60 Hz clamp, and "never remove or weaken a clamp" binds. Whether
  static friction makes it redundant (a rule reversal) or whether it should instead extend to
  every RayWheel body (its COMPROMISE comment states the cost: tighter crawl-speed lateral grip and
  a re-measure of every vehicle) is the user's call.

## Related

Brief 04 (parking figures are meaningless until a held wheel holds; it also removes
`handbrake_grip`).
Brief 05 Part C (creep and hill hold) is a different creep (converter drag at idle), not this.

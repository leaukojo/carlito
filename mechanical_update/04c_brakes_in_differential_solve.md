# 04c — Brakes inside the differential solve

Shared context: `00_README.md`. Follows brief 04. Size: medium. Do before 04d (the pawl wants the
same solve) and before 05 Part B (converter multiplication doubles the stall drive the brakes hold).

## Summary

A wheel's brake was integrated in its own spin step, and the differentials coupled the wheels AFTER
every wheel had stepped (`WheelDrive._couple_differentials`). A wheel its brake had just held at zero
was not part of the coupled solve: the coupling could turn it again, and `RayWheel`'s patch spring no
longer counted it as held. Where one driven wheel's own brake cannot beat its own drive, the centre
(or the MFWD shaft) carries that wheel's spin to the other axle and the held wheels let go. A real
AWD body holds on its brake TOTAL; this one held only if every driven wheel's own brake beat its own
drive.

## Symptoms

1. **`suv-luxury` creeps with both pedals floored** (**measured**, `measure_vehicles -- suv-luxury 30
   stall`, 2026-10-08: 0.5 m in 10 s, peak 0.095 m/s, under `InputRouter.brake_override`'s 1 m/s, so
   nothing cuts the throttle). `BrakeSizing.stall_hold_margin` 0.83 on its 2000 Nm SUV-class brakes;
   a 2600 Nm "performance SUV" class to dodge this was rejected as a rating chosen for a sim limit.
2. **`tractor-kenney` creeps 1.4 m in 10 s** (**measured**, same probe) on 34 kNm of brake against
   23.6 kNm of gear-1 drive: the pedal engages MFWD (`brake_engages_front_axle`) and brakes only the
   rears (`brake_bias_front` 0), so the driven fronts are braked only through the rigid shaft, which
   couples after the step. `stall_hold_margin` reads 0.00.
3. **The park pawl (brief 04d) is a brake on each driven wheel**, not a lock on the shaft, so an open
   diff cannot counter-rotate its two wheels in P (`WheelDrive.pawl_torque`).

All three are listed in `test_vehicle_catalog`'s STALL_CREEPERS (1, 2) or stated at the pawl (3).

## Where it lives

- `WheelDrive._couple_differentials`, `_couple_axle`, `_axle_compliance`, `_apply_axle_torque`
  (`src/vehicles/base/wheel_drive.gd`): the centre, then each axle, as `omega -= T * compliance`.
- `Differential.coupling_torque` / `bias_capacity` (`src/vehicles/base/differential.gd`): a friction
  coupling, the speed difference over the summed compliance, clamped to a capacity.
- `RayWheel._integrate_spin` (`src/vehicles/base/wheel.gd`): the brake takes off `min(brake *
  compliance, |omega|)` and sets `_spin_held` when it stopped the wheel; `held_force_cap` and the
  patch spring then hold the body to the brake's limit.
- `BrakeSizing.stall_hold_margin` (`src/vehicles/base/brake_sizing.gd`): with both axles driven it
  also takes the weakest wheel's own `B / D`, the COMPROMISE stated there.

## Why it matters

It forces a choice between an honest brake class and a body that holds (`suv-luxury` listed as a
creeper rather than sized to the sim). The same gap meets every AWD body and every pawl, and any
converter torque multiplication (05 Part B) widens it.

## Constraints

- `src/vehicles/CLAUDE.md` § Drivetrain and brakes: every differential is a friction coupling solved
  INSIDE the spin step through `spin_compliance`, never a post-tick torque; never a traction cap or
  a grip-aware split (rule 3). The brake goes through the semi-implicit step, never a `move_toward`
  after it.
- `Differential`'s coupling never reverses a spread; keep that property (it needs no 60 Hz clamp).
- The 60 Hz tick and its clamps bind. Guards: `test_wheel_spin` § brakes, § differentials;
  `test_tractor.test_the_foot_brake_engages_the_front_axle_and_brakes_only_the_rears`.
- Measure with `measure_vehicles -- <variant> 30 stall` (TC off, manual D1) and the grade and rough
  tables (`doc=grade`, `doc=rough`): a diff change moves them.

## Done

- A brake (and later the pawl) is a torque the coupled solve honours: a held wheel stays held unless
  the coupled torque past it exceeds its brake.
- `BrakeSizing.stall_hold_margin` drops its per-wheel AWD term and checks the brake total; its
  COMPROMISE note goes.
- `suv-luxury` and `tractor-kenney` leave STALL_CREEPERS (the ratchet fails until they do), and the
  stall probe shows each under 2 cm in 10 s.
- `docs/vehicles.md` § Both pedals rewritten.

## Related

Brief 04 (the stall-hold check), 04d (the pawl), 05 Part B, `docs/vehicles.md` § Both pedals.

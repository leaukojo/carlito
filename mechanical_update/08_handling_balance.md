# 08 — Handling balance: replace `rear_lat_grip` with real levers

Shared context: `00_README.md`. Root cause 3 (a stand-in for missing hardware). Size: medium. Do
after brief 07 (inertia changes spin-proneness).

## Summary

On equal tyres every body here steers near neutral and tips into a spin past the grip peak. The
understeer a road car needs is bought by giving the rear tyres more side grip than the fronts:
`rear_lat_grip` 1.08 on the cars, 1.15 on the open-wheelers. The spec doc calls it what it is:
"on a road car it stands in for the suspension design that makes it understeer". The real levers
are the front/rear split of roll stiffness (per-axle anti-roll bars) and tyre load sensitivity.

## What happens

- One `GroundDriveSpec.anti_roll_rate` for both axles: every wheel calls
  `bar_force(drive_spec.anti_roll_rate)` (`src/vehicles/base/wheel.gd`, `RayWheel.tick`).
- On the cars and vans, springs come per axle from one `ride_hz`, so each axle's spring rate, and
  its spring roll stiffness, is proportional to its load; with equal bars on top, lateral load
  transfer splits roughly like the weight. The Kenney trucks run one spring rate on every corner,
  the tractor 330 / 380 kN/m front / rear with no bar, the semis hand-sized per axle.
- Tyre force = `mu(L) * L` x grip curve, so cornering stiffness is proportional to load, bent
  only by `RayWheel.load_scaled_mu` (`mu * (1 - s * log2(L / ref))`, `s` = 0.10 cars, 0.08 trucks,
  vans and trailers, 0.12 tractor; a family number pinned by `test_kenney_variants`).
- `rear_lat_grip` multiplies the rear `mu_lat` (slope and peak), `RayWheel.apply_suspension`.
- Evidence (**measured**, `docs/vehicles.md` § Balance, step-steer probe 2026-10-03): at 1.0, a
  20 % steer step at 100 km/h spun `race` and `sedan-sports` (held or lifted) and the FWD `sedan`
  on a lift; at the shipped values none spin, one marginal case. The probe was a one-off, not a
  shipped tool.
- Rule (`src/vehicles/CLAUDE.md` § Wheels and ground): "a body's understeer margin is
  `rear_lat_grip`, never a slower steer or a detuned lock."

## Why per-axle bars alone are not enough

- With `s = 0.10`, moving lateral load across an axle changes its peak grip little (**computed**:
  outer wheel at 1.5x and inner at 0.5x its static load costs the axle ~1.9 %; lifting the inner
  wheel entirely costs ~10 %).
- The 10 % per doubling is a fair figure for peak mu (the generator's own comment says so). What
  the model lacks is the stronger flattening of **cornering stiffness** with load: here an axle's
  cornering stiffness goes as `mu(L) * L`, the same law as its peak grip, whereas a real tyre's
  cornering stiffness saturates well before its peak grip does. That saturation is what makes the
  roll-stiffness split bite in the linear range, where everyday understeer lives.
- Real road cars get understeer from front-biased roll-stiffness distribution, tyre load
  sensitivity (cornering stiffness above all), compliance and roll steer, and sometimes wider rear
  tyres. The planner should source per-class tyre figures.

## Interplay

- The open-wheelers' 1.15 is partly real: race cars run wider rears. Keep a rear tyre grip term
  for them, labelled as tyre width.
- The semi's bar (480 kN/m) is sized by the trailer twisting over through the ±1.5° plate: the
  tractor must not lean further than its trailer (truck CLAUDE.md § Rollover). A per-axle split
  must keep that.
- Trailers carry their own bar rates (`test_trailer`).
- Load sensitivity also feeds the brake split (`_front_brake_share` uses `load_scaled_mu`), launch
  and grade ceilings; a change is a re-derivation (recipe + regen) and a re-measure.
- Bars must keep reading the shared latched snapshot
  (`test_wheel_spin.test_the_bar_reads_one_shared_snapshot_whatever_the_tick_order`).
- Bar rates are sized with `measure_vehicles -- <variant> 45 corner` (4-8° of roll), then `track`.

## Done

- Front and rear roll stiffness can be set independently (in `GroundDriveSpec`, the generator and
  the hand specs).
- The tyre's cornering stiffness and peak grip each follow load the way a sourced tyre of that
  class does.
- `rear_lat_grip` back to 1.0 on road bodies (or a residual tied to a real hardware fact) with the
  step-steer results at least as good; the open-wheelers keep a labelled rear-width term.
- A step-steer pass in a shipped measure tool, so the balance claim can be re-checked.
- `docs/vehicles.md` § Balance and the CLAUDE.md rule rewritten.

## Open decisions (user)

- How much understeer each family should have (target behaviour for the step-steer pass).

## Related

Brief 07 (yaw inertia), 12 (load sensitivity becomes a tyre-class property).

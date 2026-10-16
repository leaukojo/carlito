# 15 — Roll steer: the missing source of linear understeer

Shared context: `00_README.md`. Root cause: missing suspension geometry. Size: medium.

## Summary

Per-axle bars and a cornering-stiffness load law reach the limit margin a road car needs, but not
its everyday understeer (`docs/vehicles.md` § Balance). At 0.15 g a bar split moves K by at most 0.25 deg/g, and
with `rear_lat_grip` at 1.0 most road bodies steer near neutral (−0.3 to +0.3 deg/g; the saloons ~1).
A real car's 2-3 deg/g comes mostly from roll camber, roll steer and compliance steer. Bundorf &
Leffert (SAE 760713) give tyres plus load transfer only 1.0 of 4.1 deg/g. The shortfall is stated
there.

## What happens

- A steered wheel's angle is the slewed steer alone (`WheelDrive.tick`); a rear wheel never steers.
  No angle follows the body's roll or the tyre's side force.
- Roll runs ~4.7 deg/g on the cars (`corner`: `sedan` 4.3 deg at 0.91 g), inside a road car's
  3-6 deg/g.

## Size of the effect (computed)

- Roll understeer adds `(e_f - e_r) * roll gradient` to K, where `e` is each axle's steer per degree
  of roll (+ = toward understeer). At 4.7 deg/g, 1.5 deg/g of K needs `e_f - e_r` ≈ 0.3. That is at
  the high end, so roll camber or compliance steer may have to carry part of it. Source the per-axle
  figures (Milliken RCVD; Gillespie ch. 6) before choosing.

## Considerations

- It is an honest model (CLAUDE.md rule 3): a per-axle spec figure defaulting to 0, applied as a
  wheel angle off the latched roll, never a grip multiplier.
- Each body's yaw also bleeds through Godot's default angular damping (0.1 /s;
  `VehicleSpec.angular_damping` 0). That adds +0.13-0.20 deg/g at 30 km/h, falling as 1 / v
  (measured, `docs/vehicles.md` § Balance). Decide here whether it stays or is declared per body.
- `BalanceModel` predicts K; a roll-steer term goes in beside its angular-damping term, so the
  `pred` readouts stay calibrated.
- The 60 Hz rules: an angle that follows roll is a feedback loop on the tick; it must not ring.

## Done

- Per-axle roll steer on `GroundDriveSpec`, pure tests, and a `BalanceModel` term.
- The road cars' step pass reads K inside a sourced class band at 30 km/h, with no new `spun` cell.

## Related

`docs/vehicles.md` § Balance, § Steering geometry (Ackermann: per-wheel angles).

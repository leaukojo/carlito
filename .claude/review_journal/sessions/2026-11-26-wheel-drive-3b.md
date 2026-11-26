# 2026-11-26: unit 3b, `src/vehicles/base/wheel_drive.gd` (Opus)

Read whole at cf5abde (1173 lines), with Fable's notes (`2026-11-15-wheel-fix-landed.md` § Unit 3b).

## Findings

1. Wrong comment, `tick`'s doc: "resistance reads this tick's spring load so it must follow the
   wheel loop". `_apply_resistance` calls `VehicleMath.air_force(body.linear_velocity,
   WindField.at(body), body.global_basis, gd.drag_area, gd.side_area, body.mass, delta)`: no spring
   load; the velocity does not move inside the tick and forces sum. S: clause dropped.
2. Wrong comment, `_axle_stations`: "INF on a side with no wheel"; the rear side is `-INF`
   (`var rear_z := -INF`). S.
3. History wording, `_rigid_downstream`'s doc: "so a locked clutch held its crank at up to 3x its
   wheels' spin, every tick" describes the order it replaces as a past event. S: "would hold".
4. Duplicate: `esc_step`'s off branch and `respawn` clear the same nine ESC fields (`_esc_torque`,
   `_slip_est`, `_roll_app`, `_roll_chamber`, `_esc_brake`, the three `esc_*_active`,
   `brake_light_request`). One helper; plain assignments, so order and results are unchanged. S.
5. Duplicate: `_build_dust` re-derives the rear half track from `gd.wheel_positions` with
   `RayWheel.is_rear_z`; `_init` already keeps it as `_half_track.y` (max `|anchor.x|` over
   `is_rear` wheels; `anchor` is the position, `is_rear = is_rear_z(anchor.z)`) and `build_dust`
   runs after `_init`. The loop and `_build_dust`'s `gd` argument go:
   `maxf(0.6, _half_track.y)` is the same value. S.
6. Dead clamp, `pawl_torque`: `maxf(gd.park_pawl_torque, 0.0)`. Its one caller (`tick`) takes
   `maxf(pawl_torque(...), standstill_lock / ...)`, the second term ≥ 0, so a negative spec value
   could change nothing; no spec declares one. S: returns the spec's value.

## Seen and not findings

- `LOCK_STUCK_SPIN` (Fable's cover candidate): the tolerance of `_couple_differentials`' one-pass
  `COMPROMISE` (real), stated as such in its comment and `docs/vehicles.md` § P (park);
  `test_an_awd_body_holds_on_the_pawl_through_its_centre` needs it (its residual ~0.007 rad/s). The
  fault it tolerates is labelled, not hidden. Kept.
- `LOCK_STUCK_SPIN`'s second steady state (suv rolling back ~0.3 m/s on 16.7°, then P: four wheels
  at -0.034 rad/s, never re-held): unproven at HEAD. `measure_grade`'s park table (`suv` 30 % pawl:
  0.2 mm in 60 s) starts from a settle, not a roll-back, so it does not reach that state. Queued as
  a gather.
- `abs_slip` per wheel off two loop-invariant reads: hoisting is a rewrite of the same size, not a
  finding.
- `_build_dust` / `_soft_dot_texture` in code: no cost named (the emitter's box sizes off the spec).
- `apply_at` sits in `WheelDrive` though `TowedBody` uses it too: moving it is moved code.
- The three `COMPROMISE` labels (`set_esc_mass`, the retarder's slip cap, the one pass): real.
- `hold_step`, `esc_step`, `drive_omega`, `ackermann_angle` (cotangent mean checked),
  `brake_application` (k solved), `_settled_drive_spin` (saves and restores `_coupling`; the
  readout's last call is `_couple_differentials`' own) match their comments.

## Commits

- 4dc88e9: findings 1 to 6. `test_wheel_spin.gd` + `test_drivetrain.gd` 324 pass; full suite
  2582 pass, 0 failures.

## Deferred

- The pawl's second steady state: a gather line (Sonnet), since no run at HEAD reaches the state.


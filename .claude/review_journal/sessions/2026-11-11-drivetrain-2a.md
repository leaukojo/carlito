# 2026-11-11: Unit 2a, `drivetrain.gd`

Started at dde86b9. Unit 2 (about 6.9k lines with its tests) is split in the map: 2a
`drivetrain.gd` (this session, read whole), 2b `test_drivetrain.gd` + `docs/drivetrain.md`,
2c the four small files and their tests. Cut short at the user's request (tokens):
`docs/drivetrain.md` was read but not checked line by line, so it moves to 2b.

## Findings

1. **Wrong comments: the rigid crank's rpm (S, fixed).** Four comments said the rigid crank's
   rpm follows the wheels:
   - header: "rpm follows the wheels, clamped [idle, redline]";
   - `RPM_SMOOTH`: "rate the rigid crank's rpm tracks the wheels";
   - `rpm_from_wheel`: "and the rigid crank's target ... the smoothing lerp settles an epsilon
     short of redline";
   - `drives_wheels`: "where wheel speed alone sets rpm".
   The code (`process`, rigid branch): `target_rpm := lerpf(spec.idle_rpm,
   limiter_line(spec, gear_byte), clampf(throttle, 0.0, 1.0))`, then
   `rpm = lerpf(rpm, target_rpm, 1.0 - exp(-RPM_SMOOTH * delta))`. The throttle sets it; no
   wheel does. `docs/guide/engine.md` § The simpler engine already says so.

2. **Dead outputs of the rigid branch (L, queued).** The branch runs only when
   `drives_wheels(spec)` is false, so:
   - its return, `(wheel_torque + overrun_t) * ramp`, reaches no wheel: `base_vehicle.gd:155`
     hands it only to `drive.tick`; boat, drone and train have `drive == null`; the plane's
     spec has `driven_front = false`, `driven_rear = false`, and `wheel_drive.gd:649` gives
     `drive_t` 0 to an undriven wheel, `_couple_downstream` 0 to an undriven axle. Its one
     other reader is `_drive_torque` (`HillHold.drive_holds`), and the plane's `hill_hold` is
     the default NONE;
   - its `drive_wheel_omega` is always 0 (`0.0` with no drive; `drive_omega` averages driven
     wheels, none on the plane), so `limiter_rpm` is 0 in gear and idle in N, `on_limiter`
     never sets and `crank_forward` is always true.
   What is live there: the free-rev rpm, `applied_throttle` (governor, `drag_fuel` floor,
   torque restore, ESC cap, shift cut), the gearbox. Not started: it crosses units 3 and 4
   (`WheelDrive.tick`'s `axle_torque` parameter) and the rigid-branch tests in
   `test_drivetrain.gd` (about nine sites build a `ground_drive = null` spec).
   This is not the rejected "split `Drivetrain` into gearbox and rpm" (`docs/vehicles.md`).

## Checked, no finding

- Every `func`, `const` and `var` of the file is referenced (in-file, `src/`, `tools/` or
  tests). `shift_cut_active` ("test accessor") is also read by `tools/measure_vehicles.gd`.
- The two `COMPROMISE` labels (`lockup_holds`, `cvt_efficiency`) are real: each states what is
  true and the undo cost. Count unchanged.

## Commits

- ab672ce: the four comments. Full suite: 2423 cases, 0 failures.

# 09 — Ackermann steering

Shared context: `00_README.md`. Root cause: a missing piece of geometry. Size: small.

## Summary

In a turn the inner front wheel rolls on a smaller circle than the outer one, so it needs more
steering angle; Ackermann geometry gives it that. Here both steered wheels get the same angle
(parallel steer), so in tight turns the two front tyres point at different turn centres and
scrub against each other: a slightly wider turning circle and drag at parking speeds. Negligible
at road speed.

## What happens

- `WheelDrive.tick` (`src/vehicles/base/wheel_drive.gd`) sets `w.steer_angle = _applied_steer`
  for every steered wheel.
- `WheelDrive.steer_angle_from_curvature` documents it: "One angle for both steered wheels (no
  Ackermann)". ISOBUS guidance converts curvature to an angle with the bicycle model
  (`atan(wheelbase * curvature)`).

## Size of the effect (computed)

- `sedan` (wheelbase 1.58 m, track 1.26 m) at full lock, 38° mean: the inner wheel should be
  ~49° and the outer ~31°, so both are 7-11° off. Below `RayWheel.LOW_SPEED_FLOOR` (1.5 m/s) the
  lateral slip reads `v_lat / 1.5`, so a 10° misalignment reaches the grip peak (slip 0.12) at
  about 1 m/s and passes it above that; slower, the two tyres still fight each other on the
  curve's linear rise.
- The toy-scale bodies make it larger than on a full-size car: track / wheelbase is ~0.8 here
  against ~0.57.
- Most visible on the tractor in headland turns (38° lock, 1.62 m front track, 2.12 m wheelbase)
  and when parking.

## Considerations

- Geometry: `cot(outer) - cot(inner) = track / wheelbase` is 100 % Ackermann. Road cars run partial
  Ackermann (often well under 100 %), some race cars parallel or anti. A spec fraction (0 = today's
  parallel steer) fits the "spec flag defaulting off" rule.
- The bicycle (mean) angle should stay what guidance and the speed taper compute, so guidance
  curvature tracking is unchanged (`test_tractor.test_guidance_wheel_angle_matches_the_slewed_steer_with_no_taper`,
  `test_guidance_curvature_clamps_to_the_mechanical_lock_not_the_taper`).
- Which wheel the mechanical lock limits (usually the inner) is a decision; the taper margin test
  `test_vehicle_catalog.test_a_steering_taper_never_out_limits_the_tyres` reads the lock.
- The tractor's rigid MFWD winds up in tight turns (`TRACTOR_BASE` comment); Ackermann reduces
  front scrub, not the front/rear axle speed mismatch.
- Wheel visuals already follow each wheel's `steer_angle` (`RayWheel._update_visual`).

## Done

- Per-wheel steered angles from the mean angle, track and wheelbase, with a per-spec Ackermann
  fraction; pure-function tests.
- The user drives the sedan and the tractor at full lock: no front scrub, turning circle as
  expected.

## Related

Brief 10 (per-axle radius and an MFWD lead ratio also bear on tight-turn wind-up).

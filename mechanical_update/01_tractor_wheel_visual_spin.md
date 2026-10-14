# 01 — Tractor tyres visually spin too fast

Shared context: `00_README.md`. Root cause: none (a visual bug). Size: trivial.

## Summary

The tractor's rear tyres visually spin 1.83x too fast and its front tyres 1.22x. Physics and
telemetry are correct; only the drawn rotation is wrong.

## What happens

- `RayWheel._update_visual` (`src/vehicles/base/wheel.gd`, ~line 463) advances
  `_spin_angle += omega * delta`, where `omega` is the physics spin at the physics radius
  `GroundDriveSpec.wheel_radius` (0.36 m on every body).
- The tractor draws bigger tyres: `wheel_visual_radius` 0.44 (front) and
  `wheel_visual_radius_rear` 0.66 (rear) in `src/vehicles/kenney/tractor-kenney_spec.tres`, set by
  `WHEEL_TRACTOR_FRONT` / `WHEEL_TRACTOR_REAR` in `tools/gen_kenney_vehicles.gd`. Tread speed is
  `R * omega`: 0.66 / 0.36 = 1.83x ground speed rear, 0.44 / 0.36 = 1.22x front. Front and rear turn
  at the same rate, where a real tractor's smaller fronts turn ~1.5x faster.
- Only the tractor ships a visual radius different from its physics radius; any future body that
  declares `wheel_visual_radius` inherits the bug. The ISOBUS `wheel_speed` / `wheel_slip`
  (`TractorTelemetry.wheel_kmh`) are right.

## Constraints

- RayWheel overwrites the visual's root transform every tick; per-instance tweaks ride the visual's
  children (`src/vehicles/CLAUDE.md` § Wheels and ground). The right-side flip is
  `Basis(Vector3.RIGHT, PI)` on the child.
- RayWheel knows the visual radius only through `visual_lift`; `WheelDrive._init` computes
  `vis_radius` per corner and could hand it over.
- Do not change the physics radius here (brief 10). A pure static helper for the angle step is cheap
  to unit-test (root rule 8).

## Done

- Each wheel's visual rotation advances at `omega * physics_radius / visual_radius`, so the drawn
  tread matches the contact's surface speed.
- The user drives the tractor and sees the tyres roll without apparent slip.

## Related

Brief 10 (a per-axle physics radius would remove most of the mismatch).

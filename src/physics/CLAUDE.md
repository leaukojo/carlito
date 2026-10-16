# Collision layers — rules

- Masks are deliberately generous: a too-narrow mask drops a body through geometry silently.
  Widen first, diagnose second.
- **The water kill volume is a pairing across two files**: `WaterSurface`'s mask names `VEHICLE`
  and `BaseVehicle`'s layer is `VEHICLE`. `tests/test_collision_layers.gd` pins only the
  `WaterSurface` half.
- The authoring ground-snap rays (`scatter_base`, `scatter_brush`, `ground_snap`,
  `flying_check`) stay unmasked on purpose: they snap to whatever is there.

# Collision layers — rules

`collision_layers.gd` is the declaration. It is a bake input: a code edit (not a whole-line
comment) re-stales every level.

- **The seven bits are FROZEN**: they are written into `project.godot`'s `[layer_names]`, every
  `.baked.scn` and `cargo_payload.tscn`. A new layer appends at bit 8+; none is renumbered.
- **`SOLID` (everything but `Containment`) masks every gameplay ray.** `Containment` is
  `WorldBounds`, walls off the coast reaching 1500 m up: a ray that sees them makes the drone lose
  satellites over open water and pulls the chase camera in at the beach.
- Moving bodies mask `WORLD`; static bodies mask `DYNAMIC`. Masks are deliberately generous: a
  too-narrow mask drops a body through geometry silently. Widen first, diagnose second.
- **The water kill volume is a pairing across two files**: `WaterSurface`'s mask names `VEHICLE`
  and `BaseVehicle`'s layer is `VEHICLE`. `tests/test_collision_layers.gd` pins only the
  `WaterSurface` half.
- Bodies take their layer in `_ready`, never in a `.tscn`. Exception: `CargoPayload`, authored in
  `cargo_payload.tscn` (and copied into its instances in `level_6.tscn`), because `_ready` is
  where it remembers the layer to restore on release.
- The authoring ground-snap rays (`scatter_base`, `scatter_brush`, `ground_snap`,
  `flying_check`) stay unmasked on purpose: they snap to whatever is there.

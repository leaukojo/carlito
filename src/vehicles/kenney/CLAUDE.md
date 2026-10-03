# Kenney bodies — rules

`tools/gen_kenney_vehicles.gd` writes every scene and spec here; a change goes into its recipe
(`vehicle-feel` skill).

- **Lamps are measured, never guessed**: the generator samples the colormap atlas per triangle
  and unions same-shade triangles into lens clusters (amber = front, red = rear), filtering
  candidates BEFORE merging (or a lens fuses into a same-hue panel: the firetruck). Each lens
  splits inboard 65 % head/brake, outboard 35 % indicator. A `fallback` in the lens report is a
  body-box guess; correct its height in `_fallback_lamp_y`, never in the `.tscn` (`Lamps` is
  generator-owned).
- **Hand-authored anatomy survives a regen by whitelist**: the generator owns only
  `GENERATED_CHILDREN` (`Model`, `Lamps`) and transplants every other direct child (the
  collision box pair, the tractor's `ThreePointHitch`, `HoodCam`). Only a variant with no scene
  yet gets a generated convex hull; to reset one, delete its collision nodes, then regen. A new
  generated child joins `GENERATED_CHILDREN`, or the old one is transplanted beside it.
  - Extras are **reparented** out of a `GEN_EDIT_STATE_INSTANCE` load, never duplicated:
    `duplicate()` loses instance state, so the hitch would land pinned to today's hitch script.
  - A `;` comment in a generated `.tscn` does not survive, and while one is there the regen
    re-churns every `unique_id`. Notes go here or in the generator.
  - Guard: `test_regen_reproduces_every_shipped_scene` (a regen of a current scene is a no-op).
- **Wheel stations use one track for the whole body** (`_analyze` averages the four
  half-widths); flush-X alone would follow the flared fender and tucked arch. A body whose axles
  wear different wheel models (the tractor) keeps per-axle stations.

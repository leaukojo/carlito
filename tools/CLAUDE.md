# Tools — rules and run lines

Editor/CI scripts. Kit/bake rules: `kit/CLAUDE.md`.

- **A level generator's chain lives in its manifest**, `src/levels/**/<id>_gen.json`; a generator
  edit moves the manifest in the same commit (`src/levels/CLAUDE.md`).
- **Thumbnail generators run WINDOWED** (a headless capture is blank) and never in CI. They share
  `shot_stage.gd`. Their PNGs are not byte-deterministic: compare a re-run with `png_drift.gd`,
  not a byte diff.
- **Never speed a measure tool up with `Engine.time_scale`**: it enlarges the physics step. Pass
  `--fixed-fps 60` before `--` instead: same tick, byte-identical output, ~10x faster.
- **A new measurement is a scenario in an existing tool**; shared setup goes in `measure_rig.gd`.
- Measure-tool run lines, flags and the `doc=` figure presets: `docs/vehicle_measurements.md`
  § Measure-tool run lines.

## Rare generators

```powershell
# palettes/prefabs (after kit/import recipe edits only)
& $GODOT --headless --path . --script res://tools/gen_kit_assets.gd
# kit thumbnails (windowed), re-import, then regen to embed the previews
& $GODOT --path . res://tools/gen_thumbs.tscn ; & $GODOT --headless --path . --import
& $GODOT --headless --path . --script res://tools/gen_kit_assets.gd
# vehicle selector cards (windowed; every variant + implement/trailer), then re-import
& $GODOT --path . res://tools/gen_vehicle_thumbs.tscn ; & $GODOT --headless --path . --import
# Kenney / watercraft bodies (after a recipe edit)
& $GODOT --headless --path . res://tools/gen_kenney_vehicles.tscn
& $GODOT --headless --path . res://tools/gen_boat_variants.tscn
# drone-mk2 model (Blender 5.1; only to regenerate, the GLBs are committed), then re-import
& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --factory-startup --python tools/gen_drone_model.py
```

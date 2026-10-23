# Tools — rules and run lines

Editor/CI scripts. Kit/bake rules: `kit/CLAUDE.md`; a level generator's manifest: `src/levels/CLAUDE.md`.

- Thumbnail generators run windowed (a headless capture is blank), never in CI; they share
  `shot_stage.gd`. Their PNGs are not byte-deterministic: compare a re-run with `png_drift.gd`.
- Never speed a measure tool up with `Engine.time_scale` (it enlarges the physics step): pass
  `--fixed-fps 60` before `--`, same tick and output, ~10x faster.
- A new measurement is a scenario in an existing tool; shared setup goes in `measure_rig.gd`.
  Run lines, flags, `doc=` presets: `docs/vehicle_measurements.md` § Measure-tool run lines.

## Rare generators

```powershell
# palettes/prefabs (after kit/import recipe edits only)
node tools/godot_run.mjs -- --headless --path . --script res://tools/gen_kit_assets.gd
# kit thumbnails (windowed), re-import, then regen to embed the previews
& $GODOT --path . res://tools/gen_thumbs.tscn ; node tools/godot_run.mjs -- --headless --path . --import
node tools/godot_run.mjs -- --headless --path . --script res://tools/gen_kit_assets.gd
# vehicle selector cards (windowed; every variant + implement/trailer), then re-import
& $GODOT --path . res://tools/gen_vehicle_thumbs.tscn ; node tools/godot_run.mjs -- --headless --path . --import
# Kenney / watercraft bodies (after a recipe edit)
node tools/godot_run.mjs -- --headless --path . res://tools/gen_kenney_vehicles.tscn
node tools/godot_run.mjs -- --headless --path . res://tools/gen_boat_variants.tscn
# drone-mk2 model (Blender 5.1; only to regenerate, the GLBs are committed), then re-import
& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --factory-startup --python tools/gen_drone_model.py
```

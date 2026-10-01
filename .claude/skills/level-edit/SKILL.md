---
name: level-edit
description: Closing steps after any change to a level, kit/, a bake input, or a level generator (re-bake, check_bakes, manifest, card).
---

Rules: `kit/CLAUDE.md`, `src/levels/CLAUDE.md`. Steps:

1. A CLI generator touched the level: its `src/levels/**/<id>_gen.json` moves in the same change.
2. Re-bake, then check (one headless Godot at a time):
   ```powershell
   & $GODOT --headless --path . res://tools/bake_levels.tscn      # or -- src/levels/<level>.tscn
   & $GODOT --headless --path . res://tools/check_bakes.tscn
   ```
3. A road or road-profile edit: re-run the paint before the bake (never on `car_arena`):
   `& $GODOT --headless --path . res://tools/paint_road_asphalt.tscn -- src/levels/<...>/<level>.tscn`
4. The level's look changed: ask the user to re-shoot its card (Polish tab, windowed, after the
   bake).
5. `powershell -File tools/preflight.ps1`; sweep new GDScript warnings.
6. Ask the user to verify by driving the level (F6).

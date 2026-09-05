Editor/CI scripts. The kit/bake/editor-tool gotchas apply here too:

**A feel change edited into a GENERATED scene must be edited into its recipe here in the same
commit** — the generator is the source, the `.tscn`/`.tres` is output. Worked example and the
family-baseline form: `src/vehicles/CLAUDE.md`.

**A level generator's CHAIN lives in that level's manifest, not in a header comment** —
`src/levels/**/<id>_gen.json`, described in the root `CLAUDE.md`. These headers point at it;
edit a generator's stages or ordering and the manifest moves in the same commit. Run one with
`powershell -File tools/rebuild_level.ps1 -Level <id>` (`-DryRun` prints the chain and stops).
The driver judges each Godot step by OUTPUT rather than exit code — leak-at-exit makes the code
meaningless, and `preflight.ps1` does the same.

**`tools/shot_stage.gd`** (`preload`ed, not `class_name`d) is the offscreen-capture sequence
shared by the three PNG-writing thumbnail generators (`gen_thumbs.gd`, `gen_level_thumbs.gd`,
`gen_vehicle_thumbs.gd`): build the capture `SubViewport`, settle N frames, read back and
write the PNG. Framing, lighting and subject setup are genuinely per-generator and stay there;
`src/ui/scene_bounds.gd` is the matching shared AABB walk (detail: `src/ui/CLAUDE.md`). All
three generators must run WINDOWED — a headless capture comes back blank — and their PNG
output is not byte-deterministic run to run, so a re-run is verified with `png_drift.gd`, not
a byte diff.

@../kit/CLAUDE.md

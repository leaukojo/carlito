# Bridge — rules

Protocol tour: `docs/systems.md` § Bridge. Contract rules: `contract/CLAUDE.md`. Lamp mirroring:
`src/vehicles/CLAUDE.md` § Lamps.

- **`web/head_include.html` and `web/shell.html` are vendored copies** that must stay in sync
  with `export_presets.cfg` and the Godot export template. Read `docs/deploying.md` § The web
  export before touching either, or before a Godot upgrade. Guard:
  `tools/check_head_include.mjs` (preflight + pre-commit).

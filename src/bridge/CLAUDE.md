# Bridge — rules

Protocol tour: `docs/systems.md` § Bridge. Contract rules: `contract/CLAUDE.md`. Lamp mirroring:
`src/vehicles/CLAUDE.md` § Lamps.

- **`web/head_include.html` is a vendored copy** that must stay in sync with
  `export_presets.cfg`. Read `docs/deploying.md` § The web export before touching it. Guard:
  `tools/check_head_include.mjs` (preflight + pre-commit).

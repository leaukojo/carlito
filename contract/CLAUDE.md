# Contract — authoring rules

`carlito_contract.json` defines every bridge signal; protocol tour: `docs/systems.md`. To make
an edit, run the `contract-edit` skill.

- **Every edit bumps `version`**, and with it `tests/test_contract.gd`'s
  `test_real_contract_is_valid` assert: nothing else pins the number.
- **An edit is a paired change across two repos**: the pre-commit hook regenerates
  `../sloppycan/carlito_contract.js` (`node tools/gen_js_contract.mjs`) and fails while that copy
  changed; commit it in `sloppycan` too, and promote both together.
- **`status` bits (`ST_*` in `src/vehicles/base/vehicle_telemetry.gd`) are append-only**: a new
  flag takes bit 7+, an existing bit is never renumbered.
- **Omit `range`** on an "out" signal with no meaningful full scale (`engine_hours`): it becomes a
  readout beside ODO instead of a bar.
- sloppyCAN has no train or plane panel. Adding one is sloppyCAN-side only.

# Contract — authoring rules

`carlito_contract.json` defines every bridge signal; protocol tour: `docs/systems.md`. To make
an edit, run the `contract-edit` skill.

- **Every edit bumps `version`**, and with it `tests/test_contract.gd`'s
  `test_real_contract_is_valid_v<N>`: the number is in the assert AND the test name, and nothing
  else pins it.
- **An edit is a paired change across two repos**: the pre-commit hook regenerates
  `../sloppycan/carlito_contract.js` (`node tools/gen_js_contract.mjs`) and fails the commit until
  that copy is committed in `sloppycan`; both land on `dev` and are promoted together.
- **`status` bits (`ST_*` in `src/vehicles/base/vehicle_telemetry.gd`) are FROZEN**: a new flag
  appends at bit 7+ (nine free in the u16), an existing bit is never renumbered. A new bit is a
  version bump.
- Signals are unique by **(name, dir)** (`battery` exists both ways).
- **`count`** (default 1) makes a signal ARRAY-valued, `range`/`warn` per element, zero-based like
  the wire. Rejected on `"in"`, on `bool` and with an `enum`; the bridge enforces the shape both
  ways.
- **`warn` requires `warn_side`** (`"low"` | `"high"`) **and a `range`**: never inferred, and the
  dashboard skips a range-less signal before it reads `warn`.
- **Omit `range`** on an "out" signal with no meaningful full scale (`engine_hours`): it becomes a
  readout beside ODO instead of a bar.
- sloppyCAN has no train or plane panel. Adding one is sloppyCAN-side only: both families already
  have exclusive `dir:'out'` signals.

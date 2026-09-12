# Contract — authoring rules

`contract/carlito_contract.json` defines every bridge signal; full protocol in
`docs/systems.md`.

- **`count` — an instanced signal** (default 1) is ARRAY-valued: `count` elements, `range`/
  `warn` per element (the drone's four ESCs; `slip` is per-axle, 0 = front). Parse-rejected
  on `"in"`, on `bool` and with an `enum`; the bridge enforces the shape in BOTH directions.
  Indices are **zero-based**, matching the wire.
- Signals are unique by **(name, dir)** — `battery` exists in both directions. `warn` is the
  dashboard danger threshold and **requires a `warn_side`** (`"low"` | `"high"`); the two are
  parse-rejected apart, never inferred from the range.
- **Omit the `range`** on an "out" signal with no meaningful full scale (`engine_hours`) and
  it lands on the readout line beside ODO instead of becoming a bar.
- The bump also moves `tests/test_contract.gd`'s `test_real_contract_is_valid_v<N>` — the
  number is in the assert AND in the test's name, and nothing else pins it.
- Edits bump `version` and **must be followed by `node tools/gen_js_contract.mjs`** (the
  runtime version-mismatch warning — **not CI** — is the drift guard). **A contract edit is
  a paired change across two repos**: the bump lands on `dev` in both `carlito` and
  `sloppycan`, and both are promoted to stable together.

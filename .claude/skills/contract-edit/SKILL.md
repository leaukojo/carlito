---
name: contract-edit
description: Steps for any edit to contract/carlito_contract.json or a new ST_* status bit (version bump, test rename, sloppyCAN copy, paired promote).
---

Rules: `contract/CLAUDE.md`. Steps:

1. Edit `contract/carlito_contract.json`; bump `version`.
2. Rename and re-number `tests/test_contract.gd`'s `test_real_contract_is_valid_v<N>` (name AND
   assert).
3. A new `ST_*` bit appends at bit 7+ in `src/vehicles/base/vehicle_telemetry.gd`; never renumber.
4. A new "out" signal needs a matching telemetry member var (`to_bridge_dict` walks the property
   list); a new "in" signal needs its `bridge_source.gd` key and arbitration in `src/input/`.
5. `node tools/gen_js_contract.mjs` (the pre-commit hook also runs it and fails until the copy is
   committed in `../sloppycan`).
6. Run `tests/test_contract.gd`, `test_telemetry.gd`, `test_dashboard.gd`, then the full suite.
7. Tell the user: the change lands on `dev` in both `carlito` and `sloppycan` and is promoted
   together (`docs/deploying.md` § Contract changes are a paired deploy).

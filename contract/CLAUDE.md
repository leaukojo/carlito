# Contract — authoring rules

`carlito_contract.json` defines every bridge signal (tour: `docs/systems.md`). Any edit runs the
`contract-edit` skill: a version bump, its test assert, the sloppyCAN copy, a paired promote.

- `status` bits (`ST_*` in `src/vehicles/base/vehicle_telemetry.gd`) are append-only: a new flag
  takes bit 7+, an existing bit is never renumbered.
- Omit `range` on an "out" signal with no meaningful full scale (`engine_hours`): it becomes a
  readout beside ODO instead of a bar.
- sloppyCAN has no train or plane panel; adding one is sloppyCAN-side only.

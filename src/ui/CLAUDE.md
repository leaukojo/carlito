# Dashboard & UI — gotchas & hard-won rules

Contract-informed, not a UI generator. Lamps and bars are **generated** from contract
metadata (a bar = an "out" signal with a `range` that is warn'd **or** flavored — any
flavor); the two radial gauges, the attitude indicator, the wind rose, the echo sounder and
the node-health strip are **hand-built** and only read scale/redline/warn/sentinel from the
contract. A gauge exists only when the vehicle declares its signal (boat: speedo, no tacho);
its text sits in the arc's bottom 90° gap.

- **A signal a hand-built widget draws leaves the bar column**, through `WIDGET_SIGNALS` — the
  sibling of `GAUGE_SIGNALS`, and what keeps the bar budget a choice rather than a side effect of
  the contract. A name goes there ONLY with a widget that draws it on EVERY family declaring it,
  since the list is otherwise a way to make a reading vanish with nothing to see;
  `test_every_widget_signal_keeps_a_display` is the guard.

- **Telemetry is bound, never polled.** `Dashboard.bind()` / `Bridge.bind()` resolve
  `level.vehicle.telemetry` ONCE — the shell rebinds both on `Level.vehicle_changed`, which every
  vehicle replacement emits (respawn keeps the same instance). `_build()` then resolves each
  generated widget to a telemetry field as a **StringName**, and a contract signal with no
  matching field is `push_warning`ed at bind and dropped, rather than freezing its widget
  silently at 60 Hz.
- **Card thumbnails**: `src/ui/scene_bounds.gd` (runtime-safe, `preload`ed) is the one
  world-AABB walk; `CardImport` owns the three card directories and the lossy-import stamp
  (`VehicleShot.THUMB_DIR` / `LevelShot.THUMB_DIR` alias them). `card_grid.gd` owns the one
  `card_box()`. Generators: `tools/CLAUDE.md`.

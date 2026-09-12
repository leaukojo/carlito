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
- **Card thumbnails.** `src/ui/scene_bounds.gd` (`preload`ed, not `class_name`d — runtime-safe,
  reachable from `tools/`) is the one `world_aabb`/`visuals` walk: world-space AABB of a
  subtree's visible geometry. `VehicleShot` (`src/ui/vehicle_shot.gd`) delegates to it and
  keeps the vehicle-specific `subject_roots`/`subject_bounds`/`frame`; `tools/gen_thumbs.gd`
  and `tools/gen_level_thumbs.gd` call it directly for their own AABBs. `CardImport`
  (`src/ui/card_import.gd`) owns both card directories (`VEHICLE_THUMB_DIR`,
  `LEVEL_THUMB_DIR`) as well as the lossy-import stamp; `VehicleShot.THUMB_DIR` and
  `LevelShot.THUMB_DIR` (`kit/helpers/level_shot.gd`) are aliases onto those constants, not a
  second copy.
- **Card frame.** `src/ui/card_grid.gd` (`preload`ed) owns the one `card_box()`, shared by both
  selectors; card content and grid container stay per-selector.
- **Thumbnail PNGs are not byte-deterministic across generator runs**, even with unchanged
  code and unchanged scene content — two consecutive runs of the same generator produce
  visually-identical but not byte-identical captures (see `tools/png_drift.gd`, which already
  exists to tell that apart from a real content change). Do not expect `git status` to stay
  clean after re-running a thumbnail generator; compare with `png_drift.gd`, not `cmp`.

# Review: tests/ against the code they test

Scope: `tests/` (203 suites, ~38.5k lines) read against `src/`, `kit/` and `addons/carlito_kit/`.
Static review only. This container has no Godot binary, so nothing here was run. Every line
reference was read in the file. "Cannot fail" means the assertion holds for any implementation
of the code it names, not only for the current one.

Depth: test_drivetrain, test_input_arbitration and test_road were read in full. test_wheel_spin,
test_trailer, test_tow_host and test_vehicle_catalog were read section by section. The rest of
the suite was swept by pattern (exact float/vector equality, tolerances of 1e-9 or tighter,
constants asserted against literals, level/bake loads, scene-state spec reads, copied fixtures).

Findings run from most to least severe within each section.

---

## 1. Assertions that cannot fail, or only restate a constant

### 1.1 `test_the_local_stalk_cycles_through_every_command_and_wraps` tests its own loop
`tests/test_input_arbitration.gd:921`. The test runs `pos = (pos + 1) % BODY_CMD_COUNT` itself
and asserts that this reaches every value and wraps to 0. It never calls the router, so it holds
for any `BODY_CMD_COUNT > 0`, whatever InputRouter's stalk does. The router's own cycle
(`src/input/input_router.gd:494-496`, the `body_cmd_toggle` edge advancing `_body_cmd`) has no
test in the suite. A grep of `tests/` for `body_cmd_toggle` outside `merge_local` finds nothing.
**Fix:** drive `body_cmd_toggle` edges through `_router()` (`_physics_process`, as
`test_fallback_advances_only_the_driving_toggles` does) and read `get_vehicle_input().body_cmd`
across `BODY_CMD_COUNT + 1` presses.

### 1.2 The governed-upshift lug guard is asserted on a clamped rpm
`tests/test_drivetrain.gd:1797`, `test_governed_upshift_will_not_lug_the_engine_below_the_downshift_point`.
The last assertion is `rpm_from_wheel(...) >= idle_rpm`, but `rpm_from_wheel` clamps to
`[idle, redline]` (`src/vehicles/base/drivetrain.gd:277`), so it always holds. The guard the name
describes, `> shift_down_rpm` (`drivetrain.gd:319`), is never checked. `is_less(size())` only
shows the walk stopped somewhere.
**Fix:** assert `wheel_engine_rpm(spec, road_omega, g) > spec.shift_down_rpm`, and assert that
`wheel_engine_rpm(..., g + 1) <= spec.shift_down_rpm` (the next gear would lug).

### 1.3 `test_shift_cut_ticks_rounds_up...` never exercises the round-up
`tests/test_drivetrain.gd:1533`. Each case is an exact multiple of the tick: 0.1 / (1/60) = 6.0
and 0.15 / (1/60) = 9.0 in float64 (checked). `floori`, `roundi` and `ceili` all pass, so a
switch to truncation would go unnoticed.
**Fix:** add a non-multiple such as `shift_cut_ticks(0.11, 1.0 / 60.0) == 7`, and one a hair over
a multiple (`0.1 + 1e-9` → 7) if that edge is intended.

### 1.4 `share + (1.0 - share) ≈ 1` is a tautology
`tests/test_trailer.gd:144`, `test_the_kingpin_and_the_bogie_carry_the_whole_trailer`. This holds
for any finite `share`, so it proves nothing about "the whole trailer". The bogie share is never
computed separately.
**Fix:** delete the line, or compute the bogie's share from the code under test (if Articulation
has one) and assert that the two sum to 1.

### 1.5 The one-tick cap is computed in the test, not read from RayWheel
`tests/test_wheel_spin.gd:1107`, `test_the_one_tick_caps_scale_with_a_rewritten_mass`. The "cap"
is `corner_mass * 3.0 / TICK`, written in the test, so `cap_laden / cap_empty == 1.5` only
restates `750 / 500`. The comment says "all three RayWheel caps are `corner_mass * |v| / delta`",
but the test never touches a cap, so a cap that stopped reading `corner_mass` would still pass.
`test_corner_mass_starts_as_the_specs_share_per_wheel` already covers the first part.
**Fix:** drive a wheel at 3 m/s of slip with a saturating force (as the surface-drag and
patch-spring tests do) and assert that the applied force scales by 1.5.

### 1.6 Coupling profiles asserted equal to the constants they are built from
- `tests/test_tow_host.gd:577` (`test_each_profile_says_the_same_thing_as_the_constants...`)
  asserts `profile().pitch_deg == PITCH_LIMIT_DEG` and so on. The stronger tests at `:148` and
  `:157` read the same constants off the joint `_build_joint` really builds, so this one adds
  nothing they don't cover.
- `tests/test_tow_host.gd:195` asserts `plate == FifthWheelScript.YAW_FRICTION_NM`. The band check
  on the next line is the real guard, and the equality only restates the constant.
- `tests/test_tow_host.gd:1232` asserts `FifthWheelScript.SPAWN_COUPLE_TICKS == TowHost.SPAWN_COUPLE_TICKS`
  and its siblings. Neither `fifth_wheel.gd` nor `drawbar.gd` declares any of the three, so each
  side of the assert reads the same `TowHost` symbol. *Plausible, not confirmed without a Godot
  run:* GDScript 2 rejects a member that shadows one in the parent class. If that covers `const`,
  the six asserts can only fail by not compiling. The `_profile_fields` half of the test is real.

**Fix:** delete `:577` and the equality at `:195`. For `:1232`, confirm on Godot 4.7 whether a
subclass `const` can shadow its parent's. If it can't, keep only the `_profile_fields` loop.

### 1.7 Test names that promise more than the test checks
- `tests/test_drivetrain.gd:1861`, `test_auto_shift_and_is_drive_agree_with_governed_upshift_on_top_gear`,
  never calls `governed_upshift`. Its two `is_drive` lines repeat `test_gear_byte_classification`
  (`:90-92`), and only the `auto_shift` line is new. Either add the `governed_upshift(…, TOP_GEAR, …)`
  check or rename the test and drop the repeated lines.
- `tests/test_drivetrain.gd:1809`: the second half (`wheeled.road_radius == dt.road_radius` with
  both set to `DEFAULT_ROAD_RADIUS`) checks that a wheeled spec copies its radius, which `:1836`
  already does with a non-default 0.36.
- `tests/test_telemetry.gd:25`, `test_gps_lon_shrinks_with_origin_latitude`, computes the expected
  metres per degree with the implementation's own formula (`METERS_PER_DEG_LAT * cos(deg_to_rad(...))`).
  A wrong formula would be mirrored, not caught. An independent figure would catch it, such as a
  geodesic reference's length of 1° of longitude at 48.8566°, cited from the page actually opened
  (CLAUDE.md § Working style).

---

## 2. Sweeps that pass vacuously when their fixture comes back empty

### 2.1 `_driven_specs()` / `_gearbox_specs()` sweeps have no non-empty guard
`tests/test_vehicle_catalog.gd:157,268`. `_spec_of` (`:1094`) returns `null` when the root's
`spec` property isn't found in the scene state. Both helpers drop nulls, so a renamed property or
a changed scene layout leaves the dict empty. Only `test_every_foot_brake_can_lock_its_wheels`
(`:290`) asserts `specs.size() > 0`. The other 13 sweeps would then pass with zero iterations:
`:176, :214, :252, :307, :318, :352, :381, :408, :450, :481, :501, :589, :624`.
**Fix:** move the guard into the two helpers (assert that the result is non-empty, or assert per
variant that `_spec_of` is non-null for every wheeled family) so each sweep inherits it.

### 2.2 `test_bake_weights_carry_every_baked_level` is vacuous without a bake
`tests/test_shell_menus.gd:112`. With no `level_2.baked.scn`, `bake_weights()` is `{}`, and
`weight_bytes(level_2)` falls back to `level_weights.json`, which the export generates and the
repo doesn't contain. The assertion becomes `0 == 0`. See also 3.1.

---

## 3. Tests that depend on `.baked.scn` without saying so

### 3.1 `test_weight_text_reads_as_megabytes` fails on a fresh clone
`tests/test_shell_menus.gd:104`. It asserts that `weight_text(level_2)` ends with `" MB"` and
`weight_bytes(level_2) > 0`. Both read `level_2.baked.scn` (`src/shell/level_registry.gd:92`)
or the export-only `src/shell/level_weights.json`, which is absent. On an unbaked worktree (the
state the SessionStart hook reports for this clone) the test fails with nothing pointing at the
bake. 2.2 is its silent twin. `test_level_select_cards_show_the_bake_weight` (`:86`) adapts
to an empty weight and is fine.
**Fix:** test the formatting without a bake. `weight_bytes` takes any scene path and reads
`<basename>.baked.scn` beside it, so write a known-size `user://weight_probe.baked.scn` and assert
on `weight_text("user://weight_probe.tscn")` (`test_bake.gd:266` already bakes into `user://`).
Keep the shipped-level check only with the dependency declared, as `tests/test_export_filter.gd:9`
does: say so in the `##` header and give the assertion an
`override_failure_message("no level_2.baked.scn: run tools/bake_levels.tscn")`.

Other level-loading suites were checked and are bake-independent. `test_challenge_runner._rig`
and `test_drone_vehicle._latched_in_a_level` load flatland, which has no bake. `test_export_filter`
declares its dependency and guards `baked > 0`.

---

## 4. Duplicate tests

| Tests | Overlap | Suggestion |
|---|---|---|
| `test_drivetrain.gd:985` (converter) and `:1039` (clutch) | Same rig: D1 at 3400 rpm on a held wheel, then D2, the same loop and the same rating bound | One test looping over both couplings, as `:831` and `:857` do |
| `test_drivetrain.gd:1269` and `:288-290` (and the rig at `:762`) | Floored against a held wheel in D1, then `applied_throttle == 1` | Delete `:1269`. Its comment calls the clutch fixture's launch line "the converter line" |
| `test_drivetrain.gd:210` and `:1483` | Same 60 ticks at 40 rad/s in D1. One checks torque ≈ 0 without brake_frac, the other torque < 0 with it | Merge into one test with both brake_frac cases |
| `test_drivetrain.gd:190-191` and `:206-207` | The redline clamp (at 40 and 1000 rad/s) and the idle-in-N reading, asserted in both tests | Keep each in one place |
| `test_drivetrain.gd:711` and `:750` | `converter_free_rpm(spec, 0.3) == idle` asserted twice | Drop one |
| `test_road.gd:303` and `:278` | `base_depth 0` is the default, so the same 8 points and mats as `test_asphalt_cross_section`. Only `materials().size()` is new | Fold that one line into `:278` |
| `test_input_arbitration.gd:215` and `:147` | Manual bridge gears 2-6 pass exactly. `:147` already covers D1, D12, TOP and TOP+1 | Drop `:215` or loop `:147` over every byte |
| `test_tow_host.gd:577` and `:148/:157` | See 1.6 | Delete `:577` |

### 4.1 The "mirrored / absent is default" and "edge survives merge_local" families
`tests/test_input_arbitration.gd` has at least 11 tests shaped as "set the key on `_bridge()`,
assert the field, absent reads the default": `:315, :356, :594, :638, :658, :688, :816, :854,
:873, :946, :973`. Nine more are "the edge survives `merge_local`": `:342, :543, :610, :652, :700,
:842, :956, :984, :1034`. Each one is correct, but a new
toggle key is untested until someone remembers to copy the shape.
`test_action_registry.gd:96` already shows the stronger form for the pad keys, reading the key
set off the source.
**Fix:** two table-driven tests. One iterates `merge_local({}, {}).keys()` filtered to `*_toggle`
/ `*_cycle` and asserts that each key survives from either side. The other runs a
`[key, sent, field, absent_default]` table through `arbitrate_bridge`. The per-feature tests then
keep only their non-generic parts (clamps, overrides, sentinels).

### 4.2 Running a pure function twice in one process
`test_road.gd:93` (`adaptive_offsets`), `:542` (`extrude`) and `:756` (`conform_heights`) call
the same function twice and compare. That only catches unseeded randomness, which the code under
test doesn't use, so the tests are cheap and low-value. Keep them only if they guard a seeded
path. Otherwise a golden value, such as the first and last offsets of `_quarter_arc`, pins more.

---

## 5. Fixture and setup code copied across files

### 5.1 The scene-state root-property read, written out five times
The same loop over `PackedScene.get_state()` for a property of the root node:
- `tests/test_vehicle_catalog.gd:1094` (`_spec_of`)
- `tests/test_tyre_class.gd:17` (`_spec_of`, verbatim)
- `tests/test_kenney_variants.gd:530-541` (`_root_property`, generalised)
- `tests/test_wheel_spin.gd:1128-1133` (inline, for `spec`)
- `tests/test_vehicle_catalog.gd:463-465` (inline, for `script`, in `test_the_laden_esc_tables...`)

**Fix:** one shared helper, following the precedent of `tests/trailer_swing.gd`, e.g. a
`tests/catalog_specs.gd` with `root_property(scene_path, prop)` and `spec_of(variant)`. Give it
the non-null assert, which also closes 2.1.

### 5.2 The minimal bakeable level, built six times
Root + `Marker3D` with `vehicle_spawn.gd` + `AuthoringRoot`:
`tests/test_bake.gd:536` (`_scatter_level`), `:650` (`_piece_level`), `:690` and `:722` (inline),
`:787` (`_authoring_level`), and `tests/test_road.gd:1150` (`_road_level`). `_authoring_level(child)`
already does this, but the others don't use it.
**Fix:** have them all build on `_authoring_level`, moved to a shared helper so test_road can
reach it.

### 5.3 A router on an idle pad, written twice
`tests/test_input_arbitration.gd:29-38` (`_IdlePad`, `_router`) and `tests/test_key_shaper.gd:161-166`
(`_StubPad`, `_router`) build the same fixture to keep the machine's joypad out of the suite. A
third suite building a bare `RouterScript.new()` would silently read real hardware.
**Fix:** one shared `idle_router()` helper.

### 5.4 Smaller copies
- `_marker_mat(mesh)` appears in both `tests/test_trailer.gd:1691` and `tests/test_tow_host.gd:863`.
- `test_bake.gd:401` `_quad_arrays` and `test_road.gd:974` `_two_quad_arrays` build the same
  up-facing quad arrays.
- Scene loads are written inline many times, e.g. `(load(CatalogScript.scene_of(v)) as
  PackedScene).instantiate()` in test_trailer and test_tow_host. A single `_instance(variant)`
  helper per suite would do, and test_tow_host's `_semi()` and `_tractor()` already show the shape.

---

## 6. Rule-8 pure logic with no test or weak tests

### 6.1 The outbound wire gate is untested
`src/bridge/bridge.gd:154` `_all_finite` and `:164` `_is_instance_array` are static and pure. They
are the only thing between telemetry and `JavaScriptBridge.eval`, and the comment states the
failure: one `nan` "throws inside eval, killing every publish". No test references either one.
That is the outbound half of the contract codec (rule 8, "contract codec"). The inbound half is
covered (`test_bridge_source_survives_non_numeric_json`).
**Fix:** a test_contract (or new test_bridge) case covering NAN and INF scalars, NAN inside an
Array, a wrong-length Array, a non-numeric element, an int element, and a plain finite float.

### 6.2 Road and terrain authoring math in addons/carlito_kit
No test references `addons/carlito_kit/ground_snap.gd:38` `ray_plane` (pure ray/plane
intersection, including the parallel and behind-origin cases) or
`addons/carlito_kit/road_draw_tool.gd:663` `_to_world_curve` (Curve3D through a Transform3D,
where handles must transform as directions, not points). Both sit under rule 8's "road" and
"terrain" math. `tile_conform.gd` is tested (`test_road.gd:1066`), so the folder can be tested.
**Fix:** a short test of each. `_to_world_curve` should include a scaled and a mirrored transform,
matching `test_transform_surface_arrays_preserves_winding_when_mirrored`.

### 6.3 Weak spots in covered logic
- GPS: see 1.7. Heading is tested at the four cardinals only. A 45° case, plus a forward vector
  just west of north that should read near 359.9 rather than a negative angle, would pin the
  `fposmod` in `heading_from_forward`.
- `tests/test_telemetry.gd:42` has an empty `# --- odometer ---` header. The odometer test sits
  under the true-wind section further down.

---

## 7. Float comparisons

No flaky float32 comparison was found: the sweep turned up none that compares float32-derived
values exactly or at 1e-9. The tight tolerances (`1e-9`/`1e-12` in test_drivetrain,
test_wheel_spin, test_steering_geometry, test_telemetry) are all on float64 GDScript scalars.
The exact `assert_vector(...).is_equal` calls are all zero vectors, identities, inputs passed
through untouched, integer translations (`test_rail.gd:257`), or re-reads of a pose captured
earlier in the same test (`test_three_point_hitch.gd:343-374`). Suites that read float32 sources already widen correctly: `test_wheel_spin.gd:1233-1268`
(`1e-2`, commented "float32 Basis") and `test_road.gd` (`Vector3.ONE * 0.001`).

Two are worth a second look:
- `tests/test_drivetrain.gd:298, 827, 1032, 1059, 1168, 1380` compare a crank rpm (~2000-4600)
  coming out of the coupled solve to `wheel_engine_rpm` at `1e-6`. That is about 2e-10 relative,
  safe in float64 only while the solve lands exactly. Any iterative step added there makes these
  boundary tests, so `1e-3` rpm loses nothing.
- `tests/test_road.gd` uses `assert_bool(a < b).is_true()` 37 times (also test_train 12,
  test_scatter 11, test_brush_ops 10, test_terrain_gen 8). These aren't flaky, but a failure prints
  only "expected true", with no value and no loop index. `assert_float(a).is_less(b)` (plus
  `override_failure_message` in loops) would print both.

---

## 8. Smaller notes

- `tests/test_input_arbitration.gd:1060`: a stray doc comment ("A bridge that is live and sending
  full throttle in D1.") sits above the brake-override section. It describes `_LiveBridge`
  (`:1220`).
- `tests/test_drivetrain.gd:119, 1296, 1348, 1631, 1708` write `1.0 / 60.0` beside a suite-level
  `TICK`.
- `tests/test_input_arbitration.gd:783-791, 798-808` set `Bridge._active` and `_inbound` on the
  autoload and reset them at the end of the test body. An `after_test` reset would survive a test
  that errors out before the end.

---

## Checked and fine

- test_drivetrain's shift-timer tests leave a tick of slack for the float sum (`:2046`, `:2081`),
  so they don't sit on an exact boundary.
- The wire enum pins (`test_drone_modes.gd:43`, `test_drone_arming.gd:40`, `test_boat_autopilot.gd:25`,
  `test_telemetry.gd:217`) are deliberate freezes of contract ordinals and are cross-checked
  against the contract tables (`test_drone_arming.gd:55`).
- `test_trailer.gd:1503, 1555, 1610` compare `live_kingpin_share` to `kingpin_share` at `1e-9`.
  Both run the same `Articulation.kingpin_share` on the same float32 `spec.center_of_mass.z`
  (`src/vehicles/base/towed_body.gd:383-390`), so they agree exactly while the load offset is 0.
- `test_collision_layers.gd` pins the frozen layer bits, as CLAUDE.md § Gotchas requires.
- `test_action_registry.gd:96` polls a real `PadSource`, but only for its key set, which doesn't
  depend on attached hardware.

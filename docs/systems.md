# Runtime systems

The plumbing every vehicle rides: signal contract, input pipeline, telemetry/dashboard,
bridge, lamps, shell, level framework. Per-family vehicle detail is in `docs/vehicles.md`
and `docs/heavy_vehicles.md`. Editor/authoring tooling is in `docs/level_kit.md`; rules and
gotchas are in `CLAUDE.md`.

## Signal contract

`contract/carlito_contract.json` (v35) defines every bridge signal: name, dir, type, unit,
range, optional `warn` + `warn_side`, optional `count`, enum, vehicles, optional `flavor`
(`isobus`, `j1939`, `iso11992`, `j2497`, `cleanopen`, `canaerospace`, `dronecan`, `train`,
`nmea2000` — names/semantics borrowed, frame layout stays on the sloppyCAN side).
`Contract` (`src/bridge/contract.gd`) parses and validates it at startup into `Contract.data`,
collecting every fault. `tests/test_contract.gd` fails if a required signal is missing.

- Signals are unique by (name, dir) — `battery` exists in both directions (in = warning LED,
  out = voltage).
- `warn` is the dashboard danger threshold; the parser rejects one without `warn_side`
  (`"low"` | `"high"`).
- `todo` marks a signal declared but unimplemented on both sides.
- `count` (integer >= 1, default 1) makes a signal instanced: an Array of N elements of the
  declared type, `range`/`warn` per element, indices zero-based. Examples: `esc_rpm`/
  `esc_current`/`esc_temp` (4), `node_health` (8, DroneBus roster), `slip` (2 — 0 front, 1
  rear, every wheeled family, no `warn`/`flavor`). `count` > 1 is parse-rejected on `"in"`,
  on type `bool`, and with an `enum`. `Bridge._publish` enforces the shape both ways at
  runtime, dropping a wrong-shaped value with a single warning.
- Omitting `range` on an "out" signal puts it on the dashboard readout line instead of a bar.

Contract edits bump `version`; both sides warn on mismatch at runtime (sloppyCAN has no CI,
so this warning is the drift guard). `tools/gen_js_contract.mjs` regenerates
`../sloppycan/carlito_contract.js` (`window.CARLITO_CONTRACT`, committed so it loads from
`file://` with no build step) — run it after any contract edit. A contract edit is a paired
change: the version bump lands on `dev` in both `carlito` and `sloppycan`, promoted together.

## Input pipeline

`InputRouter` merges input sources into one normalized `VehicleInput`; all arbitration lives
here as static/pure functions, unit-tested in `tests/test_input_arbitration.gd`:

- `merge_local` (pure): keyboard + touch (max analog, summed steer, OR'd bits) before
  `arbitrate_local`.
- `arbitrate_local`: key gating (ignition required for throttle), brake-never-throttle, S =
  brake-then-reverse at standstill, foot brake drives `brake_lamp`.
- `arbitrate_bridge`: while the bridge is active and the gear byte is a real gear (D1-D6 or
  R), the gear owns direction (`throttle = accel` signed by the byte, `gear_auto = false`).
  Byte 0 falls back to auto-shifting forward, so a CAN source that never sends gear (RAMN
  `0x077`) still drives. Reverse always needs the explicit R byte. The "ignition off" notice
  clears the moment the key reaches Ignition (`GameState.notice_cleared`), not after its
  20 s dwell.

  Every other bridge-owned field is mirrored verbatim from sloppyCAN; an absent key falls to
  the rest state (lamp/warning bits off, hitch raised, PTO off, 540/open diff/2WD, SCV shut,
  flaps retracted, disarmed, doors shut, LEDs black, body Idle).

  Two in-signals override `steer` when present: the boat's `rudder` and the tractor's
  `guidance` (from `guidance_curvature`). `bridge_source.gd` includes the key only when
  sloppyCAN actually sent it, since a commanded 0 is a real command, not an absence.

`_physics_process` prefers the bridge source when fresh (< 300 ms, `Bridge.FRESHNESS_MS`),
else falls back to `arbitrate_local`. `bridge_source.gd` normalizes contract-in fields
(%->unit); `local_source.gd` reads the keyboard; the touch overlay registers via
`InputRouter.set_touch_source()`.

Toggle state is owned by the router, never a source: headlight level `_lights`
(OFF->CLEARANCE->LOW->HIGH), tractor hitch/PTO/PTO-speed/diff-lock/MFWD, drone arm/cargo
hook/injected node failure/flight mode, plane flaps, train pantograph/doors, refuse body
command. Train pantograph defaults raised so a locally-driven train spawns able to move.
Sources report per-frame edges only, ORed by `merge_local`; the `var _*` block at the top of
`input_router.gd` is the list.

`VehicleInput` (`src/input/vehicle_input.gd`) is a `class_name`, not an inner class of the
autoload, so a vehicle's static types don't depend on the autoload's registered name. Fields
are flat except `lamps`, grouping the fourteen verbatim-mirrored lamp/warning bits (one
rule, not one family — the router knows no vehicle family). `lights` stays flat: a level the
router cycles, not a mirrored bit. `get_vehicle_input()` returns the router's own struct,
read-only by convention — `arbitrate_*` build a fresh struct each tick, so a stashed
reference reads stale; no defensive `copy()`.

The raw-intent wire is `Dictionary[StringName, Variant]` across all four producers
(`local_source.gd`, `touch_controls.gd`, `bridge_source.gd`, `tools/measure_drone.gd`'s
`StickSource`) and `merge_local`. Two tests guard the untyped keys: the registry's
`poll_key` values against `LocalSource`/`merge_local` key sets, since `merge_local` builds
its dict explicitly and a key on one side only drops the keyboard's edge silently.
`arbitrate_local`/`arbitrate_bridge` take a plain `Dictionary`.

Bindings live in `project.godot`'s InputMap, shown by the CONTROLS sheet generated from the
action registry. `tests/test_input_map.gd` asserts no two actions share a physical key.

### The action registry

`src/input/action_registry.gd` describes what each bound action is: a static table keyed by
row (a control on two keys — drive/reverse, steer, climb/descend — is one row), each
carrying a label, a `group` (drive/vehicle/world/shell), a gate, and how the touch overlay
offers it. No key string is typed there: `keys_for()` reads the live binding from `InputMap`.

Two consumers describe controls — the pause menu's CONTROLS sheet (`src/ui/pause_menu.gd`)
and the touch button stack (`src/ui/touch_controls.gd`). `tests/test_action_registry.gd`
asserts every bound (non-`ui_*`) action is in exactly one row.

`applies(id, ctx)` is the shared gate predicate; `gate_note()` gives the reason. Four gate
shapes:

- **families**/**excludes** — vehicle-family lists (`flaps` is plane, `steer` is everything
  except the rail-guided train).
- **capability** — a bool the shell reads off the vehicle (`boot.gd:_capabilities()`), for
  when one family disagrees with itself (within `truck` the semi tows, the garbage truck
  does not). Sources are duck-typed and ORed: `cycle_implement`, `vehicle_capabilities()`,
  `attachment_controls()`.
- **bridge_owned** — the control rides `VehicleInput`, inert while sloppyCAN drives. Not set
  on shell conveniences (ATTACH, VIEW, GARAGE, LEVEL, MENU). Exception: pedals/
  joystick stay visible though inert, since hiding them would make the pedal blink as
  sloppyCAN stutters.

Family gates are validated against the contract, not copied: a row that rides contract IN
signals names them in `signals`, and `tests/test_action_registry.gd` asserts the offered
families equal the union of those signals' own `vehicles` lists. The one row with no
`signals` is `hitch` (tractor `hitch_pos`, semi tipper valve — shared local toggle).

## Telemetry & dashboard

- `VehicleTelemetry` (`src/vehicles/base/vehicle_telemetry.gd`) carries every contract "out"
  signal for ground vehicles. Motion (speed, rpm, gear, slip, yaw, accel, heading, position)
  is read straight out of the sim; aux systems (fuel/coolant/battery) are simple honest
  models. Each non-trivial derivation is a static pure fn (GPS `gps_lat`/`gps_lon` around
  Paris 48.8566/2.3522, `heading_from_forward`, `odo_step`, `body_accel`, `impact_gate`,
  fuel/coolant/battery models, `pack_status`), unit-tested in `tests/test_telemetry.gd`.
  `BaseVehicle._update_telemetry(input, delta)` holds the only per-tick state (prev velocity
  for accel/impact, accumulators); respawn zeroes the accel history so a teleport isn't read
  as an impact. The `status` bit layout (`ST_*`) is the wire assignment and is FROZEN: a new
  flag appends at bit 7 or above (nine free in the u16); an existing bit is never renumbered.
  Adding one bumps `version` and ships as a paired promote.
- `to_bridge_dict()` maps telemetry fields to contract "out" names in contract units
  (throttle/steer as %, slip as ratio); a `test_telemetry` case fails if it stops covering a
  non-todo ground "out" signal. It walks the telemetry's property list, so a subclass just
  declares its fields — the `WIRE_*` tables hold the five renames, the two rounding
  rules and the synthesised `slip`.
- Dashboard (`src/ui/dashboard.gd`) is contract-informed, not a UI generator: repetitive
  parts are generated by walking the contract for the active vehicle type; the instruments
  are hand-built. Plain text + color only.
  - Generated tell-tale row: a lamp per bool "in" signal, `key`/`lights` enum chips, a
    telemetry-driven lamp per flavored bool "out" (PTO, IMPL, ARMED, tractor DIFF/MFWD, train
    PANTO/DOORS), a telemetry-driven chip per flavored enum "out" (tractor TOOL chip). An
    HFlowContainer wraps to however many lamps the contract declares (fifteen on a truck with
    a trailer). Where a signal exists in both directions the request lamp sits beside its
    state lamp, captioned REQ (PTO REQ/PTO, DIFF REQ/DIFF, MFWD REQ/MFWD, PAN REQ/PANTO, DOOR
    REQ/DOORS).
  - Generated bars: every "out" signal with a `range` that is warn'd (fuel/coolant,
    altitude/vspeed, pitch/roll) or flavored (tractor implement panel, FLAPS, ROTOR, drone
    SATS/HDOP/AGL, train LINE/AMPS/PIPE), minus the two gauge signals. An instanced signal
    becomes a group caption plus N bars labelled by zero-based index (drone ESC RPM/AMP/TEMP
    groups). Bars flow into `BAR_ROWS_MAX`-row columns; a group never splits across a break;
    the panel pins to the bottom edge. Widget is `dash_bar.gd`.
  - Generated readout line: an "out" signal with no `range` lands here beside HDG/ODO/GPS
    (tractor HRS hour meter, truck LIM road-speed limit, drone BARO/GMB/PAY, the boat's
    SOG/STW/DRIFT in m/s, BURN, OIL and the sailboat's SAIL boom angle from
    `READOUT_EXTRAS`), gated on the contract
    declaring it for that family, never on the telemetry field being present. The Label wraps
    inside the middle column: the boat's line is long enough that an unwrapped one would widen
    the whole cluster instead of growing it downward.
  - Hand-built, reading only scale/redline/warn/sentinel from the contract, built only where the
    vehicle declares the signals: the two radial gauges (`gauge.gd`, one widget instanced
    twice — speedo on `kmh`, tacho on `rpm`, so the boat gets a speedo and no tacho), the
    attitude indicator (`pitch` and `roll`, in the tacho's slot), the wind/track rose
    (`wind_rose.gd`, the boat's `awa`/`aws`/`twd`/`tws`/`cog`/`sog`, heading-up so the crab
    angle is an angle), the echo sounder (`depth_readout.gd`, `depth`, blanking the -1 no-bottom
    sentinel to `---` rather than colouring it) and the node-health strip
    (`node_health`, above the tell-tales). A signal one of these draws leaves the generated bar
    column through `WIDGET_SIGNALS`. Gauge text sits in the arc's bottom 90° gap; gear
    shows in the tacho gap. The train declares `gear` out but not `rpm`, so it gets a bespoke
    `REVERSER N/D/R` centre readout. Short captions (`BAR_LABEL`, `LAMP_TEXT`) are
    hand-picked.
  - Density (`Dashboard.Density`): FULL is everything above; COMPACT (the default) keeps the
    tell-tale row, node strip and the gauge-slot instruments (speedo/tacho/horizon, smaller),
    drops bars, the readout and the two instruments beside the gauges rather than in a slot
    (rose, sounder — their signals were bars until `WIDGET_SIGNALS`, so this drops nothing new);
    OFF hides the cluster. COMPACT drops only whole sections, so no signal can go missing in one
    mode (`tests/test_dashboard.gd`). The SETTINGS page's one button (and F2, `toggle_dashboard`)
    cycles COMPACT -> FULL -> OFF -> COMPACT; persisted in `user://shell.cfg`, an unknown or
    stale key (an old "auto") falling back to COMPACT. Every metric is logical px through
    `UiTheme.px`, so the cluster rebuilds on `NOTIFICATION_THEME_CHANGED`.
- Debug overlay (`debug_overlay.gd`): FPS/frame ms/draw calls/primitives/VRAM/node count
  from `Performance` monitors, toggled with F3. Target is 60 fps in the worst view of the
  deployed build; draw calls are the first diagnostic there, not a budget.

## Bridge

- Transport is web-only. The export Head Include (`export_presets.cfg` `html/head_include`;
  reviewable source `src/bridge/web/head_include.html`) installs `window.__carlito`: stashes
  inbound `{type:'carlitoInput'}` values with a timestamp, exposes `publish()` for outbound
  `{type:'carlitoOutput'}`.
- `Bridge` autoload (`src/bridge/bridge.gd`): `OS.has_feature("web")` gates everything (inert
  on desktop — `is_active()` false, no JS touched). Polls the inbound stash each physics tick
  (~60 Hz), freshness-gated 300 ms in JS; publishes telemetry at `PUBLISH_HZ` (20),
  marshaling `values` by contract name from
  `Contract.data.signals_for_vehicle(GameState.current_vehicle, "out")` ×
  `telemetry.to_bridge_dict()` — vehicle-aware, so a car emits car signals and the tractor
  adds its thirteen ISOBUS "out" signals. Both sides stamp their contract version on outgoing
  messages and warn once on mismatch.
- `boot.gd` calls `Bridge.bind(level)` (mirrors `Dashboard.bind`); both rebind on
  `Level.vehicle_changed`.

## Lamps, horn & day/night

- Lamp state rides `VehicleInput`, mirrored verbatim, with no local blink timer anywhere
  (`CLAUDE.md` § Input, lamps, bridge). Locally only `brake_lamp` is driven, from the foot
  brake; turn signals and warning LEDs stay off. `tests/test_lamps.gd` asserts the absence
  of a clock by reading `lamp_set.gd`.
- `LampSet` (`src/vehicles/base/lamp_set.gd`) applies lamp state to scene-authored lamp nodes
  the `VehicleSpec` names by NodePath (`headlight_paths` = SpotLight3D with distinct
  energy/range per `lights` level; `brake_lamp_paths`/`turn_*_paths` = MeshInstance3D lenses
  given a private emissive material at setup). Rear lamps are tri-state via the pure
  `LampSet.rear_tier(brake_on, headlights)`: STOP > TAIL (headlights >= clearance) > OFF (dim
  housing, never invisible) — unit-tested in `tests/test_lamps.gd`. `BaseVehicle` builds one
  `LampSet` in `_ready` and calls `apply()` each tick. A semi-trailer builds a second one off
  its own spec (`TowedBody`), driven by the tractor from the same `VehicleInput` bits — the
  resolve root is an argument, so a coupled rig lights at both ends with no new signal.
- Horn is procedural (`horn.gd`: a dual-tone buzz — two harmonic series a minor third apart,
  formant-lifted and soft-clipped — synthesized once into a shared looping `AudioStreamWAV`, no
  asset). Plays on the horn rising edge, holds while pressed.
- Day/night is a `Level` concern (not a bridge signal): N (`toggle_day_night`) flips, the pause
  menu's CONDITIONS page sets it directly (`set_night(on)`), both between scene-authored day
  values (captured at load) and a dim night preset (`level.gd`); `is_night()` reads it back.
  Either path emits `GameState.night_changed`, which the shell tracks for the session so the
  key and the menu can never disagree.
- Wind/current overrides are the same shape (`src/levels/base/world_conditions.gd`,
  `Level.set_conditions`): a LEVEL/CALM/LIGHT/STRONG preset per field plus one shared FROM
  compass direction, replacing the level's authored `wind`/`current` side-cars at runtime
  (LEVEL restores them). Only families in `WorldConditions.WIND_FAMILIES`/`CURRENT_FAMILIES`
  read the corresponding field at all (drone/plane/boat for wind; boat alone for current).

## Shell, touch controls & garage

- Shell flow lives in `boot.gd` (the `boot.tscn` root; no giant main.tscn): boot -> load
  level -> play, with a pause overlay over the top. It drives first in every mode —
  standalone, the sloppyCAN embed, and headless all take the same path. Persistent HUD
  (dashboard, debug overlay, touch controls) is authored in `boot.tscn`;
  `PauseMenu`/`LevelSelect`/`VehicleSelect` are transient Control overlays the shell creates
  and frees.
- Boot target is decided by `_boot()` from three authorities in order: deep link, saved
  session, `boot.gd`'s `DEFAULT_LEVEL` (`flatland` — no bake at all; the city's is 13.9 MB
  and must never boot).
  - Deep link: `?level=<id>&vehicle=<variant>` on the page URL, `--level=`/`--vehicle=`
    after `--` locally, or `CARLITO_LEVEL` env var (CI). Parsed and validated in
    `src/shell/boot_params.gd`: unknown ids are dropped, not clamped. `vehicle` names a
    VARIANT (`semi`), not its family (`truck`).
  - Saved session: `src/shell/shell_prefs.gd` writes level id + variant to `user://shell.cfg`
    on every load and vehicle swap. Skipped with a deep link present, and under `--headless`.
    `ShellPrefs.ENABLED` is `false` today — none of the four persisted keys (this one,
    first-run cue, dashboard density, UI scale) reach `user://`; `shell_prefs.gd`'s header
    notes what to decide when re-enabling it.
  - The requested variant reaches the level through `Level.initial_variant`, set before the
    level enters the tree, so `_ready` spawns it instead of the level's own default. Not
    allowed there (or a train with no loop) and the default wins.
- One theme, rebuilt per window size (`src/ui/theme/ui_theme.gd` + `src/ui/ui_scale.gd`).
  `UiTheme` holds design tokens (colour roles, a five-step type scale, metrics);
  `build(scale)`
  turns them into a `Theme`. `UiScale` (a Control in `boot.tscn`, not an autoload or the
  Window) recomputes scale from the window's short edge on every resize, times the player's
  SETTINGS factor. Every shell screen declares a ROLE (`theme_type_variation`) rather than a
  pixel size, relayouts on `NOTIFICATION_THEME_CHANGED`; anything the theme can't express
  goes through `UiTheme.px(self, …)`. Engine content scaling is not used — both
  `Window.content_scale_factor` and `CONTENT_SCALE_MODE_CANVAS_ITEMS` were measured on 4.7.1
  to resize the 3D render target too, ruled out by standing rule 9 on web. Only semantic
  overrides survive in screens (a lamp's lit colour, a bar's warn red, the notice amber).
  Keyboard/gamepad reach
  everything: a `focus` box on every Button, `Choice` for a radio-group toggle,
  `follow_focus` on every scroll area. Exception: the CONTROLS sheet is all Labels, so
  `PauseMenu` moves the scroll on Up/Down itself.
- Notice line (`src/ui/notice_line.gd`, the `Notice` Label in `boot.tscn`): transient message
  from `GameState.notice` ("NO ROOM FOR A TRAILER"), dwelled for `Boot.NOTICE_DWELL_S`,
  re-shown rather than queued.
- Pause overlay (`src/ui/pause_menu.gd`, Esc or touch MENU): RESUME / RESPAWN / CONDITIONS /
  CONTROLS / SETTINGS. Esc walks back the way it came in, only then resumes. RESPAWN is a
  signal — respawning stays the shell's to do. GARAGE and LEVEL are not here: they are the
  touch overlay's important buttons (hidden only by F5, never by F4) and G / 4. CONTROLS is generated
  from the action registry: grouped rows read live from `InputMap`; a row the current
  vehicle/attachment can never use (family/capability gate fails, `ActionRegistry.relevant_entry`)
  is hidden outright, and a group whose rows are all hidden loses its heading, while a row
  blocked only because the bridge owns it right now stays, greyed, with its reason
  ("sloppyCAN is driving") — that one goes away on its own. The shell hands it the same
  capability dict the touch buttons gate on (`setup(caps, density, ui_scale, wind_preset,
  current_preset, wind_from_deg, night_on)`, before `add_child`). SETTINGS is two cycling
  buttons — dashboard density and UI scale — emitting the new value; the shell applies it and
  writes `user://shell.cfg`. CONDITIONS is four more cycling buttons — WIND/WATER CURRENT preset
  (`WorldConditions.Preset` LEVEL/CALM/LIGHT/STRONG), the shared FROM compass direction, and
  TIME (day/night) — emitting `conditions_changed`/`night_toggled`; WIND/CURRENT grey out (with
  a reason) on a family `WorldConditions.WIND_FAMILIES`/`CURRENT_FAMILIES` doesn't name. The
  shell keeps all four for the session (`ShellPrefs` stays disabled), applies them to the
  current level and re-applies them to every level it loads next (`Boot._finish_load`); the
  night value tracks `GameState.night_changed` so the N key and the menu can never disagree.
  Pausing: `Boot` is `PROCESS_MODE_ALWAYS` so shell and menus keep running under
  `get_tree().paused`; the level is a child of it, so `_finish_load` puts it back to
  `PAUSABLE` explicitly. Autoloads pause with the world.
- First-run cue (`src/ui/coach_cue.gd`): one line over the first frames of a first visit,
  dismissed by the first input or a short timeout, never shown again
  (`ShellPrefs.coach_seen`).
  Listens on `_input`, which does not consume — the dismissing press also drives the car.
- Level select (`src/ui/level_select.gd`), opened by touch LEVEL or 4, carrying a BACK
  button and a `closed` signal. Reads `LevelRegistry.LEVELS` (`src/shell/level_registry.gd`)
  — `{id, name, scene, desc}` entries; a `dev: true` entry (none today) is a test fixture
  level-select hides but bake/check/smoke still cover. A card grid: one Button per entry with
  that level's screenshot (`src/ui/level_thumbs/<id>.png`, via `LevelShot.thumb_path`),
  falling back to a "no screenshot" plate. Cards are shot from the kit's Polish tab
  (`docs/level_kit.md`); framing lives in a side-car `<level>_shot.tres`, not the level
  scene, so re-framing never re-stales a bake.
- Vehicle selector (`src/ui/vehicle_select.gd`), opened with G or touch GARAGE, pauses the
  world from either. Three axes: family column, variant picture cards,
  and (when towing) what it can pull.
  - One live preview, never one per card: pre-baked stills on cards, one long-lived
    SubViewport holds the selected machine on a turntable (camera orbits — rotating a frozen
    RigidBody3D would fight the physics server). Preview body is a real vehicle from
    `VehicleShot.spawn_display`: frozen KINEMATIC with no gravity (`_physics_process` still
    runs, RayWheel poses the wheels) and `display_only = true`, keeping it out of
    `InputRouter`'s single vehicle slot.
  - Nothing is hidden: a family this level won't spawn is still listed, opens and previews,
    carrying the reason on its cards; only DRIVE is refused (`_on_drive`). Reasons are derived
    from `allowed_vehicles` and `Level.has_closed_rail()`.
  - Attachment row is the previewed machine's own answer: `attachment_ids()` /
    `current_attachment()` / `set_attachment(id)`, duck-typed on `TractorVehicle` and
    `SemiTractor`; `cycle_implement()` goes through the same setter. DETACHED / BOBTAIL are
    real cards reading NONE.
  - Emits `vehicle_chosen(variant)` then `attachment_chosen(id)`; `Level.set_vehicle(variant)`
    runs only when the variant changed, so swapping a trailer doesn't teleport back to spawn.
    Respawns at a `VehicleSpawn` matching the variant's family, emits
    `Level.vehicle_changed(type)` to rebind dashboard/bridge. `Dashboard.bind` reads
    `GameState.current_vehicle`, falling back to `LevelInfo.default_vehicle`. Adding a
    vehicle = a `VehicleCatalog.VARIANTS` entry + its family in a level's `allowed_vehicles`
    + a thumbnail run.
- Vehicle cards: `tools/gen_vehicle_thumbs.tscn` (windowed only) writes every catalog
  variant, implement and trailer to `src/ui/vehicle_thumbs/<id>.png`. Framing/lighting/pose
  come from `src/ui/vehicle_shot.gd`, shared with the live turntable; camera distance is
  measured off the body's AABB. PNGs live under `src/` — `tools/*`/`kit/thumbs/*` are
  export-excluded.
- Garage showroom level (`src/levels/garage/`, id `garage`): a real Level whose spawned
  vehicle is frozen KINEMATIC above the floor — `_physics_process` still runs (wheels
  steer/spin, engine revs, lamps toggle) while the orbit camera (`orbit_camera.gd`) inspects
  from any angle including underneath; a wall screen shows the active variant's spec. Input,
  dashboard and bridge flow through Level unchanged.
- Touch controls (`src/ui/touch_controls.gd`) are a second local `InputSource`: steering
  joystick (bottom-left), gas/brake pedals (bottom-right, with UP/DOWN flight pads extending
  the row leftward for aircraft), and generated buttons. Widgets take touch and mouse. On by
  default everywhere (`_should_show()`), in two layers hidden independently: IMPORTANT (F5,
  `toggle_important`) and DRIVING (F4, `toggle_touch`). `poll()` contributes nothing while the
  driving layer is hidden; the important layer writes no intent.
  - Buttons are generated from the action registry — captions, order, when shown, which
    raw-intent key each writes. Split by `ActionRegistry.is_universal`: what every vehicle has
    is the top-left important column (MENU, GARAGE, LEVEL on top in that order — `STACK_HEAD`
    — then VIEW); what only the current machine has (tractor implement/driveline buttons,
    ATTACH, garbage truck BODY...) goes in the EQUIP drawer on the driving layer, closed by
    default, opening leftward beside the pedals. The bottom-right cluster is three tiers: the
    pedal row (GAS green, BRAKE red, PANTO beside BRAKE, UP/DOWN for aircraft), a QUICK row
    spanning exactly the pedal row's width (LIGHTS, HORN, the family's MODE/FLAPS/DOORS, then
    the safety latch HAND/ARM above GAS), and the EQUIP button above it. Widgets are hand-built,
    but the registry decides whether each is shown — the rail-guided train loses its steering
    joystick, only flying families get the UP/DOWN pads.
  - The important column wraps into a further column when its band (`STACK_TOP` to the
    joystick) can't hold it, sized for every pad being visible (`_columns_for`). The drawer is
    a GridContainer, which lays out only visible children, so it packs what THIS machine has;
    `_fit_equip_drawer` widens it leftward past the rows its band holds.
  - A switch whose row names a `touch_state` (a VehicleInput field) reads "<label> ON" in amber
    while engaged, like the latching HAND.
  - On a pointer display the driving pads are drawn at `DESKTOP_PAD_SCALE` of the theme scale:
    the keyboard carries every control there, so the pads give the 3D view back. The top-left
    column is exempt (`MENU_BTN_SIZE`, theme scale only) — the way out stays easy to hit.
  - The bottom-right is one lattice of `CELL_SIZE`: a pedal is two cells tall plus the gap, so
    the drawer's rows line up with DOWN, UP, the QUICK row and EQUIP.
  - Seven bound actions have no touch button, keyboard-only and documented on the CONTROLS
    sheet: `next_vehicle` (garage is how touch changes vehicle), `toggle_dashboard` (F2),
    `respawn` (R; the pause menu's RESPAWN row reaches touch) and `day_night` (N; the
    CONDITIONS page's TIME row reaches touch), dev keys `debug_overlay` (F3), `toggle_touch`
    (F4) and `toggle_important` (F5). `LEVEL` opens the level selector directly (pauses the
    world and hides the pads itself, mirroring GARAGE) and also has a keyboard action
    (`level_select`, key 4). `_shell_signals()` is checked against the registry by
    `tests/test_action_registry.gd`.
  - Raw intent lives in two dicts keyed by the registry's `poll_key` — `_held` for levels,
    `_edges` for one-shot toggle edges — drained by `poll()`. A pad hidden mid-press emits
    its own release (`Pad._notification`), so held state can't stick when the bridge goes
    live; `poll()` returns `{}` entirely while hidden.

## Level framework

- `src/levels/base/`: `Level` (reads a `LevelInfo`, spawns the default vehicle at the first
  matching `VehicleSpawn`, wires the `ChaseCamera`, handles respawn; variant -> scene comes
  from `VehicleCatalog`). The train branches out of the marker path: `_spawn_vehicle` gates
  on `has_closed_rail()`, self-places on the loop; the shell drops "train" from the garage
  roster with no closed loop. `LevelInfo` (Resource: display name, allowed/default
  vehicles), `VehicleSpawn` (`Marker3D` with a vehicle-type filter + `is_water` for
  boat/drown-respawn spots), `HeightmapTerrain` (authoring side in `docs/level_kit.md`; at
  runtime a greyscale image -> chunked welded grid mesh + matching `HeightMapShape3D`, and
  the per-surface grip source: eight `channel_grip` values blended by
  `grip_at(world_pos)` over bilinear splat weights, from splat + height Images decoded once
  and cached, never `get_image()`d per tick. `grip_at` pow-sharpens weights with the
  material's `blend_sharpness`, matching the splat shader; `get_splat_weights` returns the
  raw weights).
- `level.tscn` is the authoring template (env + sun + camera + one spawn); duplicate it to
  start a level.
- `src/levels/island/level_1/` .. `level_6/` are the six playable islands — generated
  terraced terrain + auto-splat + sea, each rostering at least car/truck/tractor/boat.
  `level_1` is dressed (roads, props, scatter, the ISOBUS farm playground in its free
  centre) and is the CI baked-level smoke target; 2-4 are blank canvases with an empty
  `AuthoringRoot`. `level_5` (railway — closed rail loop with grades) and `level_6`
  (skyport — drone bench: pads at altitude, mast slalom, a canyon that takes satellites
  away) are each owned end to end by their generator (`tools/gen_rail_level.gd`,
  `tools/gen_skyport.gd`); re-running one overwrites the level.
- `src/levels/island/car_arena/` is the car challenge arena (`arena: true` in the registry, so not
  in LEVEL select): a car-only plateau with three roads, owned with its challenge courses by
  `tools/gen_car_arena.gd`.
- `flatland` and `open_sea` are endless, unbounded levels with no kit content (nothing to
  bake): an `InfiniteGround` (`src/levels/base/infinite_ground.gd`) or an `infinite`
  `WaterSurface` that re-centres on the active camera, with the grid and the waves laid in
  world space so the re-centre is invisible. No `WorldBounds`; float precision is the limit.
- `src/levels/dev/flat.tscn` is a bare test plane for isolated wheel checks.
- Loading a stranger's level is arbitrary code execution (a `.tscn` can embed scripts) —
  third-party level sharing stays out of scope.

### Water & world bounds

- `WaterSurface` (`src/water/water_surface.gd`, `@tool Area3D`, group `"water"`): the height
  API (`get_height(pos)`, flat), the visual plane (optional `far_sea_extent` skirt so the
  horizon reads as sea, not the square map edge), and the non-boat kill/respawn volume — box
  top `kill_margin` below the surface so a shoreline splash isn't death, `body_entered` ->
  `call_deferred("respawn")` on any non-boat `BaseVehicle` (deferred for physics flush),
  region tested with `contains_xz`. Water does not own the map boundary. See `CLAUDE.md` §
  Levels & water (waves never feed physics, don't rotate the kill rect, water is a direct
  child of the level).
- `WorldBounds` (`src/levels/base/world_bounds.gd`, `@tool StaticBody3D`): the containment
  box for every vehicle — four invisible perimeter walls on the `extent` rect plus a ceiling
  at `ceiling_height`, from `floor_depth` below origin to the ceiling. Pure collision, no
  meshes. Direct child of the level, axis-aligned, never rotated, never under `Authoring`.
  Sized independently of the water so a drone or plane can't climb over it into the
  collision-less far sea. Set `extent` to the water `size` so sea wall and map wall are the
  same wall. Unit-tested in `tests/test_world_bounds.gd`. Default `ceiling_height` is
  1500 m, clear of the contract's 0-500 m `altitude` scale.
- Depth-fade shading (`water.gdshader`, fragment-only): samples `hint_depth_texture`,
  reconstructs view distance behind each water fragment, fades `shallow_alpha`->`deep_alpha`
  / `water_color`->`deep_color` over `depth_fade_m` — a free shore gradient, opaque deep
  water hiding the seafloor and map edge. NDC z is reconstructed for gl_compatibility
  (`depth * 2.0 - 1.0`; Forward+ leaves depth as-is) — the project runs Compatibility.

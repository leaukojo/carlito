# Runtime systems

Per-system detail for everything that runs in the game. Editor/authoring tooling is in
`docs/level_kit.md`; rules and gotchas are consolidated in `CLAUDE.md`.

## Signal contract

`contract/carlito_contract.json` (currently v19) defines every bridge signal: name, dir,
type, unit, range, optional `warn`, enum, vehicles, optional `flavor` (`"isobus"` —
tractor, `"canaerospace"` — plane, `"dronecan"` — drone, `"train"` — train: protocol
signal names/semantics borrowed, frame layout stays on the sloppyCAN side). The
`Contract` autoload loads + validates it at startup; `tests/test_contract.gd` fails if a
required signal goes missing. Signals are unique by **(name, dir)** — `battery` exists in
both directions (in = warning LED, out = voltage). `warn` is the danger threshold the
dashboard highlights (tacho redline, low fuel, coolant overheat); the dash infers low- vs
high-side from which end of `range` it sits near (`SignalDef.warn_is_low()`). No entry is
`todo`; a future planned-but-unimplemented signal would use that marker again.

Contract edits bump `version`; both sides warn on mismatch at runtime (that warning — not
CI — is the drift guard; sloppyCAN has no CI). **Sharing is a synced copy, canonical here:**
`tools/gen_js_contract.mjs` regenerates `../sloppycan/carlito_contract.js`
(`window.CARLITO_CONTRACT`, a committed JS global so it loads from `file://` with no build
step). Run it after any contract edit.

## Input pipeline

`InputRouter` (autoload) merges input sources into one normalized `VehicleInput`;
**all arbitration lives here** as static/pure functions, unit-tested in
`tests/test_input_arbitration.gd`:

- `arbitrate_local`: key gating (ignition required for throttle), brake-never-throttle,
  S = brake-then-reverse at standstill, foot brake drives `brake_lamp`.
- `arbitrate_bridge`: while the bridge is active and the gear byte is a real gear (D1–D6 or R),
  the **gear owns direction** (`throttle = accel` signed by the byte, `gear_auto = false`).
  Byte 0 is **not** Park — it means "no gear opinion", and the gearbox falls back to auto-shifting
  forward exactly as with no bridge connected, so a CAN source that models no gearbox (hardware
  that never sends RAMN `0x077`) still drives. Reverse always needs the explicit R byte.
  Brake never throttle; key gates throttle — and the "ignition off" notice is taken down the
  moment the key reaches Ignition (`GameState.notice_cleared`) rather than sitting out its 20 s
  dwell. Lamp/warning bits (`turnL`/`turnR`/`brakeLamp`/
  `checkEngine`/`battery`) are mirrored **verbatim** — sloppyCAN is the sole authority; any
  absent bit defaults off. The ISOBUS fields mirror sloppyCAN verbatim too — the implement
  requests (`hitch_request` from `hitch_pos` %→unit, `pto`; absent → raised/off), the driveline
  requests (`pto_mode`/`diff_lock`/`fwd_drive`; absent → 540, open diff, 2WD — a real tractor's
  rest state) and the bridge-only `scv_flow` (absent → valve shut) — and so do the flight fields
  (`elevator`/`climb`/`arm`/`flaps`; absent → neutral/disarmed/retracted). Two in-signals
  **override `steer` when present**: the boat's `rudder` (its rudder IS the steer channel) and
  the tractor's `guidance` (from `guidance_curvature` — an external computer is holding the
  wheel). Presence is the whole rule, so `bridge_source.gd` includes either key only when
  sloppyCAN actually sent it; a commanded dead-straight 0 is a real command, not an absence.
- `merge_local` (pure): combines keyboard + touch (max analog, summed steer, OR'd bits)
  before `arbitrate_local`.

`_physics_process` prefers the bridge source when fresh (< 300 ms), else falls back to
`arbitrate_local` untouched. `src/input/sources/bridge_source.gd` normalizes contract-in
fields (%→unit); `local_source.gd` reads the keyboard; the touch overlay registers itself
via `InputRouter.set_touch_source()`.

Toggle-state owners: the router owns the shared headlight level `_lights` (cycles
OFF→CLEARANCE→LOW→HIGH), the hitch toggle `_hitch_up`, the PTO toggle `_pto`, the tractor
driveline toggles `_diff_lock` / `_fwd_drive` / `_pto_mode` (540 ↔ 1000), the drone
arm toggle `_armed`, the plane flaps toggle `_flaps_down`, and the train pantograph/doors
toggles `_pantograph`/`_doors` (pantograph defaults **raised** — the usable-default
pattern, so a locally-driven train spawns able to move; lowering it visibly cuts traction);
sources report per-frame edges (`lights_cycle`, `hitch_toggle`, `pto_toggle`,
`pto_mode_toggle`, `diff_lock_toggle`, `fwd_drive_toggle`, `arm_toggle`,
`flaps_toggle`, `pantograph_toggle`, `doors_toggle`) that `merge_local` ORs, so keyboard
and touch share one owner.

Local keys: W/S (or arrows) accel + brake-then-reverse, A/D steer, Space handbrake,
H horn, L lights, V next vehicle variant, I hitch, P PTO, J PTO mode (540/1000),
K diff lock, M MFWD front axle, R/F flight up/down (plane
elevator / drone climb — one shared axis), T arm, B flaps, U pantograph, O doors,
G garage, N day/night, Backspace respawn, F3 debug overlay, F4 force-show touch controls.
`tests/test_input_map.gd` asserts no two actions share a physical key.

### The action registry

`src/input/action_registry.gd` is the one description of what each bound action *is*: a static
table keyed by row (a control on two keys — drive/reverse, steer, climb/descend — is one row),
each carrying a label, a `group` (drive / vehicle / world / shell), a **gate**, and how the touch
overlay should offer it. It is a *registry, not a second input map*: no key string is typed there,
`keys_for()` reads the live binding out of `InputMap`.

Two consumers and nothing else describes controls — the pause menu's CONTROLS sheet
(`src/ui/pause_menu.gd`) and the touch button stack (`src/ui/touch_controls.gd`) — so a control
cannot be on screen without being documented, or documented without being reachable. That is the
point: the hand-typed help this replaced had drifted to ten missing actions and six with no touch
button, silently. `tests/test_action_registry.gd` asserts every bound (non-`ui_*`) action is in
exactly one row, so adding a binding without documenting it fails CI.

`applies(id, ctx)` is the single gate predicate both consumers share — the touch overlay hides
what it says no to and the sheet greys it, with `gate_note()` giving the reason. Four gate shapes:

- **families** / **excludes** — vehicle-family lists (`flaps` is plane, `steer` is everything
  except the rail-guided train).
- **capability** — a bool the shell reads off the vehicle (`boot.gd:_capabilities()`), used
  wherever one family disagrees with itself: within `truck` the semi tows and the garbage truck
  does not, only the garbage truck has a refuse body, and cycling a semi's trailer changes the
  answer without changing the body. Sources are duck-typed and OR'd —
  `cycle_implement` (tows), `vehicle_capabilities()` (spec driveline flags on `BaseVehicle`, the
  refuse-body geometry declaration on `TruckVehicle`), `attachment_controls()` (the trailer's or
  implement's own PTO / lift).
- **bridge_owned** — the control rides `VehicleInput`, so it is *inert* while sloppyCAN drives:
  InputRouter takes the bridge branch and never polls a local source at all. Deliberately *not*
  set on the shell conveniences (ATTACH, VIEW, GARAGE, NEXT, RESPAWN, MENU), which are overlay
  signals that never reach `VehicleInput` and keep working with the bridge live. Known deliberate
  exception: the pedals and joystick are equally inert but stay on screen — they are the identity
  of the overlay and `Bridge.is_active()` follows data freshness, so hiding them would make the
  gas pedal blink in and out as sloppyCAN stutters.

The family gates are **validated against the contract, not copied from it** (rule 4): a row that
rides contract IN signals names them in `signals`, and `tests/test_action_registry.gd` asserts the
families it is offered to are exactly the union of those signals' own `vehicles` lists. That sweep
is what caught `handbrake` omitting the plane — whose tricycle gear takes `handbrake_torque` on
three RayWheels, so its park brake was real in the sim and absent from the contract (fixed in
v19). The one row with no `signals` is `hitch`: on a tractor it is `hitch_pos`, but on a semi it is
the tipper's valve, which reuses the same local toggle and deliberately has no signal of its own —
`hitch_pos` is flavored `isobus` and a bulk tipper is a J1939 truck.

## Vehicle framework

`src/vehicles/base/`:

- **`VehicleSpec`** — ALL drive tuning in one `.tres`; new vehicle = new spec + scene.
  Feel tuning is data-only: edit the spec numbers, keep the input-hierarchy test green
  (brake > peak drive > handbrake; handbrake holds only below ~30% throttle).
- **`VehicleCatalog`** (`src/vehicles/vehicle_catalog.gd`) — static registry of vehicle
  *variants* (one concrete body scene each: the hand-built vehicles + the Kenney
  car-kit bodies + the Watercraft-pack boats) mapped onto the contract *families*
  (car/truck/tractor/boat/bike/drone/plane). The FAMILY drives bridge marshaling, dashboard cluster and
  spawn filtering; a variant carries its own spec (and, for boats, its own hull/buoyancy
  knobs), so it drives differently but signals identically. Generated one-shot by
  `tools/gen_kenney_vehicles.tscn` and `tools/gen_boat_variants.tscn` (game-mode tool
  scenes, deterministic, destructive-by-run — re-run after a scale/feel change).
  V (or the touch NEXT button) cycles variants within the current
  family via `Level.set_vehicle`; `GameState.current_variant` tracks the active one, and it does
  this on every vehicle without exception. What hangs off the back is a **separate axis on its own
  key**: E (or the touch ATTACH button) duck-types `cycle_implement()` on the active vehicle, so
  the tractor's implement and the semi's trailer cycle without ever changing the body. Keeping
  them apart is why neither key means two different things depending on what you are driving, and
  why a one-body vehicle like the tractor is not a dead end. ATTACH hides itself where the vehicle
  tows nothing. Unit-tested in `tests/test_vehicle_catalog.gd`. The contract never sees variants.
- **`Drivetrain`** — pure math: engine torque curve, gear ratios, RAMN gear byte
  (0x00 = N, 0x01..0x06 = D1–D6, 0xFF = R), real RPM (wheel speed through the ratio with
  idle/redline clamps), auto-shift. Unit-tested in `tests/test_drivetrain.gd`. With the
  bridge gear byte, auto-shift is bypassed and the byte is exact.
- **`RayWheel`** — one ray per wheel: spring-damper suspension + slip-based tires. The
  60 Hz stability clamps live here (damper ≤ one-tick reversal, suspension force cap,
  low-speed slip floors + one-tick lateral force cap). Tire grip scales by the painted
  ground: each contact samples `HeightmapTerrain.grip_at()` (BaseVehicle collects the
  level's grip terrains once, duck-typed `grip_at`+`contains_xz`+`height_at`); the
  multiplier rides `mu_long`/`mu_lat` — the 60 Hz clamps are untouched (they cap by
  momentum, independent of mu). The terrain used is the one whose surface is *nearest the
  contact point* and within `SURFACE_GRIP_REACH` (1 m) of it — a conformed road's deck sits
  at the flattened terrain height and still reads the paint, while a bridge or ramp passing
  over a painted patch keeps neutral grip instead of inheriting it.
- **`BaseVehicle`** (RigidBody3D) — consumes `InputRouter.get_vehicle_input()` only, runs
  wheels/drivetrain, publishes telemetry, applies lamps, plays the horn on the rising edge
  (source-agnostic). Zero-wheel-safe (the boat spec has empty `wheel_positions`). Two
  virtual seams for subclasses: `_make_telemetry()` (telemetry factory used in `_ready`)
  and `_tick_extras(input, delta)` (empty in base, run **last** in `_physics_process` so
  drivetrain RPM + telemetry motion are current). Subclasses never fork `_physics_process`.
- **`ChaseCamera`** — follows `get_global_transform_interpolated()`.
- **`LampSet`** / **`Horn`** — see Lamps & horn below.

Arcade drift: `VehicleSpec.handbrake_grip` scales rear lateral grip while the handbrake is
pulled (car: 0.45). It exists because the hierarchy test caps `handbrake_torque` too low to
lock the rears — drift comes from the grip cut, not brake torque.

### Measuring a vehicle: `tools/measure_vehicles.tscn`

A dev tool for the questions the unit tests can't answer, because they need a whole vehicle
on the ground for a minute rather than a pure function: *how fast is this thing, and does it
go where it's pointed?* Not a CI gate — it always exits 0, and a FAIL is something to go
look at, not something that blocks a push. Game-mode tool scene (autoloads + a live physics
step, which `--script` mode has neither of):

```powershell
& $GODOT --headless --path . res://tools/measure_vehicles.tscn -- sedan-sports
& $GODOT --headless --path . res://tools/measure_vehicles.tscn -- all 45
```

The argument is a `VehicleCatalog` variant id (default `sedan-sports`) or `all`, which walks
every **wheel-driven** variant — the boat/drone/plane have no driven axle and need water and
air, not a strip. The optional second argument is the per-pass time cap in seconds.

The strip is a bare 40 × 6000 m `StaticBody3D`, which means `surface_grip` 1.0 (RayWheel only
drops below 1.0 over painted terrain) — the sim's asphalt-equivalent surface. Two passes per
vehicle, both with the steering input never touched:

- **Acceleration / top speed** — 0-50/100/150/200 km/h, 0-60 mph, quarter mile, and the
  settled top speed with the gear and rpm it lands in. It also flags when a vehicle tops out
  below its tallest ratio, i.e. carries gears it can never use. Top speed is reported as
  *settled*, not exact: the approach to terminal speed is asymptotic, so the run stops once
  it gains less than ~0.2 % over three seconds. Waiting for the true asymptote added minutes
  per vehicle and moved the number by well under 1 %.
- **Straight-line tracking** — the one that catches a chassis that quietly pulls. The
  vehicle is respawned, accelerated to 60 km/h (so the launch transient — wheelspin, squat,
  the first-tick suspension settle — isn't counted), and only then is the pose latched as
  the ideal line. It then runs 200 m with zero steer while lateral offset from that line and
  heading change are measured. Thresholds are 1.0 m and 1.0°; every shipped vehicle today
  measures **0.000 m and 0.000°**, so a FAIL means a real asymmetry — a mistyped
  `wheel_positions` x, a one-sided drive split, uneven brake torque. The detector was
  falsified before being trusted: a deliberate 400 N lateral force makes it read 6.033 m and
  2.825°.

**Do not try to make this faster with `Engine.time_scale`.** Godot scales the delta handed to
`_physics_process` rather than running more iterations, so it enlarges the step instead of the
rate — the locked-60-Hz rule, broken. Measured: the default car's 0-100 goes 5.30 s → 6.40 s
at `time_scale` 8. An `all` run is genuinely several minutes of wall clock; background it.

## Telemetry & dashboard

- **`VehicleTelemetry`** (`src/vehicles/base/vehicle_telemetry.gd`) carries every contract
  "out" signal for ground vehicles. Motion (speed, rpm, gear, slip, yaw, accel, heading,
  position) is read straight out of the sim; the aux systems (fuel/coolant/battery) are
  simple *honest models*, not fakes. Each non-trivial derivation is a static pure fn (GPS
  `gps_lat`/`gps_lon` around the Paris origin 48.8566/2.3522, `heading_from_forward`,
  `odo_step`, `body_accel`, `impact_gate`, fuel/coolant/battery models, `pack_status`) —
  unit-tested in `tests/test_telemetry.gd`. `BaseVehicle._update_telemetry(input, delta)`
  holds the only per-tick state (prev velocity for accel/impact, accumulators); respawn
  zeroes the accel history so a teleport isn't read as an impact. The `status` bit layout
  is **provisional** (named `ST_*` bits; the final assignment is fixed with sloppyCAN when
  CAN frame packing is finalized).
- **`to_bridge_dict()`** is the one place mapping telemetry fields → contract "out" names
  in contract units (throttle/steer as %, slip as ratio); a `test_telemetry` case fails if
  it stops covering a non-todo ground "out" signal. Subclasses = `super()` + append.
- **Dashboard** (`src/ui/`): `dashboard.gd` **generates** the tell-tale row (a lamp per
  bool "in" signal + `key`/`lights` enum chips, plus a telemetry-driven lamp for each
  flavored bool "out" — the PTO, IMPL and ARMED lamps, the tractor's DIFF/MFWD and the train's
  PANTO/DOORS state lamps, and a telemetry-driven chip for each flavored enum "out" — the
  tractor's TOOL chip, whose text is decoded by the contract's own enum table) and
  the bars (each "out" signal that has a `range` **and** a `warn` — fuel/coolant,
  altitude/vspeed, pitch/roll — or a `flavor` — the tractor's
  HITCH/PTO/LOAD/WHEEL/GROUND/SLIP/DRAFT panel, FLAPS,
  ROTOR, the train's LINE/AMPS/PIPE) by walking the contract for the active vehicle type.
  Where a signal exists in both directions the **request lamp sits beside its state lamp**,
  captioned REQ (PTO REQ/PTO, DIFF REQ/DIFF, MFWD REQ/MFWD, PAN REQ/PANTO, DOOR REQ/DOORS):
  the pair is what separates "commanded" from "actually engaged", and a request that does not
  become a state is the readable form of a refusal (engine off, or a spec that cannot do it).
  A flavored "out" signal with **no** `range` lands on the readout line beside HDG/ODO instead
  of becoming a bar — that is where the tractor's HRS hour meter goes, a running total having
  no meaningful full scale.
  The two radial gauges (`gauge.gd`, one bespoke widget instanced twice: speedo + tacho) are
  **hand-built** and only read scale/redline from the contract; each is built only when the
  vehicle declares its signal (`kmh`/`rpm` in `signals_for_vehicle` — the boat gets a
  speedo, no tacho). Gauge text sits in the arc's bottom 90° gap; gear shows in the tacho
  gap via the contract `gear` enum. The **train** declares `gear` out but not `rpm`, so
  there is no tacho gap to carry the label — it gets a bespoke `REVERSER N/D/R` centre
  readout instead (hand-picked like the two gauges, built only for that case). Short
  captions (`BAR_LABEL`, `LAMP_TEXT`) are hand-picked. `bar` widget is `dash_bar.gd`.
  Plain text + color only.
  **Density** (`Dashboard.Density`): FULL is everything above; COMPACT keeps the tell-tale row
  and the gauges (smaller) and drops the bars and the HDG/ODO readout; OFF hides the cluster.
  What COMPACT drops is only ever whole sections — the generation rules are identical in both
  visible modes, so no signal can go missing in one of them (`tests/test_dashboard.gd`). The
  setting is AUTO by default: COMPACT on a phone-sized screen (short edge ≤ 520 logical px) or
  while `Bridge.is_active()` — sloppyCAN is showing you the same numbers — and FULL otherwise;
  AUTO never resolves to OFF. Bridge freshness flips on a 300 ms window, so AUTO waits for it to
  hold 2 s before rebuilding. It is overridden from the pause menu's SETTINGS page and persists
  in `user://shell.cfg`. Every metric is logical px through `UiTheme.px`, gauge and bar
  internals included, so the cluster is proportional at any UI scale and rebuilds on
  `NOTIFICATION_THEME_CHANGED`. The tell-tale row is an **HFlowContainer**: its width is however
  many lamps the contract declares (fifteen on a truck with a trailer), so it wraps rather than
  running off the side of a phone.
- **Debug overlay** (`debug_overlay.gd`): FPS / frame ms / draw calls / primitives / VRAM /
  node count from the `Performance` monitors, toggled with **F3**. The perf guardrail is
  < ~500 draw calls in the worst view.

## Bridge

- **Transport is web-only.** The export **Head Include** (`export_presets.cfg`
  `html/head_include`; reviewable source `src/bridge/web/head_include.html`) installs
  `window.__carlito`: it stashes inbound `{type:'carlitoInput'}` values with a timestamp
  and exposes `publish()` for outbound `{type:'carlitoOutput'}`.
- `Bridge` autoload (`src/bridge/bridge.gd`): `OS.has_feature("web")` gates everything
  (inert on desktop — `is_active()` false, no JS touched). Polls the inbound stash each
  physics tick (~60 Hz), freshness-gated 300 ms in JS; publishes telemetry ~20 Hz,
  marshaling `values` **by contract name** from
  `Contract.signals_for_vehicle(GameState.current_vehicle, "out")` ×
  `telemetry.to_bridge_dict()` — vehicle-aware, so a car emits car signals and the tractor
  adds its thirteen ISOBUS "out" signals on top. Both sides stamp their contract version on outgoing messages and
  warn once on mismatch.
- `boot.gd` calls `Bridge.bind(level)` (mirrors `Dashboard.bind`); both rebind on
  `Level.vehicle_changed`.

## Lamps, horn & day/night

- **Lamp state flows through `VehicleInput`, never a side channel.** Locally only
  `brake_lamp` is driven (from the foot brake); turn signals + warning LEDs stay off —
  **there is no local blink timer** (turn lamps blink because the bridge source toggles
  the bit).
- **`LampSet`** (`src/vehicles/base/lamp_set.gd`) applies lamp state to **scene-authored**
  lamp nodes the `VehicleSpec` names by NodePath (`headlight_paths` = SpotLight3D nodes
  with distinct energy/range per `lights` level; `brake_lamp_paths`/`turn_*_paths` =
  MeshInstance3D lenses given a private emissive material at setup). Placement is
  scene-authored; the spec only declares which node is which lamp. Rear lamps are
  tri-state via the pure `LampSet.rear_tier(brake_on, headlights)`: STOP > TAIL
  (headlights ≥ clearance) > OFF (dim housing, never invisible) — unit-tested in
  `tests/test_lamps.gd`. `BaseVehicle` builds one `LampSet` in `_ready` and calls
  `apply()` each tick.
- **Horn is procedural** (`horn.gd`: a looping two-partial `AudioStreamWAV` synthesized at
  `_ready`, no asset). Plays on the horn **rising edge** and holds while pressed.
- **Day/night is a `Level` concern** (not a bridge signal): **N** toggles the level's sun +
  ambient between the scene-authored day values (captured at load) and a dim night preset
  (`level.gd`).

## Shell, touch controls & garage

- **Shell flow** lives in `boot.gd` (the `boot.tscn` root — there is no giant main.tscn):
  boot → load level → play, with a pause overlay over the top. **It drives first in every
  mode** — there is no front door, standalone and the sloppyCAN embed both open in a level
  with a car in it. The persistent HUD (dashboard, debug overlay, touch controls) is authored
  in `boot.tscn`; `PauseMenu`/`LevelSelect`/`VehicleSelect` are transient Control overlays the
  shell creates/frees. Headless is no longer a special case: nobody reaches a level by
  clicking, so the CI smoke takes the same path everything else does.
- **What it boots into** is decided by `_boot()` from three authorities, in order: a **deep
  link**, the **saved session**, then `boot.gd`'s `DEFAULT_LEVEL` (`level_1` — the dressed
  island: farm fields, coast roads and water in the first frame, on a 1.8 MB bake; `level_3`
  at 13.9 MB must never boot).
  - *Deep link* — `?level=<id>&vehicle=<variant>` on the page URL (this is how sloppyCAN asks
    for a configuration), or `--level=`/`--vehicle=` after a `--` locally, or the
    `CARLITO_LEVEL` env var CI uses. Parsed and **validated** in `src/shell/boot_params.gd`:
    unknown ids are dropped, not clamped, so a stale link falls back instead of booting into
    nothing. `vehicle` names a VARIANT (`semi`), not its family (`truck`).
  - *Saved session* — `src/shell/shell_prefs.gd` writes the level id + variant to
    `user://shell.cfg` on every load and vehicle swap, so a reload resumes where you were.
    **Skipped entirely when a deep link is present** (an explicit link is someone else's
    intent and must not overwrite yours) and under `--headless` (CI must not inherit whatever
    was last driven locally).
  - The requested variant reaches the level through `Level.initial_variant`, set *before* the
    level enters the tree — the level spawns it in `_ready` instead of spawning its own
    default and immediately throwing it away. Not allowed there (or a train with no loop) and
    the level's default wins.
- **One theme, rebuilt per window size** (`src/ui/theme/ui_theme.gd` + `src/ui/ui_scale.gd`).
  `UiTheme` is the project's design tokens (colour roles, a five-step type scale, metrics) and
  `build(scale)` turns them into a `Theme`; `UiScale` — a **Control** in `boot.tscn`, not an
  autoload and not the Window (a Control under a CanvasLayer does not inherit the Window's theme)
  — recomputes the scale from the window's **short edge** on every resize and assigns the rebuilt
  theme to itself. Every screen the shell builds is parented there, so it is themed without
  asking. Screens declare a ROLE (`theme_type_variation = &"Title"`), never a pixel size; anything
  the theme cannot express (a card size, a joystick radius) goes through `UiTheme.px(self, …)`,
  which reads the scale back off the theme the Control already inherits. Persistent screens
  relayout on `NOTIFICATION_THEME_CHANGED`. **The engine's content scaling is deliberately not
  used**: both `Window.content_scale_factor` and `CONTENT_SCALE_MODE_CANVAS_ITEMS` were measured
  on 4.7.1 to resize the *3D* render target, which standing rule 9 rules out on web.
  - Overrides that survive in the screens are the **semantic** ones — a lamp's lit colour, a bar's
    warn red, the notice line's amber. Those are signal data wearing a colour, not styling.
  - **Keyboard and gamepad reach everything.** The theme carries a `focus` box (accent border) on
    every Button, and `Choice` is the variation for a toggle standing in a radio group (the family
    column) — the plain `pressed` box reads as recessed, which is the opposite of chosen. Card
    grids rely on Godot's geometric focus neighbours; every scroll area with focusable content
    sets `follow_focus` so arrowing past the fold scrolls rather than walking the ring off screen.
    The CONTROLS sheet is the exception — every row on it is a Label, so `PauseMenu` moves the
    scroll on Up/Down itself. A screen never leaves focus on a disabled control: the vehicle
    selector hands it to BACK when the level refuses the previewed family.
- **Notice line** (`src/ui/notice_line.gd`, the `Notice` Label in `boot.tscn`): the transient
  message the sim raises through `GameState.notice` ("NO ROOM FOR A TRAILER"), dwelled for
  `Boot.NOTICE_DWELL_S` and re-shown rather than queued. It lays *itself* out — height from the
  font it is actually drawn in, and a symmetric inset that keeps it clear of the touch overlay's
  button columns (symmetric because the line is centred; insetting one side only would knock the
  text off-centre on every screen to buy clearance on one).
- **Pause overlay** (`src/ui/pause_menu.gd`, **Esc** or the touch MENU button):
  RESUME / VEHICLE / LEVEL / CONTROLS / SETTINGS. Esc used to free the level outright with no
  confirmation — it now opens this, and walks back out the way it came in (a screen opened on
  top closes back to the menu, a second page closes back to the first, and only then
  does Esc resume). VEHICLE and LEVEL are **signals**: the selector and level-select overlays
  stay the shell's to create and free, and the pause menu never learns what a level or a
  vehicle is. CONTROLS is **generated from the action registry**: grouped rows, each binding read
  live out of `InputMap`, and anything the machine you are driving does not have greyed with the
  reason ("tractor only", "nothing to tow", "sloppyCAN is driving") rather than hidden — a greyed
  row teaches, a missing one does not. The shell hands it the same capability dict the touch
  buttons gate on (`setup(caps, density)`, before `add_child`), so the help and what is on screen
  cannot disagree. SETTINGS is one cycling button — the dashboard density (above) — and it applies
  nothing itself: it emits the new value, and the shell applies it and writes it to
  `user://shell.cfg`, the same way VEHICLE and LEVEL work.
  **Pausing**: the `Boot` node is `PROCESS_MODE_ALWAYS` so shell and menus keep running under
  `get_tree().paused`; the level is a child of it, so `_finish_load` puts it back to
  `PAUSABLE` explicitly or nothing would actually pause. Autoloads pause with the world — a
  paused sandbox publishing telemetry it is no longer simulating would be a fiction.
- **First-run cue** (`src/ui/coach_cue.gd`): one line over the first frames of a first visit
  ("W to drive… Esc for the menu", or the touch wording), dismissed by the first input of any
  kind or a short timeout, and never shown again (`ShellPrefs.coach_seen`). It listens on
  `_input`, which does not consume — the press that dismisses it also drives the car.
- **Level select** (`src/ui/level_select.gd`) is the pause menu's LEVEL section rather than
  the front door, so it carries a BACK button and a `closed` signal. It reads
  `LevelRegistry.LEVELS`
  (`src/shell/level_registry.gd`) — `{id, name, scene, desc}` entries; `dev: true` entries
  are test fixtures that bake/check/smoke still cover but level-select hides.
  It is a **card grid**: one `Button` per entry carrying that level's screenshot
  (`src/ui/level_thumbs/<id>.png`, addressed via `LevelShot.thumb_path`) with the name on a
  strip across the bottom, and the entry's `desc` shown below the grid while a card is
  hovered or focused (also its tooltip). A level with no screenshot yet falls back to a flat
  plate reading "no screenshot" — nothing breaks, the card just looks unshot. Cards are shot
  from the kit's **Polish** tab (see `docs/level_kit.md`); the framing lives in a side-car
  `<level>_shot.tres`, not in the level scene, so re-framing never re-stales a bake.
- **Vehicle selector** (`src/ui/vehicle_select.gd`), opened with **G**, the touch GARAGE button,
  or the pause menu's VEHICLE entry. Three axes on one screen — the family column, the family's
  variants as picture cards, and (when the previewed machine tows) a second row of what it can
  pull — where there used to be a menu of FAMILIES plus two invisible key cycles (V bodies,
  E attachments). **It pauses the world** from either entry point.
  - **One live preview, never one per card.** ~30 variants would be ~30 SubViewports; instead the
    cards carry pre-baked stills and a single long-lived SubViewport on the right holds the
    selected machine on a turntable (the *camera* orbits — rotating a frozen RigidBody3D would
    fight the physics server for a transform it is already writing). The preview body is a REAL
    vehicle, spawned through `VehicleShot.spawn_display`: frozen KINEMATIC with no gravity (the
    showroom pose, so `_physics_process` still runs and RayWheel poses the wheels) and
    `display_only = true`, which keeps it out of `InputRouter`'s single vehicle slot — that slot
    is a plain assignment, so a preview would otherwise take the driven body's place and null it
    again on its way out.
  - **Nothing is hidden.** A family this level will not spawn is still listed, still opens, still
    previews, and carries the reason on its cards; only DRIVE is refused (and the refusal is
    checked in `_on_drive`, not just on the button). Both reasons are **derived** — the level's
    own `allowed_vehicles`, and `Level.has_closed_rail()` for the rail-guided train — so there is
    no per-family prose to drift.
  - **The attachment row is the previewed machine's own answer.** `attachment_ids()` /
    `current_attachment()` / `set_attachment(id)` are duck-typed on `TractorVehicle` and
    `SemiTractor` (and `cycle_implement()` now goes through the same setter, so a key press and a
    pick cannot diverge), so the screen offers trailers for a semi and nothing for a garbage truck
    without learning what a trailer is. DETACHED / BOBTAIL are real cards reading NONE.
  - It emits `vehicle_chosen(variant)` and then `attachment_chosen(id)`; the shell calls
    `Level.set_vehicle(variant)` — **only when the variant actually changed**, so re-picking what
    you are driving to swap its trailer does not teleport you back to the spawn marker — which
    respawns at a `VehicleSpawn` matching the variant's FAMILY and emits
    `Level.vehicle_changed(type)` so the shell rebinds the dashboard/bridge. `Dashboard.bind`
    reads `GameState.current_vehicle` (the spawned family), falling back to
    `LevelInfo.default_vehicle`. Adding a vehicle = a `VehicleCatalog.VARIANTS` entry + its family
    in a level's `allowed_vehicles` + a thumbnail run.
- **Vehicle cards** are written by `tools/gen_vehicle_thumbs.tscn` (**windowed only** — headless
  has no renderer) to `src/ui/vehicle_thumbs/<id>.png`: every catalog variant by variant id, plus
  every implement and trailer by scene basename. Framing, lighting and the display pose all come
  from `src/ui/vehicle_shot.gd`, which the live turntable uses too, so the still and the model
  beside it are the same picture — and the camera distance is **measured** off the instantiated
  body's AABB, so an artic's card shows the combination it really spawns pulling. The PNGs live
  under `src/` because `tools/*` and `kit/thumbs/*` are export-excluded and the selector needs
  them at runtime.
- **Garage showroom level** (`src/levels/garage/`, registered id `garage`): a real Level
  whose spawned vehicle is frozen KINEMATIC hovering above the floor — `_physics_process`
  still runs, so wheels steer/spin, the engine revs and lamps toggle while the orbit
  camera (`orbit_camera.gd`) inspects from any angle, including underneath; a wall
  screen shows the active variant's spec. Input, dashboard and bridge flow through
  Level unchanged.
- **Touch controls** (`src/ui/touch_controls.gd`) are a second local `InputSource`: steering
  joystick (bottom-left), gas/brake pedals (bottom-right, with the UP/DOWN flight pads extending
  the row leftward for aircraft), and a right-edge button stack. Widgets take touch **and** mouse.
  Visible only on touch/web (`_should_show()`); **F4** force-toggles for desktop tests.
  - **The stack is generated from the action registry** — which buttons exist, their captions,
    their order, when they are shown and which raw-intent key each writes all come from that one
    table. It is split by `ActionRegistry.is_universal`: the outer column is what every vehicle
    has (HORN, LIGHTS, VIEW, NIGHT, GARAGE, NEXT, RESPAWN, MENU), the ones beside it only what
    the machine you are driving has (HAND plus TIP, PTO, PTO SPD, DIFF, MFWD, ATTACH on
    a tractor; PTO/BODY on the garbage
    truck). The machine controls used *while driving* are not in the stack at all: ARM (drone),
    FLAPS (plane) and DOORS (train) are hand-built in the LIGHTS/HORN row, and PANTO beside BRAKE
    in the pedal row. Fifteen buttons down one edge was a wall on a phone, and the split is *derived* from
    the gate rather than declared, so a button's column cannot disagree with whether it is
    vehicle-specific — HAND is in the vehicle column precisely because the boat and the drone
    have no handbrake.
  - **Either group wraps into a further column** when the band between `STACK_TOP` and the pedals
    cannot hold it (`_columns_for`), so a short window does not push buttons off the bottom of the
    screen. The capacity is measured for *every* pad being visible, because which ones are gated
    off changes as you drive. A resize that changes that capacity rebuilds the stack even when the
    UI scale did not move (the scale comes off the short edge and is clamped at both ends).
  - Only two bound actions have no touch button, and both are dev keys: `debug_overlay` (F3) and
    `toggle_touch` (F4) — `day_night` joined the stack as NIGHT in the Phase 7 sweep, relayed by
    `boot.gd` to `Level.toggle_day_night()`, because a level dressing itself for night is content,
    not a dev affordance. A `SHELL_SIGNAL` row with no signal behind it is a button that silently
    does nothing, so `_shell_signals()` is checked against the registry by
    `tests/test_action_registry.gd` rather than being a map you have to remember to extend.
  - Widgets are still hand-built (they are not buttons) but the registry decides whether each is
    shown, so the rail-guided train loses its **steering joystick** and only the flying families
    get the UP/DOWN pads without this file naming a family.
  - Raw intent lives in two dicts keyed by the registry's `poll_key`: `_held` for levels a pad
    holds down, `_edges` for one-shot toggle edges a tap latches, drained by `poll()`. Key names
    are `local_source.gd`'s, which is what makes InputRouter's toggle owners shared by keyboard
    and touch rather than duplicated per source. A pad hidden mid-press drops its pointer and
    emits its own release (`Pad._notification`), so held state cannot stick when the bridge goes
    live or F4 hides the overlay; `poll()` returns `{}` entirely while hidden.

## Truck & J1939

The truck is the one family that teaches **network topology**: a J1939 chassis, a CANopen body
network across a gateway, a deliberately thin truck/trailer bus, and — on one variant — no trailer
bus at all. Four variants, three protocols and one absence.

- **The truck family is a chassis class, not a job.** `garbage-truck`, `firetruck` and the two
  hand-built tractor units (`semi`, `semi-conventional`) only: ordinary heavy vans (delivery,
  delivery-flat, ambulance) are `car`-family, because they run proprietary CAN rather than J1939.
  J1939 is the **parent** of both ISOBUS and NMEA 2000, so building it explains two families that
  already ship. The same silhouette on two different buses is the point of the exercise, not an
  inconsistency to fix.
- **Eight J1939 chassis signals, all `flavor: "j1939"`.** **In (4):** `retarder`, plus the
  J1939-73 DM1 lamp bits `red_stop` / `amber_warn` / `protect_lamp`. **Out (4):**
  `air_primary`, `air_secondary`, `retarder_state`, `axle_load`. The selection is **cited, not
  tasteful**: every one is in the published **FMS** set — the standard subset of J1939-71 six
  European manufacturers agreed to expose in 2002, precisely *because* the internal bus is
  proprietary. That public-versus-proprietary line is the lesson.
- **Four more signals are REUSED, not duplicated** (rule 4): `engine_load`, `engine_hours`,
  `pto` and `pto_state` simply list `truck` alongside `tractor`. They keep `flavor: "isobus"`
  because ISO 11783 is built on J1939 and the tractor's were always the borrowed ones —
  `engine_load` is SPN 92 whoever reads it, `engine_hours` SPN 247. `diff_lock` /
  `diff_lock_state` are deliberately **not** extended: signals are unique by `(name, dir)`, so
  sharing them would stamp the ISOBUS flavor on a truck for no new lesson.
- **`TruckVehicle extends BaseVehicle`** (`src/vehicles/truck/truck.gd`) — a real subclass
  because it owns per-tick reservoir and PTO state, all of it in `_tick_extras`. One `@export`
  (`pto_load`, the tractor's parasitic term reused). **`TruckTelemetry extends
  VehicleTelemetry`** adds the seven "out" fields, named exactly as the contract.
- **Air pressure gates the brakes — it is a rule, not a readout.** Two reservoirs (SPN
  1087/1088) charge while the engine runs and are drawn down by brake applications; circuit 2
  is smaller, so the pair diverges instead of being one signal published twice. Below
  `TruckTelemetry.AIR_SPRING_BRAKE_BAR` (3 bar) **on either circuit** the spring brakes apply
  and the truck cannot move — the same shape as the train's pantograph cutting traction. The
  contract's `warn` (5 bar) is deliberately **higher**: it is the low-pressure warning, so
  there is a band to stop in rather than a jump from a red bar to immobile. The gate reads the
  **minimum** of the two circuits, which is what makes the redundancy mean anything. Labelled
  honest model — the truck has no simulated pneumatic circuit, the draw is pedal position and
  nothing else (not the handbrake, not speed, not load), and the gate has no ramp: losing the air
  while rolling locks the rear axle in one tick, which is what a spring brake held off by air
  physically does.
- **The retarder is a real driveline torque**, not an indicator bit: an auxiliary brake on the
  driven axle worth ~1.3–1.4 m/s² at road speed, fading to nothing at walking pace. Because it
  is *driveline* behaviour it follows the differential lock's pattern rather than living in a
  vehicle subclass — the math is on `Drivetrain`, `BaseVehicle` adds its torque to the driven
  wheels' brake torque so `RayWheel` integrates it like every other brake, and
  `VehicleSpec.retarder_equipped` (true only on the truck specs) keeps it inert everywhere
  else. It **cannot skid the axle**: `RETARDER_SLIP_TARGET` caps the one-tick spin change at
  0.10 slip. That has to be a slip limit and not a force limit — a cap at μ·N·r bounds the
  *saturated* road torque, which a locked wheel is already making, so it permits a full skid.
  Rated at a fifth of the per-wheel `brake_torque` — 10 % of the four-wheel service brake — so
  the tuned brake > peak drive > handbrake hierarchy holds by construction, and the strength is
  quoted as **arithmetic** rather than a remembered measurement:
  `frac * brake_torque * rear_wheels / (wheel_radius * mass)`. `test_truck` asserts both the
  hierarchy and the 1.0–1.6 m/s² band on every shipped truck spec, so the constant and this
  paragraph cannot drift apart.
  `retarder_state` reports the torque **actually applied** — the driveline, not the request,
  exactly like `diff_lock_state`. J1939 SPN 520 reports retarder torque *negative*; the contract
  publishes the magnitude and says so in the `desc`, because a `[-100, 0]` range would fill the
  generated RET bar backwards.
- **`axle_load` is read out of the sim.** It is the summed `RayWheel.suspension_force` on the
  rear axle in kilograms (SPN 582) — never a mass lookup, so braking weight transfer moves it
  because the springs really moved. `warn` 11500 is the real EU 11.5 t drive-axle limit, above
  the range midpoint so the dashboard reads it as a high-side danger.
- **The DM1 lamps are mirrored verbatim, with no timer of any kind.** `red_stop` / `amber_warn`
  / `protect_lamp` are the J1939-73 diagnostic lamp status byte; sloppyCAN is the sole
  authority and an absent bit is off. `checkEngine` already **is** DM1's Malfunction Indicator
  Lamp, so nothing is added for it. DM1's real lamp states also include flash-1Hz and
  flash-2Hz — those are **not** modelled, because a blink would need a local clock and the
  standing rule forbids one (see the plane beacon exception in `TODO.md`).
- **The firetruck is the control case**: same chassis class, different job, so it gets the
  identical generated cluster with no body network of its own (see
  `docs/plans/truck_improvements.md` decision 3). **DIN 14700 / DIN 14704** — the firefighting CAN
  interface, CiA 301 units behind a gateway mapping to J1939 parameter groups — would be exactly
  the right profile for it, and is *not* built: `firetruck.tscn`'s model is one merged mesh with no
  separable equipment, so a body network there would be signals with nothing to show.
- **One generated cluster for the whole family: 11 bars** — FUEL, COOLANT, LOAD, AIR1, AIR2, RET,
  AXLE, ARM, HOPPER, TRLR, TBRK — plus **18 tell-tales** and **4 state chips** (KEY, LIGHTS and
  BODY CMD from the "in" side, BODY from the "out" side). It is the same shape on every variant,
  because absent functions publish real zeros rather than gaps: the firetruck and both tractor
  units show ARM and HOPPER at zero, the garbage truck shows TRLR and TBRK at zero, and the
  conventional shows the trailer signals at zero *with a trailer on the back*. `engine_hours` is
  range-less on purpose and lands on the readout line beside ODO.
  It is the widest cluster in the game and it fits: **866 x 343 px** of minimum panel against the
  1152 x 648 default window, so nothing clips at 18 px a bar (the tractor, next widest, is
  728 x 291). The named demotion lever — dropping `range` from `retarder_state` and
  `trailer_brake_demand` so they leave the bar stack — is therefore **not** pulled, and should not
  be reached for on width grounds: both are genuine 0-100 % scales, unlike the hour meter whose
  range-lessness is honest, and the readout line is a hand-built format string rather than a
  generated walker, so a demoted signal would leave the cluster altogether rather than land beside
  ODO.
- **INHIB is the one lamp that does not simply show its signal, and the suppression is
  presentation.** `body_inhibit` is true whenever the body network is down — `is_inhibited` takes
  `bus_up` deliberately, so the interlock never claims an unpowered body may swing its arm — which
  would light INHIB through the whole of ordinary driving with the PTO out, beside a BODY BUS lamp
  already saying so. Measured over a scripted refuse round: lit with the bus **dark** 44 % of
  ticks, carrying nothing BODY BUS did not; lit with the bus **up** only 20 %, which is the case it
  exists for. So the dashboard suppresses it while BODY BUS is dark. The signal, the bridge and the
  rule in `RefuseBody` are all untouched.

### The refuse body: a second network across a gateway

The garbage truck carries a **CiA 422 "CleANopen"** body control network — the CANopen application
profile for refuse collecting vehicles, standardized as **EN 16815:2019** — reaching the J1939
chassis across a **CiA 413** truck gateway (413-6 is the J1939↔CANopen interface, 413-8 the generic
I/O that lets a body use the truck's own HMI, which is precisely this project's generated-cluster
question). **ISO 25200** is the umbrella over both this and the tipper trailer and is named only as
a reference: it is protocol-agnostic, so it has no concrete boundary to teach.

Six signals, all `flavor: "cleanopen"`. **In (1):** `body_cmd` (Idle / Lift / Dump / Lower, the
`X` key). **Out (5):** `body_state`, `body_pos`, `body_inhibit`, `body_bus`, `hopper_load`.

- **The gateway is the content, and three things make it more than a story.** `body_inhibit` is
  computed on the **chassis** side (road speed, PTO state, parking brake) and published on the
  **body** network — the one value in the game that visibly crosses a bus boundary. `body_bus` goes
  down when the body network loses power (key off, or the chassis PTO disengaged), because a
  gateway that can be *offline* is what makes a second network a second network. And `hopper_load`
  adds real **mass** to the chassis, so `axle_load` and `engine_load` report the payload from their
  own honest measurements — there is no laden term in either.
- **The interlock is a real refusal, not a readout.** While `body_inhibit` is set the arm is frozen
  where it stands and `body_cmd` is ignored. It freezes rather than driving home: losing the PTO
  mid-lift leaves the arm up, which is what happens. `Idle` and `Lower` both stow, and an unknown
  command byte lands there too, so the bus fallback is the safe pose.
- **`body_pos` is written onto the arm and then read back off it** (the `ball_lift()` discipline),
  so the number and the picture cannot disagree. `RefuseBody` is pure logic with no nodes; the rig
  is found by **name lookup** (`Model/arm`, `Model/body/trash`) because
  `tools/gen_kenney_vehicles.gd` rebuilds the whole `Model` subtree on every run and would silently
  wipe any scene node added under it.
- **The geometry IS the declaration.** No `arm` mesh means no body unit, which is why the
  firetruck, the semi and the conventional publish honest zeros on all five body signals with the
  cluster the same shape. A `VehicleSpec` flag could claim a refuse body on a truck with nothing to
  show it; geometry cannot.
- Ceiling, so it is not rediscovered: the rig is a **front loader** — no separable tailgate, no body
  raise, no compaction blade — so there is no packer cycle, and respawn is the only way to empty the
  hopper (cargo goes; meters like `odo` and `engine_hours` stay).

## The towed body: tractor unit, fifth wheel, semi-trailer

The truck family's last two variants are hand-built tractor units — a European cab-over (`semi`)
and a North American conventional (`semi-conventional`) — each pulling one of four semi-trailers on
a **real joint between two RigidBody3Ds**, the project's first free-roaming towed body. The
cab-over carries the ISO 11992 trailer bus; the conventional carries none at all, which is the
whole reason it ships. **Not one of the four trailers adds a signal to either.**

- **The fifth wheel is a `Generic6DOFJoint3D`**, built in code at the scene's `Kingpin` marker
  (`SemiTractor._build_joint`): three linear axes locked (`lower == upper == 0`), yaw free out to
  the rig's own 75° jackknife stop (the next bullet — the plate itself has none), pitch
  ±15°, roll ±1.5° — near-zero rather than zero, so the solver settles instead of fighting the
  road. The pitch travel has to COVER the steepest grade the rig can climb rather than bound it:
  on its stop the two bodies are rigid, so a level trailer at a break of slope levers the climbing
  tractor's drive axle off the road and the rig loses traction entirely (that is what the shipped
  ±8° did). Crossing a sharp break onto a 25 % grade swings it -9.0° to +12.8°.
  Measured driving it: the kingpin holds to **0.0000 m**, peaking at 11 mm in a jackknife
  at 19 km/h. The named fallback (solve the articulation angle kinematically and pose the trailer
  as a follower) is written and tested in `Articulation` but **not taken** — it is deaf to
  trailer-side forces, so a tanker's surge and a trailer's own tipping would stop being physical.
- **The yaw limit is a labelled model of trailer-against-cab contact**, not something a fifth
  wheel does. It cannot be left to the collision system: the plate and the trailer's nose overlap
  while coupled, so the two bodies must not collide. Without a limit, reversing on full lock folded
  the rig to 130° and swung the trailer through where the cab is. One constant
  (`Articulation.JACKKNIFE_MAX_DEG`, 75°) serves the joint and the fallback.
- **The trailer carries its own unmodified `RayWheel`s** — undriven, braked, six of them on a
  tri-axle bogie. That is what makes `trailer_axle_load`'s summed suspension force and
  `trailer_abs` real slip rather than invented numbers, and no clamp is forked or softened for it.
  It is ticked from `SemiTractor._tick_extras`, so the order is fixed and the brake demand is
  computed on the towing side.
- **`E` cycles the combination and `V` the body**, on separate keys: box → tipper → tanker →
  flatbed → bobtail, through the same duck-typed `cycle_implement()` hook the tractor's implement
  cycle uses, with `TrailerCatalog` shaped like `ImplementCatalog` and `BOBTAIL` a real entry in
  it. A plain wrapping cycle — V still walks the truck family's bodies from the semi, so the
  trailer cycle never has to hand a press back to keep the semi escapable.
- **Coupling is honest about weight.** The trailer's centre of mass sits between its kingpin and
  its bogie, so 27 % of it rests on the plate (a real van trailer's 25-30 %); that lands on the
  tractor's single driven axle — on a 4x2 it IS the traction budget — and
  `axle_load` reports it the moment you couple, because it is summed suspension force and nothing
  was added to the signal.
- **Mass ratio: 8 t : 24 t shipped (3:1, the box), verified at 8 t : 25 t.** Raising a trailer
  past that is a re-tune, not a free number — `test_trailer` pins the suspension travel each case
  uses and fails a trailer that walks past the ratio.

### ISO 11992: five signals, and how few that is *is* the content

Part 2 of the standard is the application layer for **brakes and running gear only**, riding pins 6
and 7 of the **ISO 7638** connector, so the entire boundary is a coupling claim, the demand going
out, the ABS state coming back, an axle load, and one injectable fault. All `flavor: "iso11992"` —
and it is the one signal group in the contract that is **bidirectional by design**.

| Signal | Dir | What it is |
| --- | --- | --- |
| `trailer_ebs_fault` | in | A trailer EBS fault injected from the bus. Mirrored verbatim like the DM1 lamps; nothing in the game ever sets it |
| `trailer_connected` | out | The coupling **claim** — see below, the third state is the content |
| `trailer_axle_load` | out | SPN 582 on the towed unit. **Read out of the sim**: the trailer's own bogie suspension force through the *same* `axle_load_kg` the drive axle uses |
| `trailer_brake_demand` | out | EBS11, towing-to-towed. A **report** of the blend the tractor sent, which is also what the trailer's wheels really brake with |
| `trailer_abs` | out | EBS21, towed-to-towing. **Read out of the sim**: the trailer's worst wheel slip past `TRAILER_ABS_SLIP` |

- **`trailer_connected` is a CLAIM, not "something is on the fifth wheel."** It needs the trailer
  coupled **and** `VehicleSpec.trailer_bus_equipped` — the data pair. False with a trailer
  physically attached is a real state, the same third state `implement_connected` exists to
  distinguish: attached steel and bus silence.
- **There is deliberately no `trailer_type`.** ISO 11992 publishes no body type at all, so
  inventing one would undercut the exact thin-boundary lesson the flavor exists to teach. Which
  trailer is on the back shows through **mass** and through which tractor-side signals it moves.
  The tractor has `implement_type` because ISO 11783 really does carry a device class in the
  address claim.
- **The brake demand blends the foot brake with the retarder, and the share is arithmetic.** A
  driveline brake acts on the tractor's driven axle alone, so without a share going down the bus
  the trailer would be left pushing 8 t of tractor. The retarder at full is
  `Drivetrain.RETARDER_MAX_FRAC` of the tractor's brake torque, so it asks the trailer for that
  same fraction of the trailer's — and it reads `retarder_state` (what ran) not the request, so it
  inherits the speed fade for free.
- **A coupled trailer draws air**, through the chassis' existing reservoir model rather than beside
  it: its reservoirs charge off the tractor's supply, so coupling visibly dips AIR1/AIR2 by ~3 bar.
  That is past the low-pressure warn but not past the spring-brake gate — braking *while* it
  charges is what reaches the gate, and that is the designed catch-out.
- **Both read signals are read AFTER the trailer's wheels integrate**, and the ordering is
  load-bearing: publishing before `tick_towed` would ship last tick's loads and slip. Bobtail
  publishes a real 0 / false on all four **every tick** (`clear_trailer_bus`), never a gap.

### SAE J2497: the North American variant, and the subtraction that is the lesson

`semi-conventional` is a bonneted conventional — hood ahead of the cab, sleeper behind it, 4.70 m
on a 3.00 m wheelbase against the cab-over's 3.40 m and 2.10 m — built as a **variant** of the
cab-over: same `SemiTractor` script, same frame rails, fifth wheel, wheels and coupling plane
(y = 1.05, which every trailer is authored against and which a variant may not move), same
drivetrain and brake numbers. Its content is entirely a **subtraction**.

- **It has no trailer bus, and that is a `VehicleSpec` flag defaulting off** —
  `trailer_bus_equipped`, the `rear_diff_lockable` pattern: true on the cab-over's spec, false on
  this one, off everywhere else. Europe puts a CAN pair on pins 6 and 7 of the ISO 7638 connector;
  North America has **no data pair on the connector at all**.
- **So with a trailer coupled, `trailer_connected` reads FALSE and `trailer_axle_load` /
  `trailer_brake_demand` / `trailer_abs` read honest zeros.** Attached steel and bus silence — the
  same third state the tractor's `implement_connected` teaches, now a shipped state rather than a
  hypothetical one. Drive it with a trailer on the back: TRLR is dark and every trailer bar sits at
  zero.
- **It still tows and still brakes the trailer.** The pneumatic lines are not the data pair, so
  `tick_towed` runs either way and the trailer brakes on exactly the same EBS11 blend. Only the
  *publishing* goes dark.
- **One signal is the entire North American trailer protocol:** `trailer_abs_lamp` (in, bool,
  `flavor: "j2497"`, tell-tale **TRLR ABS**). SAE J2497 / PLC4TRUCKS modulates trailer ABS status
  onto the **power line**, because there is no data pair to put a bus on, and the payload is
  essentially LAMP ON / LAMP OFF to one dash telltale. Mirrored verbatim like the DM1 bits —
  sloppyCAN is the sole authority, an absent bit is off, no local timer. It is meaningful only on
  this unit; the cab-over reads it false, because that unit has a real bus and says all of this
  properly on `trailer_abs`.
- **Thick, thin, and absent, side by side on one family.** The refuse body is a whole second bus
  behind a gateway; ISO 11992 is five messages about brakes; J2497 is one bit on a power line. All
  three are real, and the contrast is the reason the truck family exists.

### Four trailers, and not one new signal

The variety is the point *and* the lesson, and it is the ISO 11992 table above read from the
other side: the bus carries nothing about the body, so what tells these four apart is **mass**,
**what they plug into the towing unit**, and **which tractor-side signals they move**.

| Trailer | Mass | Consumes | What it teaches |
| --- | --- | --- | --- |
| Box / curtainside | 24 000 kg | nothing | on the trailer bus it *is* the flatbed |
| Tipper / dump | 19 000 kg | chassis PTO + proportional valve | a real interlock, and a load that walks |
| Tanker | 21 000 kg | nothing | a labelled model of a shifting centre of mass |
| Flatbed | 14 000 kg | nothing | the lightest, and the baseline for the rest |

- **What a trailer consumes is declared in CODE** (`TowedBody.consumers()`, the `ImplementBase`
  rule) so a scene edit cannot claim a connection the machine does not have — and **the gating
  lives on the coupling side**, in `SemiTractor._drive_trailer_body`, never in the subclass. A
  towed body is never trusted to ignore drive or flow it never plugged in.
- **Every trailer control has a keyboard key and a touch button.** `E` / **ATTACH** cycles the
  combination, `P` / **PTO** engages the chassis PTO that drives the tipping pump, `I` / **TIP** is
  the raise/lower valve (the existing hitch toggle — `H` is the horn), and the parking brake the
  interlock wants is `Space` / **HAND**. PTO and TIP are offered by *capability*, not by family:
  `SemiTractor.attachment_controls()` answers off the same `TowedBody.consumers()` the gating
  reads, and the shell re-asks after every `E` press, so the buttons appear only with a tipper
  coupled. Unlike ATTACH they hide while the bridge drives — `pto` and `hitch_pos` are contract IN
  signals, so sloppyCAN owns them. `TractorVehicle.attachment_controls()` answers the same hook off
  its implement's `ImplementBase.connections()`, so one duck-type serves both towing machines; its
  `lift` is unconditional because the three-point linkage is tractor anatomy and raises with
  nothing on it.
- **Coupling never refuses; the fit check is REACTIVE.** Nothing decides in advance whether nine
  metres of trailer will fit. The trailer is coupled, and for `COUPLE_WATCH_TICKS` afterwards
  `SemiTractor._watch_fresh_coupling` asks whether its **body** is touching anything — if it is, the
  trailer is taken away again with a `GameState.notice` ("NO ROOM FOR A TRAILER - PULL FORWARD").
  The signal is exact rather than a threshold: a semi-trailer stands on RayWheels, which are
  *raycasts*, so its collision body touches nothing at all in normal towing, and the tractor is
  excluded by the fifth-wheel joint. One body contact means it was laid inside the world.
  - This replaced a predictive shape query (`collide_shape` against the candidate's own shapes,
    with a penetration-depth threshold) that could not be made to work in either direction: the
    query returns the contacts it finds *first* rather than the deepest, so it waved buried
    trailers through, and any threshold generous enough not to refuse a grazed kerb was generous
    enough to miss a hillside. Coupling and then *looking* is both simpler and better informed —
    the engine has already answered the question exactly.
- **`E` always does exactly one thing.** Every press couples the next entry; there is no refusal to
  swallow the press, and a trailer that turns out not to fit visibly appears and is taken away.
- **The spawn coupling is a plain countdown** (`SPAWN_COUPLE_TICKS`, 12), buying only the moment the
  chassis has risen on its own suspension — on tick one the body is still where the marker put it,
  so the coupled pose reads 0.16 m into the terrain on every heightmap level. It used to be a
  *condition* (every wheel grounded for 15 consecutive ticks) and that was a bug: a condition can
  fail to come true, so a rig driven off its marker immediately waited for a quiet moment that
  never arrived and ran bobtail forever. A counter always finishes. **And the garage freezes
  the trailer with the tractor** (`set_display_frozen`, duck-typed): the showroom pins its vehicle
  and hovers it off the floor, and a separate unfrozen 24 t body hanging off the fifth wheel in
  mid-air swings on the joint until it settles.
- **The tipper's interlock is chassis state, evaluated by the tractor.**
  `TowedBody.body_raise_allowed(speed, parking_brake)` wants the parking brake set and a genuine
  standstill — stricter than the refuse arm's walking pace, because a raised body is four metres
  of leverage. It refuses the **raise direction only**, clamped against where the body already is,
  so rolling away with the body up holds it rather than commanding it down. No PTO **freezes** the
  body where it stands; a lost drive is not a retraction. Naming reference declared and *not*
  implemented: ISO 25200 / CiA 408. Measured driving it: rolling with the raise commanded leaves
  the body at 0 %, and parked with the brake set it reaches 100 %.
- **Both load models move a real centre of mass and nothing else.** `set_load_offset_z` slides the
  body's `center_of_mass`, so the bogie's springs really carry more and the plate really carries
  less — `trailer_axle_load` and `axle_load` then move as *consequences*, the draft-force
  discipline. Measured on the tipper: `axle_load` 7671 → 4969 kg and `trailer_axle_load`
  15 063 → 18 103 kg over one tip. **The tanker's surge is a labelled model, not fluid dynamics**
  — one number chasing the trailer's own longitudinal acceleration with a lag; real wave physics
  is a non-goal, the same rule that governs the boat's water.
- **Measured behind all four at 60 Hz** (level 4, full throttle then a full brake application):
  the kingpin holds to **0.0000–0.0003 m**, trailer bogies sit at 37–39 % of travel and the semi's
  rear at 34–53 %, and `trailer_axle_load` reads 11 461 → 19 766 kg across the catalog. No clamp
  was weakened and the tick is unchanged. (Those axle loads predate the 27 % plate-share
  correction and now read lower; the bogie fractions were re-derived and still land at 36 %.)

## Tractor, implement & ISOBUS

- **Twenty ISOBUS signals, all `flavor: "isobus"`** — the widest cluster in the game.
  **In (7):** `hitch_pos`, `pto`, `pto_mode` (540/1000), `diff_lock`, `fwd_drive`,
  `guidance_curvature`, `scv_flow`. **Out (13):** `hitch_pos_actual`, `pto_state`, `pto_rpm`,
  `engine_load`, `implement_connected`, `implement_type`, `diff_lock_state`,
  `fwd_drive_state`, `wheel_speed`, `ground_speed`, `wheel_slip`, `engine_hours`,
  `draft_force`. Every one of them is either read out of the tractor sim or applied to it —
  the two modeled values (`engine_load`, the draft force behind `draft_force`) are labelled
  honest models below.
- **One body, four swappable implements.** The drivable tractor is a single variant
  (`kenney/tractor-kenney.tscn`); the interesting axis is what is on the linkage, so **V
  cycles the implement** — spreader → plough → power harrow → mower → detached, wrapping.
  Each machine teaches a different one of the **five real tractor↔implement connections**
  (three-point linkage, drawbar, PTO, SCV hydraulic remote, ISOBUS data): the plough is
  linkage-only, the harrow adds the PTO on a horizontal rotor, the mower moves the rotor to
  the vertical axis, the spreader adds the SCV. The drawbar is declared and unused — it is
  the towed trailer's connection (see `TODO.md`).
- **Absent functions publish a real zero, never a gap**, so the cluster is the same shape
  whatever is on the hitch: with the plough on, `pto_rpm` at the implement is 0 and
  `draft_force` climbs; with the mower on, `draft_force` is 0 and the rotor turns. Detached
  reads `implement_connected` false / `implement_type` 0.
- **`TractorVehicle extends BaseVehicle`** (`src/vehicles/tractor/tractor.gd`) — a real
  subclass because it owns per-tick hitch/PTO/implement state; all of it runs in
  `_tick_extras`. Only the three behaviour knobs (`hitch_travel_time`, `pto_load`,
  `hitch_path`) are `@export` — node behaviour, not a spec (drive tuning stays in the body's
  plain `tractor-kenney_spec.tres`). Spawn default: raised, PTO off, implement attached
  (respawn re-raises but keeps the implement — respawn moves the tractor, it does not
  rebuild it).
- **`TractorTelemetry extends VehicleTelemetry`** adds the ISOBUS "out" fields (named
  exactly the contract names). `engine_load` is a **modeled honest value**
  (`engine_load_pct` — throttle demand + a PTO parasitic term, pure/unit-tested, same
  latitude as fuel/coolant); the rest are read straight out of the sim. Detached is a real
  reading (`false` / device class 0) published every tick, not a gap.
- **The driveline signals change how the tractor drives**, they are not indicator bits.
  `diff_lock` locks the rear pair onto one shaft speed (`BaseVehicle._lock_rear_diff` pulls
  them onto `Drivetrain.locked_axle_omega` after they integrate, so the wheel with grip makes
  the bigger force — the open path is untouched); `fwd_drive` is MFWD, rewriting the front
  wheels' `driven` flag each tick. Both are gated on `VehicleSpec` flags
  (`rear_diff_lockable`, `front_axle_engageable`) true **only** on the tractor's spec, so the
  fields are inert on every other vehicle. The two `*_state` outs are read back out of the
  driveline — what it actually ran this tick, not an echo of the request.
- **`wheel_speed` / `ground_speed` / `wheel_slip` are the signature ISO pair and its
  difference.** Wheel-based speed is the mean spin of the **rear** axle × the physics tire
  radius (deliberately not "every driven wheel" — that set changes when MFWD engages, and
  the rear axle is the one that digs in); ground-based is the chassis' own forward velocity,
  the "radar" reading. `wheel_slip` is just how far the first runs ahead of the second,
  unsigned like J1939 SPN 1858 and floored below 0.5 km/h where the ratio is meaningless
  noise. Nothing here is derived twice — `_tick_extras` runs last, so both are this tick's.
- **`pto_mode` is a gearbox selection, not an engine speed.** 540 and 1000 are SHAFT speeds:
  the shaft follows the engine through the selected mode's ratio off `PTO_RATED_RPM` (2200),
  so revving out in 1000 lands at 1182 rev/min — inside the contract's 0–1200 without the
  clamp biting (`test_tractor` pins that against the shipped spec). An unknown byte falls
  back to 540.
- **`engine_hours` is an hour meter**: real time under the key, climbing only, surviving
  respawn like the odometer. It carries no `range` in the contract on purpose — a running
  total has no full scale — so the dashboard puts it on the readout line beside ODO instead
  of generating a bar for it.
- **`guidance_curvature` is auto-steer, and it follows the boat's `rudder` precedent
  exactly**: when the key is present in the bridge values it **overrides `steer`**, and that
  arbitration lives only in `InputRouter.arbitrate_bridge`. `bridge_source.gd` maps the
  contract's ±127 1/km onto the ±1 steer channel (full lock = the tractor's tightest circle),
  and includes the key **only when sloppyCAN actually sent it** — dead straight (0) is a real
  command a guidance system holds, not an absence. Nothing downstream knows it was steered
  from orbit.
- **`scv_flow` is a hydraulic remote with a real consumer.** It rides `VehicleInput` (no local
  key — a spool valve has no keyboard analogue) and reaches the spreader's hopper gate ram
  through `set_scv`. The pump is engine-driven, so a stopped engine means no flow however far
  the spool is opened — the same `running` gate the PTO gets.
- **Draft is a real force, and the coupling is the point.** With a draft-relevant implement
  (plough, power harrow) down in the ploughable field, `TractorVehicle._apply_draft` puts a
  rearward force **at the hitch point** on the chassis: rated draft × working depth × soil ×
  a speed ramp (`TractorTelemetry.draft_newtons`, pure/unit-tested). `engine_load`, the rpm
  sag and `wheel_slip` then move because the body was really pulled back — there is **no draft
  term anywhere else**, and adding one would double-count a force the sim already felt.
  Lift comes out of the linkage's own solve (`ThreePointHitch.ball_lift`) and the working depth
  it is measured against is the **implement's own** (`ImplementBase.tool_depth` — the plough's
  shares reach 0.055 m down, the harrow's tines 0.02 m), so each machine is in the soil exactly
  while it looks like it is. "In soil" is splat channel 4 under the hitch
  point via `HeightmapTerrain.channel_weight_at` (cached splat Images, the same lookup and the
  same nearest-surface rule `RayWheel.terrain_at` applies to tire grip). Detached, a
  mower/spreader, a lifted implement or ground that is not field each publish a clean 0.
  The speed ramp doubles as the 60 Hz margin: below `DRAFT_SPEED_REF` the force is a linear
  damper with two orders of stability margin, and the one-tick cap behind it is a backstop for a
  future rating edit rather than what holds the tick together.
- **`ThreePointHitch`** (`src/vehicles/tractor/three_point_hitch.{gd,tscn}`) is tractor
  ANATOMY, so it lives on the tractor and stays whole with nothing attached: two lower draft
  links, the rockshaft arms, the rigid lift rods between them, the top link, and the PTO stub
  shaft under its guard. **No CollisionShape, no joint** anywhere in the subtree.
- **The linkage is solved, not animated.** `HitchLinkage` (pure math, unit-tested) treats the
  side view as a four-bar: the only free variable is how far the rockshaft has swung the
  lower links, and the implement's PITCH plus the rockshaft arm angle fall out of a
  circle-circle intersection against the rigid top link and lift rods. That is why implements
  visibly tip back as they lift. `test_three_point_hitch` then checks the AUTHORED SCENE
  against that solve, joint by joint, across the whole travel — different failure from the
  maths being wrong.
- **`ImplementBase`** (`implement_base.gd`) is what an implement declares about itself, in
  code rather than exported data: which of the five real connections it uses (three-point,
  drawbar, PTO, SCV, ISOBUS data — the last two non-visual), its ISO 11783-1 device class,
  and its A-frame (`mast_offset`, which feeds the four-bar solve). It consumes the three seams
  `set_hitch` / `set_pto` / `set_scv`, and declares whether it works IN the soil (`draft_relevant()` —
  true for the plough and the power harrow) and how far its tools reach when lowered
  (`tool_depth()`, measured off its own scene). Implements are **visual only**: the draft force is
  applied at the hitch point on the chassis, never by scraping colliders on the implement.
- **The declared connections are load-bearing.** `ISOBUS_DATA` decides whether
  `implement_connected` / `implement_type` report anything at all, and `PTO` / `SCV` decide
  whether the stub shaft's drive and the remote's flow reach the implement (the hitch gates
  both; a subclass is never trusted to ignore drive or flow it never plugged in). So a
  mechanical-only implement is *attached
  but claims no address* — steel on the linkage, silence on the bus, which is exactly a dumb
  plough on a real ISOBUS tractor and the third state the two signals exist to distinguish.
- **Attach/detach is a logical address claim.** `ImplementCatalog` holds the cycle order with
  DETACHED as a real entry; attaching instances the scene under the linkage's `Mount` and
  that is the whole connection — no cable is modelled. `E` cycles it: the shell duck-types
  `cycle_implement()` on the active vehicle, so neither `boot.gd` nor `VehicleCatalog` knows
  implements exist (the tractor keeps its single catalog entry).
- **The four implements** (`src/vehicles/tractor/implements/`), each declaring a different
  connection set and a device class no other machine may share (asserted in
  `test_implement_catalog`):

  | Implement | Connections | `implement_type` | Draft | Moving part |
  |---|---|---|---|---|
  | Plough | three-point, bus | 2 tillage | 0.055 m | gauge wheel arm swings on lift |
  | Power harrow | + PTO | 3 secondary tillage | 0.02 m | tine rotor, **transverse** axis |
  | Rotary mower | + PTO | 9 forage | none | rotor, vertical axis |
  | Fertilizer spreader | + PTO, **SCV** | 5 fertilizer | none | disc + `scv_flow` hopper gate |

  Two authoring conventions they all follow: they are **authored in the LOWERED pose with the
  origin on the lower pin line** (ground is y = −0.21 in that frame — the balls sit 0.21 m up
  fully lowered, 0.78 m raised), and geometry lives in the `.tscn` while *declarations* live in
  code (a scene edit must not be able to claim a connection the machine does not have). The
  shared A-frame is `implements/headstock.tscn` — a new implement instances it instead of
  redrawing pins. PTO-driven visuals go through `ImplementBase.spin_from_pto`, whose `ratio` is
  **cosmetic and well under 1**: 540 rev/min is nine turns a second, which at 60 fps aliases
  into a slow backwards crawl — the published `pto_rpm` stays the honest number, only the
  rendering is geared down.
- **Where the signals perform:** level 1's centre is the ISOBUS farm playground — painted
  field (soil for `draft_force`), mud wallow (`diff_lock`), haul ramp (`fwd_drive`) and the
  implement yard you drive to in order to swap. See `docs/level_kit.md`.
- **Uniform wheel radius:** RayWheel is single-radius, so the tractor's big-rear/
  small-front wheels are **visual only** (two cylinder meshes in the scene; physics uses
  one `wheel_radius`).

## Boat & water

- **`WaterSurface`** (`src/water/water_surface.gd`, `@tool Area3D`, group `"water"`) is
  one node = three things: the **height API** (`get_height(pos)` returns the node's global
  Y — **flat**; the vertex waves in `src/water/water.gdshader` are visual-only and must
  never feed physics), the visual plane, and the **non-boat kill/respawn volume**: its box
  top sits `kill_margin` below the surface so a shoreline splash isn't death;
  `body_entered` → `call_deferred("respawn")` on any non-boat `BaseVehicle` (deferred —
  physics flush). The region is an **axis-aligned rect** around the node origin
  (`contains_xz`) — don't rotate it. Water is a direct child of the level (like terrain),
  **never under `Authoring`** (not bakeable kit content).
- **Depth-fade shading** (`water.gdshader`, fragment-only — physics untouched): the shader
  samples `hint_depth_texture`, reconstructs the opaque scene's view distance behind each
  water fragment, and fades `shallow_alpha`→`deep_alpha` / `water_color`→`deep_color` over
  `depth_fade_m` of water column. Shallow water stays translucent (free shore gradient),
  deep water goes opaque so the seafloor and the square map edge behind it disappear. NDC
  z is reconstructed for **gl_compatibility** (`depth * 2.0 - 1.0`; Forward+ leaves depth
  as-is) — the whole project runs Compatibility.
- **`SkylineRing`** (`src/levels/base/skyline_ring.gd`, `@tool Node3D`) is the mainland
  silhouette on the horizon: a closed low-poly ridge ring around the island, so the eye
  reads distant land instead of the void past the coast (and the far-sea quad's square edge
  is occluded from any low camera). Visual only — one mesh, one draw call, no collision, no
  LOD, no custom shader; the level's `WorldEnvironment` fog does the blending, exactly as
  the far-sea quad relies on it. Like `WaterSurface` it is a **direct child of the level,
  never under `Authoring`**, built as an internal child from five exports (`radius`,
  `height`, `band_depth`, `gen_seed`, `color`) so the scene stores numbers, not geometry.
  It is **outside the bake** (editing a level `.tscn` still re-stales that level's manifest —
  the bake hash seeds on the scene file itself — but the baked output is unaffected).
  `radius` is chosen from the **fog, not from `far_sea_extent`**: surviving colour is
  `exp(-fog_density · distance)`, so at the shared env's `0.003` a ridge reads at ~600 m
  (~17 % survives) and is invisible by ~900 m (~7 %, and the sky at the horizon already *is*
  `fog_light_color`). Keep it past everything reachable (islands stop at ~256 m, the water's
  perimeter walls at 280 m) and inside the camera's `far`. The material is **lit, not
  emissive**, so the N-key night toggle dims it with the rest of the scene; shadow casting
  and GI are off (a 600 m mesh must never enter the 150 m shadow cascades). Mesh math is
  pure and tested in `src/levels/base/skyline_gen.gd` (`tests/test_skyline_gen.gd`): crest
  noise is sampled **2-D on the circle**, which closes the ring seamlessly at θ = 0 where a
  1-D angle would tear.
- **`BoatVehicle extends BaseVehicle`** (`src/vehicles/boat/`) follows the tractor
  template exactly: only the two seams (`_make_telemetry()` → `BoatTelemetry`,
  `_tick_extras` = buoyancy/drag/thrust/rudder), `respawn()` = `super()` + trim reset.
  `boat_spec.tres` is a plain VehicleSpec with **empty `wheel_positions`** (the drivetrain
  still ticks harmlessly — keep its 6 `gear_ratios`; `auto_shift` indexes up to byte 6).
  Boat node knobs (probes, float_depth, thrust, rudder, drag, prop/keel offsets) are
  `@export` on BoatVehicle, like the tractor's hitch knobs.
- **Buoyancy = 4 probes with the RayWheel clamp discipline**: per-probe spring k is
  **derived** (`m*g / (probes * float_depth)` — floats by construction), damper clamped to
  the one-tick reversal impulse, total clamped `[0, max_probe_force_factor × weight
  share]`; hull drag/yaw damping use `damped_force` (may at most zero the velocity it
  opposes in one tick). All pure statics on BoatVehicle, unit-tested in
  `tests/test_boat.gd`. Feel comes from the levers: thrust at `prop_offset` below COM =
  bow-up under throttle; lateral drag at `keel_offset` below COM = heel in turns.
- **`BoatTelemetry extends VehicleTelemetry`** adds `pitch`/`roll` (straight from the
  basis: `pitch_deg`/`roll_deg`, + = bow up / starboard down), `rudder_actual` (the slewed
  `_steer` as %), and `trim` (**modeled honest value** like engine_load: `trim_step`
  chases forward throttle). The boat's PITCH/ROLL bars are pure contract metadata (`warn`
  30/45); `rudder_actual`/`trim` are bridge-only (no honest warn).
- Every island level's sea is a `WaterSurface` — the boat/drown-respawn rig (drive the
  car in → drown respawn); the boat is in every island roster.

## Plane & drone (flight)

- Protocols are **flavors** like the tractor's ISOBUS: plane = `canaerospace`
  (`elevator`/`flaps` in, `altitude`/`vspeed`/`flaps_actual` out), drone = `dronecan`
  (`climb`/`arm` in, `altitude`/`vspeed`/`rotor_rpm`/`armed` out). Both share the boat's
  `pitch`/`roll` outs. Bodies are primitive low-poly builds (no external assets).
- **`DroneVehicle`** (`src/vehicles/drone/`) — zero wheels (boat template: empty
  `wheel_positions`, 6 `gear_ratios` kept). `_tick_extras`: vertical thrust (gravity
  feedforward + climb axis), self-leveling attitude torque (accel/brake = tilt, steer =
  yaw), linear/angular drag. Rotors spin only when armed **and** key = Ignition;
  `rotor_rpm` is a modeled honest value derived from thrust demand. Battery-electric:
  declares no rpm/gear/fuel/coolant/ground.
- **`PlaneVehicle`** (`src/vehicles/plane/`) — three RayWheels (steered nose wheel, two
  mains) so ground roll/takeoff/wheel braking come from the base. `_tick_extras`: prop
  thrust from drivetrain rpm × throttle (the published `rpm` IS the number the thrust is
  computed from — modeled, since undriven wheels would idle the wheel-derived rpm), lift
  with a simplified stall fade, drag, control torques whose authority scales with
  airspeed. Steer = coordinated roll+yaw; elevator = pitch; flaps slew toward the request.
- All force terms follow the boat's **one-tick clamp discipline** as pure statics,
  unit-tested in `tests/test_plane.gd` / `tests/test_drone.gd`. The 60 Hz tick and the
  existing clamps are untouched.

## Train & rail

- Protocol is a **flavor** like the tractor's ISOBUS: `"train"` (in `pantograph`/`doors`;
  out `pantograph_state`/`doors_state`/`catenary_volts`/`motor_current`/`brake_pipe`/`grade`/
  `coupler_force`, plus the generic speed/gear/nav set). No real rail CAN standard is
  adopted — trains run IEC 61375, not CAN; the descs credit CiA 421 / rail practice as
  inspiration only. No `steer` (rail-guided); no `rpm`/`fuel`/`coolant` (electric). The
  reverser (N/D/R) rides the existing `gear` byte, so gear-owns-direction arbitration is
  already correct for it.
- **`TrainVehicle extends BaseVehicle`** (`src/vehicles/train/`) is a real subclass like the
  boat: empty `wheel_positions`, the 6 `gear_ratios` kept, only the two seams — it never
  forks `_physics_process`. The consist is the Kenney bullet loco + wagons at world scale
  2.4 (measured, not guessed). It self-places on a closed rail loop in `_ready` and ignores
  `VehicleSpawn` markers.
- **Locomotion = a 1D consist sim** (`TrainSim`, pure, unit-tested in `tests/test_train.gd`):
  each car is a mass at an arc position on the rail `Curve3D`; per-car grade/Davis
  resistance/brake, traction on the loco only (constant force to base speed, constant power
  above), spring-damper couplers with slack. The couplers/brakes carry the **one-tick 60 Hz
  clamp discipline** (damper ≤ one-tick reversal, total coupler force hard-capped) — the
  RayWheel rule, applied here; **don't weaken it**. `TrainPlacement.car_pose` (pure) poses
  each car from two bogie samples `s ± bogie_half_spacing`; its basis is **right-handed
  (det +1)**, guarded by a test (a left-handed basis renders meshes inside-out and, via the
  hood-camera basis copy, flips the chase views).
- The loco is driven **kinematically**: `gravity_scale = 0`, the sim writes
  `global_transform` + linear/angular velocity each tick, so `BaseVehicle._update_telemetry`
  still reads honest motion (speed, yaw, accel, impact). A collision perturbs the body for
  one tick, then the sim reasserts the pose — the train plows small props, correct for its
  mass. Wagons are `AnimatableBody3D` followers posed by the same helper.
- Aux systems are **honest labelled models** in `TrainTelemetry` (not real circuits):
  `brake_pipe` charges toward 5 bar and vents on application; `catenary_volts` = 25 kV
  nominal minus sag ∝ current; `motor_current` from traction; `grade` (i8 %) from the
  tangent; `coupler_force` (kN) straight off the sim's head coupler. Traction is live only
  with the key in Ignition **and** the pantograph raised; doors open only at standstill.
- **Rail runtime** (`RailTrack`, `src/levels/base/rail_track.gd`): rails are authored as a
  `RoadPath` carrying `RailProfile` under `AuthoringRoot`, which a baked level frees at load
  and export strips — but the train needs the `Curve3D` at runtime. So the baker emits a
  runtime-safe `RailTrack` (duplicated curve, gauge, closed flag, world transform) per rail
  road into the baked scene; in unbaked dev play the `RoadPath` itself answers the same
  duck-typed API (`get_rail_curve()`/`is_rail_closed()`/`rail_to_world()`). Exactly one of
  the two is ever present. `RailTrack.find_closed_rail(root)` is the ONE shared walk that
  finds a **closed** loop — both `Level` (spawn gate + garage roster gate) and `TrainVehicle`
  (self-placement) call it, so they can never disagree on what the train may run on; an open
  rail is never accepted.
- Dashboard: the train is the only family declaring `gear` out without `rpm`, so the gear
  label the tacho gap would carry has nowhere to go — it gets a bespoke `REVERSER N/D/R`
  centre readout (hand-picked like the two gauges, built only for that case). LINE/AMPS/PIPE
  bars and the request/state lamp pairs (`PAN REQ`/`PANTO`, `DOOR REQ`/`DOORS`) are the
  ordinary contract-metadata generation.

## Level framework

- `src/levels/base/`: **`Level`** (base script — reads a `LevelInfo`, spawns the default
  vehicle at the first matching `VehicleSpawn`, wires the `ChaseCamera`, handles respawn;
  variant → scene comes from `VehicleCatalog`). The **train** family branches out of the
  marker path: `_spawn_vehicle` gates on `has_closed_rail()` (the train ignores
  `VehicleSpawn` and self-places on the loop), and the shell drops "train" from the garage
  roster on a level with no closed loop — so a level scene can list "train" in its allow-list
  and still play as an ordinary island when its loop is absent. **`LevelInfo`** (Resource:
  display name, allowed/default vehicles), **`VehicleSpawn`** (`Marker3D` with a
  vehicle-type filter + `is_water` for boat/drown-respawn spots), **`HeightmapTerrain`**
  (see `docs/level_kit.md` — the runtime side is a greyscale image → chunked welded grid
  mesh + one matching `HeightMapShape3D`, one cell = one world unit so mesh and collision
  coincide; also the per-surface grip source: per-channel `channel_grip` (clamped to
  [0, 1]) blended by `grip_at(world_pos)` over the bilinear splat weights — the decoded
  splat + height Images are cached once, never `get_image()`/decompressed per tick.
  `grip_at` sharpens the weights with the material's `blend_sharpness` exactly as the splat
  shader does, so friction follows the border you can see instead of fading well past it;
  `get_splat_weights` still returns the raw weights).
- `level.tscn` is the authoring template (env + sun + camera + one spawn); duplicate it to
  start a level.
- `src/levels/island/level_1/` .. `level_5/` are the five playable islands: generated
  terraced terrain + auto-splat + sea, roster car/truck/tractor/boat. `level_1` is
  dressed (roads, props, scatter, and the ISOBUS farm playground in its free centre) and is
  the CI baked-level smoke target; 2-4 are blank
  canvases with an empty `AuthoringRoot`, one per independent experiment. `level_5` is the
  **railway** — a 598 m closed rail loop with grades, owned end to end by
  `tools/gen_rail_level.gd` (re-running overwrites it); its roster adds "train", chosen from
  the garage (default spawn stays car).
- `src/levels/dev/flat.tscn` is a bare test plane for isolated wheel checks.
- Loading a stranger's level is arbitrary code execution (a `.tscn` can embed scripts) —
  third-party level sharing stays out of scope until there is a validation/sandboxing
  story.

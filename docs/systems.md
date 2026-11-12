# Runtime systems

The plumbing every vehicle rides: signal contract, input pipeline, telemetry/dashboard,
bridge, lamps, shell, level framework. Per-family vehicle detail is in `docs/vehicles.md`
(its header lists the rest). Editor/authoring tooling is in `docs/level_kit.md`; rules are in
the nested `CLAUDE.md` files.

## Signal contract

`contract/carlito_contract.json` defines every bridge signal: name, dir, type, unit, range,
`warn`/`warn_side`, `count`, enum, `bits` (index -> name; required on, and only on, a `"bitfield"`),
vehicles, `flavor` (protocol family). `Contract` (`src/bridge/contract.gd`) validates it into
`Contract.data`; `tests/test_contract.gd` fails if a required signal is missing. Unique by (name, dir) —
`battery` exists both ways (in = warning LED, out = voltage). `warn` needs `warn_side`
(`"low"` | `"high"`); `todo` marks a signal unimplemented both sides; no `range` on an "out"
signal makes a readout line, not a bar. `count` (>= 1, default 1) makes an Array of N,
`range`/`warn` per element, zero-based; rejected on `"in"`, `bool`, or with an `enum` —
`Bridge._publish` drops a wrong-shaped value with one warning.

A version mismatch with sloppyCAN warns at runtime and raises a transient notice, once per session
(`push_warning` is invisible in a web release); so does a same-version content-hash mismatch
(`Bridge.contract_mismatch`). sloppyCAN reads a generated copy, `../sloppycan/js/carlito_contract.js`
(`window.CARLITO_CONTRACT`). Edit ritual: `contract/CLAUDE.md`.

## Input pipeline

`InputRouter` merges every source into one `VehicleInput` per tick. All arbitration is
static/pure, tested in `tests/test_input_arbitration.gd`.

- `merge_local`: keyboard + touch, then + gamepad (`MERGE_MAX` / `MERGE_SUM` axes, the rest
  OR'd).
- `KeyShaper` (`key_shaper.gd`): an on/off key becomes a hand and a foot. The keyboard's steer
  ramps out ever more slowly with road speed while it turns road wheels (1 / v^2 above 10 m/s;
  `BaseVehicle.key_steer_speed`, 0 for a flying plane, drone and boat) and returns faster; pedals
  ramp in over `key_shaper.gd`'s `ACCEL_APPLY_S` / `BRAKE_APPLY_S`, off in `PEDAL_RELEASE_S`. Order: keyboard steer shaped, touch merged, pedals
  shaped, gamepad merged. Local keys only: the touch stick, the gamepad and the bridge are analog.
  Those timings are the full model (SETTINGS ▸ KEY RESPONSE: REALISTIC); the player's softening
  scales every one of them, from RAW (0, the key as pressed) up, and defaults to ARCADE (0.15).
- `arbitrate_local`: ignition gates throttle; brake never throttles; S = brake, then reverse
  at standstill (manual, no bridge live: `_local_gear` exact, `shift_step`, N on reset; S brakes); foot brake drives `brake_lamp`; `tcs_off` is SANDBOX ▸ TRACTION CONTROL (a live
  bridge's own wins, fallback included), `esc_off` STABILITY CONTROL (local only; sets `tcs_off`).
- `auto_hold` (SANDBOX ▸ AUTO HOLD, off by default): on the local path, a wheel-driving body stopped in D or R with no throttle holds
  its foot brake until the throttle asks to move (`docs/drivetrain.md` § Hill hold); a feathered
  trigger is throttle too. It never applies to the bridge.
- LAB switches (pause ▸ SANDBOX, under VEHICLE's driver aids): session-only and unsaved, local only (no contract signal), stock
  under the challenge lock, dev keys included, and on a body without the hardware, so a switch kept
  through a body change never reaches the next (`InputRouter.lab_raw`). A live bridge (fallback
  included) ignores them too, so the page greys them "set by sloppyCAN", read when it opens.
  ANTI-LOCK BRAKES
  (`abs_off`; drops hill-start assist and the auto hold), DIFFERENTIALS (`axle_diff` STOCK / OPEN /
  LOCKED on every driven axle, the centre untouched; no row on a body with its own DIFF LOCK key),
  STEERING (`parallel_steer`, Ackermann fraction 0). ABS off and LOCKED each set `esc_off`, so
  `tcs_off` (`lab_cascade`: a locked axle passes ESC's one-wheel brake to its partner). Each is a pure
  read at its `WheelDrive` use site (`anti_lock_on`, `hill_hold_kind`, `axle_diff_mode`,
  `ackermann_fraction`), with no spec write; greyed per `BaseVehicle.vehicle_capabilities`. An ABS
  cluster lamp lights while it is off; F3's `slip` and `steer` lines read each wheel.
- `arbitrate_bridge`: the gear byte owns direction. Mode = `InputRouter.set_manual_gearbox`
  (vehicle selector on a `FamilyGearbox` family, or `ChallengeDef.transmission`; `Boot._apply_gearbox`).
  - Automatic (default): PRND lever. R reverses, D1-D24 = D with auto-shift, 0 = no gear
    opinion (RAMN `0x077` never sends gear): D while the accelerator is pressed, else N, or P for
    a body already parked.
  - Manual: byte taken exactly, 0 = N, no auto-shift. Fallback's local input drives automatic.
  - Absent bridge keys fall to rest state (lamps off, hitch raised, PTO off, 540, open diff,
    2WD, SCV shut, flaps up, disarmed, doors shut, LEDs black, body Idle).
  - `rudder` (boat) and `guidance_curvature` (tractor) override `steer` when the key is
    present. `bridge_source.gd` writes the key only when sloppyCAN sent it: 0 is a command.
- "Ignition off" notice clears when the key reaches Ignition (`GameState.notice_cleared`).

Three paths, chosen per tick:

| Path | When | Input |
|---|---|---|
| Bridge drives | fresh (within `Bridge.FRESHNESS_MS`) and `accel`/`brake`/`steer` present (`BridgeSource.drive_sourced`) | `arbitrate_bridge` |
| Fallback | fresh, no driving control (CHAdeMO, CANopen, DroneCAN with Drone Control closed, NMEA 2000) | `blend_local_driving`: pedals, steer, handbrake, key, gear, STOP lamp, lights, horn, arm/climb, elevator from local; the rest from the bridge |
| Local | no fresh bridge | `arbitrate_local` |

- J1939 / ISO 11783 traffic drives (EEC2/EBC1/VDC2/TC1/CCVS decode to pedals/steer/gear).
- Fallback raises `NO DRIVING CONTROLS FROM SLOPPYCAN - LOCAL CONTROLS DRIVE`; only the driving
  group's toggles (lights, arm, parking brake) advance there. Never under `set_bridge_only`.
- `InputRouter.bridge_drives()` is the "who drives" predicate (touch driving layer,
  action-registry context); `Bridge.is_active()` only says a peer is connected.
  `bridge_source.gd` normalizes contract-in fields (%->unit); `local_source.gd` reads the
  keyboard (edges from either device), `pad_source.gd` the gamepad's axes; touch registers via `InputRouter.set_touch_source()`.
- Toggle state is owned by the router, never a source (the `var _*` block at top of
  `input_router.gd` is the list); sources report per-frame edges only, ORed by `merge_local`.
  The parking brake too (Shift, R1, touch HAND): `handbrake` is the stronger of its latch and
  the held control, and the latch is airframe state (`reset_vehicle_cycles` releases it).
  Train pantograph defaults raised so a locally-driven train spawns able to move.
- `VehicleInput` (`src/input/vehicle_input.gd`) fields are flat except `lamps` (the fourteen
  verbatim-mirrored lamp/warning bits). The raw-intent wire is `Dictionary[StringName,
  Variant]`. Rules for both: `src/input/CLAUDE.md`.
- Keys and pad axes bind in `project.godot`'s InputMap (`tests/test_input_map.gd`: no shared key);
  pad buttons bind only in the registry (InputMap cannot gate Cross on L1 being up): `PadLayer`
  (`src/input/pad_layer.gd`, in `boot.tscn`) resolves each pad's L1 + slot to one row (`pad_press`:
  the L1 row, else the button's own; paused, SHELL only), injected per `device` until it lifts.
  Left stick Y is `pad_source.gd`'s (`elevator` / `climb`, opposite signs); the right stick and
  D-pad zoom are `level.gd` `_pad_view`, view-only.

### The action registry

`src/input/action_registry.gd`: one row per control (a control on two keys is one row), each with
a label, a group, a gate and how touch offers it; `keys_for()` reads the live binding.

Consumers: the CONTROLS sheet (`pause_menu.gd`), the touch stack (`touch_controls.gd`), `PadLayer`
and the L1 legend (`pad_legend.gd`). `tests/test_action_registry.gd`: every bound (non-`ui_*`)
action in exactly one row, and no context answering one `pad` slot twice.

`applies(id, ctx)` is the shared gate predicate; `gate_note()` gives the reason.

| Gate | Meaning |
|---|---|
| **families**/**excludes** | vehicle-family lists (`flaps` is plane, `steer` is everything except the rail-guided train) |
| **capability** | a bool the shell reads off the vehicle (`boot.gd:_capabilities()`), for a family that disagrees with itself (within `truck` the semi tows, the garbage truck does not); duck-typed and ORed: `cycle_implement`, `vehicle_capabilities()`, `attachment_controls()` |
| **bridge_owned** | rides `VehicleInput`, inert while sloppyCAN drives. Not set on ATTACH/VIEW/GARAGE/LEVEL/MENU. Pedals/joystick stay visible though inert, since hiding them would make the pedal blink as sloppyCAN stutters. A row also flagged **driving** (handbrake, lights, horn, arm, climb) is inert only while the bridge *drives* (`context`'s `bridge_drives`): in fallback it is the keyboard's; other bridge-owned rows read "set by sloppyCAN" |

Family gates are validated against the contract, not copied: a row riding contract IN
signals names them in `signals`, and `tests/test_action_registry.gd` asserts the offered
families equal the union of those signals' `vehicles` lists. The one row with no `signals`
is `hitch` (tractor `hitch_pos`, semi tipper valve — shared local toggle).

## Telemetry & dashboard

- `VehicleTelemetry` (`src/vehicles/base/vehicle_telemetry.gd`) carries every contract "out"
  signal: motion straight from the sim, aux (fuel/coolant/battery) as simple models (the burn
  read off the crank, `fuel_rate_lph`).
  Derivations are static pure fns, tested in `tests/test_telemetry.gd`.
  `BaseVehicle._update_telemetry(input, delta)` holds the only
  per-tick state; a respawn reseeds the whole object in place from a fresh
  `_make_telemetry()` (`BaseVehicle._reseed_telemetry`), odometer and hour meter included —
  R hands back a machine as new. `status` bits (`ST_*`) are FROZEN (`contract/CLAUDE.md`).
  `to_bridge_dict()` maps fields
  to contract "out" names in contract units (throttle/steer as %, slip as ratio);
  `test_telemetry` fails if it drops a non-todo "out" signal (`WIRE_*` tables).
- Dashboard (`src/ui/dashboard.gd`; its layers and density: the header comments): generated from
  the contract, instruments hand-built; bool "in" lamps read `LAMP_INPUT_FIELDS` /
  `LAMP_COMPUTED` (`test_dashboard` pins both against the contract). SETTINGS/F2 (`toggle_dashboard`) cycles COMPACT -> FULL
  -> OFF, saved to `user://` (`UserSettings`).
- Debug overlay (`debug_overlay.gd`): FPS/frame ms/draw calls/VRAM/node count via
  `Performance`, F3. Target: root CLAUDE.md perf target.

## Bridge

- Transport is web-only. Head Include (`export_presets.cfg` `html/head_include`, source
  `src/bridge/web/head_include.html`) installs `window.__carlito`: stashes inbound
  `{type:'carlitoInput'}` with a timestamp, exposes `publish()` for outbound
  `{type:'carlitoOutput'}`. `Bridge` autoload (`src/bridge/bridge.gd`,
  `OS.has_feature("web")`-gated): polls the inbound stash each physics tick (~60 Hz),
  freshness-gated `Bridge.FRESHNESS_MS` in JS on `performance.now()` (monotonic); runs while the tree is
  paused (menus open) so the link never goes silent, unlike `InputRouter`; publishes at `PUBLISH_HZ` (20) via
  `Contract.data.signals_for_vehicle(GameState.current_vehicle, "out")` ×
  `telemetry.to_bridge_dict()`, both sides stamping contract version and hash. `carlitoOutput` also
  carries `challenge` (bool, `Bridge.set_challenge` from `boot.gd`), not a contract signal —
  sloppyCAN mutes its RAMN demo traffic on the rising edge, restores on the falling one.
  `boot.gd` calls `Bridge.bind(level)` (mirrors `Dashboard.bind`); both rebind on
  `Level.vehicle_changed`.

## Lamps, horn & day/night

- Lamp state rides `VehicleInput`, mirrored verbatim (`lamp_set.gd`'s header); locally only
  `brake_lamp` is driven, from the foot brake. A semi-trailer builds a second `LampSet` off its
  own spec (`TowedBody`). Horn (`horn.gd`) is a synthesized loop in a shared
  `AudioStreamWAV`, no asset.
- Day/night is a `Level` concern: N (`toggle_day_night`) or the pause menu's SANDBOX ▸ TIME
  (`set_night(on)`) flips between authored day values and a dim night preset (`level.gd`),
  read back by `is_night()`, emitting `GameState.night_changed` (tracked by the shell so key
  and menu agree). Wind/current overrides (`src/levels/base/world_conditions.gd`,
  `Level.set_conditions`): a LEVEL/CALM/LIGHT/STRONG preset per field plus a shared FROM
  compass direction, replacing authored `wind`/`current` side-cars; read only by families in
  `WorldConditions.WIND_FAMILIES`/`CURRENT_FAMILIES`.

## Shell, touch controls & garage

- `boot.gd` (`boot.tscn` root): boot -> load level -> play, pause overlay on top, one path
  standalone/sloppyCAN-embed/headless. HUD is in `boot.tscn`;
  `PauseMenu`/`LevelSelect`/`VehicleSelect` are transient. Boot target, in order:

  | Authority | Source | Notes |
  |---|---|---|
  | Deep link | `?level=<id>&vehicle=<variant>`, `--level=`/`--vehicle=`, or `CARLITO_LEVEL` | `src/shell/boot_params.gd`: unknown ids dropped; `vehicle` names a VARIANT |
  | `boot.gd`'s `DEFAULT_LEVEL` | `flatland` (no bake) | keeps every island pack out of the boot download |

  Variant reaches the level via `Level.initial_variant`, read before `_ready` spawns it.
- One theme (`src/ui/theme/ui_theme.gd`+`src/ui/ui_scale.gd`): `UiTheme` tokens,
  `build(scale)` -> `Theme`; `UiScale` rescales on resize × the SETTINGS factor. Screens use
  a ROLE (`theme_type_variation`), relayout on `NOTIFICATION_THEME_CHANGED`, else
  `UiTheme.px(self, …)` — `Window.content_scale_factor`/`CONTENT_SCALE_MODE_CANVAS_ITEMS`
  are unused (also resize the 3D target on 4.7.1, rule 9); `focus`/`Choice`/`follow_focus`
  cover keyboard/gamepad, CONTROLS scrolls on Up/Down instead. Notice line
  (`src/ui/notice_line.gd`, `Notice` Label): `GameState.notice` text, dwelled
  `NoticeLine.NOTICE_DWELL_S`. First-run cue (`src/ui/coach_cue.gd`): dismissed by input or
  timeout, once per session (`CoachCue.maybe_coach`), via non-consuming `_input`.
- Pause overlay (`src/ui/pause_menu.gd`, Esc, Options or touch MENU): RESUME/RESPAWN/SPAWN POINT/
  LEVEL/SANDBOX/CONTROLS/SETTINGS, LEVEL only while the pad is the device in use as it opens
  (`State.level_row`); GARAGE/LEVEL/CHALLENGES live on touch (hidden only by F5, never F4) and
  G / 4 / 5, GARAGE on Create; the pad does not reach CHALLENGES. `setup(caps, state)` before `add_child`,
  `state` a `PauseMenu.State` (named fields, filled by `Boot._open_pause`).

  | Page | Contents |
  |---|---|
  | SPAWN POINT | the level's spawns this body may use (`State.spawns`), shown from two up; a pick emits `spawn_picked(index)` |
  | CONTROLS | off `InputMap` and the registry's `pad` (`pad_for`); hidden if unusable (`ActionRegistry.relevant_entry`), greyed if bridge-owned; the pad drawn (`pad_diagram.gd`, plain and L1 sets, the L1 set from `pad_layer_rows`) where it fits, else the text column |
  | SETTINGS | dashboard density, UI scale, KEY RESPONSE; saved to `user://` (`UserSettings`, re-applied by `Boot._apply_saved_settings`) |
  | SANDBOX | one scrolling page in two headed sections. WORLD: WIND/CURRENT preset (`WorldConditions.Preset` LEVEL/CALM/LIGHT/STRONG), FROM direction, TIME -> greys per `WorldConditions.WIND_FAMILIES`/`CURRENT_FAMILIES`, all greyed in a challenge. VEHICLE: TRACTION CONTROL, STABILITY CONTROL, AUTO HOLD (saved, as SETTINGS), then the LAB switches ANTI-LOCK BRAKES, DIFFERENTIALS, STEERING (§ Input pipeline), session-held, greyed in a challenge or under a live bridge |

  Session-held, never saved: WORLD, the LAB switches and the garage's gearbox choice (`Boot._manual_gearbox`);
  the garage's tyre choice is saved (`UserSettings.set_tyre`). WORLD and night re-apply each
  load (`Boot._finish_load`, restoring `PAUSABLE`); night tracks `GameState.night_changed`. `Boot` is `PROCESS_MODE_ALWAYS`.
- Level select (`src/ui/level_select.gd`, touch LEVEL or 4): BACK + `closed` signal, reads
  `LevelRegistry.LEVELS` (`{id, name, scene, desc}`, plus `dev: true`, hidden here but baked and
  smoke-tested, or `arena: true`, a challenge arena); cards from
  `src/ui/level_thumbs/<id>.png` (`LevelShot.thumb_path`), framed by `<level>_shot.tres`.
- Vehicle selector (`src/ui/vehicle_select.gd`, G or touch GARAGE): family column, variant
  cards, towing; one SubViewport turntable via `VehicleShot.spawn_display` (frozen
  KINEMATIC, `display_only = true`, out of `InputRouter`'s slot). DRIVE on a family the level
  cannot spawn asks, then loads its `LevelRegistry.home_of` (`level_drive_chosen`). Attachments:
  `attachment_ids()`/`current_attachment()`/`set_attachment(id)`, duck-typed on
  `TractorVehicle`/`SemiTractor`, same setter as `cycle_implement()` (DETACHED/BOBTAIL =
  NONE). Emits `vehicle_chosen(variant)` then `attachment_chosen(id)` (a towing machine),
  `gearbox_chosen(manual)` (a gear-byte family) and `tyre_chosen(variant, id)` (a tyre choice);
  `Level.set_vehicle(variant)` only on a real change, respawns at a matching `VehicleSpawn`,
  emits `Level.vehicle_changed(type)` (`Dashboard.bind` reads `GameState.current_vehicle`, so
  the shell binds only after a spawn). Cards: `tools/gen_vehicle_thumbs.tscn` (windowed) ->
  `src/ui/vehicle_thumbs/<id>.png` via `src/ui/vehicle_shot.gd`; PNGs under `src/`,
  `tools/*`/`kit/thumbs/*` export-excluded.
- Garage level (`src/levels/garage/`, id `garage`): frozen KINEMATIC vehicle, `_physics_process`
  still runs (wheels steer, engine revs, lamps toggle), `orbit_camera.gd` inspects freely.
- Touch controls (`src/ui/touch_controls.gd`), a second input source: joystick, pedals,
  UP/DOWN flight pads, buttons generated from the registry (`ActionRegistry.is_universal`,
  `STACK_HEAD`; per-machine ones in the EQUIP drawer, `_fit_equip_drawer`). IMPORTANT (F5,
  `toggle_important`) / DRIVING (F4, `toggle_touch`) layers; `poll()` empty while hidden. A
  `touch_state` row reads "<label> ON" in amber. Pads scale by `DESKTOP_PAD_SCALE`
  (`MENU_BTN_SIZE` top-left), wrap via `_columns_for`/`STACK_TOP`, lattice unit `CELL_SIZE`.
  Keyboard-only actions: the registry's no-touch rows; `LEVEL` also binds `level_select` (key 4), checked by `_shell_signals()` /
  `tests/test_action_registry.gd`. Raw intent: `_held`/`_edges` keyed by `poll_key`, drained
  by `poll()`; a hidden pad emits its own release (`Pad._notification`).
- Shader warmup (`src/shell/shader_warmup.gd`): gl_compatibility has no ubershader, so each
  material variant compiles on its first draw. Behind the loading screen every instance's cull
  margin grows past the level, so the whole level draws in its real passes for a few frames.
  Particles get an emitting twin (an idle emitter is never drawn); hidden instances are shown
  for the warmup, but one under a hidden ancestor still compiles on reveal. Not covered: a V /
  garage swap, an E attachment and light-count variants (headlights, night) still hitch on first
  draw. Covering them means delaying the reveal behind an off-screen pass, but
  `Level._spawn_vehicle` is synchronous (`ChallengeRunner.start()` and `boot.gd`'s
  `_on_vehicle_picked` read `Level.vehicle` on the next line): either thread `await` through
  those call sites or flush mid-frame (`RenderingServer.force_draw`, unverified here).

## Level framework

- `src/levels/base/`: `Level` reads a `LevelInfo`, spawns at the first matching
  `VehicleSpawn`, wires `ChaseCamera`, handles respawn (variant -> scene via
  `VehicleCatalog`); the train gates on `has_closed_rail()` and self-places, else the garage
  sends it to Level 5. `LevelInfo` (Resource: display name, allowed/default vehicles); `VehicleSpawn`
  (`Marker3D`, vehicle-type filter + `is_water`, a bake-gate coverage flag read only by
  `LevelBaker.validate_spawns`: `accepts` and `Level.pick_spawn` ignore it, and a drown respawns
  at `spawn_transform`). `level.tscn`
  is the authoring template (env + sun + camera + one spawn); duplicate it.
  `HeightmapTerrain` (authoring: `docs/level_kit.md`): runtime greyscale image -> chunked
  welded grid mesh + `HeightMapShape3D`; `channel_surface` names each paint channel's
  `Surface` (`src/levels/base/surface.gd`, one shared table; figures graded in `docs/sources.md`
  § Sourced figures): `ref_grip` (a mu multiplier, ASPHALT 1, none above) and `drag` (an ADDED
  rolling-resistance coefficient), blended by `grip_at(world_pos, response)` / `drag_at` over the
  splat weights pow-sharpened by `blend_sharpness`; `response` is the tyre's per-surface grip
  (`docs/vehicles.md` § Tyres and surfaces). Unpainted ground reads Asphalt.
- `src/levels/island/level_1/` .. `level_6/`: six islands, terraced terrain + auto-splat +
  sea, each rostering at least car/truck/tractor/boat. `level_1` is the CI baked-level smoke
  target; 2-4 (Mountain, City, Racing) are hand-dressed on a one-shot `tools/gen_islands.gd`
  scaffold. `level_5` (rail loop) and `level_6` (skyport) are
  owned by their generator (`tools/gen_rail_level.gd`, `tools/gen_skyport.gd`).
  `src/levels/island/car_arena/` (`arena: true`, also in LEVEL select; pause → SPAWN POINT
  reaches its tyre pad) is a car plateau owned by `tools/gen_car_arena.gd`. `flatland`/`open_sea`
  are endless, unbounded, no kit content: `InfiniteGround` (`src/levels/base/infinite_ground.gd`)
  or an `infinite` `WaterSurface` re-centres on the camera; no `WorldBounds`. Dev, unregistered:
  `src/levels/dev/flat.tscn` (wheel checks). Dev, registered (`dev: true`, hidden from LEVEL select,
  reached by `--level=rough_ground` for garage tyres): `src/levels/dev/rough_ground/`
  (`measure_rough`'s lanes and an ice pad, owned by `tools/gen_rough_ground.gd`).

### Water & world bounds

- `WaterSurface` (`src/water/water_surface.gd`, `@tool Area3D`, group `Groups.WATER`):
  `get_height(pos)`, optional `far_sea_extent` skirt, non-boat kill/respawn volume
  (`kill_margin` below the surface, `body_entered` -> `call_deferred("respawn")` on any
  non-boat `BaseVehicle`, region via `contains_xz`); does not own the map boundary.
  `WorldBounds` (`src/levels/base/world_bounds.gd`, `@tool StaticBody3D`): four walls on `extent` plus a ceiling at `ceiling_height`, down to
  `floor_depth`, axis-aligned. Set `extent` to the water `size` so sea wall and map wall
  match (`test_world_bounds` checks every level); default `ceiling_height` is 1500 m, clear of the
  contract's 0-500 m `altitude` scale.
- Depth-fade shading (`water.gdshader`) samples `hint_depth_texture`; `depth * 2.0 - 1.0` for gl_compatibility.

## Challenges

- The one goal-driven, bridge-only feature: a `ChallengeDef` (`src/challenges/defs/*.tres`: course,
  marker, goals, constraints, `par_s`) is listed only once it is in `ChallengeRegistry.DEFS`, which
  orders the CHALLENGES screen and whose `problems()` the suite holds every entry to.
- `ChallengeRunner` (a child of the level root) overlays the course, spawns a fresh body at its
  marker and steps a pure-logic `ChallengeAttempt` with a `ChallengeFrame` each physics tick after
  the vehicles; PASS / FAIL end it, RESET respawns, any respawn restarts it.

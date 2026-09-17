# Runtime systems

The plumbing every vehicle rides: signal contract, input pipeline, telemetry/dashboard,
bridge, lamps, shell, level framework. Per-family vehicle detail is in `docs/vehicles.md`
and `docs/heavy_vehicles.md`. Editor/authoring tooling is in `docs/level_kit.md`; rules and
gotchas are in `CLAUDE.md`.

## Signal contract

`contract/carlito_contract.json` (v42) defines every bridge signal: name, dir, type, unit,
range, `warn`/`warn_side`, `count`, enum, vehicles, `flavor` (`isobus`, `j1939`, `iso11992`,
`j2497`, `cleanopen`, `canaerospace`, `dronecan`, `train`, `nmea2000`). `Contract`
(`src/bridge/contract.gd`) parses/validates it into `Contract.data`;
`tests/test_contract.gd` fails if a required signal is missing. Unique by (name, dir) —
`battery` exists both ways (in = warning LED, out = voltage). `warn` needs `warn_side`
(`"low"` | `"high"`); `todo` marks a signal unimplemented both sides; no `range` on an "out"
signal makes a readout line, not a bar. `count` (>= 1, default 1) makes an Array of N,
`range`/`warn` per element, zero-based: `esc_rpm`/`esc_current`/`esc_temp` (4),
`node_health` (8), `slip` (2); rejected on `"in"`, `bool`, or with an `enum` —
`Bridge._publish` drops a wrong-shaped value with one warning.

Edits bump `version`; a mismatch warns at runtime and raises a sticky notice (`push_warning`
is invisible in a web release). `tools/gen_js_contract.mjs` regenerates
`../sloppycan/carlito_contract.js` (`window.CARLITO_CONTRACT`) — run after any edit, landing
on `dev` in both `carlito` and `sloppycan`, promoted together.

## Input pipeline

`InputRouter` merges every source into one `VehicleInput` per tick. All arbitration is
static/pure, tested in `tests/test_input_arbitration.gd`.

- `merge_local`: keyboard + touch (max analog, summed steer, OR'd bits).
- `arbitrate_local`: ignition gates throttle; brake never throttles; S = brake, then reverse
  at standstill; foot brake drives `brake_lamp`.
- `arbitrate_bridge`: the gear byte owns direction. Mode = `InputRouter.set_manual_gearbox`
  (vehicle selector, or `ChallengeDef.transmission`).
- Automatic (default): PRND lever. R reverses, D1-D6 = D with auto-shift, 0 = D. why: RAMN
    `0x077` never sends gear.
- Manual: byte taken exactly, 0 = N, no auto-shift. Local input is always automatic.
- Absent bridge keys fall to rest state (lamps off, hitch raised, PTO off, 540, open diff,
    2WD, SCV shut, flaps up, disarmed, doors shut, LEDs black, body Idle).
- `rudder` (boat) and `guidance_curvature` (tractor) override `steer` when the key is
    present. `bridge_source.gd` writes the key only when sloppyCAN sent it: 0 is a command.
- "Ignition off" notice clears when the key reaches Ignition (`GameState.notice_cleared`).

Three paths, chosen per tick:

| Path | When | Input |
|---|---|---|
| Bridge drives | fresh (< 300 ms, `Bridge.FRESHNESS_MS`) and `accel`/`brake`/`steer` present (`BridgeSource.drive_sourced`) | `arbitrate_bridge` |
| Fallback | fresh, no driving control (CHAdeMO, CANopen, DroneCAN with Drone Control closed, NMEA 2000) | `blend_local_driving`: pedals, steer, handbrake, key, gear, STOP lamp, lights, horn, arm/climb, elevator from local; the rest from the bridge |
| Local | no fresh bridge | `arbitrate_local` |

- J1939 / ISO 11783 traffic drives (EEC2/EBC1/VDC2/TC1/CCVS decode to pedals/steer/gear).
- Fallback raises `NO DRIVING CONTROLS FROM SLOPPYCAN - KEYBOARD DRIVES`; only the driving
  group's toggles (lights, arm) advance there. Never under `set_bridge_only`.
- `InputRouter.bridge_drives()` is the "who drives" predicate (touch driving layer,
  action-registry context); `Bridge.is_active()` only says a peer is connected.
  `bridge_source.gd` normalizes contract-in fields (%->unit); `local_source.gd` reads the
  keyboard; touch registers via `InputRouter.set_touch_source()`.
- Toggle state is owned by the router, never a source: headlight level `_lights`
  (OFF->CLEARANCE->LOW->HIGH), tractor hitch/PTO/PTO-speed/diff-lock/MFWD, drone arm/cargo
  hook/injected node failure/flight mode, plane flaps, train pantograph/doors, refuse body
  command. Train pantograph defaults raised so a locally-driven train spawns able to move.
  Sources report per-frame edges only, ORed by `merge_local`; the `var _*` block at top of
  `input_router.gd` is the list.
- `VehicleInput` (`src/input/vehicle_input.gd`) is a `class_name`, not an inner class of the
  autoload — a vehicle's static types don't depend on the autoload's registered name. Fields
  are flat except `lamps` (the fourteen verbatim-mirrored lamp/warning bits — one rule, not
  one family). `lights` stays flat: a level the router cycles, not a mirrored bit.
  `get_vehicle_input()` returns the router's own struct, read-only by convention —
  `arbitrate_*` build a fresh struct each tick, so a stashed reference reads stale; no
  defensive `copy()`.
- Raw-intent wire is `Dictionary[StringName, Variant]` across all four producers
  (`local_source.gd`, `touch_controls.gd`, `bridge_source.gd`, `tools/measure_drone.gd`'s
  `StickSource`) and `merge_local`. Three tests guard the untyped keys: the registry's
  `poll_key` values against `LocalSource`/`merge_local` key sets, and touch's
  `TouchControls.WIDGET_KEYS` against `merge_local` — `merge_local` builds its dict
  explicitly, so a key on one side only drops the keyboard's edge silently.
  `arbitrate_local`/`arbitrate_bridge` take a plain `Dictionary`.
- Bindings live in `project.godot`'s InputMap, shown by the CONTROLS sheet generated from
  the action registry. `tests/test_input_map.gd` asserts no two actions share a physical
  key.

### The action registry

`src/input/action_registry.gd`: a static table keyed by row (a control on two keys —
drive/reverse, steer, climb/descend — is one row), each carrying a label, a `group`
(drive/vehicle/world/shell), a gate, and how touch offers it. No key string is typed there:
`keys_for()` reads the live binding from `InputMap`.

Two consumers: the pause menu's CONTROLS sheet (`src/ui/pause_menu.gd`) and the touch button
stack (`src/ui/touch_controls.gd`). `tests/test_action_registry.gd` asserts every bound
(non-`ui_*`) action is in exactly one row.

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
  signal: motion straight from the sim, aux (fuel/coolant/battery) as simple models.
  Derivations are static pure fns (GPS `gps_lat`/`gps_lon` around Paris 48.8566/2.3522,
  `heading_from_forward`, `odo_step`, `body_accel`, `impact_gate`, `pack_status`), tested in
  `tests/test_telemetry.gd`. `BaseVehicle._update_telemetry(input, delta)` holds the only
  per-tick state; a respawn reseeds the whole object in place from a fresh
  `_make_telemetry()` (`BaseVehicle._reseed_telemetry`), odometer and hour meter included —
  R hands back a machine as new. `status` bits (`ST_*`) are FROZEN: new flags
  append at bit 7+ (nine free in the u16), never renumbered. `to_bridge_dict()` maps fields
  to contract "out" names in contract units (throttle/steer as %, slip as ratio);
  `test_telemetry` fails if it drops a non-todo "out" signal — `WIRE_*` tables hold the
  renames, rounding rules, and the synthesised `slip`.
- Dashboard (`src/ui/dashboard.gd`) generates repetitive parts by walking the contract;
  instruments are hand-built. Plain text + color only.

  | Layer | What |
  |---|---|
  | Tell-tale | lamp per bool "in", `key`/`lights` chips, lamp/chip per flavored bool/enum "out" |
  | Bars | warn'd or flavored "out" signals with a `range`, via `dash_bar.gd` (`BAR_ROWS_MAX`-row, `WIDGET_SIGNALS` excluded) |
  | Readout | "out" signals with no `range`, beside HDG/ODO/GPS (boat SOG/STW/DRIFT in m/s) |
  | Hand-built | gauges (`gauge.gd`, `kmh`/`rpm`, 90° text gap), attitude (`pitch`/`roll`), wind rose (`wind_rose.gd`, `awa`/`aws`/`twd`/`tws`/`cog`/`sog`), sounder (`depth_readout.gd`, `depth`, `---` for -1), `node_health`, train's `REVERSER N/D/R` |

  Captions (`BAR_LABEL`, `LAMP_TEXT`) are hand-picked. `Dashboard.Density`: FULL, COMPACT (default, no signal drops: `tests/test_dashboard.gd`), OFF — SETTINGS/F2 (`toggle_dashboard`) cycles COMPACT -> FULL -> OFF, persisted in `user://shell.cfg`.
- Debug overlay (`debug_overlay.gd`): FPS/frame ms/draw calls/VRAM/node count via
  `Performance`, F3. Target 60 fps in the worst deployed view.

## Bridge

- Transport is web-only. Head Include (`export_presets.cfg` `html/head_include`, source
  `src/bridge/web/head_include.html`) installs `window.__carlito`: stashes inbound
  `{type:'carlitoInput'}` with a timestamp, exposes `publish()` for outbound
  `{type:'carlitoOutput'}`. `Bridge` autoload (`src/bridge/bridge.gd`,
  `OS.has_feature("web")`-gated): polls the inbound stash each physics tick (~60 Hz),
  freshness-gated 300 ms in JS; publishes at `PUBLISH_HZ` (20) via
  `Contract.data.signals_for_vehicle(GameState.current_vehicle, "out")` ×
  `telemetry.to_bridge_dict()`, both sides stamping contract version. `carlitoOutput` also
  carries `challenge` (bool, `Bridge.set_challenge` from `boot.gd`), not a contract signal —
  sloppyCAN mutes its RAMN demo traffic on the rising edge, restores on the falling one.
  `boot.gd` calls `Bridge.bind(level)` (mirrors `Dashboard.bind`); both rebind on
  `Level.vehicle_changed`.

## Lamps, horn & day/night

- Lamp state rides `VehicleInput`, mirrored verbatim, no local blink timer (`CLAUDE.md` §
  Lamps & bridge); locally only `brake_lamp` is driven, from the foot brake
  (`tests/test_lamps.gd` asserts no clock in `lamp_set.gd`). `LampSet`
  (`src/vehicles/base/lamp_set.gd`) applies lamp state to nodes the `VehicleSpec` names by
  NodePath (`headlight_paths`, `brake_lamp_paths`/`turn_*_paths`); rear lamps tri-state via
  `LampSet.rear_tier(brake_on, headlights)`: STOP > TAIL > OFF (`tests/test_lamps.gd`).
  `BaseVehicle` builds one in `_ready`, calls `apply()` each tick; a semi-trailer builds a
  second off its own spec (`TowedBody`). Horn (`horn.gd`) is a synthesized loop in a shared
  `AudioStreamWAV`, no asset.
- Day/night is a `Level` concern: N (`toggle_day_night`) or the pause menu's CONDITIONS page
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
  | Saved session | `src/shell/shell_prefs.gd` -> `user://shell.cfg` | Skipped on deep link/`--headless`; `ShellPrefs.ENABLED` is `false` today |
  | `boot.gd`'s `DEFAULT_LEVEL` | `flatland` (no bake) | city bake is 13.9 MB, must never boot |

  Variant reaches the level via `Level.initial_variant`, read before `_ready` spawns it.
- One theme (`src/ui/theme/ui_theme.gd`+`src/ui/ui_scale.gd`): `UiTheme` tokens,
  `build(scale)` -> `Theme`; `UiScale` rescales on resize × the SETTINGS factor. Screens use
  a ROLE (`theme_type_variation`), relayout on `NOTIFICATION_THEME_CHANGED`, else
  `UiTheme.px(self, …)` — `Window.content_scale_factor`/`CONTENT_SCALE_MODE_CANVAS_ITEMS`
  are unused (also resize the 3D target on 4.7.1, rule 9); `focus`/`Choice`/`follow_focus`
  cover keyboard/gamepad, CONTROLS scrolls on Up/Down instead. Notice line
  (`src/ui/notice_line.gd`, `Notice` Label): `GameState.notice` text, dwelled
  `Boot.NOTICE_DWELL_S`. First-run cue (`src/ui/coach_cue.gd`): dismissed by input or
  timeout, once (`ShellPrefs.coach_seen`), via non-consuming `_input`.
- Pause overlay (`src/ui/pause_menu.gd`, Esc or touch MENU):
  RESUME/RESPAWN/CONDITIONS/CONTROLS/SETTINGS; GARAGE/LEVEL live on touch (hidden only by
  F5, never F4) and G / 4.

  | Page | Contents |
  |---|---|
  | CONTROLS | off `InputMap`; hidden if unusable (`ActionRegistry.relevant_entry`), greyed if bridge-owned. `setup(caps, density, ui_scale, wind_preset, current_preset, wind_from_deg, night_on)` before `add_child` |
  | SETTINGS | dashboard density + UI scale cycling buttons -> `user://shell.cfg` |
  | CONDITIONS | WIND/CURRENT preset (`WorldConditions.Preset` LEVEL/CALM/LIGHT/STRONG), FROM direction, TIME -> greys per `WorldConditions.WIND_FAMILIES`/`CURRENT_FAMILIES` |

  Session-held (`ShellPrefs` disabled), re-applied each load (`Boot._finish_load`, restoring `PAUSABLE`); night tracks `GameState.night_changed`. `Boot` is `PROCESS_MODE_ALWAYS`.
- Level select (`src/ui/level_select.gd`, touch LEVEL or 4): BACK + `closed` signal, reads
  `LevelRegistry.LEVELS` (`{id, name, scene, desc}`); cards from
  `src/ui/level_thumbs/<id>.png` (`LevelShot.thumb_path`), framed by `<level>_shot.tres`.
- Vehicle selector (`src/ui/vehicle_select.gd`, G or touch GARAGE): family column, variant
  cards, towing; one SubViewport turntable via `VehicleShot.spawn_display` (frozen
  KINEMATIC, `display_only = true`, out of `InputRouter`'s slot). DRIVE alone refuses
  (`_on_drive`, via
  `allowed_vehicles`/`Level.has_closed_rail()`/`Level.has_spawn_for(family)`). Attachments:
  `attachment_ids()`/`current_attachment()`/`set_attachment(id)`, duck-typed on
  `TractorVehicle`/`SemiTractor`, same setter as `cycle_implement()` (DETACHED/BOBTAIL =
  NONE). Emits `vehicle_chosen(variant)` then `attachment_chosen(id)`;
  `Level.set_vehicle(variant)` only on a real change, respawns at a matching `VehicleSpawn`,
  emits `Level.vehicle_changed(type)` (`Dashboard.bind` falls back to
  `LevelInfo.default_vehicle`). Cards: `tools/gen_vehicle_thumbs.tscn` (windowed) ->
  `src/ui/vehicle_thumbs/<id>.png` via `src/ui/vehicle_shot.gd`; PNGs under `src/`,
  `tools/*`/`kit/thumbs/*` export-excluded.
- Garage level (`src/levels/garage/`, id `garage`): frozen KINEMATIC vehicle,
  `_physics_process` still runs (wheels steer, engine revs, lamps toggle), `orbit_camera.gd`
  inspects freely.
- Touch controls (`src/ui/touch_controls.gd`), a second `InputSource`: joystick, pedals,
  UP/DOWN flight pads, buttons generated from the registry (`ActionRegistry.is_universal`,
  `STACK_HEAD`; per-machine ones in the EQUIP drawer, `_fit_equip_drawer`). IMPORTANT (F5,
  `toggle_important`) / DRIVING (F4, `toggle_touch`) layers; `poll()` empty while hidden. A
  `touch_state` row reads "<label> ON" in amber. Pads scale by `DESKTOP_PAD_SCALE`
  (`MENU_BTN_SIZE` top-left), wrap via `_columns_for`/`STACK_TOP`, lattice unit `CELL_SIZE`.
  Seven actions are keyboard-only: `next_vehicle`, `toggle_dashboard` (F2), `respawn` (R),
  `day_night` (N), `debug_overlay` (F3), `toggle_touch` (F4), `toggle_important` (F5);
  `LEVEL` also binds `level_select` (key 4), checked by `_shell_signals()` /
  `tests/test_action_registry.gd`. Raw intent: `_held`/`_edges` keyed by `poll_key`, drained
  by `poll()`; a hidden pad emits its own release (`Pad._notification`).

## Level framework

- `src/levels/base/`: `Level` reads a `LevelInfo`, spawns at the first matching
  `VehicleSpawn`, wires `ChaseCamera`, handles respawn (variant -> scene via
  `VehicleCatalog`); the train gates on `has_closed_rail()` and self-places, else refuses
  DRIVE. `LevelInfo` (Resource: display name, allowed/default vehicles); `VehicleSpawn`
  (`Marker3D`, vehicle-type filter + `is_water` for boat/drown-respawn spots). `level.tscn`
  is the authoring template (env + sun + camera + one spawn); duplicate it.
  `HeightmapTerrain` (authoring: `docs/level_kit.md`): runtime greyscale image -> chunked
  welded grid mesh + `HeightMapShape3D`; a surface is TWO numbers per paint channel, both
  blended the same way by `grip_at` / `drag_at(world_pos)` over bilinear splat weights,
  pow-sharpened by `blend_sharpness` (`get_splat_weights` returns raw weights): `channel_grip`
  (a mu multiplier, ≤ 1) and `channel_drag` (an ADDED rolling-resistance coefficient, ≤ 0.5).
  Ice is low grip and no drag; mud is low grip and high drag; grass is mostly drag.
- `src/levels/island/level_1/` .. `level_6/`: six islands, terraced terrain + auto-splat +
  sea, each rostering at least car/truck/tractor/boat. `level_1` is the CI baked-level smoke
  target; 2-4 are blank (`AuthoringRoot`). `level_5` (rail loop) and `level_6` (skyport) are
  owned by their generator (`tools/gen_rail_level.gd`, `tools/gen_skyport.gd`).
  `src/levels/island/car_arena/` (`arena: true`, not in LEVEL select) is a car-only plateau
  owned by `tools/gen_car_arena.gd`. `flatland`/`open_sea` are endless, unbounded, no kit
  content: `InfiniteGround` (`src/levels/base/infinite_ground.gd`) or an `infinite`
  `WaterSurface` re-centres on the camera; no `WorldBounds`. `src/levels/dev/flat.tscn` is a
  bare test plane for wheel checks. A `.tscn` can embed scripts — loading a stranger's level
  is arbitrary code execution.

### Water & world bounds

- `WaterSurface` (`src/water/water_surface.gd`, `@tool Area3D`, group `"water"`):
  `get_height(pos)`, optional `far_sea_extent` skirt, non-boat kill/respawn volume
  (`kill_margin` below the surface, `body_entered` -> `call_deferred("respawn")` on any
  non-boat `BaseVehicle`, region via `contains_xz`); does not own the map boundary
  (`CLAUDE.md` § Levels & water). `WorldBounds` (`src/levels/base/world_bounds.gd`, `@tool
  StaticBody3D`): four walls on `extent` plus a ceiling at `ceiling_height`, down to
  `floor_depth`, axis-aligned. Set `extent` to the water `size` so sea wall and map wall
  match (`tests/test_world_bounds.gd`); default `ceiling_height` is 1500 m, clear of the
  contract's 0-500 m `altitude` scale.
- Depth-fade shading (`water.gdshader`): samples `hint_depth_texture`, fades
  `shallow_alpha`->`deep_alpha` / `water_color`->`deep_color` over `depth_fade_m`; `depth *
  2.0 - 1.0` for gl_compatibility.

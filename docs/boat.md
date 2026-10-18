# Boat

The water it floats on is a LEVEL node: `WaterSurface`/`WorldBounds` in `docs/systems.md` §
Water & world bounds.

- `BoatVehicle extends BaseVehicle` (`src/vehicles/boat/`): two seams only
  (`_make_telemetry()` → `BoatTelemetry`, `_tick_extras` = buoyancy/drag/thrust/rudder),
  `reset_session_state()` = `super()` + trim/autopilot reset. Its spec declares no ground drive,
  so `axle_torque` off `Drivetrain` is discarded.
- Boat, drone and train run the whole engine model at 60 Hz for the gear byte (`auto_shift` on
  the kept 6 `gear_ratios`, scale `DEFAULT_ROAD_RADIUS`); only the boat reads `drivetrain` in its
  own file, for telemetry (`applied_throttle`, `rpm`) — accepted compromise,
  `docs/vehicles.md` § Rejected designs.

## Buoyancy and knobs

4 probes, RayWheel clamp discipline: spring k derived (`m*g / (probes * float_depth)`),
damper one-tick clamped, total clamped `[0, max_probe_force_factor × weight share]`.
Hull/yaw drag uses `VehicleMath.damped_force` (`damped_force` zeroes at most the velocity it
opposes in one tick). Tested `tests/test_boat.gd`.

| Knob (`@export` on `BoatVehicle`) | Effect |
| --- | --- |
| `prop_offset` (below COM) | thrust → bow-up under throttle |
| `keel_offset` (below COM) | lateral drag → heel in turns |
| `windage_offset` (body-space point) | heel in beam wind; aft of COM → weathercocks into wind |
| `float_depth` | probe plane; also the `depth` datum and aground threshold |

Above-waterline hull takes anisotropic drag from air-relative velocity (`windage_long`/
`windage_lat`) via `WindField.at(self)`, not `VehicleMath.air_damper` (its `axis` masks
WORLD space). Air is 1/800 water density. Level 6 is the only level with a `WindField`;
`Level.wind` defaults to null elsewhere.

## Sailing: `boat-sail-a`

`BoatSail`: lift/drag force at `sail_center` above COM, resisted by `keel_extra` 0.60.
Flat-plate polar (`Cl = CL_MAX·sin 2a`, `Cd = CD_MIN + CD_STALL·(1 − cos 2a)/2`). Below
`LUFF_DEG` the lift term is zero (irons).

- No-go zone is emergent (leeway from `drag_lat` rides `linear_velocity`, so `apparent_wind`
  sees it), not clamped. Sheet is a LIMIT, not a position (contract `sheet`, the **3** key
  or sloppyCAN, 0..1): boom travel `min(sheet · sheet_max_deg, |awa|)`. `sail_angle` (out)
  signed like `awa`, so `aoa = awa − sail_angle`; the GLB mesh (`sail_pivot`) follows.
- `sheet`/`sail_angle` are unflavored (no NMEA 2000 sail PGN; the `train` flavor is not a
  precedent, it borrows practice); `sail_angle` is range-less, on the readout line via
  `Dashboard.READOUT_EXTRAS`. Gates on `sail_area > 0`
  (`BoatVehicle.vehicle_capabilities()["sail"]`, the `body_cmd` shape); `sail_area` 0 skips
  the whole force block.
- `thrust_force` / `drag_long` are one tuned pair (~5 hp outboard, 3.3 m/s top
  speed); the § Autopilot gains table is untouched by the retune.

## Tide

`CurrentField` (`src/levels/base/`), sibling of `WindField` (same `Resource` shape,
duck-typed `at(node)`, sharing only `base_vector`):
`set_deg`/`drift`/`tide_period_s`/`tide_offset_s`, signed sinusoid. `Level` carries it
beside `wind` (`current` / `current_vector()`, both off `_env_time`). Hull drag is measured
against the water: `through_water = linear_velocity - current`, feeding rudder authority
through `v_long`. Level 6 is the only level with water under the boat rather than beside it
(`gen_skyport.gd`'s `SEA_Y`); every other island's `Sea` is a 1 m column. Tested
`tests/test_current.gd`.

## NMEA 2000 signals

| Signal(s) | PGN | Source |
| --- | --- | --- |
| `stw` / `sog` / `cog` / `current_set` / `current_drift` | 128259, 129026, 130577 | `BoatTelemetry.flow_toward` — `sog`/`cog` off ground velocity, `stw` off `through_water`, `current_set`/`current_drift` off the tide |
| `depth` | 128267 Water Depth | `HeightmapTerrain.height_at` under the transducer vs the `WaterSurface` plane |
| `awa` / `aws` / `twd` / `tws` | 130306 Wind Data | two pure statics on `BoatTelemetry`, off the wind vector and hull velocity |
| `rudder` / `rudder_actual` / `trim` | 127245 Rudder, 127488 Engine Parameters Rapid | slewed `_steer` (%) / `trim_step` chasing throttle |
| `fuel_rate` / `oil_press` | 127489 Engine Parameters, Dynamic | labelled models off `applied_throttle` / `Drivetrain.rpm` |
| `tank_level` | 127505 Fluid Level | fresh/waste ramp, `count` 3 (fresh water / waste / live-well) |
| `engine_hours` | 127489 (also J1939 SPN 247) | `running` predicate; drops the `isobus` flavor it carries on truck/tractor, like `speed_limit`/`wheel_slip` |
| `nav_mode` / `nav_mode_actual` / `heading_cmd` / `heading_target` | 127237 Heading/Track Control | `BoatAutopilot` |

- `flow_toward`: (speed, bearing it flows TOWARD). `sog` ≠ `speed`/`kmh` (signed
  longitudinal); `cog` minus `heading` is the crab angle. `current_set` = `flow_toward` bare
  (`twd` is `true_wind` + 180). Zero flow reads bearing 0. `stw`/`sog`/`current_drift` carry
  no `range`; `cog`/`current_set` are ranged, so they're bars.
- `depth` (`HeightmapTerrain.height_at`) rides `-float_depth`; `-1` is the only invalid
  reading (never 0, an alarm value), gated by `contains_xz` since `height_at` clamps outside
  the terrain's extent. `transducer_station` is the only knob.
- `awa` is 0 dead ahead, positive to starboard, 0 in a genuine calm. `twd` is comes-FROM;
  `WindField.direction_deg` is TOWARD (`true_wind` inverts it). `aws`/`tws` carry no
  `range`.
- `BoatTelemetry extends VehicleTelemetry`. `pitch`/`roll` are shared `VehicleTelemetry`
  fields written by `_update_telemetry` (also plane/drone). `rudder`/`rudder_actual`/`trim`
  carry the `nmea2000` flavor; `rudder_actual`/`trim` are ranged with no `warn` (RUDDER/TRIM
  bars). Engine room signals compute ungated by submersion (gate on Ignition, not swimming);
  `oil_press` is the one place the boat reads its own `Drivetrain.rpm`; `tank_level`'s
  live-well is held, not modeled.

## Autopilot

`BoatAutopilot` (PGN 127237): a vehicle-level controller in the `DroneModes` shape,
`BoatVehicle._autopilot` holds state, not in `InputRouter`'s arbitration.

- `nav_mode` (in, STANDBY / HEADING HOLD, the **2** key or sloppyCAN): a request.
  `nav_mode_actual` is what's running. `steer` past `HELM_DEADBAND` hands the rudder back;
  releasing re-engages on the new heading.
- `heading_cmd` follows the `rudder`/`guidance_curvature` presence rule: absent = holds the
  heading captured on engage (engage edge only). `heading_target` (out) is that captured
  course; STANDBY tracks `heading`.
- Steers through the same slew as the hand, from its own `_helm` (re-slewing `BaseVehicle`'s
  `_steer` directly would cancel: `move_toward(move_toward(x, 0, r), c, r)` is `x` below
  `c`), so `_autopilot` rewrites `telemetry.steer` instead. Same `spec.steer_speed` cap.
  One `KP`/`KD` pair suits all three hulls (derivation below).

### Autopilot gains

Linearize the hull about its heading: `I * theta_dd = rudder_torque * A * u - drag_yaw * theta_d`,
with `I` from `VehicleMath.inertia_of(mass, probe span)` and `A` the rudder authority. With
`u = KP * e - KD * e_d` (per-radian units): `wn = sqrt(rudder_torque * A * KP / I)` and
`zeta = (drag_yaw + rudder_torque * A * KD) / (2 * wn * I)`. Over authorities 0.4 to 1.0:

| Hull | I | wn | zeta |
|---|---|---|---|
| boat-speed-a | 685 | 2.8-4.4 | 1.79-1.88 |
| boat-speed-j | 2338 | 1.9-3.1 | 1.71-1.88 |
| boat-sail-a | 681 | 2.2-3.5 | 1.64-1.69 |

Overdamped on every hull (wn * dt under 0.08 at 60 Hz), and `drag_yaw` alone carries zeta
0.6-1.3, so there is no per-variant knob. The linear plant is the shipped one: rudder torque is
applied raw, and the yaw damper's one-tick clamp (`VehicleMath.damped_force`) binds only when
`drag_yaw > I / delta` (`drag_yaw` on boat-speed-a against its `I / delta`; every hull clears it by
11-13x). Raising `drag_yaw`, or cutting mass or probe span, toward `I / delta` puts the clamp in
the loop and invalidates the zetas.

## The level-6 playground

Generated end to end by `gen_skyport.gd`; hand edits are lost on the next `scaffold` replay.

| Feature | Makes visible |
| --- | --- |
| Sandbar (`SHOAL_*`, `BrushOps.FLATTEN`; `classify_splat` paints it sand) | `depth` as a reading, not a constant — elsewhere `island_falloff` clamps the seabed to 0 |
| Buoyed channel (`CHANNEL_*`, `props`) | `cog` vs `heading` crab angle with the tide on the beam |
| Measured leg (`MILE_*`, `props`, aligned to the tide's set) | `stw` against `sog` (not a real measured mile) |

Marks are `buoy`/`buoy-flag`, `collision_mode: "none"`, placed `raw` by `_place_afloat` at
`SEA_Y` (`_place` would use the wrong origin). `_report_water()` gates `scaffold` on
`NAVIGABLE_MIN` water at every mark/gate.

## The cluster

Boat declares more ranged flavored "out" signals than any family; hand-built widgets claim
their own via `Dashboard.WIDGET_SIGNALS` (sibling of `GAUGE_SIGNALS`), holding it to eleven
bar rows in one column.

| Widget | Gated on | Note |
| --- | --- | --- |
| Wind/track rose (`src/ui/wind_rose.gd`) | `awa`/`aws`/`twd`/`tws`/`cog`/`sog` | heading-up; blanks to `---` at zero |
| Echo sounder (`src/ui/depth_readout.gd`) | `depth` | blanks the `-1` sentinel to `---` off `range[0]` |
| Attitude indicator | `pitch`/`roll` | shared with plane/drone |

`aws`/`tws` ride the rose; `sog`/`stw`/`current_drift`/`fuel_rate`/`oil_press` ride the
readout line (the `engine_hours` rule). `nav_mode_actual` is the PILOT state chip. Left on
bars: fuel, coolant, VOLTS, RUDDER, TRIM, SET, TARGET, three TANKS.

Every island's sea is a `WaterSurface`; drive in to drown-respawn. The boat is in every
island roster.

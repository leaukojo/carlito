# 12 — Tyre classes and surfaces (future feature)

Shared context: `00_README.md`. A feature, not a fix. Size: medium-large. Needs briefs 03 and 04,
and ideally 08.

## Intent (user, 2026-10-05)

Tyres as a playground: each body ships a fitting tyre (all-season on the cars, lug or off-road on
the trucks and the tractor), and the user can swap tyres (summer, winter, all-season, lug) and see
the effect on slip, braking, traction and cornering. Snow and ice are future surfaces; no level
uses them today.

## Today

- One grip-curve shape for every body (`_grip_curve` in `tools/gen_kenney_vehicles.gd`: peak 1.0
  at slip 0.12, 0.9 at 0.4, 0.8 at 1.0; the hand specs copy it).
- Grip numbers per family, fixed in the recipe (`mu_long` / `mu_lat`): car 1.05 / 0.97, van
  1.0 / 0.85, truck 0.80 / 0.75, tractor 1.0 / 0.95, `race` 1.35 / 1.4, `race-future`
  1.25 / 1.35. `load_sensitivity` per family: 0.10 cars, 0.08 trucks, vans and trailers, 0.12
  tractor.
- Surfaces: `HeightmapTerrain.channel_grip` and `channel_drag` (`src/levels/base/heightmap_terrain.gd`)
  give each paint channel of each level one grip multiplier and one added rolling resistance, the
  same for every tyre. `docs/vehicles.md` § Gradeability: "The surface is also tyre-blind: a lug
  tyre loses the same half of its grip in mud as a road tyre."
- Channel identity is per level: the default names are Grass, Dirt, Sand, Rock, Snow, Mud, Asphalt,
  Gravel (`HeightmapTerrain.DEFAULT_CHANNEL_NAMES`), but levels rename them. Channel 4 is "Snow" in
  the defaults and "Field" where a farm level renames it, and the tractor's draft keys on index 4
  (`TractorVehicle.SOIL_CHANNEL`): adding snow collides with the tractor's soil slot unless surface
  identity stops being an index.
- `RayWheel.tick` multiplies `mu` by `surface_grip` (`grip_at`) and applies `surface_drag`
  (`drag_at`) as a body force at the contact.
- Blocker: "The tyre class (`mu_long` / `mu_lat`) is the root of everything brake-shaped: brake,
  retarder rating, hierarchy floor, taper margin. A mu edit is a re-derivation (recipe + regen),
  never a number edit" (`src/vehicles/CLAUDE.md`). A runtime tyre swap would silently change the
  brake hardware until brief 04 decouples brakes from tyres. The steering-taper margin is also
  checked against `mu_lat` (`test_vehicle_catalog.test_a_steering_taper_never_out_limits_the_tyres`).

## What a useful version needs

- A tyre-class resource: grip-curve shape (peak slip, peak, sliding fraction), `mu_long` /
  `mu_lat`, load sensitivity, rolling resistance, and a response per surface type (grip and drag
  multipliers). In other words, a tyre x surface table instead of one scalar per surface.
- A surface-type identity shared across levels (today channels are per-level names and indices),
  so the table can key on "snow", "mud", "asphalt".
- Real-world shape, for the planner to source: on dry asphalt a winter tyre stops a few to ~15 %
  longer than a summer tyre; on snow a winter tyre has roughly 1.5-2x a summer tyre's grip; on
  ice both are very low (studs help); a lug tyre is weaker on asphalt and much stronger in mud and
  soil.
- Temperature (winter rubber in the cold, summer rubber hardening) needs an ambient temperature
  that does not exist; likely out of scope, say so.
- Selection: a local setting or garage choice; optionally a bridge signal (a contract change,
  `contract-edit` skill). User decision.
- Content: a snow or ice patch on a level to make the difference visible (`level-edit` skill;
  levels are signal playgrounds, root CLAUDE.md).

## What would show the difference

`slip_front` / `slip_rear`, the tractor's `wheel_slip`, `acc_long` under braking, `acc_lat` in a
corner. Car ABS and TC activity is not on the bus today (only `trailer_abs` on the truck), so
making it visible may need a signal, which overlaps brief 13 § 4.

## Constraints

- Surface grip multiplies mu and leaves the 60 Hz clamps alone; `channel_grip` is clamped to
  [0, 1]; `grip_at` pow-sharpens weights like the splat shader; cached decoded images, never
  `get_image()` per tick (`src/vehicles/CLAUDE.md` § Wheels and ground).
- Non-goals (root CLAUDE.md) include "texture-layer terrain"; the splat channels are the existing
  surface mechanism and stay so.
- Load sensitivity becomes a tyre property; brief 08 may already have moved it.

## Done

- Each body declares a default tyre class; the user can swap classes and drive the same patch to
  compare; brakes and other hardware are unchanged by the swap.
- Surfaces respond per tyre class; mud punishes a road tyre more than a lug tyre; a snow patch
  separates winter from summer.

## Open decisions (user)

- Which tyre classes ship, how a swap is offered (local, garage, bridge), and which level gets a
  snow/ice patch.

## Related

Brief 03, 04, 08, 13.

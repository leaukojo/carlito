# TODO

## Tyre classes and surfaces: the user's checks

Feel only (figures: `docs/vehicle_measurements.md` § Tyre classes by surface). Garage TYRES row;
F3 names `tyre` and `surf`. Car Arena pad (pause, SPAWN POINT): `sedan` all-season / winter /
summer on PadSnow, a stop and the Skidpad. Ice pad (`--level=rough_ground`, IcePad; an F6 run has no
shell and fits the stock): studded vs winter. Level 1's wallow: `pickup` all-season
vs Mud. A swap survives a reload on the deployed web build. Grass off any road; level 3's gravel
and `car_lights` (no par).

## Tractor implements: the user's checks

Figures: `docs/heavy_vehicles.md` § Draft, hitch, linkage.

- **Drive level 1's farm playground:** lift and lower the plough (the front lightens, `axle_load`
  rises); cycle the full spreader on with E (the steering lightens); plough across a light band
  (`draft_force` and `engine_load` dip and recover); start with the plough down; lower the harrow
  and the mower on the field and over the wallow's ridges (the roller and the tail wheel ride the
  surface).
- **Run `tractor_plough`** (bridge-driven) on its 25-70 % band and hint; drop `[NOT-TESTED]` from
  its title once it passes.
- **Re-shoot the cards:** the four implement selector cards and level 1's show Cat I machines
  (`gen_vehicle_thumbs.tscn` windowed, `tools/CLAUDE.md` § Rare generators; the level card from the
  Polish tab), then `--import`.

## Aero balance: the user's check

Feel only (`docs/vehicles.md` § Aero balance). `race` on any level with a long fast sweeper: take
it at 200+ km/h. It should turn in without the rear stepping out, and stay planted through the
sweeper. Then lift mid-corner: the nose should tuck in a little, not snap round.

## Crosswind: the user's check

Feel only (`docs/vehicles.md` § Crosswind; figures `docs/vehicle_measurements.md` § Wind). Pause,
CONDITIONS, WIND: STRONG, on any land level. Drive `delivery` into the wind, then with it: the
`engine_load` gauge sits higher, then lower, at the same speed. Then across it: the van drifts
and yaws downwind with the wheel straight, weaving with the gusts. Is it a correction you make
without thinking, or a fight on the keyboard? Repeat in a `sedan`, and in the `semi` with the box.

## Compass and wind direction on the land dashboards

From the crosswind drive check: on a land vehicle you can't see your heading or where the wind
comes from, so drift under CONDITIONS wind is hard to read. Only the boat has a wind rose
(`src/ui/wind_rose.gd`). The dashboard builds it when the vehicle's out-signals carry the whole
`Dashboard.WIND_ROSE_SIGNALS` set (`awa`/`aws`/`twd`/`tws`/`cog`/`sog`), and the contract declares
those for the boat only. Two routes:
- **Contract:** declare a heading and true-wind pair for car, truck and tractor, read from the sim
  (`WindField.at`, the body's basis; `BoatTelemetry.true_wind` already does the FROM conversion),
  and have the dashboard build a compass rose off them. Follow the `contract-edit` skill (version
  bump, sloppyCAN copy). This also puts wind on the bus.
- **UI only:** a compass rose with a wind arrow fed from the level, not the contract. It is
  cheaper, but it would be the first dashboard widget the contract doesn't declare (rule 4).

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

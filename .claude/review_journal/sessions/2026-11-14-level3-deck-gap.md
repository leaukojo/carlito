# 2026-11-14: level_3's deck-to-terrain gap (step 1 of "ground under a deck")

Item: the Queue's top line, step 1. Throwaway tool scene (deleted after the run) instantiated
`level_3.tscn`, and for each of the 30 `RoadsBarrierTiles` cells took the `RoadsTiles` cell's deck
top (`to_global(map_to_local) + mesh AABB end.y`, cell origin -0.22) against
`HeightmapTerrain.height_at` over the cell's 12 x 12 footprint on a 1 m grid.

## Result: the case exists on level_3; the item stays open

- 15 barrier cells sit on flat terrain: deck top 12.02, terrain 11.84 over the whole footprint,
  so **ground 0.18 m under the deck top**, under every rail (cells (9,4,17), (9,4,16),
  (-12,4,-7..-4), (-1,4,7), (-3,4,7), (-1,4,9), (1,4,7), (-1,4,5)).
- 6 more hold 0.26 to 0.33 m at their lowest-gap corner (deck top 18.02 / 24.02 on terrain
  17.76 / 23.69: (12..15, 6, 17), (15, 8, 14), (15, 8, 13)).
- The rest are overpass or ramp cells with the terrain metres below (5.6 to 18 m) and a few that
  cross it (ramp ends: terrain 10.36..14.95 under one tile).
- The barrier mesh is 0.96 m tall (`barAABB` size y), the deck mesh bottom is at the cell's base
  (11.78), 6 cm under the terrain: from a wheel's side the terrain is within travel under the
  deck top, as in the fixture, with the gap 0.18 instead of 0.05.

Not measured: the wheel's own result at a 0.18 gap (the fixture in `2026-11-14-f2-own-body-wall.md`
§ The second trigger takes 0.07 / 0.05; whether a wheel's travel reaches 0.18 under the deck
depends on the body), and whether the sample's 1 m grid hits the rail strips exactly.

## Next

Step 2 of the Queue line stands. Its fixture with the second flat at 0.18 rather than 0.05 below
the deck is the first thing to run, per body (`race`, `sedan`, `tractor-kenney`).

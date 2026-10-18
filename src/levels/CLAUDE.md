# Levels & water — rules

- **Auto-splat on level 1 wipes hand paint.** It reclassifies channels 0..3 and zeroes
  `splatmap2` on purpose, so it wipes Field (`Surface.FIELD`, the tractor's soil), Mud, Gravel and
  the road asphalt. The recovery is to replay the level's chain.
- **A level's generator chain is a committed manifest**, `src/levels/**/<id>_gen.json`, the ONE
  copy: a generator edit moves it in the same commit. Replay with
  `powershell -File tools/rebuild_level.ps1 -Level <id>`; `"replayable": false` (levels 2-4)
  refuses without `-Force`. Not a CI gate: a replay takes minutes and rewrites committed content.
- **The water column is `Sea.y` over a pan `island_falloff` clamps to 0.** Level 6's sea is at
  y=6 (`gen_skyport.gd`'s `SEA_Y`); `depth` and `sand_height` move with it or read wrong silently.

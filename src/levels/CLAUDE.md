# Levels & water — rules

- Auto-splat on level 1 wipes hand paint on purpose (Field, Mud, Gravel, road asphalt: it
  reclassifies channels 0..3 and zeroes `splatmap2`); recover by replaying the level's chain.
- A level's generator chain is its committed manifest, `src/levels/**/<id>_gen.json`: a generator
  edit moves it in the same commit. Replay: `powershell -ExecutionPolicy Bypass -File
  tools/rebuild_level.ps1 -Level <id>` (`"replayable": false` refuses without `-Force`).
- The water column is `Sea.y` over a pan `island_falloff` clamps to 0. Level 6's sea is at y=6
  (`gen_skyport.gd`'s `SEA_Y`); `depth` and `sand_height` move with it or read wrong silently.

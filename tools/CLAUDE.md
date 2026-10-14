# Tools — rules and run lines

Editor/CI scripts. Kit/bake rules: `kit/CLAUDE.md` (read it before touching a bake or level
generator). Headless gotchas (`--script` mode, float32, freed nodes): root `CLAUDE.md` § Running.

- **A level generator's chain lives in its manifest**, `src/levels/**/<id>_gen.json`
  (`src/levels/CLAUDE.md`); a generator edit moves the manifest in the same commit.
  `powershell -File tools/rebuild_level.ps1 -Level <id>` replays it (`-DryRun` prints the chain).
- **Boat collision survives a regen by the same whitelist as Kenney's** (`kenney/CLAUDE.md`):
  `gen_boat_variants.gd` owns only `GENERATED_CHILDREN`.
- **Thumbnail generators run WINDOWED** (a headless capture is blank) and never in CI. The four
  (`gen_thumbs`, `gen_level_thumbs`, `gen_vehicle_thumbs`, `gen_challenge_thumbs`) share
  `shot_stage.gd`. Their PNGs are not byte-deterministic: compare a re-run with `png_drift.gd`,
  not a byte diff.
- **Never speed a measure tool up with `Engine.time_scale`**: it enlarges the physics step
  (`measure_vehicles.gd`). Pass `--fixed-fps 60` before `--` instead: same tick, byte-identical
  output, ~10x faster (`measure_semi_launch` 40 s -> 4.5 s).

## Rare generators

```powershell
# palettes/prefabs (after kit/import recipe edits only)
& $GODOT --headless --path . --script res://tools/gen_kit_assets.gd
# kit thumbnails (windowed), re-import, then regen to embed the previews
& $GODOT --path . res://tools/gen_thumbs.tscn ; & $GODOT --headless --path . --import
& $GODOT --headless --path . --script res://tools/gen_kit_assets.gd
# vehicle selector cards (windowed; every variant + implement/trailer), then re-import
& $GODOT --path . res://tools/gen_vehicle_thumbs.tscn ; & $GODOT --headless --path . --import
# Kenney / watercraft bodies (after a recipe edit)
& $GODOT --headless --path . res://tools/gen_kenney_vehicles.tscn
& $GODOT --headless --path . res://tools/gen_boat_variants.tscn
# drone-mk2 model (Blender 5.1; only to regenerate, the GLBs are committed), then re-import
& "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --factory-startup --python tools/gen_drone_model.py
```

## Measure tools

Dev reports, not tests; reading guide and figures: `docs/vehicles.md` § Measuring a vehicle.
Long sweeps (`all`, `baseline`) take minutes. The doc's figure tables are generated: a `doc=<id>`
preset runs that table's fixed set and rewrites its `<!-- measure:<id> -->` region
(`doc_region.gd`); refresh a figure by re-running, never by hand.

```powershell
# accel / top speed / tracking on a flat full-grip strip. Arg 1: variant or `all` (default
# sedan-sports); arg 2: time cap in s. Flags: coast, track, strict, corner, brake,
# trailer=<name|bobtail>, tc (accel pass slip-limited at the grip peak). `stall` (both pedals
# floored in manual D1, TC off, 10 s) and `handbrake` (60 km/h steer step, with and without the
# lever) replace the other passes.
& $GODOT --headless --path . res://tools/measure_vehicles.tscn -- sedan-sports 45
# launch trace + gates on the accel pass: trace[=<every n ticks>] trace_s=<s printed, 3>; notc (the
# body's TC off), gear=<1-6> (manual, held in that byte); not with a doc= preset
& $GODOT --headless --fixed-fps 60 --path . res://tools/measure_vehicles.tscn -- semi 40 trace notc
# the trace's launch held at a part pedal (its settle, gates and shift lines; `trace` adds the ticks)
& $GODOT --headless --fixed-fps 60 --path . res://tools/measure_vehicles.tscn -- sedan 90 pedal=0.3
# part-pedal probes, instead of every other pass, at each speed of the family's set from a
# standstill: cruise (PI pedal settled), kickdown (stepped to 1), pulse[=<period s>] duty=<0..1>
& $GODOT --headless --fixed-fps 60 --path . res://tools/measure_vehicles.tscn -- sedan 90 cruise kickdown pulse
# the CI `tracking` gate: skips the accel pass, exits 1 on a FAIL
& $GODOT --headless --path . res://tools/measure_vehicles.tscn -- all 45 track strict
# drone: hover / climb / lean / endurance / one-motor-out (no args, ~1 min)
& $GODOT --headless --path . res://tools/measure_drone.tscn
# coupled semi launch: steer-axle load, pitch, air gate, step-steer rollover (~30 s; flags
# trailer=<box|tanker|tipper|flatbed|bobtail> tip_kmh=<km/h> ramp front_z= com_z=; strict = the CI gate)
& $GODOT --headless --path . res://tools/measure_semi_launch.tscn -- semi
# a truck losing its air: parked on 18 %, floored in D, cut at 30 km/h. Arg 1: garbage-truck,
# semi, semi-conventional or `all`; `strict` = the CI gate (~1.5 min)
& $GODOT --headless --fixed-fps 60 --path . res://tools/measure_air_loss.tscn -- all strict
# steepest standing-start grade. Arg 1: variant, `all` or `level=<id>`; then surfaces
# (asphalt gravel grass dirt field mud; none = all); flags mfwd diff tc verbose hold=<deg> pedal=<0..1>
# gear=<1-6> (manual, held in that byte: a start gear; roll-back too)
& $GODOT --headless --path . res://tools/measure_grade.tscn -- tractor-kenney mud mfwd tc
& $GODOT --headless --path . res://tools/measure_grade.tscn -- level=level_2
# converter creep: released in D1 with no pedal, the flat creep speed and the steepest grade held
# (a converter variant or `all`; ~1 min a body)
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- sedan creep
# roll-back: released on a grade after the foot-brake settle, floored delay=<s> later (0.5); the
# roll-back, the time to 0.1 m forward and how long the hill hold held. Flags grade=<%> (else 10
# and 25), pedal=<0..1>, nohold (the hold off), tipper (the tractor's drawbar tipper), mfwd, surface,
# verbose (per-axle tyre force and slip, and the trailer's pull, every 0.5 s)
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- sedan rollback nohold
# a climb in automatic D on a fixed grade (`grade=<%>`, 8) at a held pedal (`pedal=`, full), 40 s
# or the ramp's top: each shift with the gearbox's road load, and a `falls back` gate (an upshift
# a later downshift undoes); flags tipper, mfwd, a surface
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- semi climb grade=8 pedal=0.6
# held at rest for 60 s on a grade (deg): foot brake, `hand`, `pawl` (P alone), or across the slope `cross`
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- sedan park=5.7 hand
# bumps and ditches, asphalt and mud. Arg 1: variant or `baseline`; flags mfwd diff tc
# speed=<m/s> lane= patch= verbose
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_rough.tscn -- baseline
# rewrite docs/vehicles.md's figure tables (each a few minutes)
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_vehicles.tscn -- doc=braking
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_vehicles.tscn -- doc=cornering
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_vehicles.tscn -- doc=accel
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_vehicles.tscn -- doc=cruise
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- doc=grade
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- doc=park
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_rough.tscn -- doc=rough
```

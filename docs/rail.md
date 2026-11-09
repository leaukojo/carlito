# Train & rail

Rules sit at their site: `train.gd`, `train_sim.gd`.

- Protocol flavor `"train"` (in `pantograph`/`doors`; out `pantograph_state`/`doors_state`/
  `catenary_volts`/`motor_current`/`brake_pipe`/`grade`/`coupler_force`). No real rail CAN
  standard adopted — trains run IEC 61375, not CAN (CiA 421/rail practice is inspiration
  only). No `steer` (rail-guided); no `rpm`/`fuel`/`coolant` (electric). Reverser (N/D/R)
  rides `gear`.
- `TrainVehicle extends BaseVehicle` (`src/vehicles/train/`): no ground drive, one gear ratio
  (the reverser's D never shifts, `test_train`), only the two seams. Consist is the Kenney bullet loco + wagons at
  world scale 2.4; self-places on a closed rail loop in `_ready`, ignores `VehicleSpawn`
  markers.
- `TrainSim`, `TrainPlacement` and `TrainTelemetry`: their file headers in `src/vehicles/train/`
  (tested `tests/test_train.gd`). The loco is kinematic; `BaseVehicle._update_telemetry` still
  reads honest motion. Traction live only with key Ignition + pantograph raised; doors open only
  at standstill.
- Traction (`TrainSim.tractive_effort`): the lesser of the head's grip, `mu_adh` × head mass × g,
  and constant power, `power_to_mass` × consist mass ÷ v (sourced: `docs/sources.md`, The train's
  pull). From rest on the flat (Davis is zero there) the consist starts at `mu_adh` × head mass /
  consist mass × g ≈ 0.92 m/s², inside the sourced 0.72–1.0
  (`test_the_consist_starts_inside_the_sourced_range`). The reverser gates it: a bridge N with
  `accel` held pulls nothing (`TrainVehicle.reverser_throttle`).
- Brakes: the lever vents `brake_pipe` and the train brake reads the pipe
  (`TrainTelemetry.pipe_brake_demand`); full service stays above the contract's warn, so the warn
  means emergency (`docs/sources.md`, The train's brake pipe). The parking brake is off the pipe.

## Rail runtime

- `RailTrack` (`src/levels/base/rail_track.gd`, its header): rails are authored as `RoadPath` +
  `RailProfile`. `RailTrack.find_closed_rail(root)` is the one shared walk (`Level` and `TrainVehicle` both
  call it); an open rail is never accepted.
- Train is the only family declaring `gear` out without `rpm`: bespoke `REVERSER N/D/R`
  centre readout, not the tacho.

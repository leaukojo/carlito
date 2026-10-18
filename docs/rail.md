# Train & rail

Rules sit at their site: `train.gd`, `train_sim.gd`.

- Protocol flavor `"train"` (in `pantograph`/`doors`; out `pantograph_state`/`doors_state`/
  `catenary_volts`/`motor_current`/`brake_pipe`/`grade`/`coupler_force`). No real rail CAN
  standard adopted — trains run IEC 61375, not CAN (CiA 421/rail practice is inspiration
  only). No `steer` (rail-guided); no `rpm`/`fuel`/`coolant` (electric). Reverser (N/D/R)
  rides `gear`.
- `TrainVehicle extends BaseVehicle` (`src/vehicles/train/`): no ground drive, 6
  `gear_ratios` kept, only the two seams. Consist is the Kenney bullet loco + wagons at
  world scale 2.4; self-places on a closed rail loop in `_ready`, ignores `VehicleSpawn`
  markers.
- `TrainSim` (pure, `tests/test_train.gd`): 1D consist, each car a mass at an arc position
  on the rail `Curve3D`, per-car grade/Davis resistance/brake, traction on the loco only,
  spring-damper couplers with slack, own one-tick 60 Hz clamp discipline.
  `TrainPlacement.car_pose` poses each car from bogie samples `s ± bogie_half_spacing`,
  basis right-handed (det +1), guarded by a test. Loco driven kinematically (`gravity_scale
  = 0`, sim writes `global_transform`); `BaseVehicle._update_telemetry` still reads honest
  motion. Wagons are `AnimatableBody3D` followers.
- `TrainTelemetry`: `brake_pipe` toward 5 bar, vents on application; `catenary_volts` = 25
  kV nominal minus sag ∝ current; `motor_current` from traction; `grade` (i8 %) from the
  tangent; `coupler_force` (kN) off the head coupler. Traction live only with key Ignition +
  pantograph raised; doors open only at standstill.

## Rail runtime

- `RailTrack` (`src/levels/base/rail_track.gd`): rails are authored as `RoadPath` +
  `RailProfile`; the baker emits a runtime `RailTrack` (duplicated curve, gauge, closed
  flag, world transform), or unbaked play reads `RoadPath` directly.
  `RailTrack.find_closed_rail(root)` is the one shared walk (`Level` and `TrainVehicle` both
  call it); an open rail is never accepted.
- Train is the only family declaring `gear` out without `rpm`: bespoke `REVERSER N/D/R`
  centre readout, not the tacho.

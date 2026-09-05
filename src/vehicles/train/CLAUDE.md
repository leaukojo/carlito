# Train — gotchas & hard-won rules

Descriptive tour: `docs/vehicles.md` § Train & rail.

- The train (`src/vehicles/train/`) is a real BaseVehicle subclass like the boat: empty
  `wheel_positions`, the 6 `gear_ratios` kept (the reverser N/D/R rides the gear byte). It never
  forks `_physics_process`. Locomotion is a 1D consist sim (`TrainSim`) on the level's rail curve;
  the loco is driven **kinematically** (`gravity_scale = 0`, the sim writes `global_transform` +
  linear/angular velocity each tick so `_update_telemetry` still reads honest motion). Wagons are
  `AnimatableBody3D` followers posed by `TrainPlacement`. Aux systems are honest labelled models in
  `TrainTelemetry`, not circuits. `TrainSim`'s coupler/brake clamps are 60 Hz stability — **don't
  weaken them**. Respawn re-lays the consist at `s = 0` via `_sim.setup(...)` (velocity-zeroing
  alone leaves it halted where it drifted). It self-places on a closed rail in `_ready` and ignores
  `VehicleSpawn` markers — see the rails note in `kit/CLAUDE.md` for the shared `find_closed_rail`
  walk.

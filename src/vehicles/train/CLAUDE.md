# Train — rules

Tour: `docs/vehicles.md` § Train & rail.

- The loco is driven **kinematically only when `_has_rail`** (the sim writes `global_transform`
  and velocities, so `_update_telemetry` still reads honest motion). With no closed rail it keeps
  gravity and falls rather than levitating inert; `_ready` warns.
- `TrainSim`'s coupler/brake clamps are 60 Hz stability: never weaken them.
- Respawn re-lays the consist at `s = 0` via `_sim.setup(...)`; zeroing velocity alone leaves it
  halted where it drifted.
- It self-places on a closed rail (`RailTrack.find_closed_rail`) and ignores `VehicleSpawn`.

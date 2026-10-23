# TODO

## RAMN firmware: gear bytes past 6 (outside this repo)

Carlito's `gear` byte runs D1-D24 (contract v52), and sloppyCAN reads its top off the contract
(`docs/plans/drivetrain_control.md` phase 4). Flash only once v52 is on stable. RAMN's shift
joystick stops at `MAX_GEAR_VALUE` 0x06 (`../RAMN/firmware/RAMNV1/Core/Inc/ramn_vehicle_specific.h`).
Raise it to 0x18, then check:
- the joystick step (`ramn_sensors.c`: R 0xFF wraps up to N 0, and the top clamp);
- the simulator's random shift command (`ramn_simulator.c`, `% (MAX_GEAR_VALUE + 1)`);
- SPN 525 / 523 (`ramn_can_database.c`: the +125 offset fits 24);
- the DBC ranges (`misc/busmaster_ramn.dbc`, `misc/busmaster_ramn_j1939.dbc`);
- the CARLA scripts, which pass the byte to `control.gear` (`scripts/carla/`): a CARLA car has
  far fewer gears.

Flash it only after Carlito's gear contract is on stable: an older Carlito reads a manual-mode
drive byte past 6 as N (`Drivetrain.normalize_byte`).

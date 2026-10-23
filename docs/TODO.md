# TODO


## RAMN firmware: gear bytes past 6 (outside this repo)

Carlito's `gear` byte runs D1-D24 (contract v52), and sloppyCAN reads its top off the contract
(`docs/vehicles.md`, `Drivetrain`). RAMN's shift joystick stops at `MAX_GEAR_VALUE` 0x06 (`../RAMN/firmware/RAMNV1/Core/Inc/ramn_vehicle_specific.h`).
Raise it to 0x18, then check the joystick step and top clamp (`ramn_sensors.c`), the random shift
(`ramn_simulator.c`), SPN 525 / 523's +125 offset (`ramn_can_database.c`), the DBC ranges
(`misc/busmaster_ramn*.dbc`), and the CARLA scripts' `control.gear` (`scripts/carla/`).

Flash it only after Carlito's gear contract is on stable: an older Carlito reads a manual-mode
drive byte past 6 as N (`Drivetrain.normalize_byte`).

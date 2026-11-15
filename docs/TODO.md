# TODO

## Tractor: an R-4 industrial tyre class
A TRACTOR-fit `TyreCatalog` class beside `ag_lug.tres` (the picker shows from two): better on
asphalt/gravel, worse in field/mud; factors estimated (`docs/vehicles.md` § Tyres and surfaces).

## Touch: the engaged DIFF LOCK caption overflows its pad
"DIFF LOCK ON" is 104 px in Barlow at `UiTheme.FS_BODY`, over the 96 px `BTN_SIZE` pad
(`touch_controls.gd`, `_show_on`); a wider pad or a shorter engaged caption.

## RAMN firmware: gear bytes past 6 (outside this repo)

Carlito's `gear` byte runs D1-D24 (contract v52), and sloppyCAN reads its top off the contract
(`docs/vehicles.md`, `Drivetrain`). RAMN's shift joystick stops at `MAX_GEAR_VALUE` 0x06 (`../RAMN/firmware/RAMNV1/Core/Inc/ramn_vehicle_specific.h`).
Raise it to 0x18, then check the joystick step and top clamp (`ramn_sensors.c`), the random shift
(`ramn_simulator.c`), SPN 525 / 523's +125 offset (`ramn_can_database.c`), the DBC ranges
(`misc/busmaster_ramn*.dbc`), and the CARLA scripts' `control.gear` (`scripts/carla/`).

Flash it only after Carlito's gear contract is on stable: an older Carlito reads a manual-mode
drive byte past 6 as N (`Drivetrain.normalize_byte`).

## ISOBUS

SloppyCAN side: **The trailer's ISO 11992 frames are not built from the standard.** ISO 11992-2 is paywalled,
  so the two identifiers (EBS21 = PGN 768, EBS22 = PGN 65220) come from secondary sources only.
  The trailer's axle load and brake demand aren't sent at all: no available source gives their
  scaling. If you have the standard, a correction is very welcome.
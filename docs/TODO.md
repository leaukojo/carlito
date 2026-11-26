# TODO

## Tractor: an R-4 industrial tyre class
A TRACTOR-fit `TyreCatalog` class beside `ag_lug.tres` (the picker shows from two): better on
asphalt/gravel, worse in field/mud; factors estimated (`docs/vehicles.md` § Tyres and surfaces).

## Touch: the engaged DIFF LOCK caption overflows its pad
"DIFF LOCK ON" is 104 px in Barlow at `UiTheme.FS_BODY`, over the 96 px `BTN_SIZE` pad
(`touch_controls.gd`, `_show_on`); a wider pad or a shorter engaged caption.

## Guide, forces widget: the sedan tips forwards at full brake

At 90 % brake or more the page lifts the `sedan`'s rear wheels ("close to tipping over
forwards"). The game doesn't: its full-pedal stop (`docs/vehicle_measurements.md` § Braking)
stays just under the rear's lift point, the rear barely loaded. The Kenney body's rear unloads at
(CoM-to-front-axle / CoM height) times g, about its tyres' grip (CoM 0.63 m behind the front
axle, 0.61 m high, 1.58 m wheelbase; a real sedan's point is about twice its grip, from memory).
The game's `load_sensitivity` (`RayWheel.load_scaled_mu`) keeps the loaded fronts under that
line; the page leaves load sensitivity out and brakes past it. The same short body exaggerates the
"Braking in a turn" example. Investigate: port `load_scaled_mu` into `docs/guide/widgets/forces.js`'s
tyre model, re-check every example (each must still show what its name says) and the arrow
sums, drop load sensitivity from the page's "What this page leaves out", and consider one
sentence on the Kenney cars' short wheelbases.

## RAMN firmware: gear bytes past 6 (outside this repo)

Carlito's `gear` byte runs D1-D24 (contract v52), and sloppyCAN reads its top off the contract
(`docs/vehicles.md`, `Drivetrain`). RAMN's shift joystick stops at `MAX_GEAR_VALUE` 0x06 (`../RAMN/firmware/RAMNV1/Core/Inc/ramn_vehicle_specific.h`).
Raise it to 0x18, then check the joystick step and top clamp (`ramn_sensors.c`), the random shift
(`ramn_simulator.c`), SPN 525 / 523's +125 offset (`ramn_can_database.c`), the DBC ranges
(`misc/busmaster_ramn*.dbc`), and the CARLA scripts' `control.gear` (`scripts/carla/`).

Flash it only after Carlito's gear contract is on stable: an older Carlito reads a manual-mode
drive byte past 6 as N (`Drivetrain.normalize_byte`).

## ISOBUS: trailer ISO 11992 frames from the standard (sloppyCAN side)

ISO 11992-2 is paywalled, so EBS21 (PGN 768) and EBS22 (PGN 65220) come from secondary sources
only, and the trailer's axle load and brake demand aren't sent: no open source gives their scaling.

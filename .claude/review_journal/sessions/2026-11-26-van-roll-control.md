# 2026-11-26: roll-over control on the heavy vans (`delivery`, `delivery-flat`, `ambulance`)

Item: the Queue's approved line (user, 2026-11-20). Started at 1fd084e. Method as the trucks'
(`2026-11-20-truck-roll-control.md`): each body's first-lift `acc_lat` in `measure_vehicles`'
`corner` pass (ESC off), the table in the generator, regen.

## First lift, `measure_vehicles -- <variant> 60 track corner noesc` (40 km/h, 10 s wind-on)

| Body, kg | first lift | corner peak (`v r` / path) | saturates | roll at peak | inner wheel at no load |
| --- | --- | --- | --- | --- | --- |
| `delivery` 4200 | never | 0.73 / 0.72 g | front (0.98, rear 0.77) | 2.8 deg | 1 |
| `delivery-flat` 4000 | never | 0.73 / 0.72 g | front (0.98, rear 0.78) | 2.5 deg | 1 |
| `ambulance` 4800 | never | 0.75 / 0.74 g | front (0.98, rear 0.81) | 2.9 deg | 0 |

## Baseline at HEAD, `-- <variant> 60 step` (ESC on, 30 / 60 / 100 km/h)

No wheel lifts in any of the 18 cells on any van; roll peaks 2.4 (`delivery`), 2.2
(`delivery-flat`), 2.2 deg (`ambulance`). One `UNSETTLED` (ambulance 60 km/h 30 % held, speed 0.026
against a 0.02 gate), a settling gate, not a roll.

## Stop condition hit

The approved line: "Stop and ask if a van slides before any wheel lifts (no figure)". All three do:
the front tyres saturate at 0.72-0.74 g before an inner wheel leaves the road. There is no first-lift
g to key a table on. Asked the user.

## Closed (user, 2026-11-26: "Close: no table")

The vans slide before they tip, so roll stability has nothing to act on; yaw ESC covers them. No
code or doc change: `test_vehicle_catalog`'s roll test (truck family with ESC) and the docs' "the
trucks" stay true. Not queued: a check of the vans' tip threshold (`com_y`, `mu_lat` on a laden
box van) was offered as a proposal and not chosen.

Noted for the answer: `StabilityControl.roll_chamber_step` models air brake chambers
(`CHAMBER_FILL_S`, R13 / FMVSS 121 air figures); the vans brake hydraulically, so a van table would
also put an air chamber's lag on a hydraulic brake. No spec field says which brakes a body has.

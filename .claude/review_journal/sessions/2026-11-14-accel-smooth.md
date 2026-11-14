# 2026-11-14: `BaseVehicle.ACCEL_SMOOTH`, model or cover (diagnose only, no runs)

Started at e42feba. Read-only: code, `git log -S`, yesterday's table. Nothing measured today.

## Verdict: a cover on the contract's `accLong` / `accLat` / `acc_vert`

No place that states it names a real part or a source; the one reason given is a symptom.

- Constant, `src/vehicles/base/base_vehicle.gd:20`: "1/s exp rate the reported long/lat accel
  tracks raw". What it does, not why. No source for 10 /s.
- Added in 06a6f65 "Initial commit": no reason. 885a5a1 and ed80c4f move text only; 5d09ed8 adds
  the second use below.
- `docs/guide/position.md:64`: "The readings are smoothed a little, so a single bump does not
  swamp them." A symptom.
- Contract: `accLong` is "Longitudinal acceleration.", `accLat` "Lateral acceleration.": the lag
  is not declared. `acc_vert` says "smoothed at the same rate", with no reason. Standing rule 3
  wants telemetry read out of the sim, and a model labelled.
- Tests: none names the constant.

## What it hides (measured 2026-11-13, `sessions/2026-11-13-f1-standing-rock.md`)

Standing `semi` bobtail: raw accel 2.435 m/s2 p-p alternating every tick, 0.202 as sent (8 %).
That source is F1's (`docs/plans/parked_rocking.md`), not this finding's. Not measured: what the
raw first difference (`VehicleTelemetry.body_accel`) carries while driving, on other bodies.

## The second use is a different case

`src/vehicles/base/towed_body.gd:208` lags `TowedBody.accel_lat` with the same constant. Its
comment says what it stands for ("its EBS's sensor ... smoothed as telemetry `acc_lat` is") but
gives no source for the rate, and it borrows the cover's number. Roll-over control and the lift
table (`measure_semi_launch`, `ground_drive_spec.gd:167`) read it, so touching it changes driving
and re-measures the table. Sorted: a model by its claim, with an unsourced constant. The proving
run leaves it alone.

## Queued

One line in `summary.md`: proving run on line 280 only, trace the driving-state content, ends in
a proposal (contract signal). No new filter.

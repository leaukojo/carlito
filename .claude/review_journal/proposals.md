# Proposals

Changes that need the user's decision. One entry each: what, evidence, cost, risk. An approved
entry moves to the Queue in `summary.md`; a refused one is deleted.

## The wheel and the body exchange one force (2026-11-13, from F1)

- **What.** The body takes the tyre's force at the slip the wheel's settled spin step ends on,
  instead of the slip the tick started on; the step's stiffness at zero slip comes from the grip
  curve's first slope; `RayWheel.road_change` and its fade go (F1's plan as first approved, before
  the shared cap replaced it). Never a filter on a reading or a signal.
- **Evidence.** `sessions/2026-11-13-f1-standing-rock.md`. On a free wheel the tyre force puts the
  contact on the rim's speed (0.93 to 0.99 of its one-tick cap) in the tick the spin step puts the
  rim on the road's (within 0.03 to 0.04), so the slip reverses every tick and decays about 5 % a
  tick. With the rolling drag's fault fixed (d849de9) that ring is left with nothing feeding it.
  Standing in D (`measure_semi_launch -- <unit> [trailer=bobtail] steady`, `rest reading:`,
  `sessions/2026-11-13-f1-rest-guard.md`): laden `semi`, `axle_load` steps 0.81 kg a tick and the
  dashboard's whole-kg AXLE number changes on 73 % of ticks; bobtail, 0.46 kg and 6.7 speed sign
  changes a second; `semi-conventional` 0.00 laden, 0.34 kg bobtail. The gate's limits
  (`REST_FLIPS_S`, `REST_STEP_KG`) are sized over this ring and come down with it. Derived, not measured: with the
  pedal down below `LOW_SPEED_FLOOR` the body gets `T / ((1 + a) r)`, `a` the force's share of its
  cap, up to half the drive; `road_change` patches that above 3 m/s only.
- **Cost.** `wheel.gd`'s tick reordered (the force along the wheel applied after `settle_spin`),
  `wheel_drive.gd` and `towed_body.gd` with it; `test_wheel_spin`'s 51 `_integrate_spin` and
  `road_change` call sites read again; `docs/vehicles.md` § Spin step, § Following the body and
  § One-tick caps rewritten; every `doc=` table re-run, since launches, stops and crawls can move.
- **Risk.** It is the centre of the vehicle sim. A near design is on the rejected list (a
  predicted-slip cap alternates the force 0 / 2x, 7b6d3be): this one must be shown not to, on a
  crawl trace, before anything lands. Prototype first, uncommitted, with before and after runs.
  [xhigh, plan]

## accLong / accLat / acc_vert: raw or a declared sensor filter (2026-11-14)

- **What.** `BaseVehicle.ACCEL_SMOOTH` (10 /s lag, `base_vehicle.gd:280`) has no source; its one
  reason is "so a single bump does not swamp them" (`docs/guide/position.md`). Either (a) send
  `body_accel` raw and drop the constant, or (b) keep a lag as the accelerometer's own filter,
  with a time constant from a sensor datasheet page actually opened, declared in the three
  contract descriptions (`/contract-edit`) and `position.md`. Either way `TowedBody.accel_lat`
  stops borrowing it: it takes (b)'s figure, or its own sourced EBS sensor rate. Recommended:
  (a), unless a source is found, since nothing is left for it to hide.
- **Evidence.** `sessions/2026-11-14-accel-smooth-proof.md`. Standing at HEAD, raw p-p 0.001
  m/s2 (`semi`, `tractor-kenney`). Driving, tick-rate amplitude 0.000 to 0.015 m/s2 at held
  speeds on `sedan-sports`, `semi`, `tractor-kenney`; the large raw-vs-sent gaps are real jolts
  (landings, shifts) cut to about half. One source left: the tractor's launch under 3 m/s,
  0.11 to 0.28 m/s2, the speed band of `road_change`'s fade (the proposal above).
- **Cost.** (a): three lines and a constant; `position.md`'s "smoothed a little" sentence and its
  citation; `acc_vert`'s contract `desc` ("smoothed at the same rate", `/contract-edit`) and the
  `vehicle_telemetry.gd:80-81` comments; `measure_vehicles` corner and sine passes and `measure_semi_launch`'s `acc_lat_g`
  read it, so the `doc=cornering` table re-runs. (b) adds the contract edit and the source hunt.
- **Risk.** Player-visible: a raw `accLat` reads a shift or kerb jolt at full size, and
  `car_corner_budget`'s 4.0 m/s2 limit fails on the first such tick (the steady corner itself
  moves by under 0.1 m/s2). The challenge's limit or hint may want a look after (a). A bridge
  consumer sees the tractor's launch ring at full size until the proposal above lands.
  [medium, plan, Opus]

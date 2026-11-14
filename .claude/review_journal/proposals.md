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

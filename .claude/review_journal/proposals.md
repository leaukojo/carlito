# Proposals

Changes that need the user's decision. One entry each: what, evidence, cost, risk. An approved
entry moves to the Queue in `summary.md`; a refused one is deleted.

## The wheel and the body exchange one force (2026-11-13, from F1; diagnosed 2026-11-14)

- **What.** The body takes the tyre's force at the slip the wheel's settled spin step ends on,
  instead of the slip the tick started on; the step's stiffness at zero slip comes from the grip
  curve's first slope; `RayWheel.road_change` and its fade go. Never a filter on a reading or a
  signal. The brief is the Queue's line of the same title (`summary.md`).
- **Evidence.** `sessions/2026-11-14-wheel-body-one-force.md` (the cause as a map of two speeds,
  and a prototype run and reverted). Today the wheel reacts the force at its end slip and the
  body takes the force at the start slip: two forces for one contact. Free, the slip reverses
  every tick. Driven under `LOW_SPEED_FLOOR`, the body gets `1 / (1 + a)` of the drive (`a` the
  share of the slip the body closes in a tick) and the take-up alternates; `road_change` patches
  that above 3 m/s only. Measured, HEAD then prototype:
  - `tractor-kenney` floored: at the same clutch torque 0.33 -> 0.45 g; the take-up's `a g` reads
    0.12, 0.04, 0.13, 0.09 a tick at HEAD and rises every tick with the prototype;
  - `semi` bobtail: 0-2 m/s 0.833 -> 0.550 s, 0-5 m/s 1.600 -> 1.250 s;
  - `sedan`: 0-50 km/h 3.47 -> 3.20 s, 0-100 8.28 -> 8.03 s, top speed the same; full-pedal stop
    from 100 km/h 41.6 -> 40.7 m, 30 % 157.3 -> 156.1 m;
  - standing bobtail `semi`, `rest reading:` 1.3 -> 0.3 speed sign changes a second, 0.12 ->
    0.08 kg a tick; the ring left after the spawn drop is gone by the third second (HEAD: still
    0.01 mm/s a tick at the ninth).
  Not the ring, so not fixed by this: the laden `semi`'s 0.7 kg a tick on `axle_load` (0.6 with
  the prototype); it goes to the towing diagnosis.
- **Cost.** `wheel.gd`'s tick split (the patch's force applied after `settle_spin`), one loop in
  `wheel_drive.gd`, nothing in `towed_body.gd`; `test_wheel_spin`'s 56 `_integrate_spin`,
  `settle_spin` and `road_change` sites read again; `docs/vehicles.md` § Spin step, § Following
  the body and § One-tick caps rewritten; every `doc=` table re-run. With it go the measure
  gate's two-tick means, `docs/handling.md:94` and the report's "(two-tick mean)" (cover sweep 2),
  and the bobtail's share of `REST_FLIPS_S` / `REST_STEP_KG`.
- **Risk.** It is the centre of the vehicle sim, and every launch gets quicker by about a quarter
  of a second (the drive the step loses today under 1.5 m/s). Not run with the prototype: parking,
  creep, roll-back, cornering, a coupled launch, the suite. A near design is on the rejected list
  (a predicted-slip cap alternates the force 0 / 2x, 7b6d3be): the session file shows why this
  one does not, and the three ways it would (keeping `road_change`, no stiffness at zero slip,
  the secant's force on the body). [high, plan, Opus]


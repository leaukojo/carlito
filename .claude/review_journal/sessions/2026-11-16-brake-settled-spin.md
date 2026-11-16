# 2026-11-16: A6, `brake_settled_spin` relabel (Sonnet)

Finding (from `2026-11-15-wheel-leftovers.md` finding 2): the `COMPROMISE` is a design choice. The
settled spin is the angle the wheel turns in the tick, so the brake's heat on it is the step's own
work; with the tyres' slip read on the same spin the ledger closes to second order. The mean over
the settle counts the spin the road lent the step (5 % of an ABS stop).

Fix: `wheel.gd:141-148` comment, label dropped, reason and known edge stated (a wheel the brake
stops off the ground inside one tick heats nothing). No code change.

Run: `measure_grade -- sedan stops` (10 stops, 100.1 km/h -> 41.0 m): energy check
`brakes / (drop - the rest)` 0.986 every stop, i.e. residual 1.4 %, PASS (±5 %); tyre slip 0.046 MJ
of the 0.459 MJ drop.

`check_docs` passes. `COMPROMISE` count in `src kit tools tests`: 34 -> 33 (docs 22, unchanged:
no doc text names this one).

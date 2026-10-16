# Plan — Wheel contact: crawl-speed caps and the patch under the hub

`RayWheel` reads its contact patch's velocity about the centre of mass (`VehicleMath.point_velocity`).
That velocity now includes the pitch and roll the patch's own force turns. The one-tick caps
therefore have to be sized off what the contacts really move (`RayWheel.contact_masses`), or a crawl
rings and a parked semi slides. The tighter caps cost traction at a crawl, though, which an honest tyre
would not lose. This plan wins that traction back without reopening the ring. It then moves the patch
under the hub, the remaining geometry artefact (formerly a `docs/TODO.md` item).

Written 2026-10-15. Status: **not started.**
Serves: rule 3. Every drive signal (`speed`, wheel slip, `engine_load`, TC state) is read out of these
contacts, so a cap artefact shows up as a slow launch or a short climb in telemetry.

## Evidence (2026-10-15, `--fixed-fps 60`)

Lever fixed. Each figure is with the shipped tensor caps / with the caps on `corner_mass` alone (an
experiment, reverted) / at HEAD `fd067b1` (origin lever):

| Probe | tensor caps | `corner_mass` caps | HEAD |
| --- | --- | --- | --- |
| `measure_grade -- suv-luxury asphalt` | 66.8 % | 81.0 % | 81.0 % |
| `measure_vehicles -- race 20 tc`, 0-50 | 2.13 s (tick cap 0.09) | 2.00 s | 2.00 s |
| `measure_vehicles -- semi 40 tc`, 0-50 | 17.05 s (tick cap 0.11) | 16.22 s (tick cap 0.01) | 16.08 s |
| `measure_rough -- suv tc`, asphalt | crosses all | `stuck-12.8` everywhere (rings at rest) | crosses all |
| `measure_grade -- semi park=16.7 hand` | 0.4 mm | slides 5 m | holds |
| `... semi park=16.7 cross` | 9.5 mm | 846 mm | 1.2 mm |

So both effects come from the cap mass. The tensor figure is what keeps a crawl stable, and the same
figure cuts steady force at low speed. The tick-cap share of the launch's grip loss is the readout
(`measure_vehicles` `launch 0-50` line).

## Phase 1 — Caps that bind on overshoot, not on steady force

Effort **high**, mode **plan-mode-first**.

The cap clamps the tyre force to `m · |slip_vel| / dt`, as if that force alone had to cancel the slip
velocity in one tick. In a launch or a climb, the drive torque and the grade carry the force, and the
slip velocity barely changes. Under `LOW_SPEED_FLOOR` (1.5 m/s) the slip velocity at the grip peak is
`peak_slip · 1.5 m/s`. So a cap mass 15-50 % under `corner_mass` stops the tyre short of its budget,
and the TC holds past the peak (`tcs_cap_vel`).

Candidates, in order of preference:
1. **Cap against the predicted slip velocity.** Bound the force by what would cancel the slip velocity
   left after this tick's other forces. The spin step already predicts the road's change
   (`dv_long`, `_integrate_spin`); the cap reads the same predictor.
2. **Cap the force's change per tick** (`|f - f_prev| <= m · |slip_vel| / dt`). A steady force passes;
   a reversal is still bounded. Check that the patch spring (`stick_stiffness`, sized on the same mass)
   stays inside it.
3. Rejected unless 1 and 2 fail: a factor between the deadbeat bound (1) and the explicit stability
   limit (2) on `contact_masses`. That weakens a clamp (`src/vehicles/CLAUDE.md` § Physics).

Done when every row of the evidence table reads within ~1 % of HEAD's traction figures, and the
crawl and park rows stay as the tensor caps hold them (`suv tc` crosses, semi park ≤ ~1 mm). Also:
`test_wheel_spin` § contact_masses still passes, and a new pure test pins the chosen cap's steady-force
pass-through.

## Phase 2 — The patch under the hub

Effort **high**, mode **plan-mode-first**. After Phase 1, so the patch's moment change is not read
through a cap artefact.

`RayWheel` casts down the body's own up axis, so a pitched body carries its patches with it (`h sin θ`
ahead of the COM's line, against a real tyre's `(h - r) sin θ`; the COMPROMISE at the ray cast in
`wheel.gd`). The extra `r sin θ` is a destabilising pitch moment: the `r / h` share of the trace's
`lean` term, ~0.7 on a car and ~0.4 on a truck (`docs/vehicles.md` § Pitch). Fix: find the patch
world-below the hub. Either cast down the contact plane's normal from the hub, or correct the hit
point by `r sin θ`. Keep the spring along the body's travel. `size_cap_masses`'s lever (full droop
along body up) follows the patch.

Done when the trace's `lean` term reads the `(h - r)` share, the `front axle` gate's lean
subtraction is restated to match, and the COMPROMISE comment is gone.

## Phase 3 — Re-measure and distil

Effort **medium**, mode **accept-edits**. Every patch moves, so serially, in the background:
- the CI gates: `measure_vehicles -- all 45 track strict`, `measure_semi_launch -- semi strict` and
  `-- semi-conventional strict`, `measure_air_loss -- all strict`;
- every `doc=` preset (§ Measure-tool run lines);
- the rollover table (`docs/heavy_vehicles.md`: `ramp`, the default step and `tip_kmh=` per trailer);
- the hand-written figures around the generated tables (§ Gradeability's prose, the heavy vans).

Then distil into `docs/vehicles.md` (the one-tick caps and § Pitch), repoint the `07b` row of
`docs/plans/mechanical_update/00_README.md` (it cites this path), and delete this plan.

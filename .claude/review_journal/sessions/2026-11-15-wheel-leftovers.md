# 2026-11-15: what else the wheel's two forces explained (Queue, Fable's item 1, diagnose only)

Started at d547176. Read whole: `wheel.gd`. Read in part: `WheelDrive.tick`, the retarder's law
(`drivetrain.gd:950-1009`), `TractorTelemetry.slip_pct` and its caller, `surface.gd`'s table,
`measure_grade`'s stop ledger. Nothing fixed, nothing run: every verdict is derived from the code
at HEAD, and the one measured figure it leans on is already in
`2026-11-15-wheel-fix-landed.md` § Still open (the 25 % coast cell), taken on the fixed tick.

Symbols: `s` slip velocity, `C` the tyre's slope (N per m/s), `k = C r^2 dt / I`, `A` the body's
gain a tick, `T_r = crr N r` the rolling moment, `tau_r = T_r r dt / I`.

| Leftover | Verdict |
| --- | --- |
| `surface_drag_force`'s `taken`, the laden roll-back | still there, not the two forces': finding 1, its own brief |
| the rolling resistance `COMPROMISE` | the same finding: its undo is now cheap, and is the fix |
| `brake_settled_spin`'s `COMPROMISE` | still there, untouched by the reorder; a false label: finding 2 |
| the retarder's `COMPROMISE` | still there, untouched; a real one, the label stays: finding 3 |
| the links' force off last tick's `force_long` | gone as a carrier of the ring; the lag stays and is stated: finding 4 |
| `TractorTelemetry.SLIP_FLOOR_KMH` | the wheel's ring is gone; a 0 / 0 is left: finding 5, cover sweep (5) amended |

## 1. The rolling drag is a second force at the contact, and `taken` cannot be made right

`apply_patch` (`wheel.gd:613-616`):

    force_roll = surface_drag_force(_patch_v_long, rolling_crr + surface_drag, suspension_force,
            _patch_long_mass, _patch_delta, maxf(-signf(_patch_v_long)
            * (f.x + _patch_long_mass * body.get_gravity().dot(_patch_forward)), 0.0))

and `surface_drag_force`: `tick_cap = maxf(mass * absf(v_long) / delta - taken, 0.0)`.

The cap is a friction law's stick test in discrete time: the drag may take the contact's speed to
zero, never through it. That test needs the speed the contact would have after every other force
of the tick. `taken` stands in for "every other force" with what one contact can see: its own
tyre's force and gravity on its own cap mass. It cannot see another wheel's tyre, a coupling or
the air. Three faces of the one fault, all from the two lines above:

- **A free wheel going uphill.** `f.x` is about 0, so `taken = long_mass * g sin` and the cap is
  `long_mass * (|v| / dt - g sin)`: no drag under `g sin * dt` (39.6 mm/s on 25 %, 16 on 10 %),
  whatever the mass. Gravity is counted against a contact whose gravity the drive wheels' tyres
  already hold. Fixture: `RayWheel.surface_drag_force(0.03, 0.007, 54400.0, m, 1.0 / 60.0,
  m * 9.8 * 0.2425)` is 0 for any `m`, where the wheel owes -381 N. Measured on the fixed tick
  (`2026-11-15-wheel-fix-landed.md` § Still open): the laden `semi` crawling up 25 % prints `roll -762 N`, its two
  drive wheels' alone; eight wheels of ten carry none.
- **A drive wheel holding more than its own cap mass** (the towing item's (a)). Rolling back
  (`v < 0`) while it drives at the budget, `taken = f.x - long_mass * g sin`: 38.4 kN less a few
  kN, so its cap is 0 until `|v|` passes `taken * dt / long_mass`, some 0.3 m/s. The tyre's force
  there holds the trailer through the coupling; it is not stopping this contact. Same lines, same
  cause: no trace is needed for (a).
- **A held wheel on a grade** (derived, not measured; small). It holds `corner_mass * g sin` and
  `taken` takes off `long_mass * g sin` (sedan: 287.5 kg against 199.1): the 86 N left on 10 %
  count against a downhill speed only, so a held contact's drag damps uphill motion and not
  downhill under 7 mm/s. A candidate for parked creep on grades; it goes with the fix either way.

The two-force fix did not touch any of this: `taken` reads the settled slip's force now, the one
the body takes, and the per-contact view is what is wrong.

**A force keyed on the wheel's spin instead of the contact's speed** (no `taken`: the tyre's cap
is on `omega r - v` and the drag's would be on `omega r`, which never sum past `v` when the wheel
turns with the body) is rejected: a spinning wheel on a standing body would be pushed backward by
`crr N`, and a wheel spinning forward on a body rolling back would be pushed with its motion.

**The fix: the rolling resistance is a moment on the wheel, solved as a brake inside the spin
step.** It is what the `COMPROMISE` at `wheel.gd:610-612` names as the true thing, and the brake
law already is a Coulomb torque that stops a wheel and never reverses it (`braked_spin`), solved
with the differentials. Before d22b3ee it could not be done: the body took the start slip's
force, so a torque in the step reached it a tick late on a false mass. Now:

- Steady rolling, linear tyre: the settle gives `s* = (s0 - tau_r) / (1 + k)` and next tick
  `s0' = s* - A`; steady, `k s* = -(A + tau_r)`, so the body takes
  `C s* = -I A / (r^2 dt) - T_r / r`: the wheel's inertia and **the whole `crr N`**.
- At rest: the wheel stops when `T_r >= C |v| r` (the settle's own check) and the body then sits
  on the tyre's viscous force alone, under its one cap: one force, so nothing to share and
  nothing to rock. The force is continuous through the stop (`C v = crr N` at the threshold).
  Under `crr N` of push the body creeps at `F / sum C` with its wheels still, as today (today the
  drag's cap gives `F / (sum long_mass / dt)`, the same bound: about 2 mm/s for a sedan on 1 %).
- Every wheel pays it at every speed and in every direction, coupled or not, because the tyre
  carries it and the tyre's cap is on the slip.

What must not happen: the moment is **never part of `hold_torque`** (`wheel.gd:552`). A hold
winds the patch along the wheel and clamps `f.x` into `held_force_range`, which keeps the wheel
at `omega == 0` up to STICK_SPEED: every undriven wheel would stand still for the first 0.5 m/s of
every launch. `_spin_held` does go true on a free wheel at rest (`brake_spin > 0.0 and omega ==
0.0`), and `_patch_held` stays false because `hold_torque` is 0.

What goes: `surface_drag_force`, `taken`, the gravity term, the second `apply_force`, the
`force_roll` term of `contact_force`, the `COMPROMISE` at `:610-612`,
`test_the_tyre_force_and_the_drag_together_never_carry_a_contact_through_zero` (one force cannot),
`test_wheel_spin.gd:30-63` and the drag line of `_free_pair_speeds`; `docs/vehicles.md` § One-tick
caps loses its `taken` paragraph.

What moves, by derivation (the fix ends in a proposal):

- An anti-lock stop takes the tyre's peak and no more: the moment is inside the brake the floor
  holds, where the force sat outside the friction circle. About `crr / mu` longer (`sedan` 100 %:
  40.7 m to about 41.2). True to a tyre: its road force is all the body gets.
- A locked wheel sliding has no rolling resistance (it has now).
- The laden `semi`'s 25 % roll-back and crawl cells: all ten wheels drag at every speed (about
  2.1 kN for 762 N). The crawl cell of (c), 18 N short of holding, will stop instead of coasting.
- `measure_grade`'s stop ledger: the rolling loss is the moment on the wheel's spin, and
  `1 - brake_friction_share` is no longer the retarder's alone.

**The choice the proposal carries: the ground's share (`surface_drag`).** Soil resistance is a
force on the wheel, not a moment (a rigid wheel's soil pressure passes through its axle), and it
costs a drive wheel slip: pull = thrust at that slip less resistance. As a moment, a driven
wheel's own soil drag costs engine torque and no slip. Estimated, not measured: a four-wheel-drive
tractor on FIELD (grip 0.5, drag 0.06) reads about 2 points of `wheel_slip` at no draft today and
about 0 after; an undriven wheel's share still costs the driven ones slip. No wheel locks: the
largest drag over grip is MUD's, 0.1 / 0.45.
(A) both shares one moment, the soil's labelled a `COMPROMISE` (a driven wheel's own soil drag
costs no slip; undoing it is the force below): one path, everything above goes. Recommended.
(B) the tyre's `rolling_crr` a moment, `surface_drag` stays the capped force with `taken`: the
slip reading keeps its 2 points, and the fault of this finding stays on painted ground only, where
nothing measures it; two paths, nothing deleted.

**Decided, user 2026-11-15: (A).** The Queue line is approved on it; the plan still shows the
measured moves before the commit.

## 2. `brake_settled_spin`'s `COMPROMISE` is a false label

`wheel.gd:141-146`. The reorder did not touch it: "the spin the road lent the step" is the
wheel's own split (step with the reaction, then the brake), `omega_u - omega_0 = (T_d + R_0) /
((1 + k) I) * dt`, about `k / (1 + k)` of an ABS wheel's 0.12 slip, which is the 5 % the label
quotes for the mean over the settle.

The settled spin is not a weaker stand-in. The wheel turns `omega_s * dt` in the tick
(`update_visual`), so `brake_reacted * omega_s * dt` is the brake's torque on the angle the wheel
turns: the integrator's own work. From the step, `I (omega_s - omega_0) / dt = T_d + R_s - T_b`
exactly (`R_s` the secant's reaction at the settled spin), and with the brake and the tyre's slip
loss read on the same `omega_s` (`measure_grade`'s ledger does) their sum is off the wheel's and
the body's energy change by `I (omega_s - omega_0)^2 / 2` a tick: second order. What it
under-reads against the start-and-settled mean is first order, `1 / n` of a stop of `n` ticks
(0.6 % of a 3 s stop), and the slip term over-reads by the same. The one real hole is the label's
own: a wheel the brake stops off the ground inside one tick heats nothing, and its `I omega^2 / 2`
leaves the ledger (3.8 kJ for a car wheel at 100 km/h).

Triage: a design choice with a known edge, not a compromise. Queue: relabel.

## 3. The retarder's `COMPROMISE` is real and stays

`wheel_drive.gd:664-669`. The cap (`Drivetrain.retarder_slip_cap`) sizes a torque off last tick's
`spin_compliance`; this tick's is known only inside `_integrate_spin`. Nothing in d22b3ee touches
it: the fix moved where the body takes its force, not the step's compliance. Exact is the
anti-lock's form, a floor latched by the step and applied in the settle, at the retarder's own
slip (0.10 against ABS's 0.12): a third stage in `settled_spin` and in
`Differential.braked_coupling_torque`. For a backstop that the anti-lock already rides on every
body with both, on one tick of a wheel lifting: not worth it. No brief.

## 4. The links' force off last tick's `force_long`

`wheel.gd:496-501`. `force_long` is the settled slip's force now, the one the body took. Before
the fix it was the start slip's, which alternated tick to tick under the floor in a take-up, and
`link_slope * force_long` carried that into `suspension_force` and every load readout. That
carrier is gone with its source. The one-tick lag stays, stated at the site, and is no fault: the
loop `N' = S + link_slope * F(N)` has gain `link_slope * mu` at the limit, positive and under 0.3
on every shipped spec (slopes 0.066 to 0.219), so it converges without alternating. No brief.

## 5. `TractorTelemetry.SLIP_FLOOR_KMH`

`tractor_telemetry.gd:20-21`, `tractor.gd:181-184`: `wheel_speed` is the drive axle's mean
`|omega| r`, `ground_speed` is `|speed|` of the body. The wheel's part of "the ratio is noise" is
gone: a held wheel settles at `omega == 0` exactly (the `<= 0` guard), and a free one sits at the
settled slip, with no ring. What is left is a quotient of two speeds of two points: a free wheel
follows its contact, the contact moves against the centre of mass by the pitch rate times its
lever, and at mm/s the ratio of the two is anything in 0 to 100. So cover sweep (5)'s proving run
stands, with one column more (the body's pitch rate) and a changed reading of its outcome: a
non-zero `wheel_slip` on a body standing in N is this, and is not a source in the wheel to queue.
A real unit's minimum speed (a page opened) is then the only thing that keeps a floor.

## For unit 3a's next read (seen reading `wheel.gd` whole, not acted on)

- `_slip_force`'s doc says the lateral cap "kills parked-car jitter": a symptom's wording on a
  60 Hz clamp; the reason is `docs/vehicles.md` § One-tick caps.
- `reset()` leaves `long_cap` (diagnostic) and the `_patch_*` store as they were; harmless
  (`apply_patch` returns off the ground), noted only.
- A wheel `_patch_held` at `tick` and released by the same tick's settle still takes its patch
  spring and `held_force_range` clamp in `apply_patch` for that one tick (`_patch_held` is
  `tick`'s, `_spin_held` the settle's). By design ("last tick's settle"); one tick.

## Deferred

Everything: this session fixes nothing. Queue: the rolling moment (Opus, plan, approved on
variant A), the relabel (Sonnet); the towing item's (a) and cover sweep (5) amended.

## Commits

The journal's only.

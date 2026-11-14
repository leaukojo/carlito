# 2026-11-14: the wheel and the body exchange one force (Queue top, diagnose only, Fable)

Started at 193e05e. Read whole: `wheel.gd`, `wheel_drive.gd`. Nothing fixed; one prototype, run
and reverted (`git status` clean after). Runs: `--headless --path . --fixed-fps 60`.

## Cause

One contact, two forces. Along the wheel, with `v` the contact's speed, `u = omega r` the rim's,
`s = u - v` the slip, `C` the tyre's slope (N per m/s; `budget * rise / slip_denom` on the grip
curve's rise):

- the body takes `C s`, the force at the slip the tick STARTS on (`wheel.gd:514-530`, applied at
  `:561`);
- the wheel reacts `C (u' - v)`, the force at the slip its own step ENDS on: `_integrate_spin`
  divides by `1 + reaction_stiffness` (`:1153-1157`), which is the implicit solve of
  `u' = u + (T - C r (u' - v)) r dt / I`.

Three numbers per tick: `a = C dt / m` (the share of the slip the body closes; `slip_floor_for`
and the cap keep it at 1 or under on the cap mass), `k = C r^2 dt / I` (`reaction_stiffness`),
`tau = T r dt / I` (the rim speed a torque `T` gives a free wheel in a tick).

### HEAD's map

    v' = v + a s
    u' = u + (tau - k s) / (1 + k)
    s' = (1 / (1 + k) - a) s + tau / (1 + k)

- Free (`tau = 0`): `s' = (1 / (1 + k) - a) s`. `semi`: `k` about 63, `a` 0.93 to 0.99, so
  `s' = -0.95 s`: the slip reverses every tick and decays about 5 %. The measured ring.
- Driven: fixed point `s = tau / (k (1 + a) + a)`, so the body gets
  `C s = (T / r) k / (k (1 + a) + a)`, about `(T / r) / (1 + a)`, while the wheel reacts about
  `T / r`. The rest of the drive is lost in the step. It is reached alternating (the factor is
  negative): the take-up's tick-rate ring.
- `road_change` adds `k / (1 + k)` of the centre of mass's last speed change to `u'`. That moves
  the fixed point to `(T / r) k / (k + a)`, the right one, where it is on (above 3 m/s, fading
  from 1.5). It is a predictor patching the mismatch, and its fade is where the patch rings.
- `a` here is the share the body REALLY closes. The cap mass is a row-sum bound over every wheel
  pushing (`contact_masses`); with two of four wheels driven the real share is about half the
  cap's. So a 2WD launch loses about a quarter of its drive under the floor, an AWD one up to half.

### The map with the body taking the force at the settled slip

`s* = u' - v = (s + tau) / (1 + k)` is the slip after `settle_spin`. The body takes `C s*`:

    v' = v + a s*
    s' = (1 - a) s* = (1 - a) (s + tau) / (1 + k)

- Free: factor `(1 - a) / (1 + k)`, between 0 and `1 / (1 + k)` for every `a` in 0..1. No
  reversal; the slip is gone in a tick.
- Driven: fixed point force `(T / r) k / (k + a)`: the drive less the wheel's own share of the
  acceleration (`I / r^2` against `m`). Exact at every speed with no predictor, reached without
  alternating.
- Braked, brake slipping: the same map with `tau < 0`. On the ABS floor or the TC ceiling `u'` is
  pinned, so `s*` is the 0.12 slip itself and the body gets the curve's peak each tick. Locked or
  held: `u' = 0`, `s* = -v`, which is HEAD's own force: a held wheel, its patch spring and
  `held_force_range` do not change.
- Why this is not the rejected predicted-slip cap (7b6d3be, `docs/vehicles.md` § Rejected
  designs): that kept the start-slip force and capped it by a predicted slip; once the force
  cancels the slip the prediction is 0, the cap 0, the next tick 2x. Here the force and its cap
  read one slip, `s*`. A change in the contact's speed (the pitch the force rocks) enters the
  force with gain `a / (1 + k)` (1 / 64 on the `semi`, about 1 / 9 on the tractor's rear), where
  HEAD's is `a`.

### Where it alternates, and what that rules out

1. `road_change` kept beside it: the fixed point becomes `(T / r) k / (k (1 - a) + a)`, over the
   drive. Measured (variant 2 below). The predictor, `_prev_com_long` and `_prev_vel_valid` go.
2. No stiffness at exactly zero slip (derived, not reached in any run: variant 3 printed variant
   1's figures to the digit). `reaction_stiffness = |reaction| / max(null_slip_torque, 1e-6)` is
   0 at `s = 0`: the wheel takes the whole `tau`, `s* = tau`, and the body gets `k T / r`, capped
   at the budget, for that tick. At HEAD the same tick gives the body nothing, so HEAD does not
   need it. The step's stiffness at zero slip must be the curve's first slope:
   `min(budget * rise0 / slip_denom, long_mass / dt) * r^2 * dt / I`.
3. The body must take the CURVE at `s*`, never the secant times `s*` (what the wheel's step
   reacts): on a growing wheelspin the secant's force passes the budget. Past the peak the two
   differ, as they do at HEAD.

## Evidence

Prototype (uncommitted, reverted): `tick` keeps its start-slip force only to size the spin step;
after `settle_spin` a new `apply_patch` reads the slip off the settled `omega` against the tick's
stored contact speed, runs `combined_slip_force`, both caps, the patch spring's stored force, the
ellipse and the held range, then applies the tyre's force and the rolling drag. A trailer's wheel
(not `coupled_spin`) calls it at the end of `tick`; `WheelDrive.tick` calls it per wheel after
`_couple_differentials`. An environment switch chose: off (HEAD's path), 1 (the above, no
`road_change`), 2 (with `road_change`), 3 (1 without the zero-slip stiffness). Off printed HEAD's
figures to the digit on every run below.

`measure_semi_launch -- semi trailer=bobtail steady`, the `rest reading:` line:

| | speed sign changes /s | `axle_load` kg a tick |
| --- | --- | --- |
| HEAD | 1.3 | 0.12 |
| prototype | 0.3 | 0.08 |

(HEAD read 6.7 /s and 0.46 kg at d849de9; what moved it since was not bisected.)

`measure_vehicles -- <v> 20 rest ...`, "speed step a tick, by second (mm/s)":

| run | HEAD | prototype |
| --- | --- | --- |
| `semi` bobtail, D | 2.40 0.25 0.03 0.03 0.01 0.01 0.01 0.01 0.01 | 1.08 0.13 0.00 0.00 0.00 0.00 0.00 0.00 0.00 |
| `tractor-kenney`, N | 2.06 0.08 0.01 0.00 ... | 1.95 0.07 0.00 0.00 ... |
| `sedan`, N | 0.00 ... | 0.00 ... |
| `semi` + box, D | 1.86 0.66 0.04 0.00 ... | 3.24 0.62 0.04 0.00 ... |

`measure_vehicles -- tractor-kenney 8 trace trace_s=2.5` (floored, D7, rear drive), `a g` per tick:

| t s | 0.150 | 0.167 | 0.183 | 0.200 | 0.217 | 0.233 | 0.250 | 0.500 (clutch 694 N·m) | 2.500 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| HEAD | 0.00 | 0.12 | 0.04 | 0.13 | 0.09 | 0.14 | 0.14 | 0.33 at 2.7 km/h | 22.7 km/h |
| prototype | 0.13 | 0.13 | 0.15 | 0.17 | 0.19 | 0.21 | 0.23 | 0.45 at 4.1 km/h | 24.3 km/h |
| with `road_change` | as prototype | | | | | | | 0.45 | 26.8 km/h |

- HEAD's take-up alternates (0.12, 0.04, 0.13, 0.09); the prototype's rises every tick.
- At the same clutch torque the body gets 0.33 g at HEAD and 0.45 g: `(0.33 + 0.02) / (0.45 +
  0.02) = 0.74` with the rolling drag, the map's `1 / (1 + a)` at `a` about 0.35 (two of four
  wheels pushing). Check on the prototype's figure: `694 * 3.632 * 12.299 / 0.805 = 38.5 kN` at
  the rims; `7000 kg * 9.81 * 0.47 = 32.3 kN` plus the wheels' own inertia (574 kg at 4.4 m/s2,
  2.5 kN) is 34.8 kN, 0.90 of it (the spec's efficiency not read).
- With `road_change` kept the body runs ahead above 3 m/s (26.8 against 24.3 km/h at 2.5 s).

Other bodies, HEAD then prototype:

- `measure_semi_launch -- semi trailer=bobtail`: 0-2 m/s 0.833 -> 0.550 s, 0-5 m/s 1.600 ->
  1.250 s; the spawn settle's peak forward acceleration 0.420 -> 0.121 m/s2.
- `measure_vehicles -- sedan 45 brake`: 0-50 km/h 3.47 -> 3.20 s, 0-100 8.28 -> 8.03 (the launch's
  0.25 s, nothing after it), the launch's grip use 0.91 -> 0.95; top speed at the cap 202.3 ->
  202.5; full-pedal stop from 100 km/h 41.6 -> 40.7 m (0.95 -> 0.98 g mean); 60 % 62.4 -> 61.9 m;
  30 % 157.3 -> 156.1 m and 11.58 -> 11.10 s (the crawl at its end).

Not run: parking, creep, roll-back, cornering, any coupled launch, the suite.

## Findings

1. **The cause above**: one finding, with its fix. Brief in the Queue; the fix changes driving, so
   it waits on the proposal.
2. **The laden `semi`'s axle-load step is not the wheel's ring.** `measure_vehicles -- semi 20
   rest` (box coupled): rear axle 0.7 kg a tick at HEAD, 0.6 with the prototype, speed sign changes
   0.0 /s both ways. The proposal and "Please verify" gave it to the ring. Not traced: it goes to
   the towing item (Fable's next), which reads the coupling. `REST_STEP_KG` cannot come down on
   the laden rig with this fix alone.
3. **The prototype's gaps the fix must close.** `WheelDrive._report_to_controller` reads
   `long_slip` inside `_couple_differentials`, before the settled slip exists
   (`Drivetrain.drag_control` would under-read). `long_slip`, `slip`, `slip_size` and
   `slide_speed` must be the settled slip's: under the floor the start slip is what is left over,
   near zero, and the dust, the contract's `slip` and the tractor's `wheel_slip` read them.

## Unit 3b (`wheel_drive.gd`), findings only, for its review on Opus

- Wrong comment, `tick` (`:602-603`): "resistance reads this tick's spring load so it must follow
  the wheel loop". `_apply_resistance` (`:957-961`) passes `VehicleMath.air_force` the velocity,
  the wind, the basis, two areas, the mass and `delta`; the rolling drag is `RayWheel`'s
  (`vehicle_math.gd:192`). No spring load is read.
- Cover candidate, `LOCK_STUCK_SPIN` (`:26-31`): an epsilon under which a pawl-locked wheel "reads
  as stopped", because the one-pass solve (the `COMPROMISE` at `:711-713`) leaves a 7.5e-4 rad/s
  spread. Not in the cover sweep's list. Prove: set it to 0 and read `suv-luxury` parked on 16 %.
- `tick`'s loop sets `abs_slip` per wheel from two loop-invariant reads (`:657`): hoistable, S.
- `_build_dust` and `_soft_dot_texture` (`:1067-1133`) build a particle emitter in code, 67 lines
  of a 1133-line file. Whether a `.tscn` would carry it is for the unit's review; no cost named.
- Seen and sound: the retarder's `COMPROMISE` (`:667-669`) is real; `_settled_drive_spin` saves
  and restores `_coupling` around its trial solve; `hold_step`, `esc_step` and `drive_omega`
  match their comments.
- Already queued: the rigid crank's `axle_torque` path (`:604-605`, `:649`).

## Deferred

Everything: this session fixes nothing. Queue: the fix's brief, tagged for Opus; the proposal
entry carries the measured figures and is the user's to approve.

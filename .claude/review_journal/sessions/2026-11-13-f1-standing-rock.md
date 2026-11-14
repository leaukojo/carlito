# 2026-11-13: F1, a standing body rocks every tick (Queue top, plan mode)

Started at c6715df. Plan: `docs/plans/parked_rocking.md` (approved by the user this session).
This file: phase 1's findings and runs.

## Read before any run (code and the earlier trace)

The repro's truck is neither held nor driven. `Drivetrain.coupling_step` opens an AMT clutch with
the pedal up and the wheel side under idle; `semi_spec.tres` declares `hill_hold = 1` (ASSIST),
which latches only a pedal that was pressed; `Differential.bias_capacity(0, ...)` is 0. Every wheel
is free: no drive, no brake, `_spin_held` false, so no patch spring along the wheel.

On a free wheel two steps cancel the same slip in one tick:
1. `wheel.gd:512-513`: the body takes the tyre force up to `long_mass * |slip_vel| / delta`, and
   `slip_floor_for` puts the curve's slope at that cap near rest.
2. `wheel.gd:1038-1042` (`_integrate_spin`): the wheel closes `k / (1 + k)` of the slip; with
   `wheel_inertia = 3.0`, radius 0.36 and a cap mass near 1500 kg, `k` is about 63.
So the slip reverses each tick at about -0.95. `surface_drag_force` (`wheel.gd:555`) is signed by
this tick's `v_long`, which the swap reverses, so it pushes the body the way it is about to go.

Checked against `reports/semi_launch/semi_bobtail.csv` (the run of
`sessions/2026-11-13-ui-gamepad-plan-review.md` § F1), rows t = 8.0000 and 8.0167:
- rim speed `0.0332 * 0.36 = 0.0120` and `-0.0461 * 0.36 = -0.0166` m/s; contact speed = `speed`
  plus the pitch step (0.0041 deg a tick = 0.0043 rad/s on about 1 m) = `0.0121` and `-0.0167`;
- rows t = 1.0 to 1.25: the tick-to-tick step of `omegaRL` grows from 0.004 to 0.037 rad/s by a
  near-constant 0.003 a tick (linear, a constant-size push);
- predicted swing of the contact speed, lumped model `v = d / ((2 - a) - a k' / (2 - k'))` with
  `d = crr N dt / m = 550 / 60 / 5988`, `a = 0.97`, `k' = 0.984`: 0.017 m/s; the trace: 0.014.
The pitch inertia in that figure is an estimate (24000 kg m2), not read off the solver.

## Phase 1 runs

`node tools/godot_run.mjs -- --headless --path . --fixed-fps 60 res://tools/measure_vehicles.tscn -- <variant> 20 rest[=n|brake|handbrake] [trailer=] [crr=0] [surface=]`
(the `rest` scenario added this session; 10 s stood, the last 3 s read per tick; about 2 s a run).
At c6715df plus the tool:

| run | wheels held | speed sign changes /s | speed p-p mm/s | mean mm/s | raw accel p-p m/s2 | `accLong` as sent p-p | rear axle p-p kg | kg a tick |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `semi` bobtail, D pedals up | 0 / 4 | 59.7 | 20.44 | -2.35 | 2.435 | 0.202 | 101.3 | 98.5 |
| same, `crr=0` | 0 / 4 | 0.0 | 0.06 | +1.15 | 0.004 | 0.000 | 3.1 | 0.4 |
| same, N | 0 / 4 | 59.7 | 20.44 | -2.35 | 2.435 | 0.202 | 101.3 | 98.5 |
| same, foot brake 30 % | 4 / 4 | 59.7 | 2.41 | 0.00 | 0.289 | 0.024 | 14.9 | 11.9 |
| same, handbrake | 2 / 4 | 59.7 | 4.45 | 0.00 | 0.533 | 0.044 | 24.4 | 21.6 |
| `semi` + box, D pedals up | 0 / 4 | 59.7 | 2.89 | +0.16 | 0.346 | 0.029 | 8.2 (bogie 13.6) | 5.9 (12.7) |
| same, `crr=0` | 0 / 4 | 0.0 | 0.01 | +67.00 | 0.001 | 0.000 | 3.3 (1.0) | 0.8 (0.3) |
| same, foot brake 30 % | 4 / 4 | 0.0 | 0.01 | -0.21 | 0.001 | 0.000 | 4.1 (1.5) | 0.4 (0.1) |
| `sedan`, N | 0 / 4 | 59.7 | 7.77 | +1.85 | 0.933 | 0.078 | 7.1 | 7.0 |
| `sedan`, foot brake 30 % | 4 / 4 | 0.3 | 0.03 | 0.00 | 0.000 | 0.000 | 0.0 | 0.0 |
| `garbage-truck`, N | 0 / 4 | 0.0 | 21.51 | -11.70 | 2.228 | 0.187 | 315.2 | 264.5 |
| `garbage-truck`, foot brake 30 % | 2 / 4 | 59.7 | 4.30 | 0.00 | 0.515 | 0.043 | 73.4 | 71.6 |
| `tractor-kenney`, N | 0 / 4 | 59.7 | 12.97 | -0.64 | 1.489 | 0.124 | 36.6 | 35.4 |
| same, `surface=field` | 0 / 4 | 59.7 | 48.42 | +13.94 | 5.808 | 0.483 | 137.4 | 136.0 |
| same, `surface=mud` | 0 / 4 | 59.7 | 67.64 | +19.51 | 8.114 | 0.675 | 191.1 | 190.0 |
| same, `surface=field`, foot brake | 2 / 4 | 2.7 | 0.05 | +0.02 | 0.001 | 0.000 | 0.3 | 0.0 |

The bobtail in D, per axle: the rim lands 0.03 (front) and 0.04 (rear) off the road's speed of the
tick before and the contact the same off the rim's (0 = lands on it: the swap); the tyre force is
0.99 and 0.93 of its one-tick cap; the rolling drag (143 and 131 N a wheel) changes sign 59.7 times
a second. Clutch OPEN, hill hold off. In N the figures are the same to the digit.

Against the plan's predictions:
- Held: the free-wheel swap (clutch open, no wheel held, the rim on the road's speed and the
  contact on the rim's, the force at 0.93 to 0.99 of its cap, the drag flipping every tick); with
  `crr=0` the ring is gone inside 2 s and nothing steady is left; N as D; smaller laden; every
  body in N; larger on soft ground (`tractor-kenney` on mud: 191 kg and 8.1 m/s2 peak to peak).
- **Failed: "foot brake / handbrake: steady".** A bobtail `semi` on the foot brake, every wheel
  held, still alternates (14.9 kg; 24.4 kg on the handbrake), and `garbage-truck` on the foot brake
  73.4 kg. `sedan`, the laden `semi` and the tractor are steady on the brake.
- So the swap is an amplifier, not the source. The source is the rolling drag: it is applied in
  the same tick as a tyre force that already cancels the contact's speed, each under its own
  one-tick cap, so the two together carry the contact through zero by `crr N dt / m` every tick
  (bobtail: `143 / 60 / 1497 = 1.6 mm/s` a contact; measured contact speed 1.74 mm/s, body p-p
  2.41 mm/s on held wheels). `wheel.gd:548-551` names the hazard for the tyre's and the soil's
  drag ("Two separately clamped terms could take twice the cap") and shares one cap between
  them; the tyre force is the third term on the same speed and has its own cap.
- Other findings: a slow roll is never stopped (`garbage-truck` in N rolls back at 11.7 mm/s
  without its speed crossing zero; the drag's mean over the alternation is zero);
  `BaseVehicle.ACCEL_SMOOTH` passes 8 % of the raw alternation to `accLong` (0.202 of 2.435 m/s2).

## Probe (uncommitted, reverted in the same command): one cap shared by the tyre force and the drag

`surface_drag_force` given what the tyre's force already takes of the cap against the contact's
speed (`taken = max(-sign(v_long) * f.x, 0)`, `tick_cap = max(mass |v_long| / dt - taken, 0)`):
two lines in `wheel.gd`. Same runs:

| run | speed p-p mm/s (before) | mean mm/s | rear axle p-p kg (before) | kg a tick (before) |
| --- | --- | --- | --- | --- |
| `semi` bobtail, D pedals up | 0.09 (20.44) | +0.02 | 1.7 (101.3) | 0.7 (98.5) |
| same, foot brake 30 % | 0.07 (2.41) | +0.03 | 0.2 (14.9) | 0.0 (11.9) |
| same, handbrake | 0.12 (4.45) | 0.00 | 2.1 (24.4) | 0.1 (21.6) |
| `semi` + box, D pedals up | 0.01 (2.89) | +0.04 | 3.7, bogie 0.4 (8.2, 13.6) | 1.0, 0.0 (5.9, 12.7) |
| `sedan`, N | 0.02 (7.77) | +0.01 | 0.0 (7.1) | 0.0 (7.0) |
| `garbage-truck`, N | 0.01 (21.51) | -0.04 | 1.1 (315.2) | 0.2 (264.5) |
| `garbage-truck`, foot brake 30 % | 0.09 (4.30) | -0.01 | 1.1 (73.4) | 0.3 (71.6) |
| `tractor-kenney`, N | 0.02 (12.97) | +0.02 | 0.5 (36.6) | 0.2 (35.4) |
| same, `surface=mud` | 0.11 (67.64) | 0.00 | 1.2 (191.1) | 0.1 (190.0) |

The peak-to-peak kilograms left are the springs still settling over the 3 s window (kg a tick near
0), except the bobtail in D: 0.7 kg a tick and 20.3 speed sign changes a second at 0.09 mm/s, the
swap's own ring with nothing feeding it. Not measured: any driving figure with the probe in.
`src/vehicles/base/wheel.gd` is back at HEAD.

## State at the gate

The plan's phase 1 said a failed prediction stops it. The fix the plan approved (the body takes the
tyre force at the wheel's settled slip) does not reach a held wheel, whose spin does not move. The
change proposed to the user: phase 2 becomes the shared cap above; the approved redesign becomes a
proposal of its own (`proposals.md`), for the ring that is left and the crawl's lost drive.

## Phase 2: creep and parking, before and after (one script, `all creep` and `doc=park` each way)

- Shared cap as approved (`taken = max(-sign(v_long) * f.x, 0)`): the steepest grade creep holds
  drops one bisect step (0.4 points) on 11 of the converter bodies and two on `delivery` (7.0 to
  6.1 %); `semi` parked across 30 %: 14.6 to 16.5 mm in 60 s, 10 % foot 0.4 to 0.7; the other
  parking cells move 0.1 to 0.2 mm either way.
- Reading (derived): on a slow roll-back the tyre force that balances gravity counts as taking the
  cap, so the rolling drag is zero below about `g sin(grade) dt` (1 cm/s on 7 %) and its hold is
  lost.
- Probe (in the working tree, not approved): gravity's share on the contact mass comes out of
  `taken` (`f.x + long_mass * gravity . forward`). Creep hold is HEAD's on every body but
  `garbage-truck` (8.2 to 7.8 %); `semi` across 30 %: 14.3 mm; one cell up (`pickup` 10 % cross
  0.2 to 0.9 mm). `rest` rows stay quiet (speed p-p 0.00 to 0.10 mm/s, 0.0 to 1.0 kg a tick:
  laden `semi` D / brake / handbrake, `sedan` N, `garbage-truck` N / brake, `tractor-kenney` N on
  mud).
- The user chose the gravity term. With it: bobtail `semi` in D and N 0.12 mm/s, 0.5 kg a tick
  (6.7 sign changes /s); foot brake 0.13 mm/s, 0.3 kg; handbrake 0.13 mm/s, 0.3 kg;
  `tractor-kenney` N 0.05 mm/s, 0.0 kg; `measure_semi_launch -- semi steady` rest: axle p-p 3 kg,
  trailer 0. Roll-back (`sedan` with and without the hold, `semi`, `garbage-truck`) ran clean but
  has no HEAD run beside it; the stops and `preflight.ps1` were not run.

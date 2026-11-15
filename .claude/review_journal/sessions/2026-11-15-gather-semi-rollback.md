# 2026-11-15: gather for the hand-back's (c), the laden `semi` on 25 % (Sonnet)

Run at dc64569 (patch `git apply --include='src/*'` clean). Probe: one `print` per tick in
`measure_grade._roll_step` (hold, `_hold.x`, gear, rpm, `abs_release`, `drag_control`; per rear
wheel `omega`, `force_long`, `long_slip`, `abs_active`, `tcs_active`), from the release to
`gain` 0.15 m. Probe and patch reverted; tree as found. Run: `node tools/godot_run.mjs -- --headless
--path . --fixed-fps 60 res://tools/measure_grade.tscn -- semi rollback grade=25`, HEAD then the
patch with step 4 dropped (`_integrate_spin`'s stiffness back to `absf(reaction_torque) /
maxf(null_slip_torque, 1e-6)`). Reproduced: forward at 3.12 s (HEAD), 4.32 s (patched); back 0.1 /
-0.0 mm; held 0.62 s both.

## What is the same

Every state flag, every tick to the end of HEAD's run (305 ticks, t 0.017 to 5.08 s): hill hold
releases on the same tick (t 0.6333), `gear_byte` 1, rpm (600, then the pedal at 0.5 s: 680, 771,
874, 900) to the digit, `abs_release` 0, `drag_control` 0, `abs_active` 0 on every wheel,
`tcs_active` 1 on both rear wheels from the release on. Before the release: `omega` 0, `force_long`
7140..7208 N within 1 N (the held rig).

## First tick that differs: t 0.6333, the release tick

Both rear wheels (identical to each other in each run):

| | `omega` | `force_long` | `long_slip` | body gain |
|---|---|---|---|---|
| HEAD | 1.005 | 34 N | +0.0001 | -0.1 mm |
| patched | 1.005 | 29702 N | +0.1200 | +1.0 mm |

`omega` is the same; the force and the slip read are not: HEAD reports the force of the slip the
tick started on (about 0), the patch the force at the settled slip (the TCS's 0.12). From then on
HEAD's force is a tick behind (t 0.65: 29251 N at slip 0.129, `omega` 0.927; patched 30178 N,
`omega` 1.143).

## Then

- Pull-away (t 0.63 to 1.0): patched is ahead: gain 0.0233 against 0.0158 m at 0.8 s, `force_long`
  36917 against 33536 N, `omega` peak 1.767 (t 0.85) against 1.725 (t 0.92).
- The dip (t 1.0 to 1.5): `force_long` falls under the steady 38.4 kN in both (min 37085 N at
  1.52 s, `omega` 1.328, HEAD; 37070 N at 1.42 s, `omega` 1.297, patched); patched `omega` falls
  0.031 lower and earlier.
- Steady (t 3 to 5 s): both at `force_long` 38.40 kN, `long_slip` +0.1200, `tcs_active` 1. HEAD
  `omega` 1.371, creep 25.4 mm/s; patched `omega` 1.343, creep 15.2 mm/s. The force is the same and
  the body speed is not; gain crosses 0.1 m at 3.12 s against 4.32 s.

Not traced, not guessed: why `omega` (hence the body speed at the same force and slip) settles
2 % lower after the dip. Under `LOW_SPEED_FLOOR` the slip's denominator is the floor, so a body
speed difference of 10 mm/s is `delta omega * r` (r about 0.36 m from these numbers: unchecked).
Next step for whoever fixes it: the same log at `omega`'s dip (t 1.0 to 1.5), adding the drivetrain's
coupling state and the converter's torque, to see which side makes the patched dip deeper.

## Commits

The journal's only.

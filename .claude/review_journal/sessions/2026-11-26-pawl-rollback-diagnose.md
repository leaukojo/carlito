# 2026-11-26: diagnose, the park pawl creeping after a roll-back (Opus)

From `sessions/2026-11-26-pawl-rollback-gather.md`: `suv` on 30 % (16.7 deg), P at 0.31 m/s rolling
back, creeps at 0.113 m/s for 20 s, wheels at -0.024 rad/s, `_spin_held` never true. HEAD c0cee71.

## Cause

The pawl's lock is solved before the couplings under it (`WheelDrive._couple_differentials`, the
documented one-pass `COMPROMISE`, `docs/vehicles.md` § The solve order: "a biasing centre or axle
moves the driven wheels' mean after the gearbox output settled against it (the pawl:
`LOCK_STUCK_SPIN`)"). The lock lands the four driven wheels' arithmetic mean on the case (0), but
shares its torque equally, so front and rear land apart; the centre (`suv`: Torsen 3.0) then ties
them back on their compliance-weighted mean, which is not 0 when their compliances differ. The
gearbox output is not held during the centre's solve, so the mean it leaves is the pawl slipping
in the model, never in the machine.

`LOCK_STUCK_SPIN` (0.01) was sized on the static case (7.5e-4 on `suv-luxury` parked). After a
roll-back the error is 45x that: the viscous tyre's reaction (no patch spring along an unheld
wheel) pulls each wheel to near rolling speed every tick (-0.29 / -0.30 rad/s before the
couplings), and the one-pass error scales with that spread. The hold check then fails, so
`hold_by_lock` never runs, `_spin_held` stays false, the patch spring stays off along the wheel
(`RayWheel.tick`: `_patch_held = _spin_held and ...`), and the tyre is the viscous slip force
alone (own slip floor 3.03 m/s on a 227 kg cap mass), which carries the grade at 0.105 m/s of
slide. A self-sustaining second state: creeping keeps the spread large, the spread keeps the
hold off.

## Evidence

Temporary trace in `_couple_differentials` (reverted; a print each 60th physics frame while a
lock is in), `measure_grade -- suv park=16.7 rolled`, t = 3 s (every second after reads the
same to 1e-4):

```
DBG lock 1459.3 cap 12000 holds true moved (0.0, 0.0, -252.3289)
  w0 pre -0.29116 c 0.001078 afterlock  0.10232 afterdiffs -0.03375 roll 0.00985 denom 3.03 lmass 227.4
  w1 pre -0.29116 c 0.001078 afterlock  0.10232 afterdiffs -0.03375 roll 0.00985 denom 3.03 lmass 227.4
  w2 pre -0.30232 c 0.000543 afterlock -0.10404 afterdiffs -0.03547 roll 0.01157 denom 3.03 lmass 227.4
  w3 pre -0.30232 c 0.000543 afterlock -0.10404 afterdiffs -0.03547 roll 0.01157 denom 3.03 lmass 227.4
  settled -0.02390 -0.02390 -0.02390 -0.02390
```

- `afterlock`: mean exactly 0 (+0.102 fronts, -0.104 rears): the lock solve is right on its own.
- `afterdiffs`: the centre moved 252 N·m and left all four at -0.034 (fronts' compliance twice
  the rears'); the rolling moment takes it to -0.024: over `LOCK_STUCK_SPIN`, no hold.
- `lock_holds` true every tick, 1460 N·m of a 12 000 N·m rating: the pawl is far from slipping.

Second run, `LOCK_STUCK_SPIN` raised to 0.06 for one run only (reverted): the hold latches on the
first tick and the body stops: 21.7 mm moved by t = 1 s, 22.0 mm from t = 2 s to 20 s, every wheel
0.00000 and held. So the hold check is the only missing piece; raising the tolerance would be a
cover (the model would still slip the output by 0.034 rad/s), not the fix.

Failing fixture for the fix (not committed): `test_an_awd_body_holds_on_the_pawl_through_its_centre`
with the trace's figures, `_set_spin(drive, [-0.29116, -0.29116, -0.30232, -0.30232], [0.001078,
0.001078, 0.000543, 0.000543])`: one pass leaves ~-0.034 on every wheel, no hold; it asserts every
wheel 0 and held.

## Not findings

- The patch spring acting along the wheel only while it is held (`_spin_held`) is the design
  (`RayWheel._spin_held`'s comment); the viscous creep is what it says an unheld wheel does.
- The test comment of `test_an_awd_body_holds_on_the_pawl_through_its_centre` and the doc's
  COMPROMISE sentence are right for the code as it is; both change with the fix.

# Plan: tests that cannot fail

Sonnet, effort **medium**, mode: delegate (one agent per pass, sequential). Delete this file
when done.

## Problem

Round two found three green tests guarding exactly the invariant that was broken: the gimbal
sign (asserted the inverted value), the sail-plane test (flat literals in, so `y` is 0 for any
implementation), the train brake test (two constants of the same object). The suite is large
and part of it is tautological.

## Prompt

Pass 1 — mutation sweep over the pure-math suites (rule 8 list: drivetrain, contract
encode/decode, arbitration, GPS/odometer, buoyancy, terrain/scatter/road/bake math, plus
`boat_sail`, `train_sim`, `drone_*` statics). For each source file: apply one obvious mutation
at a time (flip a sign, drop a clamp, swap `x`/`z`), run only that file's suites, record which
mutations survive. Do not fix anything; report the survivors as a table (file, mutation, suite
that should have caught it).
Pass 2 — for each survivor, make the existing test real or add one that fails under the
mutation. Assertions must go through the same call path production uses (a heeled basis, a
built consist, a real `DroneGimbal.basis_of`), never a literal restating the constant. Re-run the
mutation to confirm the kill, then revert the mutation.
Finish with the full `runtest.cmd -a tests`.

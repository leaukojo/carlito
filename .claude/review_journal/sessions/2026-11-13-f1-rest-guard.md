# 2026-11-13: F1's rest (Queue top): the rest guard, the plan's open ends

Started at d849de9. Item: `docs/plans/parked_rocking.md` phase 3's last guard (`measure_semi_launch
steady`'s rest reading fails `strict`), then the plan distilled and deleted. Earlier phases:
`2026-11-13-f1-standing-rock.md`.

## HEAD's rest reading, before the guard

`node tools/godot_run.mjs -- --headless --path . --fixed-fps 60 res://tools/measure_semi_launch.tscn -- <unit> [trailer=bobtail] steady`

| rig | `axle_load` at rest: kg a tick (max) | whole-kg number changes | `trailer_axle_load` kg a tick |
| --- | --- | --- | --- |
| `semi`, box | 0.8 (3) | 73 % of ticks | 0.0 |
| `semi`, bobtail | 0.5 (1) | 52 % | - |
| `semi-conventional`, box | 0.0 (0) | 0 % | 0 (no data link: the signal reads 0) |
| `semi-conventional`, bobtail | 0.3 (2) | 31 % | - |

`measure_vehicles -- semi 20 rest trailer=box` at HEAD: speed sign changes 0.0 /s, p-p 0.01 mm/s;
rear axle 1.0 kg a tick; rolling drag flips 0.0 /s; the rear tyre force 1.00 of its one-tick cap,
the rim 0.01 off the road's speed and the contact 0.05 off the rim's.

## Findings

1. **The guard cannot be the plan's zero.** The plan says the rest reading fails `strict` "on a
   sign change of speed or a per-tick axle-load step". At HEAD the laden `semi`'s `axle_load`
   still steps 0.8 kg a tick with no speed sign change and no drag flip: the free wheel's ring
   (`proposals.md`, "The wheel and the body exchange one force"), which the earlier session
   reported on the bobtail only. So the gate carries two limits (`REST_FLIPS_S` 20 /s,
   `REST_STEP_KG` 2 kg), each between the ring and the fault it guards, and its comment says what
   the limits let through. They are a tolerance over a known fault: the proposal's entry says they
   come down with the ring.
2. **"Please verify" promised a steady AXLE.** With the ring left, the whole-kg AXLE number of a
   standing `semi` changes on 52 to 73 % of ticks by 1 kg (3 at most). The line is reworded: known,
   and whose it is.
3. **The roll-back moved on one rig (the plan's missing before / after).** `measure_grade --
   <v> rollback [nohold]`, HEAD against `wheel.gd` at d849de9~1 (restored in the same command):
   - with the hold: `sedan`, `garbage-truck` and `semi` 10 % the same to the digit; `semi` 25 %
     rolled back 0.1 mm both ways, "forward never" before, "forward at 3.10 s" at HEAD;
   - `nohold`: `sedan` 10 % 35.7 to 36.6 mm, 25 % 333.0 to 333.2; `garbage-truck` 24.1 to 25.1 and
     300.1 to 300.3; `semi` 10 % 5.8 to 6.0; **laden `semi` 25 %: 685.1 to 927.4 mm**, "forward
     never" both ways.
   Reading (derived, not measured): `taken` takes gravity's pull on the contact's own mass out of
   the tyre's share, never the trailer's pull through the coupling, so a drive wheel holding a
   trailer on a grade counts as stopping its contact and loses its rolling drag below about
   0.1 m/s. Queued.
4. **A doc sentence the runs contradict** (`docs/drivetrain.md`, "The laden semis roll back far on
   25 % with or without the hold"): `semi rollback` on 25 % with the hold prints 0.1 mm, before
   and after F1's fix. `semi-conventional` not run. Queued as a doc check.

## The guard, proven

`... measure_semi_launch.tscn -- <unit> [trailer=bobtail] steady strict`, the `rest reading:` line:

| rig | HEAD | `wheel.gd` at d849de9~1 |
| --- | --- | --- |
| `semi`, box | 0.0 /s, 0.81 kg: PASS | 59.7 /s, 12.67 kg: FAIL, exit 1 |
| `semi`, bobtail | 6.7 /s, 0.46 kg: PASS | 59.7 /s, 98.50 kg: FAIL |
| `semi-conventional`, box | 0.0 /s, 0.00 kg: PASS | 59.7 /s, 8.23 kg: FAIL |
| `semi-conventional`, bobtail | 5.0 /s, 0.34 kg: PASS | 59.7 /s, 139.00 kg: FAIL |

About 3 s a run under `--fixed-fps 60`. CI's semi step runs it laden on both units and wants the
`rest reading: ...: PASS` line. Not in the plan's text: the CI wiring (the plan said "fails
`strict`", and `strict` is the tool's CI gate; a guard nothing runs guards nothing).

## The plan's open ends, run at HEAD (d849de9's `src/`)

- `measure_grade -- doc=park`: region rewritten. Every cell within 0.3 mm of the 2026-11-09 table
  but `pickup` 10 % cross (0.2 to 0.9), `semi` 10 % hand (0.5 to 0.8), `semi` regulation hand
  (1.0 to 0.5) and `semi` 30 % cross (14.6 to 14.3). `pickup`'s cell stays unexplained: under a
  millimetre in a minute, not traced.
- `measure_vehicles -- doc=braking`: every stop prints as on 2026-11-09 (the region's date alone
  changed).
- `measure_grade -- all creep`: `garbage-truck` holds 7.8 % (8.2 before the fix, one bisect step),
  every other body as `docs/drivetrain.md`'s table; its row and date updated. Not traced further.
- The three CI measure gates: `measure_vehicles -- all 45 track strict` ("all vehicles tracked
  straight"), `measure_semi_launch -- <unit> strict` (steer floor PASS, 11350 / 11379 N and
  13795 / 13822 N), `measure_air_loss -- all strict` (9 of 9 PASS).
- Full suite: 2498 cases, 0 failures.

## Commits

- 17842e1 `review: measure: steady's rest reading fails strict; CI runs it on both tractor units`
- 6604613 `review: docs: the parked-rocking plan distilled and deleted; park, braking and creep re-run`
  (`docs/vehicles.md` § One-tick caps: the ring that is left, the two guards; zero lines added,
  the docs budget is full).

## Deferred

- Finding 3: Queue, [xhigh, plan] (a change inside the wheel's tick; it ends in a proposal).
- Finding 4: Queue, [medium, auto, Sonnet].
- Seen, not this item's: a standing rig still drifts at a steady 0.04 to 0.2 mm/s in the 7 to 10 s
  window (`rest`: laden `semi` +0.04 in D, -0.20 on the foot brake with every wheel held;
  `semi-conventional` -0.17). Not traced: settling, or a slide. It goes with finding 3's item.

# 2026-11-15: the body takes the tyre's force at the settled slip (Queue, approved, Opus)

Started at 420dd03. Brief: the Queue item (summary.md), Fable's diagnosis
(`2026-11-15-wheel-handback-diagnosis.md`), the hand-back and its patch
(`2026-11-15-wheel-settled-slip.md` / `.patch`, `git apply --check` clean at 420dd03). Plan
approved by the user (plan mode). Runs `--fixed-fps 60`; the HEAD baseline in a detached worktree
at 420dd03 outside the repo (`.godot/` copied).

## Steps

- [x] patch applied, amendment (i) the guard, (ii) the mass-law test and doc sentence
- [x] `test_wheel_spin` 161/161, full suite 2516/2516
- [x] runs HEAD -> after
- [x] commit 1, `doc=` tables, commit 2, journal

## Findings

1. **(i) The guard.** New `test_a_held_wheel_at_zero_slip_stays_rigid_under_its_patch_spring`
   failed on the patch as built (`|omega|` 0.260824, expected under 1e-6), passes with the amended
   two lines; the patch's zero-slip test still passes.
2. **(ii) The mass law.** New `test_a_pushed_body_gains_speed_on_its_mass_and_its_wheels_inertia`
   (the 1500 kg bench in N, 1500 N on the body, 40 ticks under 1.5 m/s): gains 1.0000 of
   `F / (M + sum I / r^2)`, held at 1 % (`F / M` would read 1.024). First run read 0.9532: Godot's
   default linear damp (0.1 /s) on the bench body, zeroed in the test.
   `docs/vehicles.md` § One force at the patch rewritten round the law (check_docs: 53 left).
   At HEAD (the same test, scratch, in the worktree) it reads 0.5791: the bench's four contacts
   carried 0.73 of the body's mass beside it.

## Measured (HEAD -> after), `--fixed-fps 60`

- `doc=park`: every held cell within 1 mm along and across but one: `semi 30 % cross` along
  15.5 -> 14.2 mm (peak 0.155 -> 0.148 m/s; it creeps at HEAD too). Largest other: `semi 30 % foot`
  across -0.2 -> -1.1. The pawl slides (`garbage-truck`, `semi`, 10 and 30 %) are HEAD's.
- `suv park=16.7 pawl`: +0.2 mm both (amendment (i) holds; the patch as built slid 5 m).
- `all creep`: every body creeps faster on the flat (van 4.8 -> 5.8 km/h, suv 5.4 -> 6.1); held
  grade the same on every body but `hatchback-sports` 5.3 -> 4.9 % (one bisect step, one body).
- `sedan rollback`: hold on 0.3 / 1.0 -> 0.0 / 0.0 mm, forward at 0.97 / 1.10 -> 0.88 / 0.98 s;
  `nohold` 36.6 / 333.2 -> 48.5 / 503.6 mm, forward at 1.05 / 1.88 -> 0.97 / 1.87 s (the honest mass,
  amendment (ii)).
- `semi rollback`: 10 % forward at 1.17 -> 1.13 s, 15 % 1.27 -> 1.23 s, 20 % 1.47 -> 1.40 s (sooner:
  amendment (iii)'s judge); 25 % 3.10 -> 4.27 s (the coast cell). `nohold` 10 % 6.0 -> 6.9 mm,
  25 % 927.3 -> 886.0 mm, never forward both.
- `sedan 45 brake`: 0-50 3.47 -> 3.20 s, 0-100 8.28 -> 8.03 s, launch grip use 0.91 -> 0.95; stops
  30 % 157.3 -> 156.1 m, 60 % 62.4 -> 61.9 m, 100 % 41.6 -> 40.7 m (0.95 -> 0.98 g). Every stop shorter.
- `tractor-kenney 8 trace`: HEAD's take-up alternates tick to tick (`a g` 0.12 0.04 0.13 0.09 at
  0.17 s; 0.50 0.44 0.51 0.48 at 0.93 s); after, a smooth rise to a 0.45 g plateau, no alternation.
- `measure_semi_launch` bobtail `steady`: sign changes 1.3 -> 0.7 /s, axle step 0.12 -> 0.11 kg;
  laden `steady strict` axle step 0.80 -> 0.95 kg a tick (under 2; the towing item's (c)).
- `measure_vehicles semi 20 rest`: rear axle 0.7 -> 0.6 kg a tick, drag 7 -> 11 N a wheel.
  `trailer=bobtail`: sign changes 1.3 -> 0.7 /s, rear axle p-p 1.5 -> 0.7 kg, speed step in the
  first second 2.40 -> 1.08 mm/s; the drag-sign flips at 0 N 8.0 -> 13.7 /s and "the contact off
  the rim's" 0.52 -> 1.21 (at a contact speed of 0.00 mm/s).
- `all 45 track strict`: every body PASS (the two non-zero drifts 0.027 and 0.029 m).

No stop condition hit but one cell read literally: `semi 30 % cross` moved 1.3 mm, toward a
better hold. Asked the user: land it.

## The `doc=` tables (7a7cd9f)

All sixteen regions re-run. Launches about a quarter second sooner (`doc=accel` sedan 0-50 3.48 ->
3.20 s, `race` grip use 0.93 -> 1.00), stops shorter, cruise and wind within a digit; the ESC
table does not move. `doc=grade`: every body the same or up a bisect step but `suv` asphalt
79.0 -> 71.3 %. Its bisect, `measure_grade -- suv verbose` after the fix:

    33.75 deg CLIMB  speed 3.84 | 39.38 fail -1.93 m/s | 36.56 fail 0.00 m/s (suspension 9359 N)
    35.16 deg CLIMB  speed 3.53 | 35.86 fail +10.49 m/s, sum f_long 3940 N | 35.51 CLIMB

Not monotonic, and 35.86's failure looks like a slide back with the tyres nearly unloaded. Not
traced (a new item: Queue). `doc=brake_fade`: on ice the laden `semi` jackknifes at 75 deg with
the foot brake and the retarder, as at HEAD; which of the two leaves the ramp swapped.

## Deferred

- The `suv` climb (Queue, Opus).
- The rest gates' limits re-sized on the new figures (Queue, Sonnet).

## Commits

- d22b3ee review: the body takes the tyre's force at the settled slip
- 7a7cd9f review: doc= tables re-measured on the settled-slip force
- the journal's

## Measured (HEAD -> after)

## Commits

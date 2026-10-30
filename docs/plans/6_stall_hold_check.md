# Plan — The stall-hold check against the sim

`BrakeSizing.stall_hold_margin` counts a driven wheel spinning against its brake (a brake-stand
burnout) as pushing at its tyre's PEAK grip. The sim's grip curve falls past its peak (0.9 at slip
0.4, 0.8 at full slip on the Kenney and truck specs), so a wheel spinning at a near-standstill
pushes with less than the check assumes. At a converter stall ratio of 2.0 that decides two bodies:
`sedan-sports` reads 0.937 and `police` 1.0000 at any brake under the size that stops the rears
spinning (4334 N·m on `sedan-sports`), because there the margin is front grip against rear grip,
not brake against drive (`docs/drivetrain.md` § Converter). `police`'s 1.0000 is
an exact tie, so its `>= 1.0` passes only until a float rounds the other way.

The check also errs the other way. `suv-luxury` (AWD, a 3:1 Torsen centre) reads 1.15 at 2.0, the
centre carrying what its bias allows to the fronts' spare brake, yet floored on both pedals it
creeps 0.117 m in 10 s (`measure_vehicles -- suv-luxury 30 stall`, 2026-10-24), where every other
body moves under 2.5 cm. The check's one transfer at the stall drive and the coupled solve
(`WheelDrive._couple_differentials`, one pass a tick) disagree on this body.

All three stay at 1.0 until this plan finds where the check and the sim part, settles the check's
law with the user, and ships each at 2.0 if it then holds with a real margin.

Written 2026-10-24. Status: **not started.**
Serves: the "how an automatic pulls away" lesson — both pedals floored at stall read honestly
(`docs/vehicles.md` § Both pedals), and the brake-stand burnout a RWD car really does.
State: done — nothing; next — phase 0; open findings — none.

The other converter bodies ship 2.0 (1.98 on the Kenney trucks); `sedan-sports`, `police` and
`suv-luxury` stay at 1.0 until this plan's phase 2.

## Phase 0 — What the sim does (effort: low; mode: accept-edits)

- With `converter_stall_ratio` 2.0 set in memory (a throwaway hook, never committed), run
  `measure_vehicles -- <variant> 30 stall` on `sedan-sports`, `police` and `suv-luxury`, plus one
  passing RWD body as a control (`van`). Read: HOLDS / CREEPS, distance moved, the spinning rear's
  slip and longitudinal force over its peak grip, and on `suv-luxury` the torque its centre
  carries against `Differential.bias_capacity` at the stall drive.
- Compute the static margin with a spinning driven wheel counted at the curve's value at that
  slip instead of at peak, for the same bodies; on `suv-luxury`, say which of the check's
  assumptions the coupled solve breaks.
- Done when: one table — static margin as shipped, static margin at the curve's slip value,
  dynamic distance moved — per body, and the user has seen it.

## Phase 1 — The check's law, decided with the user (effort: medium; mode: plan-mode-first)

- Options laid out, each with the phase 0 numbers: keep peak (the conservative bound; `sedan-sports`
  stays at 1.0); count a spinning driven wheel at the grip curve's value at the slip it settles
  at (the check then reads the sim's own tyre, rule 3); or another law the phase 0 data suggests.
- Source what a real RWD automatic does on both pedals at stall (holds, or creeps in a brake-stand
  burnout) from a page actually opened; the grip curve's tail figures: cite where they come from
  (`docs/sources.md`) or label them estimates.
- Relaxing `test_vehicle_catalog`'s stall assertion is the user's call; no change before the pick.
- Done when: the law is recorded here.

## Phase 2 — Ship it (effort: medium; mode: accept-edits)

- The picked law in `BrakeSizing.stall_hold_margin`, with gdUnit4 cases for it beside the existing
  margin tests in `tests/test_vehicle_catalog.gd` (rule 8).
- For each of `sedan-sports`, `police` and `suv-luxury` that then holds at 2.0, statically with a
  margin clear of a float tie and dynamically under the both-pedals list's 5 cm: follow the `vehicle-feel` skill, set its ratio in `tools/gen_kenney_vehicles.gd`, regenerate.
- Update `docs/vehicles.md` § Both pedals and § Brake hardware and the code comment at
  `stall_hold_margin` to the new law; the COMPROMISEs in `docs/drivetrain.md` § Converter and at
  the recipe shrink to the bodies still at 1.0.
- `test_vehicle_catalog`, `test_drivetrain` pass.

## Phase 3 — Re-measure (effort: low; mode: accept-edits)

- In the background with `--fixed-fps 60`: `measure_vehicles -- <variant> 30 stall` on
  `sedan-sports`, `police` and `suv-luxury`, at HEAD first and after, alone against alone; the both-pedals list in
  `docs/vehicles.md` reads the new figures.
- Done when: the docs read the new figures and the user has floored both pedals on `sedan-sports`
  for feel.

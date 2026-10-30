# Plan — `hatchback-sports` on the coupling its reference has

`hatchback-sports` ships a torque converter held at ratio 1.0, a fluid coupling (a COMPROMISE in
`tools/gen_kenney_vehicles.gd`). Its reference, a Mk7 Golf GTI, is a six-speed manual or a
six-speed DSG, a wet dual-clutch box, with no converter (secondary: a buyer's guide and a review in
a search summary). If that holds, the honest model is a clutch coupling, not a converter at 1.0:
it changes how the body creeps, launches and shifts, so it is its own plan.

Written 2026-10-24. Status: **not started.**
Serves: the "how an automatic pulls away" lesson — a converter car and a dual-clutch car side by
side, each read off its own coupling (`rpm`, `engine_load`, creep at idle).
State: done — nothing; next — phase 0; open findings — none.

## Phase 0 — What the GTI has, from opened pages (effort: medium; mode: plan-mode-first)

- Source, from a page actually opened: the Mk7 GTI's gearboxes (manual, DSG and which DSG), and
  for the DSG its launch behaviour (does it creep at idle on the brake release; its launch slip or
  launch rpm) and its shift (clutch-to-clutch overlap, time).
- Read what the sim's clutch path gives a road body today (`VehicleSpec.Coupling.CLUTCH`;
  `launch_engage_s`, `launch_rpm_over_idle`, `shift_handover_s`, `shift_cut_s`; the racers' and
  the semis' settings) and whether a clutch body creeps.
- Done when: a short table of the GTI's figures beside what the sim's clutch path can express, and
  the user has picked: a DSG-class clutch body, keep the COMPROMISE, or something else.

## Phase 1 — Ship the pick (effort: medium; mode: accept-edits)

- Follow the `vehicle-feel` skill: the recipe in `tools/gen_kenney_vehicles.gd`, regenerate,
  `test_vehicle_catalog`, `test_kenney_variants`, `test_drivetrain` pass.
- Retire or rewrite the COMPROMISE at the recipe and in `docs/drivetrain.md` § Converter, and the
  `hatchback-sports` mention in `docs/vehicles.md` § Rejected designs.

## Phase 2 — Re-measure (effort: low; mode: accept-edits)

- In the background with `--fixed-fps 60`, at HEAD first and after, alone against alone:
  `measure_vehicles -- hatchback-sports 45 trace`, `-- hatchback-sports 30 stall`, and
  `measure_grade -- hatchback-sports rollback` with and without `nohold`; the generated tables
  re-run where the body appears (`doc=accel`).
- Done when: the docs read the new figures and the user has driven a launch and a stop-and-go on
  `hatchback-sports` for feel.

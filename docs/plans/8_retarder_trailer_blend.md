# Plan — The retarder's share of the trailer brake

On a long descent the semi's retarder keeps the tractor's brakes at ambient, but the 24 t box still
fades: `TruckTelemetry.trailer_brake_blend` adds the retarder's share (`Drivetrain.retarder_fraction`,
0.068 on the semis) to the trailer's friction-brake demand, so on a retarder-held 7 % descent the
trailer reaches 459 °C and a fade factor of 0.87, almost the foot brake's 466 °C
(`docs/vehicle_measurements.md` § Brake heat). The share exists so a retarding tractor is not
pushed by its trailer (`docs/truck.md` § Air, retarder). This plan settles how a real EBS treats an
endurance brake, then changes the blend so that the retarder spares the rig's friction brakes
without the trailer pushing the unit.

Written 2026-10-24. Status: **not started.**
Serves: the "why trucks have retarders" lesson on a rig (the brake heat plan's finding 1, above),
read off `brake_temp` and the trailer's own brakes; `trailer_brake_demand` (ISO 11992 EBS11) as a
real EBS sends it.
State: done — nothing; next — phase 0; open findings — none.

Builds on the brake heat model (`BrakeThermal`) and `measure_grade`'s `descent` pass. Towing is shared: the change
lands in `TowHost` / `TruckTelemetry`, never on one machine (`src/vehicles/CLAUDE.md` § Physics).

## Decisions for the user (asked in phase 0)

1. **The blend.** From phase 0's sources, one of:
   - (a) the retarder sends the trailer nothing (an endurance brake on the tractor alone);
   - (b) a share capped at what keeps the coupling force under a stated bound;
   - (c) a coupling-force control: the trailer demand set so the kingpin's longitudinal force stays
     near zero, which on a steady descent asks less than (a)'s push and more than nothing;
   - (d) the share kept, and the finding recorded as how the shipped EBS behaves.
2. **Low grip.** Whether a retarder-held rig on a low-mu descent with less trailer brake is in
   scope (a pushing trailer is a jackknife risk), or measured only.

## Phase 0 — Sources and decisions (effort: high; mode: plan-mode-first)

From pages actually opened, or labelled estimates:
- what EBS does with the endurance brake: UN R13 (the endurance-braking and the
  compatibility annexes: the coupling-force bands between a towing unit and its trailer), and the
  EBS makers' own descriptions of retarder integration or coupling-force control (WABCO, Knorr-Bremse,
  Haldex) if their pages are open;
- ISO 11992-2 EBS11's demand: whether the towing unit's demand includes an endurance brake's share;
- whether a real retarder-held descent keeps the trailer's brakes cool (any field run with the
  trailer's brake temperatures, e.g. the WY-1901F / Yaxi runs `docs/sources.md` § Brake heat
  already cites).
- The two decisions above, asked once, recorded here.
- Done when: every claim has a source or a labelled estimate, and the decisions are recorded.

## Phase 1 — The blend (effort: medium; mode: accept-edits)

- Change `TruckTelemetry.trailer_brake_blend` (and its caller in `semi.gd`, or `TowHost` if the
  chosen law needs the coupling's state) per decision 1; a coupling-force law reads the joint's
  force out of the sim (root rule 3), never a derived estimate.
- `tests/test_trailer.gd` and `tests/test_truck.gd` pin the blend today (the share's arithmetic,
  the crawl cut-out, the 0.068 fraction): re-pin them on the new law; `retarder_fraction` keeps its
  own tests if it stays in use.
- `trailer_brake_demand`'s contract `desc` says the demand is blended from the foot brake and the
  retarder: if that changes, the `contract-edit` skill (a version bump, the sloppyCAN copy, a paired
  promote).
- `docs/truck.md` § Air, retarder: the share's paragraph follows the new law.

## Phase 2 — Measure (effort: medium; mode: accept-edits)

- `measure_grade -- semi descent`: on the retarder run the
  trailer's brakes stay under fade onset (or the chosen law's stated bound), and the energy check
  holds ±5 %. Print the kingpin's longitudinal force on the hold beside it.
- If decision 2 put low grip in scope: the same descent on a low-mu patch (`measure_rig`'s
  `GripPatch`), the rig's articulation angle held under a bound stated before the run.
- `doc=brake_fade` regenerates its region; the finding above closes.
- Done when: the retarder run spares both ends' friction brakes and the rig does not push past the
  stated bound; the user drives `semi` + box on the retarder for feel.

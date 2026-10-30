# Plan — The semi-trailer's own stability function

A laden semi tips on its trailer, and the trailer brakes only when the tractor asks
(`TowedBody.tick_towed` follows `trailer_brake_demand`). A real air-sprung semi-trailer carries
its own stability function in its EBS: it senses its own lateral acceleration and load, brakes
itself before the trailer rolls, and reports "VDC active" to the tractor over ISO 11992, which J1939
carries to the cab as SPN 5624 (`docs/sources.md` § Stability control). This plan gives the
towed body that function: roll-over control at least, read off the trailer's own sim.

Written 2026-10-25. Status: **not started.**
Serves: the "trailers roll over first" lesson on a rig, made visible with the tractor's ESC off;
a trailer VDC-active flag on the ISO 11992 bus, read out of the trailer's own intervention.
State: done — nothing; next — phase 0; open findings — none.

Follows the tractor's ESC (`docs/handling.md` § Stability control, which brakes the trailer only
through `trailer_brake_demand`), which lands the tractor's
roll stability and its ESC-active bit first. Towing is shared: the trailer's function lives on
`TowedBody`, never on one trailer (`src/vehicles/CLAUDE.md` § Physics).

## Decisions for the user (asked in phase 0)

1. **Scope of control.** Roll-over control only (R13 5.2.2.23's minimum for O3/O4 trailers), or
   directional control too (selective braking against trailer swing, R13 Annex 21 2.2.1).
2. **Which trailers.** The four semi-trailers (`box`, `flatbed`, `tanker`, `tipper`) take it;
   whether the tractor's `farm_tipper` does too, from phase 0's sources on agricultural trailers.
3. **Two controllers, one brake.** When the tractor's roll stability and the trailer's own both ask
   the trailer to brake, how the demands combine (the higher one, or the sum capped at the
   hardware), from the sources on EBS behaviour if they say.
4. **Signal.** A contract `in`/`out` flag on `truck` (`flavor: "iso11992"`, beside `trailer_abs`)
   for ISO 11992-2's VDC active; whether its J1939 mirror (SPN 5624) is also a signal or a
   `desc` note.

## Phase 0 — Sources and decisions (effort: high; mode: plan-mode-first)

From pages actually opened, or labelled estimates:
- the trailer function's requirements: R13 5.2.2.23, Annex 21 2.2 (its inputs: wheel loads, or at
  least lateral acceleration and wheel speeds; its "VDC active" reporting, 2.2.4; select-low to
  select-high during an intervention, 2.2.5), and Annex 19 Part 1 paragraph 6's test report if open
  (`docs/sources.md` [179] holds the 11 series copy);
- how a trailer EBS sets its roll threshold from its load (WABCO / Knorr-Bremse / Haldex TRSP-type
  descriptions, if their pages are open), else a labelled estimate keyed on the trailer's
  measured tip;
- ISO 11992-2's VDC active parameter (6.4.2.2.36): which message and states, if a page is open;
  J1939's SPN 5624 states are already recorded;
- NHTSA's finding that tractor-based systems held off trailer wheel lift to higher speeds than
  trailer-only systems ([184]): the expectation phase 3 measures against.
- The four decisions above, asked once, recorded here.
- Done when: every claim has a source or a labelled estimate, and the decisions are recorded.

## Phase 1 — The function, pure and tested (effort: medium; mode: plan-mode-first)

- Static functions (root rule 8) beside `StabilityControl` (or inside it, if plan 3's shape
  allows): from the trailer's lateral acceleration, wheel speeds and its load
  (`TowedBody.bogie_suspension_force`, the EBS load sensing), the roll threshold and the brake
  demand past it, proportional and rate-limited, never the cycling ABS/TC design
  (`docs/vehicles.md` § Rejected designs). Directional control too if decision 1 says so.
- Its gdUnit4 tests: below the threshold it asks nothing; the demand rises with the excess and
  never passes the trailer's declared brake; a heavier load lowers the threshold.

## Phase 2 — Wire it in and publish it (effort: high; mode: plan-mode-first)

- `TowedBody.tick_towed` combines the tractor's demand and its own per decision 3, through the
  same lagged service term and the trailer's own ABS, so the heat model (`BrakeThermal`) sees it.
- The flag per decision 4 through the `contract-edit` skill, read out of the trailer's own
  intervention this tick (root rule 3); bobtail publishes a real "not installed" / false, as
  `clear_trailer_bus` does for the rest of the group. The tractor's lamp follows R13 Annex 21
  2.1.6 (warn the driver when the trailer reports VDC active).
- The flag gets a row in `docs/truck.md` § ISO 11992: brakes and running gear only.

## Phase 3 — Measure (effort: medium; mode: accept-edits)

- The laden semi's tipped cells (the corner pass and plan 3's J-turn), background,
  `--fixed-fps 60`, a baseline at HEAD first: tractor ESC off with the trailer function on and off,
  and both on.
- Done when: the trailer function alone holds off or slows the laden rig's trailer tip, both
  together hold at least as well as the tractor's alone, nothing chatters, and its figures go into
  a `<!-- measure:<id> -->` region (never loose figures); the user drives the laden box rig through
  a fast bend with the tractor's ESC off for feel.

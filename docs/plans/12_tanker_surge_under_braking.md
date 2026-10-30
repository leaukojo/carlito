# Plan — The tanker's surge under roll-stability braking

Roll stability brakes the rig as it nears its tip (`StabilityControl.roll_application`). On the
tanker, that braking drives the surge model forward (`tanker.gd`: `surge_target` off the
longitudinal acceleration, `set_load_offset` moving the real centre of mass), the kingpin load
rises and the tractor lifts earlier: with plan 3's first share (0.8) and no steer term, the laden
tanker lifted on the slow wind-on at a lower tractor g than unbraked; the shipped share (0.7) and
the steer term hold it, by margin rather than by understanding (`docs/handling.md` § Stability
control). Whether the surge's answer to braking is honest, and whether the roll table should
read the live coupled load, is open.

Written 2026-10-25. Status: **not started.**
Serves: the "liquid loads surge" lesson on the tanker, honest under the braking the rig's own
electronics command; the tanker's roll stability holding by its model, not its margin.
State: done — nothing; next — phase 0; open findings — none.

## Decisions for the user (asked in phase 0)

1. **Surge model.** Keep `surge_target` / `surge_step` as they are, or bring them to a sourced
   figure for a baffled tank's forward shift and lag under braking, if phase 0 finds one.
2. **Roll table under surge.** The table reads `brake_load_kg` (the live kingpin share, which the
   surge moves): keep it live, or read the parked load so braking does not lower the threshold
   mid-intervention.

## Phase 0 — Sources and a measurement (effort: medium; mode: plan-mode-first)

- From pages actually opened, or labelled estimates: a tanker's longitudinal surge under braking
  (baffled vs smooth-bore, its shift and period) and its effect on rollover threshold.
- Background, `--fixed-fps 60`: `measure_semi_launch -- semi trailer=tanker ramp` and the step
  pass with the tanker, ESC on: the surge offset, the kingpin load, the roll application and the
  tractor g at first lift per tick through an intervention; the same with the surge pinned at 0 in
  memory, to size its share.
- The two decisions above, asked once, recorded here.

## Phase 1 — Apply and measure (effort: medium; mode: plan-mode-first)

- Per the decisions; gdUnit4 for any changed pure function (`tanker.gd`'s statics,
  `StabilityControl`). Re-run phase 0's runs and the tanker's rows of plan 3's step and corner
  passes, baseline at HEAD first; no chatter; `docs/truck.md` updated in place.

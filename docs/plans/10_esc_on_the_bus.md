# Plan — ESC on the bus: the brake-light request and the truck's VDC frames

Stability control brakes wheels (`StabilityControl`, `docs/handling.md` § Stability control) but
that braking reaches neither the brake lamp nor `Drivetrain.braking` (the converter's lock-up
release), and the truck's ESC-active bit (status bit 7) never becomes the J1939 frames a real
truck's stability unit sends: VDC1 (PGN 65103: SPN 1813 lamp, 1814 fully operational, 1815
brake-light request, 1816-1819 ROP / YC engine and brake control active) and VDC2 (PGN 61449:
steering wheel angle, yaw rate, lateral and longitudinal acceleration; `docs/sources.md`
§ Stability control, [159]). sloppyCAN's j1939-flavor.js transmits neither ("nothing in
sloppyCAN transmits EBC1, VDC2, ...").

Written 2026-10-25. Status: **not started.**
Serves: the brake lamp lighting when the car brakes itself; the truck's ESC intervention readable
on the J1939 bus as the real VDC1 / VDC2 groups.
State: done — nothing; next — phase 0; open findings — none.

Follows `docs/handling.md` § Stability control (ESC and roll braking are not
`drivetrain.braking` nor the brake lamp; one ESC-active bit, read on a truck as VDC1 YC / ROP).

## Decisions for the user (asked in phase 0)

1. **Lamp authority.** sloppyCAN is the sole authority on lamp state while the bridge drives
   (`brakeLamp` is an `in` bit). Whether ESC's brake-light request is an `out` signal (a status bit
   or the truck's VDC1 SPN 1815) that sloppyCAN mirrors into its lamp command, the local router
   ORing it into `lamps.brake_lamp`, or something else the sources support.
2. **When it lights.** Every ESC brake application, or only past a deceleration threshold, from
   the regulation's rule for automatically commanded braking if a page says (R13-H / R13).
3. **`Drivetrain.braking`.** Whether ESC's and roll stability's brake count as braking for the
   converter's lock-up release, as a TCU sees a brake-light switch.
4. **VDC2's scope.** VDC2 publishes the unit's own sensors (steer, yaw rate, accelerations):
   whether the truck sends it at its 10 ms rate or a slower one the bridge can carry.

## Phase 0 — Sources and decisions (effort: medium; mode: plan-mode-first)

- From pages actually opened, or labelled estimates: the stop-lamp rule for braking a stability
  function commands, the trailer's own included (WABCO's RSS requests none by default [195];
  R13 5.2.2.22.1 not opened); VDC1's SPN 1813-1819 states and VDC2's layout (J1939-71 [159] is open);
  how a TCU treats ESC braking for the lock-up, if a source says.
- The four decisions above, asked once, recorded here.

## Phase 1 — The brake light and the drivetrain (effort: medium; mode: plan-mode-first)

- Per decisions 1-3: the request read out of the tick's real ESC and roll torques (root rule 3),
  through the `contract-edit` skill if a signal is added; `Drivetrain.braking` per decision 3.
- gdUnit4: no request with ESC idle; a request while it brakes per decision 2; the pedal's own
  lamp unchanged.

## Phase 2 — VDC1 / VDC2 in sloppyCAN (effort: medium; mode: plan-mode-first)

- sloppyCAN's j1939-flavor.js packs VDC1 off status bit 7 (YC and ROP control active, decision 5 of plan
  3), `esc_off` (SPN 1814) and the phase 1 request (SPN 1815); VDC2 per decision 4 off signals
  the contract carries or adds. Layout read off J1939-71, as the file's own rule says; the groups
  join j1939-tables.js's `J1939_DB` so its j1939.js decodes them. A paired change: both repos on
  `dev`, promoted together (`docs/deploying.md`).

## Phase 3 — Verify and document (effort: low; mode: accept-edits)

- The truck's frames in sloppyCAN's J1939 tab during a step-pass spin; the brake lamp lighting in
  `car_arena`'s wet bend with ESC acting (the user, for feel); `docs/truck.md` and
  `docs/handling.md` § Stability control updated in place.

# Plan — Telemetry honesty: aux models and contract texts

Several published signals are not read out of the model that produces the motion, or their
contract text says something the code does not do. On the boat, `fuel` and `fuel_rate` come from
two unreconciled models. Battery voltage droops with fuel rather than with electrical load. The
truck's air is drawn only on the driver's pedal. `trailer_brake_demand` publishes the trailer's
lagged response, not what EBS11 sent. `engine_load` and `throttle` describe themselves wrongly.
Findings: `reviews/A_vehicle_physics.md` #5, #9, #10, #11, #12, #17, and its "Noticed outside the
scope" (the boat cannot go astern from the bridge).

Written 2026-11-05. Status: **not started.**
Serves: rule 3, every aux signal a simple honest model read out of the sim, labelled.
State: done — nothing; next — phase 0; open findings — none.

## Phase 0 — Sources and decisions (effort: medium; mode: plan-mode-first)

Read only; the output is a short report and the user's answers.
- `engine_load` (#10): read SPN 92 and SPN 513 / 544 in the local J1939-71 PDF
  (`../j1939-71.pdf`) and cite the page. Then decide: rename the flavor note (SPN 513-like), or
  publish `applied_throttle` as SPN 92 and keep the torque reading under its own name.
- `trailer_brake_demand` (#5): publish `demand01`, what the towing unit sent (recommended). Decide
  whether the trailer's applied level gets its own towed-to-towing signal beside `trailer_abs`.
  Recommended: not now, since it would be a new signal.
- Battery (#11): droop on the lamps actually lit, or hold the charging voltage flat. Decide also
  the train's auxiliary supply, gated on the pantograph. Recommended: lamps; the train flat while
  the pantograph is up.
- Boat astern from the bridge: a `gear` input for `boat`, or leave astern local-only. This is a
  contract and arbitration change (`src/input/`), so the user decides.

Done when the user has answered the decisions.

## Phase 1 — Contract texts (effort: low; mode: accept-edits)

- One contract bump through the `contract-edit` skill. It covers `throttle` (#17: "the arbitrated
  pedal; the delivered fuel shows in `engine_load` / `fuel_rate`"), `trailer_brake_demand` with
  `semi.gd:112` and `truck_telemetry.gd:46` agreeing (#5), and `engine_load` per decision (#10).
- Done when the contract tests and the sloppyCAN copy check pass, and the paired promote is noted.

## Phase 2 — One fuel chain for the rigid crank (effort: high; mode: plan-mode-first)

- Boat and plane (#9) use the wheel-driving bodies' chain: `VehicleTelemetry.fuel_rate_lph` on the
  crank's `rpm` and `applied_throttle`, drained through `fuel_drain` from `tank_litres`, with the
  coolant on the burn's share of `rated_fuel_rate_lph`.
- This retires `FUEL_IDLE_BURN` / `FUEL_LOAD_BURN` and `BoatTelemetry.fuel_rate_model`.
- Tests: tank drain equals the integrated `fuel_rate`; coolant follows the burn.
- Done when the user has run a boat at idle and at full throttle and the readouts agree.

## Phase 3 — Battery and air draws (effort: medium; mode: accept-edits)

- Battery per decision (#11), with a pure law and a test.
- Truck air (#12): draw on the rise of the service level actually applied, meaning the pedal raised
  by `drive.roll_application()` plus the ESC yaw corners' share. Test: an ESC intervention with no
  pedal draws air.
- Done when the tests are green.

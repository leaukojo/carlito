# Plan — Brake heat and fade

The foot brake never tires: a truck braking down `level_2`'s long grades on the service brake
alone stops as short at the bottom as at the top, so the retarder and engine braking
(`docs/truck.md` § Air, retarder) have no consequence to teach. This plan gives every service brake
a lumped heat model: the brake's own dissipated power heats it, the air cools it, and past a
temperature its torque falls (fade). A simple honest model, labelled (root rule 3).

Written 2026-10-23. Status: **not started.**
Serves: the "why trucks have retarders and drivers use a low gear downhill" lesson; a
`brake_temp` reading on the bus, read off the sim's own dissipated energy.
State: done — nothing; next — phase 0; open findings — none.

Reads the brake classes' fade record (`docs/sources.md`, *Brake hardware*: each class's rotor or
drum size, mass and lining). `3_stability_control.md` is independent; if both land, ESC's
brake use heats the brakes through this model with no extra code.

## Decisions for the user (asked in phase 0)

1. **Signal.** A contract `brake_temp` out (°C; one value, the hottest brake, or one per axle as an
   array) on car, truck and tractor, or no signal and fade only felt. A J1939 brake-temperature SPN,
   if phase 0 finds one on an opened page, sets the truck's encoding; otherwise the signal is
   Carlito's own, labelled.
2. **Lamp.** Whether a hot brake lights an existing lamp (`amber_warn` on the truck) or none.
3. **Tractor.** Wet discs in oil fade little: the tractor takes the model with its own figures, or
   opts out by spec flag with the reason.

## Phase 0 — Figures and decisions (effort: high; mode: plan-mode-first)

From pages actually opened (root `CLAUDE.md` § Working style), or labelled estimates:
- heat capacity: per class from the phase 1 record (rotor or drum mass, cast iron's specific heat);
- cooling: a convective coefficient rising with road speed (`h0 + h1 · v`), over the rotor's
  swept area; radiation in only if the sources show it matters over the range the descents reach;
- fade: the lining's friction against temperature for a passenger pad and a truck drum lining
  (onset and the fall past it), plus drum expansion fade if sourced;
- ambient: the level's (a constant until weather gives one).
- The three decisions above, asked once, recorded here.
- Done when: every figure has a value and a grade, and the decisions are recorded.

## Phase 1 — `BrakeThermal`, pure and tested (effort: medium; mode: accept-edits)

- A new `BrakeThermal` class in `src/vehicles/base/`, static functions only (root rule 8):
  `step(temp, power_w, speed, delta, figures) -> temp` (explicit; its time constants are seconds to
  minutes, far from the 60 Hz edge) and `fade_factor(temp, figures)` in (0, 1], 1 below onset.
- Its figures live on `GroundDriveSpec` per axle (heat capacity, cooling, the lining's curve),
  defaulting to "no thermal model" (factor 1 for ever) so no body changes until it declares them.
- Its gdUnit4 test file: with cooling off, the heat in equals `C ΔT` (`∫ P dt` over steps of any
  size); zero power heats nothing; cooling at rest and at speed decays toward ambient, never past
  it; the factor's ends and monotonic fall. The whole-body energy check (a stop's `½ m v²` less what
  rolling and air take, landing in the brakes) is phase 4's, on a live body.

## Phase 2 — Wire it into the spin step (effort: high; mode: plan-mode-first)

- Power: each wheel's brake torque actually reacted this tick times its spin; never the commanded
  torque (a locked or held wheel dissipates nothing at the rotor). No such output exists today
  (`WheelDrive.retarder_torque_applied` is the commanded figure): the settle
  (`RayWheel.settle_spin`) gains a per-wheel reacted-brake output. `brake_t` sums the foot brake,
  the parking brake and the retarder; the reacted torque is split in proportion to those commanded
  shares, and only the friction brakes' share (foot and parking, one rotor or drum) heats it. The
  retarder's share heats nothing here.
- Fade acts on the declared hardware: `WheelDrive.tick`'s `brake_t` multiplies the service share
  by the wheel's factor, inside the spin step as every wheel torque is (`src/vehicles/CLAUDE.md`
  § Physics). The service share is every foot-brake demand: the pedal, the hill hold and, if it
  lands, ESC. The pedal map stays anchored on the cold capacity (`brake_application`), so a faded
  brake asks more pedal for the same deceleration, which is what fade feels like. The handbrake and
  spring brakes heat the drum but do not fade (hot-drum parking is out of scope).
- Trailers: `TowedBody.tick_towed` takes the same model on its service term (`_brake_actual ·
  brake_torque`), its parking term heating without fading (towing is shared: `TowHost` /
  `TowedBody`, never one machine).
- State lives on the wheels; `BaseVehicle.reset_session_state()` (and `TowedBody.reset_body()`)
  returns every brake to ambient, never `respawn()` alone.
- `BrakeSizing` and `test_vehicle_catalog` stay cold-brake checks: nothing there moves.
- Declare figures per class: the Kenney recipes (`tools/gen_kenney_vehicles.gd` + regen, the
  `vehicle-feel` skill), the semis' and trailers' `.tres`, the tractor per decision 3.

## Phase 3 — Telemetry (effort: medium; mode: accept-edits)

- Per decision 1 and 2: the `contract-edit` skill (version bump, test assert, sloppyCAN copy);
  `VehicleTelemetry` reads the model's temperature, never a derived one; the dashboard walks the
  contract as usual.

## Phase 4 — Measure, then a level check (effort: medium; mode: accept-edits)

- `measure_grade` gains a `descent` pass: hold a set speed down a set grade for a set distance on
  (a) the foot brake alone, (b) a lower gear and the foot brake, (c) the retarder (trucks); print
  the peak temperature and factor, then a full-pedal stop from the hold speed against the same stop
  cold. Run in the background (`--fixed-fps 60`).
- The pass prints the energy check: the heat the brakes took against the stop's kinetic and
  potential energy less what rolling and air took, within a stated tolerance.
- Done when: on `semi` + 24 t and `garbage-truck` the foot-brake-only descent fades measurably and
  the retarder run does not; a `sedan` hard-stop series (several full stops back to back) shows the
  same trend; the model goes into `docs/vehicles.md` § Brake hardware and the figures into
  `docs/vehicle_measurements.md`, as a generated `<!-- measure:<id> -->` region (a `doc=<id>`
  preset written through `tools/doc_region.gd`), never loose figures: `tools/check_docs.mjs` holds the loose-figure count at its cap, and
  the top-level docs had 3 lines of headroom when this was written (trim, or the user raises a cap).
- The user drives `level_2`'s long grades for feel. If none is long enough to fade a laden truck,
  say so: a longer descent is a level change, a new plan.
- Optional, a new plan if wanted: a bridge-only challenge ("descend reading `brake_temp` off the
  bus, use the retarder"), since challenges are where the CAN lesson lives.

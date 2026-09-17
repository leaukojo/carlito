# Plan — wheeled feel, shared mechanisms: tyre load sensitivity (engine braking, shift cut and surface drag shipped)

Goal: the three things every wheeled body (car, truck, tractor, plane on the ground) is missing
that a driver feels every time they lift, corner or shift. All three are ONE code path each in
`Drivetrain` / `RayWheel` / `GroundDriveSpec`, gated by a spec knob that defaults to "off = today's
behaviour", so no shipped number moves until a family opts in. Family numbers are separate plans
(`heavy_vehicle_feel.md`, `centre_of_mass_heights.md`). Each phase stands alone; delete this file
when done and distil each phase's conclusion into `src/vehicles/CLAUDE.md`.

Written 2026-09-17. Status: **phases 1 (engine braking), 3 (shift cut) and 4 (surface drag) done 2026-09-17**, distilled into `src/vehicles/CLAUDE.md` § Drivetrain / § Wheels and `docs/systems.md`; phase 2 (the only one left) not started. Delete this file when it lands. Independent of `truck_model_hygiene.md`.

Read first, every phase: root `CLAUDE.md` (rules 3, 5, 8, 9), `src/vehicles/CLAUDE.md` § Wheels,
§ Measuring and § `VehicleMath`, `src/vehicles/base/drivetrain.gd` header (clutch-less: rpm
follows the wheels, the limiter is a fuel cut), `src/vehicles/base/wheel.gd` header (60 Hz
clamps, semi-implicit spin). Measure, never tune by feel: `tools/measure_vehicles.tscn -- all 45
track strict` is the CI gate and must stay green after every phase.

## What is wrong today (the evidence)

- **No tyre load sensitivity.** `RayWheel.tick` makes `f = mu * suspension_force * curve(slip)`,
  exactly linear in load. Weight transfer therefore cannot reduce a body's total grip, so the
  understeer/oversteer balance never emerges from the physics; only the `mu_lat` numbers set it.
  Real tyres lose ~10-20 % of mu per doubling of load.

## Phase 2 — tyre load sensitivity

Effort **high**. Mode: **plan-mode first**, then accept-edits. Opus for the tyre law and the
brake-derivation consequences, Sonnet for tests and the measure sweep.

Mechanism, in `RayWheel.tick` + `GroundDriveSpec`:

1. `GroundDriveSpec` gets `@export var load_sensitivity := 0.0` — fractional mu lost per doubling
   of load relative to the static per-wheel load. 0 = today's linear law.
2. Pure `static func load_scaled_mu(mu, load, ref_load, sensitivity) -> float`:
   `mu * (1 - sensitivity * log2(max(load, ref*0.25) / ref))`, clamped to `[0.5 mu, 1.25 mu]`.
   Above static load grip grows slower than load; below it, faster. `ref_load` is
   `corner_mass * g` (the live corner share RayWheel already carries, so a laden refuse truck
   re-references itself through `set_corner_mass_from`).
3. Apply to BOTH `mu_long` and `mu_lat` before the friction circle, never after (the circle must
   be drawn on the load-scaled budget).
4. **The consequence that makes this plan-mode**: `gen_kenney_vehicles._derive_brakes` sizes
   `brake_torque` at `BRAKE_GRIP_FRAC * mu_long * static load * r`. Under braking the front
   axle carries more than static, so its grip per newton drops and a 0.95-of-static brake
   torque now locks a front wheel that yesterday held. Decide in plan mode, with numbers off the
   sedan (front share 0.55 static, ~0.75 under 0.9 g braking, wheelbase 1.58, COM 0.2 m): either
   lower `BRAKE_GRIP_FRAC` to keep "full pedal never locks", or accept a front lock at full
   pedal as the honest outcome and keep the fraction. The retarder band and the trailer brake
   apportioning both ride on this fraction (`truck/CLAUDE.md` § Brakes), so the choice must be
   arithmetic, not a feel.
5. Numbers to ship: 0.10 on the car family, 0.08 on truck and trailers, 0.12 on the tractor
   (big soft tyres are more load-sensitive). Plane 0.
6. Tests (`tests/test_wheel.gd` or wherever RayWheel's pure functions live — check first):
   `load_scaled_mu` is identity at ref load and sensitivity 0, monotone decreasing in load,
   clamped. A tick-level test on a two-wheel fixture: with transfer toward one wheel the pair's
   summed lateral capacity is less than with even load.
7. Verify: `measure_vehicles -- all 45 track strict` (a body that tracked straight can start to
   pull if its static split moves the reference); the `sedan-sports` skid-pad figure in the
   accel report if one exists, else add a steady-state lateral-g reading to `measure_vehicles`
   (constant steer at 40 km/h, report the settled lateral acceleration and which axle saturates
   first). Before/after on sedan, suv, semi coupled to the box, tractor.
8. Distil into `src/vehicles/CLAUDE.md` § Wheels: the law, the reference load, and the brake
   fraction decision.

## Not in this plan

- Sinkage (the ray shortening with soil depth) and bulldozing: second-order next to the surface
  drag that shipped, and both touch the suspension geometry. Revisit only if mud still reads
  wrong.

- Steering slew (`steer_speed` 7/s on the car: full lock in 0.14 s on keys). Leave it: the speed
  taper hides it, and a gamepad user wants the speed. A per-source slew belongs in
  `src/input/`, not the vehicle.
- Ackermann geometry, brake bias, anti-roll bars: none is a feel problem at the shipped COM
  heights. Revisit anti-roll only after `centre_of_mass_heights.md`.

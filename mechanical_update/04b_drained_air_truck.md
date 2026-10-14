# 04b — A truck that loses its air, end to end

Shared context: `00_README.md`. Follows brief 04 (spring brakes as a torque, the park-brake
auto-neutral). Size: small.

## Summary

Below `TruckTelemetry.AIR_SPRING_BRAKE_BAR` (3 bar) on either circuit a truck's spring brakes apply
and its box drops to N. Both halves were tested only as parts; nothing drained a live truck's
reservoirs and checked what happens. A coupled trailer did not brake when the tractor's air gate
tripped.

## Tested as parts

- `test_truck.test_spring_brakes_are_the_handbrake_torque_and_no_stronger_than_the_service_brake`:
  `WheelDrive.parking_torque` arithmetic and spring brake <= service brake on the drum.
- `test_truck.test_the_drive_inhibit_engages_neutral_until_it_lifts`: `Drivetrain.drive_inhibit` on a
  bare `Drivetrain`.
- `test_truck.test_spring_brakes_apply_below_the_cut_in`, `test_spring_brake_notice_*`: the gate
  predicate and its notice.
- `test_trailer.test_coupling_and_pumping_the_brake_can_reach_the_spring_brake_gate`: the air
  arithmetic reaches the gate; no body moves.
- `measure_semi_launch -- <unit> strict` (CI) asserts the gate stays shut with air above 3 bar
  (`gate (spring brakes): 0 ticks true`); it never takes the air under the gate.

## Where it lives

- `TruckVehicle._tick_extras` (`src/vehicles/truck/truck.gd`): reads the gate off this tick's air,
  sets `drive.spring_brake` and `drivetrain.drive_inhibit` for the NEXT wheel tick (a one-tick lag,
  stated there), raises the notice.
- `WheelDrive.parking_torque` (`src/vehicles/base/wheel_drive.gd`): `max(handbrake, spring) *
  handbrake_torque` on the rears, no ABS.
- `Drivetrain.drive_inhibit` (`src/vehicles/base/drivetrain.gd`): D or R engaged as N. COMPROMISE
  stated there: it engages at any speed, where a real auto-neutral waits for the vehicle to stop.
- `TowHost.tick_towing` (`src/vehicles/base/tow_host.gd`): hands the trailer `input.handbrake` as its
  parking brake; the tractor's air gate does not reach it.
- Air model: `TruckTelemetry.air_step` (charges only while the engine runs, draws per press),
  `SemiTractor._trailer_air` (the trailer's own charge).

## Why it matters

- The spring brakes are sized as hardware (7 kNm a wheel on the Kenney trucks, 12 kNm on the semis,
  under the service brake on the drum), so "a truck with no air cannot drive away" rests entirely on
  the auto-neutral. A regression there is silent: the truck would drag its rears.
- **A coupled trailer keeps rolling free when the tractor's air gate trips.** A real trailer's
  spring brakes apply when its supply line loses pressure, the same event: a semi that loses its air
  stops on two tractor wheels with 24 t pushing behind them.

## Constraints

- Truck CLAUDE.md § Brakes, retarder, air: air is a GATE, not a bar; losing air has no ramp; the gate
  does not zero `retarder_state`; the tach falling to idle at the gate is correct.
- A probe is a game-mode tool scene or a gdUnit test that ticks a real truck, never a `--script`
  tool (autoloads).
- Draining the air honestly: the engine off stops the compressor (`running`), and the brake draws per
  press. A probe may also write `air_primary` directly, saying so.

## Done

- A test or measure drains a live truck's reservoirs under the gate and checks, on the garbage truck
  and on a coupled semi:
  - parked on 18 % (UN R13): it holds;
  - floored in D on the flat: the gear reads N and it does not move;
  - rolling at ~30 km/h: it stops, rears braked, with no drive into them.
- The trailer's spring brakes apply when the tractor's gate trips (through `TowHost`, both units), or
  the absence is justified in `truck/CLAUDE.md`.
- `measure_semi_launch` or the new probe documents the result in `docs/heavy_vehicles.md` § Air.

## Open decisions (user)

- Whether the auto-neutral keeps engaging at speed or waits for a stop, as a real Allison
  auto-neutral does.

## Related

Brief 04. `docs/heavy_vehicles.md` § Air, retarder, axle load.

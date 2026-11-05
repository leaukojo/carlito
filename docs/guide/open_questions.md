# Open questions

Places where the code and the developer docs disagree, or where the code looks wrong to a
reader. The guide does not explain these until they are checked; each entry names what the guide
says meanwhile. Newest last.

## 1. Mud's rolling drag: 0.1 or 0.2?

- **Code:** `src/levels/base/surface.gd` gives Mud an added rolling-resistance coefficient of 0.1
  (the `DRAG` table).
- **Docs:** `docs/tractor.md`, in the drawbar section ("Laden on 10 % mud the rig is
  traction-bound"), works the sum with "mud's 0.2 drag on the whole load".
- **Guide meanwhile:** the surfaces page will quote the code's 0.1 and not repeat the tractor
  doc's sum.

## 2. Which wheels does the tractor's wheel_speed read?

- **Code:** `src/vehicles/tractor/tractor.gd` (`_drive_axle_omega`) reads the mean spin of the
  rear axle only, with or without front-wheel drive engaged.
- **Contract:** the `wheel_speed` description says "the mean spin of the driven wheels". With
  MFWD engaged the fronts are driven too, and they are not in the mean.
- **Guide meanwhile:** the tyres page says the rear axle, as the code does.

## 3. Can an engine stall?

- **Code:** the header of `src/vehicles/base/drivetrain.gd` says "Nothing stalls: the controller
  opens a clutch first, and the idle controller fuels a converter's load."
- **Docs:** `docs/vehicles.md` (Physics derivations and figures, the braking notes) says that with
  ABS switched off in the LAB "the coupling stays shut on a locked driven wheel, so a manual
  stalls".
- **Guide meanwhile:** the engine page will say the game has no stall, and leave the LAB case out.

## 4. Does `slip` show a car running wide?

- **Code:** `WheelDrive.fill_slip` publishes, per axle, the mean of `RayWheel.slip`, which is the
  size of the longitudinal slip ratio only (`wheel.gd`, `slip = absf(slip_ratio)`). The sideways
  slip, `v_lat / slip_denom`, is not in it.
- **Contract:** the `slip` description says "slip on the front with the rear planted is a car
  washing wide, slip on the rear alone is the back stepping out". A front axle washing wide on
  rolling, unbraked wheels slides sideways with almost no longitudinal slip, so the published
  value would stay near 0.
- **Guide meanwhile:** the tyres page says `slip` is the slip ratio along the wheels and does not
  include the slip angle.

## 5. Is 127 1/km of guidance curvature full lock?

- **Code:** `WheelDrive.steer_angle_from_curvature` turns the curvature into an angle on the
  tractor's own wheelbase, `atan(wheelbase * curvature)`, clamped to `max_steer_deg`. On
  `tractor-kenney` (wheelbase about 2.58 m, lock 38°) 127 1/km gives about 18°, half the lock;
  the tractor's full-lock circle is about 3.3 m, which the signal cannot ask for.
- **Contract and comment:** the `guidance_curvature` description says "+-127 1/km is a 7.9 m
  radius, which is full steering lock here", and `bridge_source.gd`'s `FULL_LOCK_CURVATURE`
  comment says the same. The bridge's `guidance` steer unit (curvature over 127) is not what turns
  the wheels: `base_vehicle.gd` slews to `WheelDrive.guidance_steer_unit` instead whenever a
  curvature is present.
- **Guide meanwhile:** the steering page says the tightest command is a circle of about 8 m and
  does not call it full lock.

## 6. Does traction control brake, or cut engine power?

- **Code:** `RayWheel.tcs_take` (`wheel.gd`) says "TC removes drive, never brakes": the hold takes
  drive away at each driven wheel inside the spin step, and the `TCS_SLIP` comment calls it an
  ideal TC that "only ever removes drive". The engine's fuel is trimmed only by drag-torque control
  in overrun (`Drivetrain.drag_control`) and by stability control (`Drivetrain.esc_cap`).
- **UI text:** the pause menu's help for TRACTION CONTROL (`TCS_HELP` in `pause_menu.gd`) says it
  "Cuts engine power when a driven wheel spins"; the help for DIFFERENTIALS (`AXLE_DIFF_HELP`) says
  "Traction control brakes a spinning wheel and hides some of it". The two disagree with each
  other and with the code's comment.
- **Guide meanwhile:** the driver aids page says traction control takes away drive at the
  spinning wheel and never brakes it, as the code's comment does, and does not say whether the
  engine's power is cut.

## 7. Which levels have wind?

- **Code:** both `src/levels/island/level_6/level_6.tscn` and `src/levels/open_sea/open_sea.tscn`
  set a `wind` resource (`level_6_wind.tres`, `open_sea_wind.tres`), and the level list describes
  Open Sea as "Endless open water under a steady wind".
- **Docs:** `docs/boat.md` (Buoyancy and knobs) says "Level 6 is the only level with a
  `WindField`; `Level.wind` defaults to null elsewhere."
- **Guide meanwhile:** the floating page says Level 6 and Open Sea both have wind of their own, as
  the level scenes do.

## 8. Does the wind change the plane's stall?

- **Code:** `src/vehicles/plane/plane.gd` (`_tick_extras`) works out the lift, the angle of attack
  and the sideslip from `linear_velocity`, the speed over the ground, and uses the wind only for
  drag: "Lift and the flow angles stay on absolute velocity: wind is here to be flown against,
  not to change the stall speed."
- **Code comment elsewhere:** `src/levels/base/world_conditions.gd`, at `WIND_STRONG_SPEED`, says
  "The plane's 13 m/s `stall_speed` (`plane.gd`) means a strong tailwind gust bites into margin
  on a slow final — the intended bite, not a bug." With lift read over the ground, a tailwind gust
  changes the lift only through the drag it removes, not through airspeed.
- **Also:** a real wing's lift follows airspeed, so a headwind shortens a take-off run; the
  game's does not. This may be intended (the plane.gd comment says so) but is worth confirming.
- **Guide meanwhile:** the plane page says lift reads the speed over the ground, as the code
  does, and lists it under what the game leaves out; the conditions page does not repeat the
  tailwind remark.

## 9. Should an empty tank stop the engine?

- **Code:** `BaseVehicle` drains `telemetry.fuel` (`VehicleTelemetry.fuel_drain`, `fuel_step`) but
  nothing reads it back: at 0 % the drivetrain still runs and burns, and the `fuel_rate` signal
  still reads the burn. The tank itself is a labelled game-scale COMPROMISE
  (`VehicleTelemetry.FUEL_TANK_FULL_LOAD_S`, about eight minutes at full load).
- **Docs:** no doc says what an empty tank does.
- **Guide meanwhile:** the aux page says an empty tank does not stop the engine, as the code
  does, and lists it under what the game leaves out.

## 10. Gravity: 9.81 or 9.8?

- **Code:** `src/vehicles/base/wheel.gd` (`tick`) sets the tyre's reference load as
  `corner_mass * 9.81`, a constant written in place. The world's gravity is the project's
  `physics/3d/default_gravity`, which `BaseVehicle` reads as 9.8 (`base_vehicle.gd`, `_gravity`),
  and `train_sim.gd` declares `GRAVITY := 9.8` "matches the project default_gravity".
- **Effect:** small. At rest a tyre's load is about 0.1 % under its reference, so
  `load_scaled_mu` gives it about 0.015 % more grip than at exactly the reference (sedan,
  `load_sensitivity` 0.1). The question is only whether the two figures should be one.
- **Guide meanwhile:** the forces page uses 9.8 throughout and the guide quotes no figure that
  depends on the difference.

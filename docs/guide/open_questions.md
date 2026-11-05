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

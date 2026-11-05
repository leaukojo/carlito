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

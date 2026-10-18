# 13 — Minor items

Shared context: `00_README.md`. Independent small items, any order. Each can be its own small plan
or be folded into a bigger brief that touches the same code.

## 1. Land vehicles ignore wind

- Aero drag uses the absolute velocity: `WheelDrive._apply_resistance` and
  `TowedBody.tick_towed` call `VehicleMath.road_resistance(linear_velocity, …)`.
- The infrastructure exists: `WindField.at(node)`, and the free bodies use `VehicleMath.air_damper`
  on `vel - wind`. Only the water levels carry a `WindField` today (level 6 and open sea); no land
  level has wind.
- A crosswind on a high-sided body (box trailer, vans) is real and visible. `air_damper`'s `axis`
  masks world space, so a body-frame side force needs its own term, like the boat's windage
  (`docs/boat.md`).
- Low priority until a land level has wind.

## 2. Aero forces act at the centre of mass

- Drag (`_apply_resistance`) and downforce (`WheelDrive._apply_downforce`) are
  `apply_central_force`. No aero pitch moment, and downforce splits by static weight (the two
  winged bodies run `front_weight` 0.42), so aero balance is not a tuning lever.
- A centre of pressure, or a front/rear downforce split, for `race` and `race-future`.
  Constraint: downforce must fit inside the suspension travel at top speed (`test_vehicle_catalog`).

## 3. Rolling resistance opposes the whole velocity

- `VehicleMath.road_resistance` sums aero drag and `crr * N` and applies them along `-velocity`, so
  a sideways slide or vertical motion also receives rolling resistance. Physically it is a
  longitudinal force at each contact.
- Tiny (~135 N on a sedan). Fix if the code is open for another reason; the trailers share the
  path.

## 4. ABS and traction control are ideal

- `RayWheel.ABS_SLIP` / `TCS_SLIP`: they know the true road speed and hold the slip exactly at the
  0.12 peak with no cycling ("an honest model of an ideal ABS").
- Real systems estimate speed from the wheels and cycle around the peak (a few per cent longer dry
  stops than an ideal hold; the pulsing is the visible sign).
- Fine as a choice. If ABS or TC activity should become a teaching signal (only `trailer_abs` is on
  the bus today), a cycling model makes it visible. User decision.
- Related: TC is a hold solved with the brakes inside the differentials (`RayWheel.settled_spin`),
  exact under a biasing diff. The drive reaches the wheels through the crank's coupling, so an
  open diff sends the cut across too (`src/vehicles/CLAUDE.md`, the TC bullet).
- Tyre classes (brief 12, landed) keep the body curve's 0.12 peak on every class and surface, so
  the ideal hold is right for each. A class or surface with its own peak slip (studded on ice,
  a mud lug) is where a hold that follows the tyre's peak, or a cycling estimate, would differ.

## 5. The speed-tapered steering lock applies to analog input too

- `min_steer_frac` / `steer_falloff_speed` (`WheelDrive.tick`) shrink the usable lock with speed for
  every input source, bridge and gamepad included; sized to stay at least 1.5x the lock the tyres
  can use (`STEER_GRIP_MARGIN`,
  `test_vehicle_catalog.test_a_steering_taper_never_out_limits_the_tyres`).
- Defensible (real cars with speed-sensitive steering do similar). No action unless the user wants
  analog input to bypass it.

## 7. The heavy vans' twin rears are not drawn

- `VAN_BASE` runs twin rear tyres (`rear_twin_tyres`, `docs/vehicles.md` § Balance), but the
  Kenney van bodies render one wheel per rear corner (`WHEEL_DEFAULT`).
- A twin-rear wheel scene for the vans' rear axle (`wheel_scene_rear`, as the tractor's), measured
  against the arches. Visual only: physics stays one ray per corner.

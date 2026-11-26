[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# Open questions and ideas

<p class="lead">This page lists what still needs to be checked, and ideas for future work.</p>

## Open questions

These are places where the code, the tests and the docs disagree, or where the code looks wrong to
a reader. The guide does not explain them until they are checked; each entry names what the guide
says meanwhile. Newest last.

### 1. Does the CVT tractor have a park pawl?

- **Code:** `tools/gen_kenney_vehicles.gd` gives every tractor `park_pawl_torque` 33542, so
  `tractor-cvt_spec.tres` carries one too, and `Drivetrain.has_park_pawl` lets its P engage.
- **Contract and docs:** the `gear` description says P engages a park pawl "where one is fitted
  (cars, vans, the tractor's powershift)"; `holding.md` gives the tractor "the powershift's hill
  hold and park pawl, or the CVT's active standstill", and `inventory.md` lists the park pawl on
  the tractor powershift only.
- **Guide meanwhile:** the tractor page's CVT gearbox names no park position either way.

### 2. Which trucks have roll stability?

- **Code:** the specs of all four trucks have an `esc_roll_lift_g` table, the garbage truck and
  the fire truck included.
- **Contract and docs:** the `esc_off` description and `inventory.md` give roll stability to the
  semis (and their trailers) only.
- **Guide meanwhile:** the teaching pages describe roll stability for trucks in general.

### 3. What should the catalog test check?

- **Test:** `tests/test_vehicle_catalog.gd` fails. It reads `boat.md` and `drone.md` in this guide,
  but both pages wait in `docs/guide-drafts/`. It also expects the `suv` row of `car.md` to match
  the catalog.
- **Catalog and guide:** the catalog's `suv` line does not say "governed to 180 km/h", and the
  guide's does.
- **Guide meanwhile:** the car page keeps the 180 km/h, which is what the `suv` spec sets.

## Ideas

### Load scenarios in the simulator

A scenario of [Forces on a vehicle](forces.md) could have a button that opens it in the simulator,
with the same vehicle, speed, slope, ground, wind and driver aids. Each scenario already has an id,
and the simulator can already open a level and a vehicle from its web address
(`?level=<id>&vehicle=<family>`), so the missing part is the rest of the settings.

### Scenarios that the forces diagram cannot show yet

| Page | Scenario | What the diagram lacks |
| --- | --- | --- |
| [Understeer and oversteer](understeer.md) | Handbrake turn | A handbrake |
| [Clutch and torque converter](coupling.md) | Creep and stall speed | A torque converter |
| [Kinds of gearbox](gearbox-kinds.md) | The same start with four gearboxes | Time |
| [Differentials](differentials.md) | Open against locked differential | A choice of differential |
| [Brakes](brakes.md) | Fade on a long descent | Time and heat |
| [ABS, traction and stability control](driver-aids.md) | Catching a spin | Stability control |
| [Holding still](holding.md) | Auto hold | Time |
| [Towing](towing.md) | A trailer following its truck, jackknife | Trailers |
| [Implements and the PTO](implements.md) | Ploughing a field | Draft and PTO load |
| [Fuel, coolant, battery and air](auxiliary.md) | Warming up, using up air | Time, and these systems |
| [Position, heading and distance](position.md) | A lap of the compass | Movement |
| [Controls and who drives](controls.md) | Key response | Time |

### Controls reference

The guide has no keyboard or gamepad shortcuts for now. A controls reference could come back
later, ideally generated from `ActionRegistry` like the pause menu's CONTROLS page.

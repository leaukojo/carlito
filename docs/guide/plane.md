# The plane

<p class="lead">The plane is a single light aircraft of about 800 kg, with a propeller at the
nose and three landing wheels. On the ground it is a wheeled vehicle like a car; in the air it
flies on its wing. Its signals follow CANaerospace, a standard for aircraft electronics.</p>

## What the plane has

- [Lift, the stall, flaps, drag, the weathervane and the controls](plane-flight.md).
- A simpler [engine](engine.md#the-simpler-engine-on-the-boat-and-the-plane) whose speed follows
  the throttle, with spool lag; the gear byte sets forward, neutral or reverse thrust.
- Three landing wheels with [tyres](tyres.md), [suspension](suspension.md), wheel
  [brakes](brakes.md) and a parking brake, and a steerable nose wheel.
- No ABS, traction control or stability control.
- The wind it flies through ([Wind, current and conditions](conditions.md)), and the
  [fuel, coolant and battery models](aux.md).
<!-- plane_spec.tres mass 800, three wheel_positions, brake_torque 900, handbrake_torque 100, max_steer_deg 40; abs_equipped false -->

## Where to fly it

The plane is allowed on Levels 1, 2, 3, 5 and 6, and on **Flatland**, which has room in
every direction for take-off and landing. **Level 6 - Skyport** has a wind of its own.
<!-- *_info.tres allowed_vehicles: plane on Garage, Flatland, Levels 1, 2, 3, 5, 6 -->

## What you see in sloppyCAN

Beyond the shared signals the plane takes `elevator`, `flaps`, `beacon` and `strobe`, and
publishes `flaps_actual`, `altitude`, `vspeed`, its attitude and turn rates, `acc_vert` and the
propeller's `rpm`. [Plane flight](plane-flight.md#what-you-see-in-sloppycan) lists them.

## Related

- [Plane flight](plane-flight.md): every idea on this page.
- [Glossary](glossary.md): every term on this page.

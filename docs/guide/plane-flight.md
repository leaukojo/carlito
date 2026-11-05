# Plane flight

<p class="lead">A plane's wing holds it up only while it moves fast enough. Too slow, and the
wing stalls. The game's light aircraft has a propeller for thrust, a wing whose lift grows with
speed, flaps to fly slower, and control surfaces that work only when air flows over them.</p>

<div class="badges"><span class="label">Which vehicles have this</span>
<span class="badge no" title="It drives">Car</span>
<span class="badge no" title="It drives">Truck</span>
<span class="badge no" title="It drives">Tractor</span>
<span class="badge yes" title="One light aircraft, the plane">Plane</span>
<span class="badge no" title="It floats">Boat</span>
<span class="badge no" title="It flies on rotors, on its own page">Drone</span>
<span class="badge no" title="It runs on rails">Train</span>
</div>

## The plane

The game's plane is a light aircraft of about 800 kg, about the weight of a small car, with a
propeller at the nose. On the ground it stands on three wheels, a steerable nose wheel and two
main wheels, each a full wheel with tyre, suspension and brakes like a car's. On the ground it
steers with the nose wheel; in the air the same steering banks and turns it.
<!-- plane_spec.tres mass 800, wheel_positions (0 = nose, 1 and 2 = mains), max_steer_deg 40, brake_torque 900, handbrake_torque 100 -->

## Thrust

The engine turns the propeller. Its speed follows the throttle, but takes a moment to spin up
and down. The propeller's push grows from nothing at idle to its full force at the top of its
range, enough to accelerate the plane at more than 1 g with no air holding it back.
<!-- plane.gd prop_spool_rate 3500 rpm/s; prop_thrust: thrust_frac(rpm, idle, redline) x max_thrust 9000 N; 9000 / (800 x 9.81) = 1.15 -->

The gear byte sets the propeller's direction, as on a car: D pushes forward, N gives no push, and
R gives a weak reverse push, a quarter of forward, for backing out of a parking spot.
<!-- PlaneVehicle.prop_thrust: "D forward, R a weak reverse (beta) fraction, N none"; reverse_thrust_frac 0.25 -->

## Lift

A wing is shaped and angled so that air flowing over it is pushed down; the air pushes the wing
up. That push is [lift](glossary.md#lift). It grows with the square of the speed: twice as fast,
four times the lift.

It also grows with the wing's [angle of attack](glossary.md#angle-of-attack): how far the nose
points above the direction the plane is actually travelling. Raise the nose a little and the wing
meets the air more steeply and lifts more. In the game a few degrees make a large difference, and
past about 8° the extra lift stops growing.
<!-- plane.gd aoa_lift_slope 5.7 per rad, aoa_lift_max 1.8: 1 + 5.7 x 0.14 rad = 1.8 at about 8 deg -->

At zero angle of attack, the plane's lift equals its weight at about 25 m/s, 90 km/h. Lift is
capped at about twice the weight, so the plane cannot pull more than about 2 g.
<!-- plane.gd lift_coeff 13: 13 v² = 7848 N at 24.6 m/s; lift_cap 16000 N; drag_coeff comment: "the zero-AoA trim speed (~25 m/s)" -->

<div class="widget" data-widget="lift-speed"></div>

### The stall

Fly too slowly and the air can no longer follow the wing's upper surface: it breaks away, and the
lift collapses. That is a [stall](glossary.md#stall). In the game the lift begins to fade below
20 m/s and is gone completely at 13 m/s, about 47 km/h. As it fades in the air, the plane's nose
drops by itself, so the plane dives and gathers speed again. It never spins.
<!-- plane.gd stall_speed 13, full_lift_speed 20 (lift_frac smoothstep), stall_pitch_gain: "the nose drops as lift fades (recover by diving, never a spin)" -->

### Flaps

[Flaps](glossary.md#flaps) are panels at the back of the wing that fold down. They make the wing
lift more at a given speed, so the plane can fly slower for take-off and landing, at the price
of much more drag. Press **B** to lower them fully, and again to raise them; sloppyCAN's `flaps`
can set any position. They move slowly, taking about two and a half seconds to go fully down.
<!-- plane.gd flap_lift_bonus 4 (on lift_coeff 13), flap_drag_bonus 40, flap_slew_rate 0.4 per s; key B -->

## Drag and the weathervane

The air holds the plane back in proportion to its speed, and that drag sets its top speed,
about 26 m/s, a little over 90 km/h. Sideways and up-and-down, the drag is much stronger, so the
plane's path follows where its nose points within a fraction of a second.
<!-- plane.gd drag_coeff 350 N per m/s ("sets top speed (~26 m/s)"), drag_lat and drag_vert 1600 -->

The tail works like a weathervane's: if the nose points away from the direction of travel, the
air pushes it back into line. That keeps the plane flying straight and makes it steady to fly.
<!-- plane.gd weathervane_torque: aoa_stiffness 110, sideslip_stiffness 60 -->

## Controls

A real plane has three sets of [control surfaces](glossary.md#control-surface): the elevator on the tail pitches the nose up
and down, the ailerons on the wings roll it, and the rudder on the fin yaws it. The game uses all
three.

- **Pitch.** The elevator command raises or lowers the nose. Press **R** and **F**, or send
  `elevator`.
- **Bank and turn.** The steering does two things at once: it banks the plane to an angle, up to
  45° at full steering, and asks for a turn rate. Let go and the wings level themselves. A
  banked wing's lift tilts with it and pulls the plane round in a turn, as a real plane turns.
<!-- plane.gd max_bank_deg 45, roll_torque spring "always acts, so the wings self-level", max_yaw_rate 0.5 rad/s; keys aircraft_up R / aircraft_down F (elevator) -->

Every control surface needs air flowing over it. In the game they have no effect standing still,
grow stronger with speed, and reach their full effect at 15 m/s. Unlike the boat's rudder, the
plane's tail gets no help from the propeller's wash.
<!-- plane.gd authority_speed_ref 15; control_authority: "No prop-wash term (the tail sits outside the prop stream), unlike the boat's rudder" -->

## Taking off and landing

On the runway, with the throttle open, the plane rolls and gathers speed. The elevator does
little until it is moving fast; past about 20 m/s the wing gives full lift, and raising the nose
a few degrees lifts it off. To land, close the throttle, lower the flaps to fly slower, and let
the plane settle onto its main wheels. On the ground its brakes and parking brake work like a
car's.

## What the game leaves out

- **Lift reads the speed over the ground, not through the air.** The game's code works out the
  lift and the angle of attack from the plane's movement over the ground and uses the wind only
  for drag, so a headwind does not shorten the take-off run or lower the stall speed as it would
  in a real plane.
  <!-- plane.gd _tick_extras: "Lift and the flow angles stay on absolute velocity: wind is here to be flown against, not to change the stall speed." See open_questions.md 8 -->
- **No spins, no inverted flight**: below zero angle of attack the wing gives no lift, never
  negative lift.
- **No fuel or engine failures**, no propeller torque that swings the nose.
- **No ground effect** near the runway, and the air is the same at every height.
  <!-- plane.gd aoa_factor: "negative AoA takes lift to zero, never below (no inverted lift)"; VehicleMath.AIR_DENSITY constant -->

## What you see in sloppyCAN

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `elevator` | in | % | Nose up (+) or down (−). |
| `flaps` | in | % | The flap setting asked for. |
| `flaps_actual` | out | % | Where the flaps are, as they move. |
| `gear` | in | enum | D for forward thrust, N for none, R for weak reverse. |
| `rpm` | out | rev/min | The propeller's modelled speed. |
| `altitude` | out | m | Height above sea level. Warns at 450 m. |
| `vspeed` | out | m/s | Climb or sink rate. Warns below −15 m/s. |
| `pitch`, `roll` | out | deg | The plane's attitude. |
| `pitch_rate`, `roll_rate`, `yaw` | out | rad/s | How fast it is pitching, rolling and turning. |
| `acc_vert` | out | m/s² | Acceleration along the plane's own up axis: the g you feel in a pull-up. |
| `beacon`, `strobe` | in | flag | The anti-collision lights, flashed by sloppyCAN. |
<!-- contract/carlito_contract.json: elevator, flaps, flaps_actual, gear, rpm, altitude (warn 450), vspeed (warn -15), pitch, roll, pitch_rate, roll_rate, yaw, acc_vert, beacon, strobe -->

## Try it in the game

<div class="box try">
<p class="box-title">Try it in the game: find the stall</p>

1. Pick the plane on **Flatland**, where there is room in every direction. Press **F2** until the
   dashboard shows FULL, with its altitude and climb bars.
2. Open the throttle fully. As the speed passes about 90 km/h, press **R** briefly to raise the
   nose: the plane lifts off.
3. Climb to a safe height, then close the throttle and hold the nose up with **R**. The speed
   falls. Below about 70 km/h the plane starts to sink however high the nose is held, and near
   47 km/h the nose drops by itself: the stall.
4. Let the nose fall, open the throttle and recover. Then try it again with the flaps fully down
   (**B**): the plane flies more slowly before it stalls.

</div>

## Related

- [Wind, current and conditions](conditions.md): the wind the plane flies through.
- [Glossary](glossary.md): every term on this page.

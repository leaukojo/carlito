# Floating and boats

<p class="lead">A boat has no wheels to push against. Water holds it up, its propeller pushes
water backwards, and its rudder turns it by deflecting the flow. Everything it does is measured
against the water, which may itself be moving.</p>

<div class="badges"><span class="label">Which vehicles have this</span>
<span class="badge no" title="A car that drives into deep water is respawned">Car</span>
<span class="badge no" title="Respawned in deep water">Truck</span>
<span class="badge no" title="Respawned in deep water">Tractor</span>
<span class="badge no" title="It has no floats">Plane</span>
<span class="badge yes" title="Two speedboats and a sailing dinghy">Boat</span>
<span class="badge no" title="It flies">Drone</span>
<span class="badge no" title="It stays on its rails">Train</span>
</div>

## The water

Every island has a sea, and Open Sea is nothing else. The water's surface in the game is flat:
the waves you see are drawn, and never move a boat. Any vehicle but a boat that drives in more
than half a metre deep is put back on land: it has drowned.
<!-- water_surface.gd: "get_height() returns the node's global Y, flat; shader waves are visual-only and never feed physics"; kill_margin 0.5; "body_entered -> respawn on any non-boat body" (docs/systems.md) -->

## Buoyancy

A floating boat pushes water out of the way. The water pushes back up with a force equal to the
weight of the water pushed aside. That is [buoyancy](glossary.md#buoyancy), Archimedes' principle.
A boat floats when it has pushed aside its own weight of water: a 600 kg boat sits low enough to
displace 600 kg, about 0.6 m³.

The game does not work out the shape of the hull under water. Instead it gives each boat four
float points, one near each corner of the hull, and treats each as a spring in the water: the
deeper the point, the harder the water pushes it up. The springs are set so that the empty hull
rests with each point a set depth under the surface, about 30 cm on the speedboat. A damper on
each spring stops the boat bobbing for ever.
<!-- boat.gd probe_force: k = mass x g / (probes x float_depth), buoyancy_damp 0.5 of critical; boat-speed-a.tscn float_depth 0.3 -->

Four separate points are enough to make a boat behave like a boat. If the bow dips, its float
points go deeper and push harder, so the boat levels itself. If it leans, the low side pushes
harder and rights it. Each float can push at most three times its share of the boat's weight,
so a boat landing hard from a jump cannot be catapulted out.
<!-- boat.gd max_probe_force_factor 3.0 -->

<div class="widget" data-widget="buoyancy"></div>

## Pushing and steering

### The propeller

The speedboats' engines drive a propeller at the stern. Its push is a fixed force at full
throttle, less in reverse (about two fifths of forward). It acts only while the stern is in the
water: a boat that jumps clear stops pushing. The push acts low at the stern, below the boat's
centre of mass, so the bow rises as the boat accelerates.
<!-- boat.gd thrust_force, reverse_thrust_factor 0.4, prop_offset below the COM ("Thrust at the stern, below the COM, so the bow rises under throttle"), gated on stern_wet -->

### The hull's drag

Water holds the hull back. The game uses three drags, all measured against the **water**, not the
ground:

- **Forwards**, which sets the top speed: about 50 km/h on `boat-speed-a`, 60 on `boat-speed-j`.
- **Sideways**, much stronger, standing for the keel. It is what stops a boat sliding sideways in a
  turn. It acts low down, at the keel, so a turning boat leans, or [heels](glossary.md#heel).
- **Turning**, which slows the boat's spin.
<!-- boat.gd drag_long, drag_lat at keel_offset, drag_yaw; thrust over drag_long: 5200 / 360 = 14.4 m/s (52 km/h), 11000 / 660 = 16.7 m/s (60 km/h) -->

The game makes each drag grow in proportion to the speed. Real water drag grows faster than
that, with the square of the speed, so the game's boats reach their top speed more gently than a
real one.
<!-- VehicleMath.damped_force: N per m/s, linear (boat.gd drag_long "N per m/s forward") -->

### The rudder

A [rudder](glossary.md#rudder) is a blade at the stern. Turned, it deflects the water flowing past
it, and that turns the boat. With no water flowing past it, a rudder does nothing. The game gives
the rudder its full effect once the boat moves at about 6 m/s, and less below. The propeller's
wash also blows over the rudder: at full throttle it adds half the rudder's effect even at a
standstill, so a boat can turn out of a dock.
<!-- boat.gd RUDDER_SPEED_REF 6 m/s, RUDDER_PROP_WASH 0.5; VehicleMath.flow_authority clamps to 1 -->

### Trim

A speedboat's drive can be tilted, its trim. The game models the trim as following the throttle,
up to its full setting at full throttle, and publishes it. It does not change how the boat
handles.
<!-- BoatTelemetry.trim_step: "follows forward throttle demand"; TRIM_RATE 40 %/s; published as trim -->

## Wind on the hull

The part of a boat above the water catches the wind. The game pushes it with a drag against the
air, much stronger from the side than from ahead. The side push acts above the water, so a wind
from the side makes the boat heel. It acts a little behind the middle, so the boat tends to swing
its bow into the wind, like a weathervane. Level 6 and Open Sea have wind of their own, and
CONDITIONS can set it anywhere; [Wind, current and conditions](conditions.md) explains it.
<!-- boat.gd windage_long, windage_lat at windage_offset (0, 0.55, 0.45): above the waterline and aft; docs/boat.md: "aft of COM -> weathercocks into wind" -->

## Current

On Level 6 the sea itself moves: a [tide](glossary.md#tide) flows one way, slackens, and turns.
Because every drag on the hull is measured against the water, a boat in a current is carried
along with it. Its speed through the water and its speed over the ground differ, and so do the
direction it points and the direction it travels. That difference is how sailors and pilots
read a current.
<!-- boat.gd: through_water = linear_velocity - current; docs/boat.md Tide; contract stw, sog, cog -->

## Sailing

`boat-sail-a` is a sailing dinghy with a small motor. Its sail is a wing standing on end: the wind
flowing past it makes [lift](glossary.md#lift), a force across the wind, and some drag along it.
The game models the sail as a flat plate. Its lift is greatest when the wind meets it at 45°.
Pointed too close to the wind, below about 12°, the sail flaps uselessly and gives no lift: the
boat is [in irons](glossary.md#in-irons).
<!-- boat_sail.gd: CL_MAX 1.5 at 45 deg, CD_MIN 0.08, CD_STALL 1.2, LUFF_DEG 12 -->

The wind the sail feels is the [apparent wind](glossary.md#apparent-wind): the true wind combined
with the wind of the boat's own movement. The game works it out each moment, so a boat cannot
simply sail straight into the wind: that no-go zone is not a rule but a result.

The [sheet](glossary.md#sheet) is the rope that controls the sail. It does not set where the
boom points; it sets how far the boom may swing out. Let it out with the wind behind and the sail
swings wide; haul it in to sail across the wind. Press **3** to haul in and ease it, or send
sloppyCAN's `sheet`.
<!-- contract sheet: "IT IS A LIMIT, NOT A POSITION"; BoatSail.boom_angle min(sheet x sheet_max_deg, |awa|); key 3 -->

The sail's push acts high above the water, against the keel's grip low down, so a sailing boat
heels. The dinghy's motor is small, about a tenth of the speedboat's push.
<!-- boat-sail-a.tscn thrust_force 500 against boat-speed-a 5200; sail_center above the COM -->

## Autopilot

Each boat has an [autopilot](glossary.md#autopilot) that holds a compass heading. Press **2** to
switch it to HEADING HOLD: it steers to the heading the boat had at that moment, through the same
rudder and at the same rate a hand would. Touch the steering and the autopilot stands aside;
let go and it holds the new heading. sloppyCAN can also give it a heading to steer with
`heading_cmd`.
<!-- BoatAutopilot: HELM_DEADBAND 0.05; docs/boat.md Autopilot -->

## Depth and running aground

A boat's echo sounder measures the water under the hull. In the game it reads the depth below
the float points, so 0 means the bottom is touching the hull. Level 6 has a sandbar where the
depth changes. A boat that stays settled with little water under it for a second counts as
aground.
<!-- contract depth: "THE TRANSDUCER RIDES THE PROBE PLANE"; boat.gd aground_now, AGROUND_SHALLOW_FRAC 0.5, AGROUND_DEBOUNCE 1 s; docs/boat.md level-6 sandbar -->

## What the game leaves out

- **No real waves**: the sea is flat, and boats do not pitch over swells.
- **No hull shape**: buoyancy comes from four float points, not from the hull's volume, and a
  boat cannot take on water or capsize from flooding.
- **No planing**: a real speedboat rises onto the surface at speed and its drag changes; the
  game's drag simply grows with speed.
- **No spray, wake or wash** affecting other boats.

## What you see in sloppyCAN

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `rudder` | in | % | The rudder request, negative to port. Replaces `steer` when present. |
| `rudder_actual` | out | % | The rudder as applied, after the steering rate. |
| `trim` | out | % | The modelled drive trim, following the throttle. |
| `stw` | out | m/s | Speed through the water. |
| `sog` | out | m/s | Speed over the ground. Differs from `stw` in a current. |
| `cog` | out | deg | Course over the ground: where the boat actually travels. |
| `current_set`, `current_drift` | out | deg, m/s | Which way the tide flows, and how fast. |
| `depth` | out | m | Water under the hull; −1 when there is no bottom to find. |
| `awa`, `aws` | out | deg, m/s | The apparent wind's angle from the bow and its speed. |
| `twd`, `tws` | out | deg, m/s | The true wind's direction and speed. |
| `sheet` | in | % | Sailing dinghy: how far the boom may swing, 0 hauled in, 100 eased. |
| `sail_angle` | out | deg | Sailing dinghy: the boom's actual angle. |
| `nav_mode`, `nav_mode_actual` | in, out | enum | The autopilot: STANDBY or HEADING HOLD, asked and actual. |
| `heading_cmd`, `heading_target` | in, out | deg | The heading the autopilot is told, and the one it is steering. |
| `pitch`, `roll` | out | deg | The hull's tilt. `roll` warns at 45°, a capsize risk. |
| `status` | out | bitfield | Bit 1, "on the ground", means aground for a boat. |
<!-- contract/carlito_contract.json: rudder, rudder_actual, trim, stw, sog, cog, current_set, current_drift, depth, awa, aws, twd, tws, sheet, sail_angle, nav_mode, nav_mode_actual, heading_cmd, heading_target, pitch, roll (warn 45), status; boat.gd t.ground = aground -->

## Try it in the game

<div class="box try">
<p class="box-title">Try it in the game: steer with and without flow</p>

1. Pick `boat-speed-a` on **Open Sea**. Press **F2** until the dashboard shows FULL, with its
   compass rose and heading readout.
2. Stop the boat. Turn the steering fully with no throttle: almost nothing happens. Now add full
   throttle: the propeller's wash over the rudder turns the boat round almost on the spot.
3. Press **2** for the autopilot and let go of the steering: the boat holds its heading.
4. Take the boat to **Level 6 - Skyport**, where the tide runs, and drive slowly across the
   stream. The dashboard's course over the ground and the heading differ: the boat crabs sideways
   with the tide.

</div>

## Related

- [Glossary](glossary.md): every term on this page.

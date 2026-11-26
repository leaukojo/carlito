[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# The chassis view

<p class="lead">This page explains each mark in the chassis view, the live plan of every tyre's
load, grip and push, and where the guide explains it.</p>

The chassis view is a small panel on the right, above the dashboard. It shows the vehicle seen
from above, front up, with one shape for each tyre. It can be shown or hidden, and the simulator
remembers the choice. It has nothing to show on a vehicle without wheels, and it hides when the
window is too short to draw it readably.
<!-- boot.gd _toggle_chassis saves "chassis_on"; ChassisView.bind: no drive wheels, no panel; MIN_H -->

Everything in it comes from the numbers the physics has just used, one physics step at a time,
with nothing smoothed or held. If something flickers there, it flickers in the simulation. The
panel itself is not sent to sloppyCAN, but some of what it draws is: the body's acceleration
(`accLong`, `accLat`) and each axle's slip (`slip`), for example.
<!-- chassis_view.gd header: "no lag or hold"; "Not in sloppyCAN: no bus has this"; ChassisReading.of each physics frame; contract accLong, accLat, slip -->


<!-- figure: a screenshot of the chassis view on a car braking in a turn, its marks labelled -->

## The tyres

| What you see | What it means | Explained on |
| --- | --- | --- |
| The size of a tyre's shape | Its share of the weight on all the tyres. The area, not the side, grows with the load, so a tyre carrying twice as much has twice the area. | [Weight transfer and rollover](weight-transfer.md#why-weight-moves) |
| Blue | Less than 70 % of the tyre's grip in use. | [Sharing grip between braking and turning](slip.md#sharing-grip-between-braking-and-turning) |
| Yellow | 70 to 95 % in use. | the same |
| Red | At the limit. | the same |
| Diagonal stripes | The tyre is past the peak of its grip curve: it is sliding, not just working hard. | [The grip curve](slip.md#the-grip-curve) |
| A dashed outline | The wheel is off the ground. | [Wheel lift and rollover](weight-transfer.md#wheel-lift-and-rollover) |
| A tiny dot | The tyre touches the ground but carries almost nothing. | the same |
<!-- chassis_view.gd patch_scale (area = share), COOL_BELOW 0.7, WARM_BELOW 0.95, GRIP_COLORS, past_peak hatch, _draw_dashed_rect, the near-zero dot -->

The grip in use counts braking, driving and turning together: a tyre turning hard has little grip
left to brake with, and the colour shows that. The line at the bottom of the panel repeats the
three colours.
<!-- ChassisReading.grip_use: the share of the friction ellipse, |(F_long / B_long, F_lat / B_lat)| -->

## Arrows and bars on the tyres

| What you see | What it means | Explained on |
| --- | --- | --- |
| A white arrow on a tyre | The push the road gives the vehicle through that tyre: forward when driving, back when braking, sideways when turning. All the arrows share one scale, so they can be compared. | [Grip comes from friction](tyres.md#grip-comes-from-friction) |
| A short bar beside a driven or braked wheel | How fast the wheel turns compared with the road. The small flat tick is zero: the wheel rolls at road speed. Up means it turns faster than the road (wheelspin); down means slower, towards locking (braking). | [A tyre needs slip to grip](slip.md#a-tyre-needs-slip-to-grip) |
| The bar turns purple and thicker | ABS, traction control or stability control is holding that wheel. | [ABS, traction and stability control](driver-aids.md) |
<!-- chassis_view.gd force_arrow (ARROW_LEN per weight / wheel count, capped at ARROW_CAP), spin_bar, HELD_COLOR for abs_held / tcs_held / esc_braked -->

The arrows' scale is set by the vehicle's weight, not by what the tyres carry this instant, so a
bump or a landing changes the arrows, never the scale. The bar's full length is a locked wheel, or one spinning at twice the road speed. The
grip curve's peak, at a slip of about 12 %, reads about a third of the bar, so a tyre working at
its best shows a short bar, not a long one.
<!-- ARROW_LEN 20 px for weight / count; SPIN_LEN at a slip ratio of 1, sqrt scale: 0.12 reads 0.35 -->

## The differentials

Lines between the wheels are the [differentials](differentials.md): one across each driven axle
and, on a four-wheel-drive vehicle, one down the middle for the centre differential.

| What you see | What it means | Explained on |
| --- | --- | --- |
| No line | No differential there (an axle that is not driven). | [Which wheels are driven](differentials.md#which-wheels-are-driven) |
| A thin grey line | The differential is moving no drive from one side to the other. | [The open differential](differentials.md#the-open-differential) |
| A thick white line | It is moving drive from one side to the other this instant. | [Limited-slip and Torsen-type differentials](differentials.md#limited-slip-and-torsen-type-differentials) |
| A double line | It is locked: both sides turn together. | [The tractor's diff lock](differentials.md#the-tractors-diff-lock-and-front-wheel-drive) |
<!-- ChassisReading.Diff NONE / OPEN / BIASING / LOCKED; chassis_view.gd DIFF_WIDTHS, DIFF_COLORS, diff_lines -->

## The body: the yellow arrow and the yellow dot

**The yellow arrow** starts at the centre of mass and shows which way the body is speeding up,
slowing down or being turned, longer for more g. Braking points it back; in a turn it points to
the inside, towards the centre of the turn. It is the acceleration sloppyCAN receives as `accLong`
and `accLat`.
<!-- ChassisReading.accel = (acc_lat, -acc_long); base_vehicle.gd: body_accel off the velocity change, so a turn's reads towards its centre; accel_arrow BODY_ARROW_LEN per g, capped at BODY_ARROW_CAP 2 g -->

**The yellow dot** is where the weight on the tyres is centred. Standing still on flat ground it
sits under the centre of mass. When the body speeds up, brakes or turns, weight moves from one set
of tyres to the other and the dot moves with it, the opposite way to the arrow: forward under
braking, to the outside in a turn. How far it moves is the
[weight transfer](weight-transfer.md). If it reaches the line joining the two outside wheels,
the inside wheels carry nothing and lift.
<!-- ChassisReading.centre_of_loads: the normal loads' centre; _draw_load_dot -->

## With a trailer

With a trailer coupled, the panel grows and draws the trailer's wheels behind, at its real angle,
on a thin line from the coupling. The trailer has its own yellow dot but no arrow: the towing
vehicle's arrow stands for the whole rig. The drawing holds still while the trailer swings up to
45° either way, and zooms out only past that, so a lifted trailer wheel shows in a tight turn.
See [Towing](towing.md).
<!-- ChassisReading.towed (no acceleration: "the unit's arrow is the rig's"), RIG_PANEL_SIZE, _draw_spine, SWING_HELD_DEG 45 (held_swing) -->

## Reading common situations

| Situation | What the chassis view shows | Explained on | Scenario |
| --- | --- | --- | --- |
| Hard braking in a straight line | The front tyres grow and the rear ones shrink; the dot moves forward and the arrow points back. Where ABS holds a wheel, its bar dips and turns purple. | [Weight transfer](weight-transfer.md#why-weight-moves), [ABS](driver-aids.md#abs) | [Emergency stop](forces.md#example-emergency-stop) |
| The same stop without ABS | The wheels that lock show a bar at full length down, and their tyres are striped: they slide. | [The grip curve](slip.md#the-grip-curve) | [Without ABS](forces.md#example-stop-without-abs) |
| A corner taken too fast | The outside tyres grow and the inside ones shrink. One axle reaches red first: the front on a car that runs wide, the rear on one whose tail swings out. | [Which end lets go first](understeer.md#which-end-lets-go-first) | [Too fast](forces.md#example-too-fast) |
| Braking in a turn | The tyres reach red with less brake than in a straight line, because turning already uses part of their grip. The rear ones often go first, since braking also takes weight off them. | [Sharing grip between braking and turning](slip.md#sharing-grip-between-braking-and-turning) | [Braking in a turn](forces.md#example-braking-in-a-turn) |
| Pulling away hard on slippery ground without traction control | The driven wheels' bars shoot up: wheelspin. With traction control, the bars turn purple and stay short, near the grip curve's peak. | [Traction control](driver-aids.md#traction-control) | [Wheelspin](forces.md#example-wheelspin) |
| A tight turn in a truck | The inside wheels shrink to dots, then dashed outlines: they have lifted. | [Wheel lift and rollover](weight-transfer.md#wheel-lift-and-rollover) | [Truck lifts a wheel](forces.md#example-truck-lifts-wheel) |
| Accelerating out of a turn with a limited-slip or Torsen-type differential | Its line turns thick white while it moves drive towards the wheel with more grip. | [Limited-slip and Torsen-type differentials](differentials.md#limited-slip-and-torsen-type-differentials) | |
| The tractor's rear diff lock engaged | The line across its rear axle is double. | [The tractor's diff lock](differentials.md#the-tractors-diff-lock-and-front-wheel-drive) | |

## Related

- [Controls and who drives](controls.md): the dashboard and the debug overlay, the other two
  read-outs on the screen.
- [Forces on a vehicle](forces.md): the same forces drawn from the side, with sliders to change
  them.
- Glossary: [friction ellipse](glossary.md#friction-ellipse),
  [weight transfer](glossary.md#weight-transfer), [centre of mass](glossary.md#centre-of-mass),
  [slip ratio](glossary.md#slip-ratio), [grip curve](glossary.md#grip-curve).

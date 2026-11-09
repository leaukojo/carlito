# Forces on a vehicle

<p class="lead">Everything a vehicle does comes from pushes and pulls: gravity, the ground, the
tyres, the air and the water. This page draws them all at once, for each of the seven kinds of
vehicle, and lets you change the speed, the slope, the wind and the controls to see how each
force answers.</p>

<div class="box note">
<p class="box-title">An illustration, not the physics</p>

The arrows come from a simplified copy of the game's formulas, worked out for one instant. They
use the game's own figures for each vehicle: its weight, grip, engine, brakes and drag. The game
itself works wheel by wheel, 60 times a second, with springs, slip and momentum, so its numbers
differ from these. [What this page leaves out](#what-this-page-leaves-out) is listed below.
<!-- src/vehicles/CLAUDE.md: the physics runs at 60 Hz -->

</div>

<!-- widgets/forces.js: its header and data blocks name every figure the widget uses -->
<div class="widget fx-widget" data-widget="forces"></div>

## How to read it

- There are two views, from above and from the side. The vehicle faces right in both, so the
  side view shows its right-hand side. The side view draws only the near wheels. The arrows of
  the far-side wheels are drawn faint, a little offset.
- Each arrow starts where its force acts and points the way the force pushes. Forces are
  measured in [newtons](glossary.md#newton): one newton is roughly the weight of a small apple.
- All the arrows in a view share one scale, shown by the bar in its bottom corner: an arrow
  twice as long is a force twice as big. The longest ticked force in the view sets its scale, so
  the two views can have different bars.
- Weight is usually the biggest force by far, and the ground's push answers it. Untick both to
  zoom in on the small forces, such as [rolling resistance](glossary.md#rolling-resistance). A
  force too small to draw at the scale shows as a dot.
- Point at an arrow or a force's name, or tap it, to read what that force is. A tyre asked for
  more than its [grip](glossary.md#grip) gets a red ring in the view from above.
- Tick **Net force** to see what is left when every push is added up. The box under the views
  says what it does: speed the vehicle up, slow it down, or turn it.

## The seven vehicles

Each choice uses one body from the game and its figures. The **Load** slider means something
different for each, and only where the game has a load:

- **Car**: the sedan, which drives its front wheels. The cars carry no load.
- **Truck**: the garbage truck. Its load is the refuse in the hopper, up to about 5 tonnes when
  full, which the game adds to the truck's weight at its
  [centre of mass](glossary.md#centre-of-mass).
  <!-- refuse_body.gd HOPPER_PAYLOAD_KG 5000; truck.gd set_live_mass(spec.mass + payload) -->
- **Tractor**: the standard tractor. Its load is an implement raised on the three-point hitch, up
  to the harrow's 1.5 tonnes, hanging behind the rear axle. Watch it take weight off the front
  wheels.
  <!-- harrow.gd MASS_KG 1550; TractorVehicle._apply_implement_mass -->
- **Boat**: the speedboat. Boats have no brakes and carry no load.
- **Plane**: the plane, rolling along the runway until its wings carry its weight.
- **Drone**: the standard drone. The throttle slider becomes its climb stick, and its load is a
  parcel on the hook, up to 4 kg.
  <!-- drone_payload.gd MAX_PAYLOAD_KG 4 -->
- **Train**: a locomotive and four wagons. The game's train ignores the wind.

## What this page leaves out

- **Time.** The page shows one instant. Nothing springs, rolls, pitches or builds up speed; the
  readout only says which way the vehicle would go.
- **Tyre detail.** A tyre here grips up to its
  [coefficient of friction](glossary.md#coefficient-of-friction) times the weight on it, and no
  further. The game's tyres also lose a little grip per kilogram as the load rises
  ([load sensitivity](glossary.md#load-sensitivity)), and build their forces from
  [slip](glossary.md#slip). Past the limit the page uses the game's figure: a locked or spinning
  tyre keeps 0.8 of its best grip, and ABS or traction control hold it at the best.
  <!-- GroundDriveSpec.grip_curve (1, 0.8); RayWheel.ABS_SLIP, TCS_SLIP hold the peak -->
- **Turning.** The wheels point along a circle set by the wheelbase and the steering angle, the
  [bicycle angle](glossary.md#bicycle-angle). The side force is shared between the axles by where
  the weight sits, and the load moves to the outside wheels. The game's tyres turn with a
  [slip angle](glossary.md#slip-angle); here they do not.
- **The engine.** The drive force is the throttle's share of the most the best gear can give at
  that speed. There are no gear changes, pedal maps or engine braking, and at low speed the
  engine is allowed to sit at its strongest while the clutch or converter slips.
- **Brakes.** Moving, the brakes push at their full strength for the pedal; at a standstill they
  push only as hard as it takes to hold. No heat, no fade and no hill-start assist.
- **The ground.** Dry asphalt only. In the game each kind of ground changes grip and rolling
  resistance: see [Ground and tyre types](surfaces.md).
- **The air and the water.** A steady wind with no gusts, and still water with no current: see
  [Wind, current and conditions](conditions.md).
- **The boat.** Its four buoyancy points share the weight equally; in the game the bow or stern
  point pushes harder as the boat pitches. The water's sideways drag is left out.
- **The plane.** The wings stay level, with no nose-up angle and no flaps.
- **The drone.** The four rotors share the thrust equally; the game's
  [mixer](glossary.md#mixer) sets each one apart to tilt and turn it.
- **The train.** The cars move as one, so the couplers pull steadily; the game's couplers are
  springs that stretch and settle.
- **The tractor's load.** Every implement is placed where the harrow's weight sits when raised.

## What you see in sloppyCAN

No signal sends a force itself. These show what the forces do:

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `accLong`, `accLat` | out | m/s² | Acceleration along and across the vehicle: the net force divided by the mass. All seven. |
| `acc_vert` | out | m/s² | Up-and-down acceleration: lift or thrust against weight. Plane and drone. |
| `axle_load` | out | kg | The weight on the drive axle, read off its springs. Truck and tractor. |
| `payload_weight` | out | N | The weight hanging on the drone's hook. |
| `draft_force` | out | % | The pull of an implement working in the soil. Tractor. |

<!-- contract/carlito_contract.json: accLong, accLat (all seven, m/s^2), acc_vert (plane, drone), axle_load (tractor, truck, kg), payload_weight (drone, N), draft_force (tractor, %); base_vehicle.gd: acc_long and acc_lat are VehicleTelemetry.body_accel of the velocity change, smoothed -->

## Try it in the game

<div class="box try">
<p class="box-title">Try it in the game: compare the page with the car</p>

1. Open sloppyCAN beside the game and pick the `sedan` on **Flatland**.
2. Get up to about 100 km/h, then brake as hard as you can and watch `accLong` go negative.
3. On this page pick the car, set the speed to 100 km/h, the throttle to 0 and the brake to
   100 %. The readout's "slowing down at" is the page's version of the same number.
4. The two are close but not the same: the game's tyres lose a little grip under load, and its
   nose dips as it brakes. That gap is the part this page leaves out.

</div>

## Related

- [Tyres and slip](tyres.md): how a tyre makes its drive, braking and side forces.
- [Weight transfer and rollover](weight-transfer.md): why the ground's push moves between the
  wheels.
- [Air and rolling resistance](resistance.md): the two forces that are always there.
- [Floating and boats](floating.md), [Plane flight](plane-flight.md),
  [Drone flight](drone-flight.md) and [Trains](rail.md): the forces of each.
- [Glossary](glossary.md): every term on this page.

<style>
  /* Forces page only, here because guide.css stays shared. The widget draws with the guide's
     --fig-* tokens plus two of its own, set for light and dark. */
  :root { --fx-purple: #7b3fb0; --fx-teal: #13807a; }
  :root[data-theme="dark"] { --fx-purple: #c39bf0; --fx-teal: #5cc8bf; }
  .page:has(.fx-widget) { max-width: 72rem; }
  .page .widget.fx-widget { max-width: 72rem; }
  .fx-pick { margin-bottom: 0.6rem; }
  .fx-pick label { color: var(--muted); margin-right: 0.3rem; }
  .fx-views { display: grid; grid-template-columns: 1fr; gap: 0.75rem; }
  .fx-view { border: 1px solid var(--rule); border-radius: 6px; background: var(--bg); }
  .fx-view-title { margin: 0.35rem 0.6rem 0; font-size: 0.75rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.06em; }
  .fx-info { margin-top: 0.75rem; padding: 0.55rem 0.75rem; min-height: 3.2em; border-left: 3px solid var(--accent); background: var(--accent-soft); border-radius: 0 6px 6px 0; }
  .fx-this { color: var(--muted); }
  .fx-panels { display: grid; grid-template-columns: 1fr; gap: 1rem; margin-top: 0.75rem; align-items: start; }
  .fx-panels .w-controls { margin-top: 0; }
  .fx-legend { margin: 0; padding: 0.3rem 0.7rem 0.5rem; border: 1px solid var(--rule); border-radius: 6px; min-width: 0; }
  .fx-legend legend { color: var(--muted); padding: 0 0.3rem; }
  .fx-row { display: grid; grid-template-columns: auto 28px 1fr auto; gap: 0.5rem; align-items: center; padding: 0.22rem 0; cursor: pointer; }
  .fx-swatch { width: 28px; height: 10px; }
  .fx-val { font-variant-numeric: tabular-nums; color: var(--muted); white-space: nowrap; }
  .fx-off { opacity: 0.45; }
  .fx-body { fill: var(--fig-fill); stroke: var(--fig-muted); stroke-width: 1.2; }
  .fx-glass { fill: var(--fig-grid); stroke: var(--fig-muted); stroke-width: 1; }
  .fx-load { fill: var(--fig-grid); stroke: var(--fig-ink); stroke-width: 1; }
  .fx-wheel { fill: var(--fig-grid); stroke: var(--fig-ink); stroke-width: 1.5; fill-opacity: 0.6; }
  .fx-rotor { fill: none; stroke: var(--fig-muted); stroke-width: 1.2; stroke-dasharray: 3 2; }
  .fx-strut { stroke: var(--fig-muted); stroke-width: 2; }
  .fx-ground { stroke: var(--fig-ink); stroke-width: 1.5; }
  .fx-water { fill: var(--fig-blue); opacity: 0.12; }
  .fx-guide { stroke: var(--fig-muted); stroke-width: 1; stroke-dasharray: 4 4; }
  .fx-arrow { cursor: pointer; outline: none; }
  .fx-arrow:focus-visible line:first-of-type, .fx-arrow:hover line:first-of-type { stroke-width: 4; }
  .fx-far { opacity: 0.45; }
  .fx-hit { stroke: transparent; stroke-width: 14; fill: transparent; pointer-events: all; }
  @media (min-width: 1180px) {
    .fx-views, .fx-panels { grid-template-columns: 1fr 1fr; }
  }
</style>

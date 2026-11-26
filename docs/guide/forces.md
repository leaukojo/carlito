# Forces on a vehicle

<p class="lead">This page draws every force on a vehicle on a diagram. Use it to observe the effect of the different parameters that impact a vehicle.</p>

<!-- widgets/forces.js: its header and data blocks name every figure the widget uses -->
<div class="widget fx-widget" data-widget="forces"></div>

<!-- Shown behind the widget's warning button (GuideKit.limitsButton). -->
<div class="widget-limits" hidden>

The arrows come from a simplified copy of the simulator's formulas, worked out for one instant.
They use its figures for each vehicle: its weight, grip, engine, brakes and drag. The simulator
itself works wheel by wheel, 60 times a second, with springs, slip and momentum, so its numbers
differ from these. This drawing leaves out:
<!-- src/vehicles/CLAUDE.md: the physics runs at 60 Hz -->

- **Time.** The drawing shows one instant. Nothing springs, rolls, pitches or builds up speed; the
  readout only says which way the vehicle would go.
- **Tyre detail.** A tyre here grips up to its
  [coefficient of friction](glossary.md#coefficient-of-friction) times the weight on it, and no
  further. The simulated tyres also grip a little less per kilogram as the load rises
  ([load sensitivity](glossary.md#load-sensitivity)), and build their forces from
  [slip](glossary.md#slip). Past the limit the page uses the simulator's figure: a locked or spinning
  tyre keeps 0.8 of its best grip, and ABS or traction control hold it at the best.
  <!-- GroundDriveSpec.grip_curve (1, 0.8); RayWheel.ABS_SLIP, TCS_SLIP hold the peak -->
- **Turning.** The wheels point along a circle set by the wheelbase and the steering angle, the
  [bicycle angle](glossary.md#bicycle-angle). The side force is shared between the axles by where
  the weight sits, and the load moves to the outside wheels. The simulated tyres turn with a
  [slip angle](glossary.md#slip-angle); here they do not.
- **The engine.** The drive force is the throttle's share of the most the best gear can give at
  that speed. There are no gear changes, pedal maps or engine braking, and at low speed the
  engine is allowed to sit at its strongest while the clutch or converter slips.
- **Brakes.** Moving, the brakes push at their full strength for the pedal; at a standstill they
  push only as hard as it takes to hold. No heat, no fade and no hill-start assist.
- **The ground.** Four kinds only, each with the all-season tyre's grip for all three vehicles.
  The simulator has more grounds and tyres: see [Ground and tyre types](surfaces.md).
- **Driver aids.** Only ABS and traction control. There is no stability control.
- **The differential.** Each driven wheel is asked for the same drive and keeps what its own grip
  allows. A real open differential would hold both wheels to what the weaker one can take.
- **The air.** A steady wind with no gusts: see [Wind and conditions](conditions.md).
- **The tractor's load.** Every implement is placed where the harrow's weight sits when raised.

</div>

## What you see in sloppyCAN

No signal sends a force itself. These show what the forces do:

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `accLong`, `accLat` | out | m/s² | Acceleration along and across the vehicle: the net force divided by the mass. |
| `axle_load` | out | kg | The weight on the drive axle, read off its springs (Truck and tractor). |
| `draft_force` | out | % | The pull of an implement working in the soil (Tractor). |

<!-- contract/carlito_contract.json: accLong, accLat (m/s^2), axle_load (tractor, truck, kg), draft_force (tractor, %); base_vehicle.gd: acc_long and acc_lat are VehicleTelemetry.body_accel of the velocity change -->

## Related

- [Slip and the grip curve](slip.md): how a tyre makes its drive, braking and side forces.
- [Weight transfer and rollover](weight-transfer.md): why the ground's push moves between the
  wheels.
- [Understeer and oversteer](understeer.md): which tyres reach their limit first in a turn.
- [Brakes](brakes.md) and [The engine](engine.md): where the braking and drive forces come from.
- [Air and rolling resistance](resistance.md): the two forces that are always there.
- [Glossary](glossary.md): every term on this page.

<style>
  /* Forces page only, here because guide.css stays shared. The widget draws with the guide's
     --fig-* tokens plus two of its own, set for light and dark. */
  :root { --fx-purple: #7b3fb0; }
  :root[data-theme="dark"] { --fx-purple: #c39bf0; }
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
  .fx-row { display: grid; grid-template-columns: auto 28px 1fr auto; gap: 0.5rem; align-items: center; padding: 0.22rem 0; }
  .fx-name { font: inherit; color: var(--ink); background: none; border: 0; padding: 0; text-align: left; cursor: pointer; text-decoration: underline dotted; text-underline-offset: 0.2em; }
  .fx-name:hover { color: var(--accent); }
  .fx-swatch { width: 28px; height: 10px; }
  .fx-val { font-variant-numeric: tabular-nums; color: var(--muted); white-space: nowrap; }
  .fx-off { opacity: 0.45; }
  .fx-check { justify-self: start; }
  .fx-body { fill: var(--fig-fill); stroke: var(--fig-muted); stroke-width: 1.2; }
  .fx-glass { fill: var(--fig-grid); stroke: var(--fig-muted); stroke-width: 1; }
  .fx-load { fill: var(--fig-grid); stroke: var(--fig-ink); stroke-width: 1; }
  .fx-wheel { fill: var(--fig-grid); stroke: var(--fig-ink); stroke-width: 1.5; fill-opacity: 0.6; }
  .fx-lifted { stroke-dasharray: 3 2; fill-opacity: 0; }
  .fx-grip { opacity: 0.75; pointer-events: none; }
  .fx-strut { stroke: var(--fig-muted); stroke-width: 2; }
  .fx-ground { stroke: var(--fig-ink); stroke-width: 1.5; }
  .fx-guide { stroke: var(--fig-muted); stroke-width: 1; stroke-dasharray: 4 4; }
  .fx-arrow { cursor: pointer; outline: none; }
  .fx-arrow:focus-visible line:first-of-type, .fx-arrow:hover line:first-of-type { stroke-width: 4; }
  .fx-far { opacity: 0.45; }
  .fx-hit { stroke: transparent; stroke-width: 14; fill: transparent; pointer-events: all; }
  @media (min-width: 1180px) {
    .fx-views, .fx-panels { grid-template-columns: 1fr 1fr; }
    /* Wide: the force explanation moves up beside the vehicle and example rows. */
    .page .widget.fx-widget { display: grid; grid-template-columns: 1fr 1fr; column-gap: 0.75rem; align-items: start; }
    .fx-widget > * { grid-column: 1 / -1; }
    .fx-widget > .w-vehicles { grid-column: 1; grid-row: 1; }
    .fx-widget > .fx-pick { grid-column: 1; grid-row: 2; }
    .fx-widget > .fx-info { grid-column: 2; grid-row: 1 / span 2; margin: 0 0 0.6rem; align-self: stretch; }
  }
</style>

# The tractors

<p class="lead">The tractor is one 7-tonne farm tractor with two gearboxes to choose from. It
carries and pulls implements, drives them from its engine, and talks to them over the farm
machinery network. It is the family with the most to switch and the most to watch.</p>

## The family

| Vehicle | Gearbox | Weight, about |
| --- | --- | --- |
| `tractor-kenney` | 16-speed powershift, with a park pawl and a hill hold | 7 t |
| `tractor-cvt` | Stepless CVT, holding itself still at a ratio of zero | 7 t |
<!-- tractor-kenney_spec.tres mass 7000, 16 gear_ratios, hill_hold 2; tractor-cvt_spec.tres mass 7000, cvt_range_tops; docs/tractor.md: V cycles the gearbox -->

Both are the same tractor otherwise. Press **V** to switch between them, and **E** to cycle the
attachments: spreader, plough, power harrow, mower, farm tipper trailer, then none.
<!-- docs/tractor.md: "V cycles the gearbox ... E cycles the attachment — spreader → plough → power harrow → mower → drawbar tipping trailer → detached" -->

## What the tractor has

- Big lugged [tyres](tyres.md) that grip best in soft ground ([Ground and tyre types](surfaces.md)).
- [Steering](steering.md), worked slowly by oil pressure, and auto-steer from sloppyCAN.
- No springs: its tyres are its [suspension](suspension.md), and its front axle swings on a pivot.
- A diesel [engine](engine.md) with an all-speed governor and a hand throttle.
- A powershift or CVT [gearbox](gearbox.md), and an automated [clutch](coupling.md) on the
  powershift.
- An open rear differential with a lock, and engageable front-wheel drive
  ([Differentials and four-wheel drive](differentials.md#the-tractors-diff-lock-and-front-wheel-drive)).
- Wet disc [brakes](brakes.md) in the rear axle's oil, which engage front drive when pressed.
- No ABS, traction control or stability control.
- Its own ways of [holding still](holding.md#the-tractors-hill-hold).
- The three-point hitch, PTO, hydraulic remote and implement bus
  ([Implements and the PTO](implements.md)), and the drawbar for its trailer ([Towing](towing.md)).
- [Air drag and rolling resistance](resistance.md), the [aux models](auxiliary.md) and an hour meter
  ([Position, heading and distance](position.md)).

## Where to drive it

The tractor is allowed on every level but Open Sea and Car Arena. **Level 1 - Island** is its
playground: a ploughable field with lighter sandy bands, a mud wallow for the diff lock, a ramp for
front-wheel drive and a yard of implements.
<!-- *_info.tres allowed_vehicles; docs/tractor.md: "Level 1's centre is the ISOBUS farm playground: painted field ..., mud wallow (diff_lock), haul ramp (fwd_drive), implement yard" -->

## What you see in sloppyCAN

The tractor speaks ISOBUS, the farm machinery standard, with more signals than any vehicle but the
drone: the hitch, the PTO, the hydraulic remote, the diff lock and front drive, auto-steer, the hand
throttle, the wheel-based and ground-based speeds and their slip, draft, engine load and the
implement's claim. Each idea page lists the ones it explains.
<!-- docs/tractor.md: "Twenty ISOBUS signals (8 in, 12 out), all flavor isobus" -->

## Related

- [Implements and the PTO](implements.md): what the tractor is for.
- [Glossary](glossary.md): every term on this page.

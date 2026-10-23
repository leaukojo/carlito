# Vehicle measurements

The measure tools and every figure table they generate. The mechanisms behind the figures:
`docs/vehicles.md`, `docs/drivetrain.md`, `docs/heavy_vehicles.md`.

## Measuring a vehicle: `tools/measure_vehicles.tscn`

For questions unit tests can't answer: how fast, does it track straight. Run lines and flags
for every measure tool: § Measure-tool run lines below. Strip: a bare 40 × 6000 m
`StaticBody3D` (the tyre's asphalt), or one `Surface` under `surface=` (`MeasureRig.GripPatch`).

### Measure-tool run lines

Dev reports, not tests. Long sweeps (`all`, `baseline`) take minutes. The figure tables here are
generated: a `doc=<id>` preset runs that table's fixed set and rewrites its `<!-- measure:<id> -->`
region (`doc_region.gd`); refresh a figure by re-running, never by hand.

```powershell
# accel / top speed / tracking on a flat full-grip strip. Arg 1: variant, a comma list or `all`
# (default sedan-sports); arg 2: time cap in s. Flags: coast, track, strict, corner, brake,
# trailer=<name|bobtail>, tc (accel pass slip-limited at the grip peak). `stall` (both pedals floored
# in manual D1, TC off, 10 s), `handbrake` (60 km/h steer step, with and without the lever), `step`
# (step steer at the family's speeds or `speeds=<km/h>,<km/h>`, pedal held then lifted), `circle`
# (full right lock at 5 km/h, no attachment unless trailer=), `hitch` (parked: axle loads bare, then each carried implement or
# trailer=<implement> lowered / raised / lowered, against statics and the composite tensor), `plough`
# (on level 1's field: each draft implement or trailer=<implement> down, held at 3 / 7 / 10 km/h
# against D497, then a floored standing start's shifts; `trace[=n] trace_s=` prints the start per
# tick; `course` runs tractor_plough's Row with its light bands instead, the plough down at 3 / 5 /
# 7 / 9 km/h and raised at 7 / 16; `pto` engages the PTO at 1000 throughout and prints its crank
# load, parked lowered and per hold; `governor` instead holds the all-speed governor at the hand
# throttle's PTO preset, PTO in at 540: parked in N raised then lowered, then in D2 (`gear=` another)
# raised, then lowered, with a `droop` gate on the shaft), `kerb` (12 / 20 cm steps) and `arm` (the
# refuse body's lift and lower, parked in N on the handbrake with the PTO in: rpm against the PTO
# mode's set speed, `engine_load`, the fuel, each stroke's time) replace the other passes.
# `rear_lat_grip=` / `bar_rear=` / `cornering_peak=` / `ackermann=<x>`: that spec field, in memory.
# `step` prints each axle's roll-steer angle, its pred and a chatter count on every body whose spec
# has roll steer; `rollsteer=<front>,<rear>` (deg/deg) overrides the spec's coefficients;
# `angdamp=<1/s>`: the body's and a coupled trailer's angular damping REPLACEd (0 = none).
# tyre=<id>: that TyreCatalog class (else stock); surface=<name>: the slabs painted (not plough).
& $GODOT --headless --path . res://tools/measure_vehicles.tscn -- sedan-sports 45
& $GODOT --headless --fixed-fps 60 --path . res://tools/measure_vehicles.tscn -- sedan 60 step
& $GODOT --headless --fixed-fps 60 --path . res://tools/measure_vehicles.tscn -- sedan 60 circle ackermann=0
& $GODOT --headless --fixed-fps 60 --path . res://tools/measure_vehicles.tscn -- tractor-kenney 20 hitch
& $GODOT --headless --fixed-fps 60 --path . res://tools/measure_vehicles.tscn -- tractor-kenney 20 plough
# launch trace + gates on the accel pass: trace[=<every n ticks>] trace_s=<s printed, 3>; notc (the
# body's TC off), gear=<1-24> (manual, held in that byte), contact (each wheel's load and contact
# under each line); not with a doc= preset
& $GODOT --headless --fixed-fps 60 --path . res://tools/measure_vehicles.tscn -- semi 40 trace notc
# the trace's launch held at a part pedal (its settle, gates and shift lines; `trace` adds the ticks)
& $GODOT --headless --fixed-fps 60 --path . res://tools/measure_vehicles.tscn -- sedan 90 pedal=0.3
# part-pedal probes, instead of every other pass, at each speed of the family's set from a
# standstill: cruise (PI pedal settled; gear=<1-24> holds it in that byte), kickdown (stepped to
# 1), pulse[=<period s>] duty=<0..1>
& $GODOT --headless --fixed-fps 60 --path . res://tools/measure_vehicles.tscn -- sedan 90 cruise kickdown pulse
# wind (any pass): wind=<from_deg>:<m/s>, steady, FROM as CONDITIONS enters it (0 = out of the
# north, -Z; the strip runs -Z, so wind=0:9 is a headwind). With cruise, one speed per family:
# headtail (two more runs from a standstill, into then with 9 m/s along the heading), xwind[=<m/s>]
# (13 m/s from the right, pedal held, wheel straight: drift, heading, yaw rate and roll at 1 s, 2 s)
& $GODOT --headless --fixed-fps 60 --path . res://tools/measure_vehicles.tscn -- delivery 120 cruise headtail xwind
# the CI `tracking` gate: skips the accel pass, exits 1 on a FAIL
& $GODOT --headless --path . res://tools/measure_vehicles.tscn -- all 45 track strict
# drone: hover / climb / lean / endurance / one-motor-out (no args, ~1 min)
& $GODOT --headless --path . res://tools/measure_drone.tscn
# coupled semi launch: steer-axle load, pitch, air gate, step-steer rollover (~30 s; flags
# trailer=<box|tanker|tipper|flatbed|bobtail> tip_kmh=<km/h> ramp front_z= com_z=; strict = the CI gate)
& $GODOT --headless --path . res://tools/measure_semi_launch.tscn -- semi
# a truck losing its air: parked on 18 %, floored in D, cut at 30 km/h. Arg 1: garbage-truck,
# semi, semi-conventional or `all`; `strict` = the CI gate (~1.5 min)
& $GODOT --headless --fixed-fps 60 --path . res://tools/measure_air_loss.tscn -- all strict
# steepest standing-start grade. Arg 1: variant, `all` or `level=<id>`; then surfaces
# (asphalt gravel grass dirt field mud; none = all); flags mfwd diff tc verbose hold=<deg> pedal=<0..1>
# gear=<1-24> (manual, held in that byte: a start gear; roll-back too) cornering_peak=<x> (in memory)
# tyre=<id> (that class fitted, every mode; the traction ceiling reads its grip)
& $GODOT --headless --path . res://tools/measure_grade.tscn -- tractor-kenney mud mfwd tc
& $GODOT --headless --path . res://tools/measure_grade.tscn -- level=level_2
# converter creep: released in D1 with no pedal, the flat creep speed and the steepest grade held
# (a converter variant or `all`; ~1 min a body)
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- sedan creep
# roll-back: released on a grade after the foot-brake settle, floored delay=<s> later (0.5); the
# roll-back, the time to 0.1 m forward and how long the hill hold held. Flags grade=<%> (else 10
# and 25), pedal=<0..1>, nohold (the hold off), tipper (the tractor's drawbar tipper), mfwd, surface,
# verbose (per-axle tyre force and slip, and the trailer's pull, every 0.5 s)
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- sedan rollback nohold
# a climb in automatic D on a fixed grade (`grade=<%>`, 8) at a held pedal (`pedal=`, full), 40 s
# or the ramp's top: each shift with the gearbox's road load, and a `falls back` gate (an upshift
# a later downshift undoes); flags tipper, mfwd, a surface
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- semi climb grade=8 pedal=0.6
# held at rest for 60 s on a grade (deg): foot brake, `hand`, `pawl` (P alone), or across the slope `cross`;
# wind=<from_deg>:<m/s> as measure_vehicles' (the ramp rises toward -Z: wind=0:13 blows downhill)
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- sedan park=5.7 hand
# bumps and ditches, asphalt and mud. Arg 1: variant or `baseline`; flags mfwd diff tc
# speed=<m/s> lane= patch= verbose tyre=<id>. Arg 1 `course=<challenge id>` instead drives that
# reach-zone challenge's line (open / lock / MFWD / both, floored unless speed=) against its par
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_rough.tscn -- baseline
# rewrite this doc's figure tables (each a few minutes)
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_vehicles.tscn -- doc=braking
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_vehicles.tscn -- doc=cornering
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_vehicles.tscn -- doc=accel
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_vehicles.tscn -- doc=cruise
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_vehicles.tscn -- doc=steer
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_vehicles.tscn -- doc=tyres
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- doc=grade
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_grade.tscn -- doc=park
& $GODOT --headless --path . --fixed-fps 60 res://tools/measure_rough.tscn -- doc=rough
```

| Pass | Measures | Note |
| --- | --- | --- |
| Acceleration / top speed | 0-50/100/150/200 km/h, 0-60 mph, quarter mile, top speed + gear/rpm | the label says which: `top (settled)`, `top (time cap)` (with what it was still gaining: `sedan` needs ~43 s for 200 km/h) or `top (lost)`; `lateral` flags a body that left the 120 m strip |
| Tracking | 60 km/h launch, 200 m zero-steer, lateral offset / heading change | thresholds 1.0 m / 1.0° (`wheel_positions` x is a common cause), and no tick with the whole front axle off the ground (a wheelie: `com_y` or pitch damping); CI gate `tracking` (`-- all 45 track strict`), parallel to `build`, `publish-dev` needs both |
| Coast-down (`coast`) | throttle cut where the accel pass ended, deceleration from resistance plus engine overrun (still in gear) | vs the `model` line: declared `0.5*rho*Cd*A*v^2 + crr*m*g` + `Drivetrain.overrun_torque / r`, mean per tick, then what the tyres carried (the wheels' spin keeps ~5-10 % of the overrun off the road), so declared + tyres closes on the measurement; the force column is on the all-up mass (`8000 kg chassis, 32000 kg all up`) |
| Cornering (`corner`) | skid pad at 40 km/h held by a PI pedal, lock wound on over 10 s: peak lateral g (`v * yaw rate`) and the path's own (`acc_lat`, which a yaw overshoot into a slip angle does not inflate: `sedan` on ice 0.22 / 0.11 g), axle saturating first beside `BalanceModel.limit`'s free-rolling call (`pred`: its first axle and margin), the tyres' summed longitudinal force at the peak (the drive the speed hold spends), roll at the peak and the front axles' share of the lateral load transfer since the lock began (LLTD, off the corners' spring loads), wheels lifted | the anti-roll bar's sizing pass (4-8 deg target); a bang-bang pedal reads a biasing diff's power oversteer instead of grip |
| Braking (`brake`) | straight stops at 30 / 60 / 100 % pedal from 100 km/h (or 90 % of top): time, distance, mean g, seconds any wheel skids (slip > 0.3) and any wheel's ABS acts | part pedal must stay proportional with no skid; ABS acts only where the pedal outruns a tyre |
| Launch trace (`trace`, on the accel pass) | settled 1.5 s on the foot brake, then floored: a line per tick (`trace=<n>` every n, `trace_s=` how long, plus each gear change) of km/h, gear, published rpm, the wheel side's rpm, the coupling's state (`c`: O, S, L, or H on the converter's law) and slip, `clutch`, the torque it carried at the crank (`Tc`), delivered fuel, limiter and shift cuts, front-axle load over parked beside what steady transfer predicts at the body's measured acceleration (`xfer`: `m a h / L`, a coupled trailer's pull at the hitch's height, counted since parked: the header's `coupled` line prints the pull and the load a braked rig rests on its coupling at the settle) and that acceleration (`a g`), each driven wheel's signed slip and TC flag; then the launch gates, `each shift` (road speed, the crank rpm that speed gives in the gear left and the gear taken, and the shift's slip: its time until the coupling locks and the peak torque it carried at the crank) | gates (a report, never CI), over the launch to 100 km/h, to the held gear's upshift point under `gear=`, or to the pass's end (the 40 km/h tractor, so its launch wheelie is checked): no downshift, no gear left inside 1.0 s, no limiter tick (its cycle rate in Hz when it toggles), every upshift landing at 1.1x the downshift point at its pedal (`ShiftPolicy.down_rpm`) or more on road speed, no two opposite shifts inside 1.0 s (hunting), the front axle never lifted and its overshoot past steady transfer (`xfer`; the gap less road resistance, the trace's tick-late acceleration and the pitched pose's lean, `docs/vehicles.md` § Pitch) at most what a body damped at 0.3 of critical overshoots a step of the event's own swing (37 %, at least 5 points; `GATE_XFER_ZETA`), judged per event, the launch and each shift's settle; the peak prints its tick, gap, share and `a g`, and `front split` takes that gap apart; `per event` prints each event's own peak (the launch, then each shift's settle), so a smaller one is not hidden under the gate's figure. A gap inside a shift's handover or cut is kept apart (`in shifts`, with the shift: `docs/drivetrain.md` § The shift policy owns it), reported, not gated. `front why` prints the peak acceleration (a spike in `a g` is a driveline shock); `pitch` prints body pitch per g over the launch gear's middle half beside the springs-and-links prediction and `h / L`. `notc` runs the pass with the body's TC off (the limiter-at-launch symptom); `gear=<1-24>` holds that byte in the bridge's manual mode (the tractor's D1, held to its upshift point); `pedal=<0..1>` holds the launch at that pedal, with the gates and shift lines (per-tick lines only with `trace`); `contact` prints under each line every wheel's suspension force, compression, patch, contact normal and collider (`RayWheel.contact_collider`), where a one-tick load spike with no drive step shows its source |
| Step steer (`step`, instead of the other passes) | at each speed of the family's set (cars 30 / 60 / 100 km/h, trucks 30 / 50 / 70, the tractor 15 / 25 / 34; none within 5.4 km/h of a governor), run up floored and settled 3 s on the PI pedal, the bridge steer stepped in one tick to 10 / 20 / 30 % of lock and held 3 s, once on the PI pedal, once lifted on the step: the body's yaw index (live tensor about its up axis over `m a b`), steady yaw rate (last 0.5 s) and lateral g, that rate over neutral steer `v * delta / L` off the bicycle angle (`docs/vehicles.md` § Steering geometry), the rise to 90 % of it, the overshoot, peak body slip and roll, most wheels lifted at once, LLTD over the steady tail against the step's first tick; on a held step the understeer gradient `K = (delta - L r / v) / (a_y / g)` in deg/g (`doc=steer` prints the smallest step's) | a spin is body slip past 20 deg, a rollover the up axis past 45 deg off vertical (its yaw and slip are then not handling figures). Run on a 400 m slab under the strip (a 100 km/h step travels ~35 m sideways in 3 s). The wheels follow the input at the body's `steer_speed` and speed taper, as for a driver |
| Part pedal (`cruise`, `kickdown`, `pulse`, instead of the other passes) | at each speed of the family's set (cars 50 / 60 / 90 / 100 / 120 km/h, trucks 30 / 50 / 70 / 85, the tractor 15 / 25 / 34; none within 5.4 km/h of a governor), from a standstill in automatic D: a PI pedal (a fuel command through the pedal map's inverse, `PedalMap.pedal_for`, so its loop gain is the same on every map) follows a setpoint ramped at 1.0 m/s² (0.5 trucks and tractor) and holds it until 5 s within 0.3 m/s with no shift. `cruise`: gear, rpm, pedal, `engine_load` (the trucks' law, read for every body) and `fuel_rate` over that hold, the approach's peak fuel command and its shifts; `gear=<1-24>` holds it in that byte (no shift gates there). `kickdown`: the pedal stepped to 1, ticks to the first downshift, gears dropped, time to +20 km/h. `pulse[=<s>]`: re-settled, then 30 s of on/off pedal at that period (1.0 s), its duty the PI's latched each period (`duty=` fixes it): the speed band, shifts per minute and the gears seen | each window (approach and hold, kick, pulse) gets the hunting, landing and limiter gates on one line. Floored is judged on the fuel command, not the pedal: on the petrol map full fuel takes the least pedal that reaches it, under 1.00. A peak approach fuel of 1.00 is a floored approach, and its shift points are those of the pedal it held (the full-pedal ones only on a LINEAR map); a hold at full fuel is flagged as the body's top, not a cruise |

- `-- semi` measures the coupled 32 t box rig (`trailer=<box|tanker|tipper|flatbed|bobtail>` or any
  attachment file name). Its launch is not bit-reproducible across run contexts (the coupling
  countdown inherits the previous vehicle): compare runs of the same shape.
- `tractor-kenney` never reaches the tracking pass's speed; its wheelie check is the trace's
  front-axle gate (`-- tractor-kenney 40 trace`).
- `tools/measure_semi_launch.tscn`: static pose off P5; P7 is the rollover skid pad (`tip_kmh=`,
  `ramp`), lateral g read at first wheel lift; `strict` exits 1 when a steer wheel drops under
  `STEER_FLOOR_N` in the P2 or P6 launch (CI runs it on both units).
- `tools/measure_drone.tscn`: hover, climb/descent, lean/translate, endurance, one-motor-out; a
  divergence from `DroneVehicle`/`DronePower` arithmetic is a finding.

### Cruise

<!-- measure:cruise (generated by `measure_vehicles -- doc=cruise`; edits inside are overwritten) -->
Measured 2026-10-20 (`measure_vehicles -- doc=cruise`; per body `-- <variant> 60 cruise`): each
speed held on the flat strip from a standstill, the setpoint ramped at 1.0 m/s² (0.5 on the trucks
and the tractor), settled after 5 s within 0.3 m/s with no shift; a speed within the governor's band
is dropped. Each cell: the gear, the crank's rpm, the pedal, `engine_load` and `fuel_rate` (L/h)
over the hold.

| Body | Held at (km/h: gear, rpm, pedal, load, burn) |
| --- | --- |
| `sedan` | 50: D5 1603 rpm, 0.04, 14 %, 1.4 L/h; 60: D6 1602 rpm, 0.05, 17 %, 1.7 L/h; 90: D6 2410 rpm, 0.08, 27 %, 4.0 L/h; 100: D6 2690 rpm, 0.11, 31 %, 5.1 L/h; 120: D6 3235 rpm, 0.14, 38 %, 7.6 L/h |
| `sedan-sports` | 50: D5 1686 rpm, 0.03, 13 %, 1.5 L/h; 60: D6 1687 rpm, 0.04, 15 %, 1.7 L/h; 90: D6 2533 rpm, 0.06, 21 %, 3.7 L/h; 100: D6 2817 rpm, 0.07, 24 %, 4.7 L/h; 120: D6 3386 rpm, 0.09, 30 %, 7.0 L/h |
| `van` | 50: D5 1599 rpm, 0.04, 15 %, 1.5 L/h; 60: D6 1601 rpm, 0.05, 18 %, 1.8 L/h; 90: D6 2414 rpm, 0.10, 30 %, 4.5 L/h; 100: D6 2677 rpm, 0.11, 32 %, 5.4 L/h; 120: D6 3230 rpm, 0.16, 42 %, 8.5 L/h |
| `delivery` | 50: D4 1577 rpm, 0.15, 14 %, 2.7 L/h; 60: D5 1433 rpm, 0.18, 16 %, 2.8 L/h; 90: D6 1714 rpm, 0.25, 25 %, 5.2 L/h; 100: D6 1906 rpm, 0.29, 28 %, 6.6 L/h; 120: D6 2291 rpm, 0.36, 36 %, 10.1 L/h |
| `garbage-truck` | 30: D3 1274 rpm, 0.15, 11 %, 3.8 L/h; 50: D4 1498 rpm, 0.20, 18 %, 7.5 L/h; 70: D5 1582 rpm, 0.22, 20 %, 8.3 L/h |
| `semi` + 24 t towed | 30: D7 1250 rpm, 0.10, 9 %, 6.9 L/h; 50: D9 1361 rpm, 0.11, 11 %, 8.5 L/h; 70: D11 1268 rpm, 0.11, 11 %, 8.0 L/h |
| `tractor-kenney` | 15: D14 1187 rpm, 0.22, 17 %, 3.7 L/h; 25: D16 1647 rpm, 0.47, 17 %, 5.3 L/h; 34: D16 2237 rpm, 0.81, 23 %, 10.5 L/h |
| `tractor-cvt` | 15: D3 1469 rpm, 0.38, 18 %, 4.9 L/h; 25: D4 1913 rpm, 0.63, 22 %, 8.0 L/h; 34: D4 2309 rpm, 0.85, 22 %, 11.1 L/h |
<!-- /measure:cruise -->

### Wind

<!-- measure:wind (generated by `measure_vehicles -- doc=wind`; edits inside are overwritten) -->
Measured 2026-10-20 (`measure_vehicles -- doc=wind`; per body `-- <variant> 60 cruise headtail
xwind`): one speed held from a standstill as `doc=cruise` holds it, and again from a standstill
into, then with, a steady 9 m/s along the heading (STRONG's steady wind): the pedal and
`engine_load` over each hold, against drag's `0.5 rho CdA ((v ± w)^2 - v^2)`. Then, from the
still-air settle, 13 m/s (STRONG's steady wind plus its gust ceiling) from the right, the pedal held
and the wheel straight: drift (+ toward the wind), the heading turned (+ into it), the yaw-rate peak
and the roll.

| Body | km/h | Still (pedal, load) | Into the wind | With it | Crosswind at 1 s | at 2 s |
| --- | --- | --- | --- | --- | --- | --- |
| `sedan` | 90 | 0.08, 27 % | 0.13, 38 % | 0.05, 19 % | -0.58 m, -3.9 deg, 4.9 deg/s, roll +0.2 deg | -2.81 m, -7.7 deg, 4.9 deg/s, roll +0.1 deg |
| `delivery` | 90 | 0.25, 25 % | 0.37, 37 % | 0.18, 17 % | -0.49 m, -3.8 deg, 4.5 deg/s, roll +0.5 deg | -2.61 m, -7.8 deg, 4.5 deg/s, roll +0.4 deg |
| `garbage-truck` | 70 | 0.22, 20 % | 0.28, 25 % | 0.19, 16 % | -0.10 m, -1.0 deg, 1.6 deg/s, roll +0.1 deg | -0.62 m, -2.7 deg, 1.8 deg/s, roll +0.2 deg |
| `semi` + 24 t towed | 70 | 0.11, 11 % | 0.15, 15 % | 0.08, 8 % | -0.07 m, -0.4 deg, 0.5 deg/s, roll -0.0 deg | -0.30 m, -0.9 deg, 0.5 deg/s, roll -0.0 deg |
<!-- /measure:wind -->

### Launches

<!-- measure:accel (generated by `measure_vehicles -- doc=accel`; edits inside are overwritten) -->
Measured 2026-10-20 (`measure_vehicles -- doc=accel`; per body `-- <variant> 60`, plus `tc` for the
slip-limited run): standing starts on the strip, pedal floored (with the body's own traction control
where fitted), then slip-limited at the 0.12 grip peak (`tc`), beside the real-world reference
(`tools/vehicle_reference_specs.json`). The breakdown is the floored run's 0-50 seconds: a driven
wheel past 0.20 slip, the limiter's fuel cut, a shift cut, the body's traction control holding a
driven wheel back, and torque-bound (pedal floored, no cut or hold, every driven tyre under its
peak), the part of that under converter stall in brackets; then grip use, the driven tyres' force
over their load-scaled `mu_long` budget, floored / tc, with the rest of that budget in brackets: the
grip curve short of its peak with the slip under / past 0.12, and what the one-tick force cap took
off.

| Body | 0-50 floored / tc / ref | 0-100 floored / tc / ref | 0-50 spin / limiter / shift / tcs / torque-bound (stall) | 0-50 grip use (under peak / past peak / tick cap) |
| --- | --- | --- | --- | --- |
| `sedan-sports` | 2.73 / 2.72 / 2.3 | 6.52 / 6.50 / 5.1 | 0.00 / 0.00 / 0.00 / 0.60 / 2.12 (0.48) | 0.82 (0.18 / 0.00 / 0.00) / 0.83 (0.17 / 0.00 / 0.00) |
| `sedan` | 3.62 / 3.60 / 3.4 | 8.43 / 8.42 / 8.0 | 0.00 / 0.00 / 0.00 / 2.65 / 0.92 (0.48) | 0.86 (0.14 / 0.00 / 0.00) / 0.87 (0.13 / 0.00 / 0.00) |
| `hatchback-sports` | 3.35 / 3.33 / 2.7 | 7.08 / 7.07 / 6.3 | 0.00 / 0.00 / 0.00 / 2.97 / 0.35 (0.35) | 0.91 (0.09 / 0.00 / 0.00) / 0.91 (0.09 / 0.00 / 0.00) |
| `suv` | 3.78 / 3.77 / 3.6 | 9.62 / 9.60 / 8.5 | 0.00 / 0.00 / 0.00 / 0.02 / 3.75 (1.52) | 0.38 (0.62 / 0.00 / 0.00) / 0.38 (0.62 / 0.00 / 0.00) |
| `suv-luxury` | 2.75 / 2.73 / 2.6 | 6.87 / 6.85 / 6.0 | 0.00 / 0.00 / 0.00 / 0.03 / 2.68 (1.07) | 0.52 (0.48 / 0.00 / 0.00) / 0.52 (0.48 / -0.00 / 0.00) |
| `taxi` | 3.67 / 3.67 / 3.8 | 8.93 / 8.92 / 9.0 | 0.00 / 0.00 / 0.00 / 1.07 / 2.55 (0.57) | 0.82 (0.18 / 0.00 / 0.00) / 0.83 (0.17 / 0.00 / 0.00) |
| `police` | 3.13 / 3.12 / 2.6 | 7.58 / 7.57 / 6.2 | 0.00 / 0.00 / 0.00 / 0.47 / 2.63 (0.78) | 0.79 (0.21 / 0.00 / 0.00) / 0.80 (0.20 / -0.00 / 0.00) |
| `race` | 1.82 / 1.82 / 1.6 | 3.83 / 3.83 / 3.7 | 0.00 / 0.00 / 0.00 / 1.77 / 0.03 (0.03) | 0.93 (0.07 / 0.00 / 0.00) / 0.93 (0.07 / 0.00 / 0.00) |
| `race-future` | 1.63 / 1.60 / 1.1 | 3.28 / 3.23 / 2.6 | 0.00 / 0.00 / 0.00 / 0.00 / 1.60 (1.02) | 0.73 (0.27 / 0.00 / 0.00) / 0.74 (0.25 / 0.00 / 0.00) |
| `van` | 4.27 / 4.25 / 4.3 | 10.87 / 10.83 / 10.2 | 0.00 / 0.00 / 0.00 / 0.05 / 4.18 (1.70) | 0.57 (0.43 / 0.00 / 0.00) / 0.57 (0.43 / -0.00 / 0.00) |
| `pickup` | 3.97 / 3.95 / 3.0 | 10.00 / 9.98 / 7.0 | 0.00 / 0.00 / 0.00 / 0.05 / 3.88 (1.57) | 0.59 (0.41 / 0.00 / 0.00) / 0.59 (0.41 / 0.00 / 0.00) |
| `pickup-flat` | 3.85 / 3.82 / 3.5 | 9.70 / 9.68 / 8.1 | 0.00 / 0.00 / 0.00 / 0.05 / 3.77 (1.52) | 0.59 (0.41 / 0.00 / 0.00) / 0.59 (0.41 / -0.00 / 0.00) |
| `delivery` | 5.57 / 5.55 / 5.0 | 18.38 / 18.37 / 11.8 | 0.00 / 0.00 / 0.00 / 0.02 / 5.53 (1.32) | 0.39 (0.61 / 0.00 / 0.00) / 0.39 (0.61 / -0.00 / 0.00) |
| `delivery-flat` | 5.33 / 5.32 / 5.3 | 17.33 / 17.32 / 12.3 | 0.00 / 0.00 / 0.00 / 0.02 / 5.30 (1.27) | 0.41 (0.59 / 0.00 / 0.00) / 0.41 (0.59 / 0.00 / 0.00) |
| `ambulance` | 6.38 / 6.37 / 5.5 | 21.22 / 21.20 / 12.9 | 0.00 / 0.00 / 0.00 / 0.02 / 6.33 (1.53) | 0.41 (0.59 / 0.00 / 0.00) / 0.41 (0.59 / 0.00 / 0.00) |
| `garbage-truck` | 6.80 / 6.78 / 8.0 | - / - / - | 0.00 / 0.00 / 0.00 / 0.02 / 6.77 (1.38) | 0.46 (0.54 / 0.00 / 0.00) / 0.46 (0.54 / 0.00 / 0.00) |
| `firetruck` | 6.43 / 6.42 / 6.0 | 20.43 / 20.42 / 15.0 | 0.00 / 0.00 / 0.00 / 0.02 / 6.40 (1.32) | 0.45 (0.55 / 0.00 / 0.00) / 0.45 (0.55 / 0.00 / 0.00) |
| `semi` + 24 t towed | 16.35 / 15.82 / 16.0 | - / - / - | 0.00 / 0.00 / 2.02 / 0.02 / 14.30 (1.92) | 0.43 (0.57 / 0.00 / 0.00) / 0.45 (0.55 / 0.00 / 0.00) |
| `semi-conventional` + 24 t towed | 16.37 / 15.85 / 16.5 | 58.72 / 58.20 / 60.0 | 0.00 / 0.00 / 2.02 / 0.02 / 14.30 (1.88) | 0.44 (0.56 / 0.00 / 0.00) / 0.46 (0.54 / 0.00 / 0.00) |
| `tractor-kenney` | - / - / 12.0 | - / - / - | - | - / - |
| `tractor-cvt` | - / - / - | - / - / - | - | - / - |
<!-- /measure:accel -->

The car family carries an ideal traction control (`tcs_equipped`; not `race-future`), a hold on
each driven wheel bounded by its share of what the coupling may pass, solved with the brakes inside
the differentials (`RayWheel.settled_spin`), so floored and `tc` match: the grip-bound cars spend
a short stretch of the 0-50 held at the peak, with no spin and no limiter. `race` holds the peak on
TC for longer; `race-future` does not spin. The semis (ASR) are torque-bound for most of it with
grip to spare and run 0-50 a little under a loaded diesel rig's typical time. Energy bounds it
(½mv² of the rig's mass at the engine's peak power, 90 % efficient, no shifts); a loaded diesel
needs far longer to 60 mph.

The heavy vans run 0-100 slower than `ref` and 0-50 a little behind theirs (the table above). The
`ref` figures are ungraded "typical" values with no road test of the class behind them (none of a
Transit 3.2 automatic was found), and they sit at or under the energy bound: ½mv² to the 0-100 speed at
the class's 147 kW, 90 % efficient, no shifts, per van mass. The vans are torque-bound through 0-50
(a brief shift, no spin) and run 0-100 in D1-D4, upshifting at `shift_up_rpm`. Their top speed is
drag's: `delivery` settles in D6 above `ref` (no governor declared), and `ambulance` is governed
(`docs/drivetrain.md` § Engine braking under a fuel cut).

### Braking

<!-- measure:braking (generated by `measure_vehicles -- doc=braking`; edits inside are overwritten) -->
Measured 2026-10-20 (`measure_vehicles -- doc=braking`; per body `-- <variant> 60 brake`): stops
from 100 km/h, or 90 % of the top where that is lower (`from`).

| Body | 30 % pedal | 60 % | 100 % |
| --- | --- | --- | --- |
| `sedan` | 0.24 g, 157.5 m | 0.63 g, 62.3 m | 0.95 g, 41.4 m, ABS |
| `pickup` | 0.24 g, 160.2 m | 0.64 g, 60.8 m, ABS | 0.98 g, 40.1 m, ABS |
| `delivery` | 0.24 g, 156.9 m | 0.64 g, 60.2 m, ABS | 0.95 g, 40.9 m, ABS |
| `garbage-truck` (from 75) | 0.16 g, 120.3 m | 0.68 g, 31.4 m, ABS | 0.75 g, 29.1 m, ABS |
| `semi` + 24 t towed (from 79) | 0.26 g, 93.2 m | 0.60 g, 40.8 m, ABS | 0.74 g, 33.5 m, ABS |
| `race` (no ABS) | 0.26 g, 132.4 m | 0.80 g, 47.1 m | 1.12 g, 35.3 m, skids 2.42 s |
<!-- /measure:braking -->

### Tyre classes by surface

Every class a body's fit takes (`TyreCatalog.fitting`):

<!-- measure:tyres (generated by `measure_vehicles -- doc=tyres`; edits inside are overwritten) -->
Measured 2026-10-20 (`measure_vehicles -- doc=tyres`; per run `-- <variant> 60 track corner brake tc
tyre=<id> surface=<name>`). Each cell: the full-pedal stop from 50 km/h, the cornering pass's path g
at 40 km/h (`slid`: the body let go), the `tc` 0-30 km/h time; `-` where the body never reached that
speed in the cap.

| Body | Tyre | Asphalt | Wet | Snow | Ice | Mud | Field |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `sedan` | all_season (stock) | 11.2 m, 0.85 g, 2.37 s | 18.2 m, 0.49 g, 3.53 s | 20.7 m, 0.39 g, 4.45 s | 70.8 m, 0.11 g, 15.12 s | 17.9 m, 0.37 g, 6.62 s | 17.7 m, 0.43 g, 4.77 s |
|  | summer | 10.4 m, 0.92 g, 2.25 s | 16.9 m, 0.53 g, 3.30 s | 31.9 m, 0.24 g, 7.33 s | 92.6 m, 0.08 g, 21.52 s | 18.1 m, 0.37 g, 6.68 s | 17.9 m, 0.42 g, 4.80 s |
|  | winter | 11.5 m, 0.82 g, 2.42 s | 18.7 m, 0.47 g, 3.62 s | 18.3 m, 0.46 g, 3.93 s | 49.7 m, 0.16 g, 9.87 s | 17.6 m, 0.38 g, 6.47 s | 17.5 m, 0.43 g, 4.68 s |
|  | studded | 11.8 m, 0.80 g, 2.47 s | 19.2 m, 0.46 g, 3.72 s | 18.1 m, 0.46 g, 3.90 s | 32.7 m, 0.25 g, 6.25 s | 18.0 m, 0.37 g, 6.80 s | 17.9 m, 0.42 g, 4.85 s |
| `pickup` | all_season (stock) | 10.7 m, 0.83 g, 2.50 s | 18.2 m, 0.51 g, 3.07 s | 20.8 m, 0.42 g, 4.02 s | 70.9 m, 0.11 g slid, 15.53 s | 17.9 m, 0.39 g, 6.22 s | 17.7 m, 0.43 g, 4.27 s |
|  | summer | 9.9 m, 0.91 g, 2.50 s | 16.6 m, 0.54 g, 2.82 s | 31.9 m, 0.25 g, 7.05 s | 93.0 m, 0.08 g slid, 22.58 s | 18.1 m, 0.39 g, 6.30 s | 17.9 m, 0.43 g, 4.32 s |
|  | winter | 10.9 m, 0.81 g, 2.52 s | 18.5 m, 0.49 g, 3.15 s | 18.2 m, 0.48 g, 3.45 s | 49.8 m, 0.16 g slid, 9.82 s | 17.6 m, 0.40 g, 6.05 s | 17.5 m, 0.44 g, 4.18 s |
|  | studded | 11.3 m, 0.79 g, 2.52 s | 19.2 m, 0.49 g, 3.25 s | 18.1 m, 0.49 g, 3.42 s | 32.8 m, 0.27 g, 5.92 s | 18.0 m, 0.39 g, 6.42 s | 17.8 m, 0.43 g, 4.37 s |
|  | mud | 11.4 m, 0.78 g, 2.53 s | 22.6 m, 0.41 g, 3.95 s | 24.2 m, 0.35 g, 5.00 s | 89.5 m, 0.08 g slid, 25.43 s | 15.6 m, 0.46 g, 4.80 s | 16.3 m, 0.47 g, 3.85 s |
| `garbage-truck` | winter | 13.0 m, 0.67 g, 3.57 s | 22.5 m, 0.40 g, 4.18 s | 21.9 m, 0.38 g, 4.75 s | 62.9 m, 0.13 g slid, 12.12 s | from 25 km/h: 5.3 m, -, - | 20.6 m, 0.36 g slid, 8.38 s |
|  | mud | 13.6 m, 0.64 g, 3.62 s | 27.8 m, 0.32 g, 5.03 s | 29.6 m, 0.27 g slid, 6.70 s | 116.7 m, 0.78 g slid, 29.03 s | from 25 km/h: 4.8 m, -, - | 19.2 m, 0.39 g slid, 7.42 s |
|  | truck_drive (stock) | 13.2 m, 0.66 g, 3.57 s | 23.0 m, 0.39 g, 4.23 s | 25.2 m, 0.33 g, 5.42 s | 95.1 m, 0.09 g slid, 19.92 s | from 25 km/h: 5.1 m, -, - | 20.2 m, 0.36 g slid, 7.60 s |
<!-- /measure:tyres -->

### Cornering

<!-- measure:cornering (generated by `measure_vehicles -- doc=cornering`; edits inside are overwritten) -->
Measured 2026-10-20 (`measure_vehicles -- doc=cornering`; per body `-- <variant> 60 track corner`):
peak lateral g, the axle that saturates first (by its share of the friction ellipse), roll at the
peak, most wheels lifted at once.

| Body | Peak | Saturates first | Roll | Lifted |
| --- | --- | --- | --- | --- |
| `sedan-sports` | 0.84 g | front | 5.0 deg | 0 |
| `sedan` | 0.85 g | front | 4.3 deg | 0 |
| `hatchback-sports` | 0.85 g | front | 5.0 deg | 0 |
| `suv` | 0.76 g | front | 4.3 deg | 0 |
| `suv-luxury` | 0.76 g | front | 5.0 deg | 0 |
| `taxi` | 0.85 g | front | 4.5 deg | 0 |
| `police` | 0.82 g | front | 4.5 deg | 0 |
| `race` | 1.26 g | front | 2.9 deg | 0 |
| `race-future` | 1.25 g | front | 1.8 deg | 0 |
| `van` | 0.75 g | front | 4.0 deg | 0 |
| `pickup` | 0.84 g | front | 4.9 deg | 0 |
| `pickup-flat` | 0.84 g | front | 4.9 deg | 0 |
| `delivery` | 0.84 g | rear | 3.0 deg | 0 |
| `delivery-flat` | 0.76 g | front | 2.5 deg | 0 |
| `ambulance` | 0.75 g | front | 2.9 deg | 0 |
| `garbage-truck` | 0.71 g | rear | 4.2 deg | 1 |
| `firetruck` | 0.67 g | front | 2.9 deg | 1 |
| `semi` | 0.55 g | rear | 24.7 deg | 4, overturned |
| `semi-conventional` | 0.50 g | front | 86.9 deg | 4, overturned |
| `tractor-kenney` | 0.80 g | front | 2.5 deg | 0 |
<!-- /measure:cornering -->

The tall box `delivery` slides on commercial-tyre side grip (`mu_lat` 0.85) before it rolls.

### Step steer

<!-- measure:steer (generated by `measure_vehicles -- doc=steer`; edits inside are overwritten) -->
Measured 2026-10-20 (`measure_vehicles -- doc=steer`; per body `-- <variant> 60 step`): from each
speed settled on the PI pedal, the bridge steer stepped in one tick and held 3 s, the pedal held /
lifted on the step. Each cell: the steady yaw rate (last 0.5 s) over neutral steer `v * delta / L`
(under 1 understeers), the rise to 90 % of it, the overshoot past it, `(n up)` with wheels lifted;
`spun` past 20 deg of body slip, `rolled` past 45 deg off vertical. The body's yaw dynamic index k²
/ (a·b) beside its name. `K` is the understeer gradient off the smallest held step (`(delta - L r /
v)` per g of side force; linear only at low g, so read it with its g), beside the front axles' share
of the lateral load transfer (LLTD).

| Body | km/h | K at 10 % held, LLTD | 10 % lock, held / lifted | 20 % lock, held / lifted | 30 % lock, held / lifted |
| --- | --- | --- | --- | --- | --- |
| `sedan` (1.03) | 30 | 1.72 deg/g at 0.22 g, 70 % | 0.88, 0.27 s, +0 % / 0.93, 0.22 s, +9 % | 0.86, 0.27 s, +0 % / 0.93, 0.20 s, +10 % | 0.82, 0.25 s, +0 % / 0.93, 0.20 s, +12 % |
|  | 60 | 2.35 deg/g at 0.48 g, 70 % | 0.58, 0.23 s, +13 % / 0.67, 0.27 s, +10 % | 0.44, 0.17 s, +35 % / 0.59, 0.22 s, +15 % | 0.37, 0.15 s, +45 % / 0.52, 0.18 s, +19 % |
|  | 100 | 2.66 deg/g at 0.51 g, 70 % | 0.30, 0.17 s, +58 % / 0.38, 0.22 s, +31 % | 0.23, 0.13 s, +88 % / 0.29, 0.17 s, +54 % | 0.19, 0.13 s, +101 % / 0.23, 0.15 s, +74 % |
| `sedan-sports` (1.03) | 30 | 1.59 deg/g at 0.24 g, 49 % | 0.89, 0.25 s, +0 % / 0.95, 0.18 s, +13 % | 0.88, 0.25 s, +0 % / 0.96, 0.18 s, +15 % | 0.86, 0.25 s, +0 % / 0.96, 0.18 s, +18 % |
|  | 60 | 1.91 deg/g at 0.55 g, 49 % | 0.63, 0.23 s, +12 % / 0.75, 0.28 s, +10 % | 0.49, 0.18 s, +36 % / 0.76, 0.27 s, +9 % | 0.31, 0.13 s, +88 % / 0.61, 0.18 s, +25 % |
|  | 100 | 2.12 deg/g at 0.62 g, 49 % | 0.35, 0.18 s, +50 % / 0.55, 0.32 s, +11 % | 0.26, 0.15 s, +89 % / 0.24, 0.13 s, +130 % | 0.19, 0.12 s, +122 % / spun |
| `suv` (1.03) | 30 | 1.36 deg/g at 0.20 g, 47 % | 0.90, 0.28 s, +0 % / 0.95, 0.23 s, +9 % | 0.89, 0.27 s, +0 % / 0.95, 0.22 s, +11 % | 0.86, 0.27 s, +0 % / 0.96, 0.22 s, +14 % |
|  | 60 | 1.72 deg/g at 0.48 g, 47 % | 0.66, 0.27 s, +12 % / 0.79, 0.33 s, +3 % | 0.51, 0.20 s, +36 % / 0.74, 0.28 s, +11 % | 0.36, 0.15 s, +76 % / 0.62, 0.20 s, +25 % |
|  | 100 | 2.14 deg/g at 0.53 g, 47 % | 0.35, 0.20 s, +57 % / 0.55, 0.33 s, +13 % | 0.17, 0.12 s, +208 % / 0.15, 0.10 s, +276 % | 0.42, 0.25 s, +10 % / spun |
| `race` (1.00) | 30 | 0.54 deg/g at 0.22 g, 46 % | 0.96, 0.20 s, +0 % / 0.91, 0.08 s, +87 % | 0.97, 0.20 s, +0 % / 0.97, 0.08 s, +96 % | 0.96, 0.23 s, +0 % / 0.99, 0.10 s, +100 % |
|  | 60 | 0.61 deg/g at 0.65 g, 46 % | 0.86, 0.28 s, +1 % / 0.88, 0.20 s, +20 % | 0.79, 0.23 s, +5 % / 0.96, 0.20 s, +31 % | 0.56, 0.17 s, +35 % / 0.98, 0.18 s, +34 % |
|  | 100 | 0.52 deg/g at 1.09 g, 46 % | 0.72, 0.33 s, +0 % / 0.88, 0.50 s, +4 % | 0.49, 0.18 s, +44 % / 0.81, 0.30 s, +10 % | 0.31, 0.13 s, +92 % / 0.59, 0.20 s, +31 % |
| `van` (1.03) | 30 | 1.25 deg/g at 0.17 g, 58 % | 0.92, 0.30 s, +0 % / 0.96, 0.23 s, +8 % | 0.90, 0.28 s, +0 % / 0.96, 0.23 s, +9 % | 0.88, 0.28 s, +0 % / 0.95, 0.23 s, +10 % |
|  | 60 | 1.73 deg/g at 0.41 g, 58 % | 0.69, 0.30 s, +10 % / 0.78, 0.35 s, +5 % | 0.55, 0.22 s, +27 % / 0.71, 0.28 s, +9 % | 0.45, 0.18 s, +43 % / 0.64, 0.23 s, +16 % |
|  | 100 | 2.07 deg/g at 0.48 g, 58 % | 0.39, 0.23 s, +48 % / 0.52, 0.32 s, +23 % | 0.29, 0.17 s, +82 % / 0.22, 0.13 s, +164 % | 0.11, 0.10 s, +309 % / spun |
| `delivery` (0.91) | 30 | 1.13 deg/g at 0.12 g, 47 % | 0.93, 0.27 s, +1 % / 0.96, 0.23 s, +6 % | 0.92, 0.28 s, +1 % / 0.96, 0.25 s, +6 % | 0.91, 0.30 s, +1 % / 0.95, 0.28 s, +7 % |
|  | 60 | 1.38 deg/g at 0.26 g, 47 % | 0.74, 0.30 s, +6 % / 0.80, 0.33 s, +3 % | 0.65, 0.27 s, +14 % / 0.73, 0.32 s, +6 % | 0.51, 0.23 s, +35 % / 0.67, 0.30 s, +9 % |
|  | 100 | 1.33 deg/g at 0.22 g, 47 % | 0.52, 0.28 s, +22 % / 0.59, 0.38 s, +9 % | 0.44, 0.27 s, +36 % / 0.51, 0.33 s, +18 % | 0.34, 0.23 s, +68 % / 0.43, 0.32 s, +26 % |
| `garbage-truck` (1.64) | 30 | -0.01 deg/g at 0.10 g, 50 % | 1.00, 0.58 s, +0 % / 1.04, 0.50 s, +4 % | 0.99, 0.60 s, +0 % / 1.03, 0.52 s, +5 % | 0.98, 0.63 s, +0 % / 1.03, 0.55 s, +5 % |
|  | 50 | 0.10 deg/g at 0.22 g, 50 % | 0.98, 0.87 s, +1 % / 1.08, 0.98 s, +0 % | 0.91, 0.75 s, +4 % / 1.08, 0.98 s, +1 % | 0.82, 0.63 s, +10 % / 1.08, 0.98 s, +1 % |
|  | 70 | 0.20 deg/g at 0.30 g, 50 % | 0.94, 1.05 s, +1 % / 1.12, 1.52 s, +1 % | 0.78, 0.75 s, +12 % / 1.09, 1.55 s, +1 % | 0.84, 1.02 s, +0 % (1 up) / 1.02, 1.43 s, +1 % (1 up) |
<!-- /measure:steer -->

## Gradeability: `tools/measure_grade.tscn`

The other question unit tests cannot answer: how steep a hill a body pulls away on, and how
steep a hill a level asks for. Surfaces are the shipped `Surface` table, by name
(`asphalt`, `mud`, ...). `tc` holds the driven slip where the tyre makes its most force instead of
flooring the pedal, the curve's peak, and lifts off as the front axle goes light (most force
is not most climb: the surplus pitches a high-COM tractor over backwards). It feathers the fuel
through the pedal map's inverse (`PedalMap.pedal_for`): on the governed tractor the pedal is a speed
setting, and a loop on the pedal there climbs less than the floored row (70.4 / 26.4 %); `hold=<deg>
pedal=<0..1>` runs one diagnostic trial with a per-wheel force / slip / omega dump. `gear=<1-24>`
holds a start gear in the bridge's manual mode (the automatic box downshifts a standing D3 to D1 on
every body without a start gear), for the climbs and the roll-back. `climb grade=<%>` instead runs
one climb from rest in automatic D at a held pedal for `ASCENT_S` (`measure_grade.gd`) or to the ramp's top, printing each
shift with the gearbox's road load and a `falls back` gate (`docs/drivetrain.md` § The shift policy).

Ramp mode bisects the steepest angle the body climbs FROM REST — no run-up, which is the
question a driver asks halfway up a hill. Each trial is a fresh body on a fresh inclined
`StaticBody3D` over a synthetic grip patch answering the same duck-typed contract
`HeightmapTerrain` does. Beside each measurement it prints three static textbook ceilings —
traction (`tan a <= (mu * driven_share - crr) / (1 - mu * h / L)`, or `mu - crr` all-wheel),
first-gear torque at the converter's full-throttle rpm, and the standing backward tip
(`tan a <= b / h`, COM ahead of the rear axle over its height) — so a disagreement says which one
bit. All ignore `load_sensitivity`. A coupled rig gets the torque ceiling on its whole mass, the
traction ceiling `tan a <= mu * share - crr` (`share` read off the driven springs at the last
trial's settle), and no tip ceiling.

<!-- measure:grade (generated by `measure_grade -- doc=grade`; edits inside are overwritten) -->
Measured 2026-10-21 (`measure_grade -- doc=grade`), standing start, full throttle unless `tc`:

| Variant | asphalt (grip 1.00, crr 0.00) | mud (grip 0.45, crr 0.10) |
| --- | --- | --- |
| `sedan` (FWD, 1.15 t) | 46.5 % | 13.6 % |
| `suv` (AWD, centre 3.0:1, 1.50 t) | 57.5 % | 35.1 % |
| `suv-luxury` (AWD, centre 3.0:1, 1.60 t) | 81.0 % | 35.1 % |
| `race-future` (AWD, centre 3.0:1, rear LSD 2.5:1, 0.85 t) | 98.8 % | 14.8 % |
| `pickup` (RWD, 1.55 t) | 54.2 % | 15.5 % |
| `garbage-truck` (RWD, 8.00 t) | 39.3 % | 12.3 % |
| `tractor-kenney` (2WD, 7.00 t) | 67.7 % | 16.7 % |
| `tractor-kenney` (MFWD, centre rigid, 7.00 t) | 76.1 % | 31.7 % |
| `tractor-kenney` (MFWD, centre rigid, diff lock, 7.00 t) | 78.0 % | 31.7 % |
| `tractor-kenney` (MFWD, centre rigid, diff lock, tc, 7.00 t) | 78.0 % | 42.1 % |
| `tractor-cvt` (MFWD, centre rigid, diff lock, 7.00 t) | 78.0 % | 32.4 % |
| `semi` (RWD, 8.00 t + 24 t towed) | 23.7 % | 0.6 % |
<!-- /measure:grade -->

Real-world reference for the same question: a laden 32-40 t artic restarts on 15-20 % (EU
type-approval asks only for 12 %), a laden rigid truck on 20-25 %, a FWD car on 25-30 %, an
AWD car on 45 % and up, a 4WD farm tractor on 35-45 % firm / 15-25 % in a wet field. Road
design: motorway 6-8 %, mountain road 10-12 %, extreme public street 20-30 %. The semi's 23.7 %
sits a little above a real artic's (ASR holds its one drive axle, which carries ~90 % of the
plate share, at the grip peak), and the cars sit within ~10 points of theirs (`mu_long` 1.05, no
FWD-specific penalty). The heavy vans, outside the generated set (`measure_grade -- <variant>`): `delivery` 43.6 % on asphalt and 19.3 % in mud, `delivery-flat` 46.5 / 18.6 %,
`ambulance` 37.2 / 14.2 %. On asphalt that is the 470 N·m through the 15.56:1 first (the torque
ceiling, 21-26 deg); in mud the driven rears are traction-bound (`delivery` 10.9 against 12.4 deg).
The table's grip is the all-season reference's: a body's stock class reads its own factor (the
tractor's R-1W lug 1.25 in mud, the trucks' M+S drive 1.15; `TyreClass`).

Every standing start here goes through the body's hill hold (`docs/drivetrain.md` § Hill hold): the brakes stay on until
the drive carries the grade.
- The MFWD tractor never rolls back through its clutch ramp (`launch_engage_s`), and from its D1 launch climbs
  under its traction and tip ceilings on asphalt (the table's `tractor-kenney` rows); a real one: 35-45 %.

In mud the bodies split by driveline:
- A biasing or rigid centre climbs toward the all-wheel ceiling the tool prints (SUV 19.3 against
  20.4 deg; the tractor's rows in the table).
- One driven axle on an open diff climbs within 1-2 deg of its ceiling on a light body (`sedan` 7.7
  against 9.1, `pickup` 8.8 against 10.3, `garbage-truck` 7.4 against 8.2). The 2WD tractor
  floored gets about half its ceiling, because one rear peels past the grip peak (`docs/vehicles.md`
  § Open-diff peel).
- The tyre answers the surface: `doc=tyres` (§ Measuring a vehicle) has the pickup's Mud tyre
  stopping in 15.7 m in mud against the all-season's 17.9.

`level=` mode instead walks every road curve in a level (the `carlito_road` group, so an
untreed instance works) at 4 m steps and reports mean and worst grade, metres above the 10 /
15 / 25 % bands, and the mean painted grip and added crr under the ribbon — which is both "is
this drivable" and "did `paint_road_asphalt` go stale". Level 1's road reads mean 4.6 %, worst
17.5 %; level 2's reads mean 16.4 %, worst 86.9 % (41 deg) over
2033 m, with 512 m above 25 %: past the semi's 23.7 % for at least a quarter of its length and past
the SUV's 57.5 % at its worst, because of the curve, not the tuning.

## Parking: `measure_grade -- doc=park`

The mechanism: `docs/vehicles.md` § Holding at rest.

<!-- measure:park (generated by `measure_grade -- doc=park`; edits inside are overwritten) -->
Measured 2026-10-20 (`measure_grade -- doc=park`), asphalt: mm moved in 60 s held after a 1.5 s
settle, nose up the slope (`foot`, `hand`, `pawl`: P alone, N on a body with no pawl) or across it
(`cross`, foot brake), and on the handbrake at the regulation grade (UN R13-H 20 % to 3.5 t, R13 18
% above; the semi with its trailer):

| Variant | 10 % foot | 10 % hand | 10 % pawl | 10 % cross | 30 % foot | 30 % hand | 30 % pawl | 30 % cross | hand, regulation grade |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `sedan` | 0.1 | 0.0 | 0.0 | 0.1 | 0.1 | 0.0 | 0.1 | 0.3 | 0.0 (20 %) |
| `suv` | 0.1 | 0.0 | 0.1 | 0.2 | 0.1 | 0.1 | 0.1 | 0.7 | 0.1 (20 %) |
| `pickup` | 0.1 | 0.0 | 0.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.7 | 0.0 (20 %) |
| `garbage-truck` | 0.0 | 0.1 | slides | 0.3 | 0.2 | 0.0 | slides | 0.1 | 0.0 (18 %) |
| `tractor-kenney` | 0.1 | 0.1 | 0.1 | 0.0 | 0.1 | 0.1 | 0.1 | 0.2 | 0.0 (18 %) |
| `semi` | 0.4 | 0.5 | slides | 1.9 | 1.0 | 0.4 | slides | 9.0 | 0.7 (18 %) |
<!-- /measure:park -->

## Rough and soft ground: `tools/measure_rough.tscn`

What the flat strip and the ramp cannot show: whether drive torque reaches the wheels that can
use it once the ground stops being even. It drives the real `src/levels/dev/rough_ground/` level
(unregistered, F6-runnable), two parallel lanes, asphalt and mud, each carrying the same patches
in the same order: a flat control, random bumps of +-5 / 10 / 20 cm on a 3 m lattice, then
V-ditches 20 / 35 / 60 cm deep. Against the 19.3 deg a perfect all-wheel drive holds in mud on the
reference tyre on a uniform grade, the 35 cm inner wall is 13.1 deg and the 60 cm one 21.8 deg,
each 1 m long: shorter than any wheelbase, so the rear axle pushes while the front climbs. It is
not a fake-traction detector; `measure_grade` against its printed ceiling is. Every position is
in `tools/rough_ground_layout.gd`, which the level's generator (`tools/gen_rough_ground.gd`,
chain in `rough_ground_gen.json`) and this tool both read.

`baseline` runs `suv`, `tractor-kenney` in 2WD / MFWD / MFWD + diff lock, `sedan` and
`pickup`. `tyre=<id>` fits that class on every config's body (the stock where its fit does not take
it, said in the header); `doc=rough` refuses it, its tables being the stock tyres'.

Each trial is a standing start 10 m before a patch. A driver holds the crawl with the pedal and
the lane's centre line with the wheel, through the bridge. The crawl is a fuel command through the
pedal map's inverse (`PedalMap.pedal_for`), so its loop gain is the same on every map. Without
`tc` it reaches full fuel whenever the body falls short of the crawl, which is the drive a player
holding the key gets. With `tc` the driver also feathers to hold the WORST driven wheel at the
0.12 grip peak, which removes throttle sensitivity and leaves the differentials' own ceiling.

It reports crossed / stuck / off lane per patch, with:
- per wheel, mean and peak slip and time in the air;
- seconds of chassis contact (`b` in the summary; a grounded body is geometry, not traction);
- `use`: the driven wheels' force over their static `mu x grip x load`, averaged over the
  DEMANDING ticks: short of the crawl with the fuel command floored (or `tc` holding the pedal
  back). `-` means traction never limited that patch.

An open diff's peel reads as low `use` (~0.6 floored on bumps) with one wheel's slip far above
its partner's.

A cell is the time over the patch and `use`:
- `stuck+N` is stopped N m into the patch; `stuck-N` never reached it; `t/o-N` timed out N m
  short of it, still creeping;
- `b` is `BODY_FLAG_S` or more of chassis contact (`measure_rough.gd`).

<!-- measure:rough (generated by `measure_rough -- doc=rough`; edits inside are overwritten) -->
Measured 2026-10-20 (`measure_rough -- doc=rough`, with `--fixed-fps 60`), mud lane below. Asphalt
cells that did not cross: `sedan` ditch_60 (stuck+1.0b .99), `pickup` ditch_60 (stuck+0.9b .82),
`sedan tc` ditch_60 (stuck+1.0b .99), `pickup tc` ditch_60 (stuck+0.9b .82).

```
floored                   flat           bumps_5        bumps_10       bumps_20       ditch_20       ditch_35       ditch_60
suv                       15.0s          14.9s          15.0s          14.4s .67      3.7s .75       4.0s .80       5.0sb .78
tractor-kenney            14.7s          14.7s          14.7s          13.8s          3.5s           3.4s           3.7s
tractor-kenney mfwd       14.8s          14.7s          14.7s          13.8s          3.5s           3.4s           3.4s
tractor-kenney mfwd diff  14.8s          14.7s          14.7s          13.8s          3.5s           3.4s           3.4s
sedan                     14.2s          14.4s          14.5s .89      15.1s .91      3.4s           4.2s .93       stuck+1.0b .99
pickup                    14.7s          14.9s          14.9s .90      15.4s .91      3.8s .92       4.5s .93       stuck+0.9b .99
hatchback-sports          14.4s          14.3s          14.3s          13.9s          3.5s           3.7s           10.1sb .95
tc
suv                       15.0s          14.9s          15.0s          14.4s .67      3.7s .75       4.0s .80       4.9sb .77
tractor-kenney            14.7s          14.6s          14.7s          13.8s          3.5s           3.4s           3.9s .66
tractor-kenney mfwd       14.8s          14.7s          14.7s          13.8s          3.5s           3.4s           3.5s
tractor-kenney mfwd diff  14.8s          14.7s          14.7s          13.8s          3.5s           3.4s           3.5s
sedan                     14.2s          14.4s          14.5s .89      15.1s .91      3.4s           4.2s .93       stuck+1.0b .99
pickup                    14.7s          14.9s          14.9s .90      15.4s .91      3.8s .92       4.5s .93       stuck+0.9b .99
```
<!-- /measure:rough -->

What the matrix shows:
- **Every car crosses the bump fields floored**, open diffs included (`sedan`, `pickup`: `use`
  .90-.92), and the limited-slip `hatchback-sports` too. The times include the measuring crawl
  driver's cycle. It overshoots to ~2.5 m/s, lifts, and in D1 the locked crank's friction brakes
  the car to ~1.2 m/s before the pedal climbs back (`-- sedan lane=mud patch=flat verbose`).
- **The 60 cm ditch is geometry first.** It holds the sedan and pickup grounded (`b`) on both lanes,
  at the grip peak in mud (.99); the suv and hatchback scrape out (`b`), every tractor crosses.
- **Every tractor driveline crosses everything**, floored or under `tc`, and is rarely short of
  traction (`-`): the R-1W lug reads mud at 1.25 of the reference (`TyreClass`).
- `baseline` omits `hatchback-sports`; `doc=rough` adds its floored row.

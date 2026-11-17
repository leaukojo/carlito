# 2026-11-17: A9, why `race` / `race-future` leave the strip (diagnose)

Item A9, Opus, diagnose only: nothing in `src/` or `tools/` changed. Figures in:
`sessions/2026-11-16-race-strip-gather.md`.

## Cause

A static yaw divergence: the linear yaw mode's real eigenvalue crosses zero near 256 km/h (`race`)
and 248 km/h (`race-future`) and grows with speed. No seed is needed: float noise (1e-5 m/s across)
is enough, and the trace's smooth exponential growth with no oscillation is that mode's signature.
Two terms push the yaw stiffness `N_beta` negative, both growing with speed:

1. **The side force acts 0.60 m ahead of the COM.** `VehicleMath.air_force` puts `q * side_area *
   sin(beta)` at `aero_centre` (`WheelDrive._apply_resistance`, `wheel_drive.gd:966-970`), and the
   generator places `aero_centre.z` `SIDE_CP_FRAC` 0.25 of the wheelbase ahead of the axles'
   midpoint (`gen_kenney_vehicles.gd:945-951`; sourced in `docs/sources.md` § Crosswind for "most
   road vehicles" [80]). `race`: COM z 0.290, aero z -0.31 (forward is -z). At 78 m/s that is
   -5120 Nm/rad of yaw stiffness. Drag acts along the nose, so z moves only the side force.
2. **The tyre balance turns from understeer to oversteer with downforce.** `reference_load` is the
   even corner load (`spec.mass / 4 * g`, `wheel.gd:322`, `wheel_drive.gd:143`): 2206 N on every
   corner. `cornering_peak_load` 2.56 puts the stiffness peak at 5649 N for both axles. Downforce
   (60 % rear) and drag's pitch take the rear corners to 5400 N at 281 km/h: the rear stiffness is
   flat there (`cornering_load_shape` 1.474 of a 1.475 peak) while the front's still rises.
   `b Cr - a Cf` goes +3914 Nm/rad at 144 km/h, 0 near 259 km/h, -1946 at 281 km/h.
   `rear_lat_grip` 1.15 scales the rear's mu and stiffness but not the load its stiffness peaks at.

Either alone nearly holds; together they diverge 30-40 km/h below top speed.

## Evidence

Linear bicycle model from the spec and `wheel.gd`'s laws (scratch scripts, not committed; their
forms below). Cornering stiffness on the grip curve's rise: `C = mu_lat * axle_lat_grip * ref *
cornering_load_shape(L) / 0.12` per tyre (`combined_slip_force` with `lateral_peak_slip`: the
load-scaled mu cancels). Loads: static split + `downforce_front` 0.4 + drag's pitch (`h` 0.52 m,
fitted to the gather's start split). `a` 1.058, `b` 0.766 m for both bodies (`race-future`'s
wheels sit 6 cm further back with its COM). Yaw inertia from the gather (729 / 741 kg m^2).

Checked against the gather:
- Stiffness at t 44.50's logged loads: front 34.2k / 31.7k N/rad, rear 43.6k. The logged forces
  over it give slips front 0.0218, rear 0.0236: ratio 0.924 against the logged slips' 0.923
  (0.024 / 0.026; the probe's slip definition reads about 10 % above the patch's).
- Onset: the model's 256 km/h (71.2 m/s); the gather's `vx` leaves 0 near t 27.8, 71.6 m/s.
- Growth rate, `race`: model 0.63 /s at 76 m/s, 0.88 at 78; measured 0.84-0.89 at 76-77,
  1.04-1.17 at 77.8-78.6. The model reads about 20 % low (its loads are estimates: the logged front
  load at t 44.50 is 6593 N, the model's 6425), same shape.
- `race-future`: model 1.15 /s at 78, 1.38 at 80; measured 1.10-1.19 at 80-82 m/s.

Onset by variant (km/h; top speeds 283 `race`, 294 `race-future`):

| variant | `race` | `race-future` |
|---|---|---|
| shipped | 256 | 248 |
| side force at the COM (aero z = COM z) | 295 | 288 |
| side force 0.3 m behind the COM | 322 | 315 |
| rear stiffness peak load x 1.15 | 308 | 296 |
| `cornering_peak_load` 0 | none below 540 | none below 540 |
| reference = each axle's static share | 398 | 381 |
| `downforce_front` = static share 0.42 | 249 | 240 |

The proving run (spec edited, run, reverted at once; `git status` clean after):
`race_spec.tres` `aero_centre` z -0.31 -> 0.2900565, then
`node tools/godot_run.mjs -- --headless --path . res://tools/measure_vehicles.tscn -- race 60`:

> top (time cap) : 291.1 km/h (180.9 mph), gear 6 @ 6087 rpm <-- still gaining 1.78 km/h ...
> lateral : 0.0 m off the centre line at most, 20 m to the edge
> tracking : PASS drift 0.000 m peak / -0.000 m final over 200 m

Shipped: leaves at 283.2 km/h, 54.1 m across. The model put this variant's onset at 295 km/h.

## Brief (for `realism_gaps.md` phase 4's first bullet)

Ends in a proposal: either lever changes how the race bodies drive. Pick from the table; no
filter, yaw damping or steer correction (that is a cover over `N_beta < 0`).

- **(a) The race bodies' side-force centre.** `SIDE_CP_FRAC` is sourced for road vehicles; an
  open-wheeler's side area is wheels, sidepods and the rear wing's endplates. A per-variant
  override in the recipe (like `cl` / `downforce_front`) for `race` and `race-future`, from a
  source that gives an open-wheeler's side-force centre (or its yaw-moment slope `C_N_beta`), page
  opened. At the COM fixes `race` only (`race-future` 288 < 294 km/h): it needs the centre behind
  the COM. Cost: recipe + regen; moves only these two bodies' crosswind and step-steer rows.
- **(b) The rear tyre's stiffness peak load.** `rear_lat_grip` (a wider rear tyre) leaves the load
  at which its stiffness peaks at the front's. Scaling the rear's peak load (or its reference
  load) with the tyre is a `wheel.gd` model change on every body with `rear_lat_grip` != 1 (`suv`
  1.08, the tractors 1.077, the race bodies 1.15): unit 3a's file, `doc=cornering` and the skid pad
  move. Needs a source that the load at peak stiffness scales with a tyre's width.
- **Guard either way:** a pure-logic test over the catalog: each wheeled body's linear yaw mode at
  its top speed (the loads with downforce, `cornering_load_shape`, the side force at its arm) has no
  positive real eigenvalue. `BalanceModel` already carries `aero_arm` and the per-axle laws; it
  fails on `race` / `race-future` now and passes after the fix. Then
  `measure_vehicles -- race,race-future 60` prints no `left the strip`.
- **Stop and hand back** if the chosen fix's onset (from the guard's model) clears top speed but
  the run still leaves: the model would be missing a term (roll, the tyres' relaxation, the lateral
  one-tick cap), and that is a `diagnose` line.

Recommendation: (a), sourced, for both bodies. (b) is the deeper question (a real tyre's nominal
load is the tyre's, not the car's mean corner load) but crosses every body and is stage B's.

## Lever (a) landed (user's choice, same day)

Source opened: Casiraghi (Tatuus Racing), "Race Car Aerodynamics", KTH 2011, slide 16: "Unlike most
road cars, race cars have their CP behind the CG in order to have a good lateral stability at high
speeds where aerodynamic forces are significant." Direction only: the distance is an estimate.
- Recipe: `side_cp_frac` -0.25 on both race bodies (a quarter wheelbase behind the axles' midpoint,
  mirroring `SIDE_CP_FRAC`); regen moved only `aero_centre.z` (`race` -0.31 -> 0.60, `race-future`
  -0.25 -> 0.66: 0.31 m behind the COM).
- Guard: `test_vehicle_catalog.gd` `test_a_winged_body_holds_its_heading_to_its_top_end` (the
  brief's model, with drag's pitch). Failed before the regen on both bodies at 250 and 300 km/h;
  passes after.
- `measure_vehicles -- race,race-future 60` (`--fixed-fps 60`): `race` 291.1 km/h at the cap, still
  gaining, 0.0 m lateral; `race-future` 300.6 km/h settled, 0.0 m lateral. Was 283.2 / 294.5, left.
- `doc=top`, `doc=steer`, `doc=cornering` re-run: only the race rows moved (top 292 / 301 km/h
  settled; steer K at 100 km/h 0.52 -> 0.60 deg/g; cornering margin +0.2 %). Suite 2525 / 0
  failures. Commit eacd286.

## Not traced

- Why the divergence always goes the same way (positive `vx`, negative yaw rate, both bodies,
  both runs): a systematic float asymmetry (wheel tick order is the likely one). Irrelevant to the
  fix: any wind, kerb or steer seeds the mode.
- The aero side force reads the COM's velocity, not the aero centre's: no yaw damping from it.
  Its size (`e^2 q S / V`, about 40 Nm s/rad against the tyres' 1600) moves nothing here.

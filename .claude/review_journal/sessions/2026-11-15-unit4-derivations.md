# 2026-11-15: unit 4's derivations (Fable's item 2, diagnose only)

Started at 109a2aa. Read whole: `balance_model.gd`, `stability_control.gd`, `docs/handling.md`.
Read in part, as what they stand on: `wheel.gd` (`tick`, the tyre laws, roll and compliance steer,
the bar, the beam, the spin step), `wheel_drive.gd` (`_init`, `esc_step`, the steer functions, the
differentials, resistance and downforce), `vehicle_math.gd`, `ground_drive_spec.gd`'s fields,
`brake_sizing.gd`'s loads, `tests/test_balance_model.gd:800-902`. Nothing fixed. One temporary test,
run and deleted (`git status` clean after).

## Finding 1: a swinging front axle's roll gives the weight and the side force two levers

`BalanceModel._roll_state`, the swinging front inside its stop (`balance_model.gd:161-170`):

    pivot_m = m g side_g (L - a) / L * pivot_h
    phi = (moment - pivot_m) / (k_r - weight_h)        # moment = m g h lat_g, weight_h = m g h
    df = 2 * pivot_m / t_f
    free = phi - pivot_m / k_f <= stop

The front's contact forces reach the body with no moment about the pivot (`WheelDrive._step_swing`
turns the beam until `RayWheel.swing_moment` about `swing_pivot` is zero), so the body rolls about
the line from the rear's ground centre to the pivot. The centre of mass sits
`h' = h - pivot_h (L - a) / L` over that line. The side force's moment is taken on `h'`
(`moment - pivot_m = m a_y h'`), which is right. The rolled body's own weight is taken on the full
`h` (`- weight_h`): the same force point, the same axis, a different lever. Derived from the forces:
the front's load `N_f = 2 _normal(front)` enters the body at the pivot, which sits
`(h - pivot_h) phi` off the centre of mass, where a rear patch pair sits `h phi` off it:

    m a_y h - F_f pivot_h + (m g h - N_f pivot_h) phi = k_r phi

With `pivot_w = N_f pivot_h` (N·m per rad):

    phi = (moment - pivot_m) / (k_r - weight_h + pivot_w)

The beam is the same case on its own tyres: its load enters at the pivot, `pivot_h` over its
patches, so its tilt `psi` on the road obeys `k_f psi = F_f pivot_h + N_f pivot_h psi`:

    psi = pivot_m / (k_f - pivot_w),  df = 2 k_f psi / t_f,  free = phi - psi <= stop

Against its stop the front patches' mid-point sits `h phi - pivot_h stop` off the centre of mass
(the beam is `stop` short of the body's roll), so:

    phi = (moment + (k_f - pivot_w) stop) / (k_f + k_r - weight_h)      # :176, has k_f * stop
    rear lifted: phi = (moment - cap_r t_r / 2 + (k_f - pivot_w) stop) / (k_f - weight_h)   # :190
    front lifted on the stop: phi = (moment - cap_f t_f / 2 - pivot_w stop) / (k_r - weight_h)  # :184

The free and the stop forms meet at `phi - psi = stop` (put `pivot_m = (k_f - pivot_w)(phi - stop)`
in the free one). With `stop = 0` (`pivot_h = 0`, `pivot_w = 0`) every form is the code's as it is.

Evidence that the lever is `h'` and not a preference: the test file's own rigid limit,
`_triangle_g` (`tests/test_balance_model.gd:828-832`), divides by
`h - pivot_h (wheelbase - a) / wheelbase`, and the model passes it (on rigid tyres `phi` is 0 and
the weight's term vanishes). The elastic test beside it is written from the code's derivation
and passes with the error (`:845-846`): `rear * t_r / 2 == weight_h * (g + phi) - pivot_m`.

Measured on the model (temporary `tests/test_zz_swing_lever.gd`, `tractor-kenney_spec.tres`, speed
0; asserted `phi == m g lat_g h' / (k_r - m g h')`, FAILED):

    h 1.0185 pivot_h 0.6175 lever 0.7839 k_r 674459 k_f 403701 weight_h 69870 w_p 16097 tip_g 0.6354
    g 0.1: phi model 0.5096 deg, one lever 0.4964 deg (+2.66 %); front transfer model 2058 N, beam's own lever in 2144 N (-3.99 %)
    g 0.3: phi model 1.5288 deg, one lever 1.4891 deg (+2.66 %); front transfer model 6175 N, beam's own lever in 6431 N (-3.99 %)
    g 0.5: phi model 2.5480 deg, one lever 2.4819 deg (+2.66 %); front transfer model 10291 N, beam's own lever in 10718 N (-3.99 %)

The fixture, for the fix's first test (it fails now):

    var m := BalanceModel.axles(load("res://src/vehicles/kenney/tractor-kenney_spec.tres"))
    var lever := h - pivot_h * (wheelbase - front_arm) / wheelbase
    var phi_one := mass * G * g * lever / (_roll_stiffness(rear) - mass * G * lever)
    assert: _roll_state(m, g)["phi"] == phi_one within 1e-4 of it, g in 0.1, 0.3, 0.5

Size and reach. The tractors' predicted roll reads 2.7 % high and their front transfer 4 % low
inside the stop; the rear's first lift, which is their `tip_g`, 0.635 g where one lever gives about
0.652 (hand figure: the rear lifts at `phi = N_r t_r / (2 k_r)` either way). Not checked against the
sim: no pass prints a held turn's roll finer than 0.1 deg on a body with no roll steer, and the
corner pass's tip (0.72 g, `docs/vehicle_measurements.md` § Cornering) is a ramp's, not a steady
figure. Consumers: `measure_vehicles`' `pred` columns and `gen_kenney_vehicles`' report. No ESC body
swings (`esc_reference_k` is empty on both tractors), so nothing the player drives reads it: no
proposal. `balance_model.gd` is not a bake input.

The same lever once more, in the yaw arms: `_corner_wheels` (`:698-700`, `:719`) moves every patch
`h sin(phi)` inboard of the centre of mass. A swinging front's patches move
`(h - pivot_h) sin(phi) + pivot_h sin(psi)`, with `psi = min(roll.front, cap_f) t_f / (2 k_f)`:
3.0 cm where the model has 4.4 at 0.5 g on `tractor-kenney`. It reaches the yaw balance only through
the fore-aft forces across the track.

## Checked and sound

Each against the code named, by hand; figures where one was worked.

- `wheel_stiffness`: `combined_slip_force` on the rise gives `budget_lat / (lat_peak * peak_slip)`;
  with `lateral_peak_slip` and `lat_budget` put in, that is the function's two branches, the twin
  share and the `ref * 0.25` floor included. It takes the curve as one straight rise to its peak:
  true of every `grip_curve` under `src/vehicles/` (`(0, 0), (0.12, 1), (0.4, 0.9), (1, 0.8)` in
  each `.tres` the grep found, and the spec's default).
- `_roll_stiffness` `(k / 2 + bar) t^2` against `tick`'s spring and `VehicleMath.anti_roll_force`;
  the transfers, `pair_loads`, the lift caps and the lifted forms of `_roll_state` for independent
  corners; `m g h phi`: the patch sits `h sin(phi)` off the centre of mass (`patch_offset`, the hub
  hanging along the body's down). `sedan`: 5.07 deg/g by hand, the doc's "~5 deg/g" and "~9 %".
- `_axle_rolled`: `transfer / (spring + 2 bar)`, and lifted `cap / (spring + 2 bar)` off
  `anti_roll_hang` (`c_out - c_in = c_out k / (k + bar)`, the outer carrying `2 n`).
- `understeer_gradient`, `roll_steer_gradient`, `compliance_steer_gradient` (signs against
  `roll_steer_angle` and `compliance_steer_angle`), `compliance_loop_gain` (`sedan`: 0.021 by hand,
  the doc's ~0.02), `yaw_damping_gradient` (`I c r / L` on each axle), `pair_grip`,
  `axle_capacity_g`, `limit`, `lltd`.
- `axles`: the loads (`BrakeSizing.wheel_loads`), the downforce split (`_apply_downforce`,
  `downforce_point`), `h` and `pivot_h` (they need both axles to touch at one origin height
  unloaded: `tractor-kenney` 0.052 m front and rear), the yaw inertia, the taper
  (`steer_lock_deg`), the aero centre's height and arm (`apply_at` from the origin).
- `_corner_state` and `_corner_wheels`: the body-frame accelerations, the air (`air_force`'s signs
  and its `drag_area` gate), the roll moment with the air at its height, pitch, each wheel's speed at
  its arm, the slips on `tick`'s denominator, the budgets and `lat_peak`, the rolling drag, the
  force's turn into the body frame, the yaw moment's signs, the compliance latch's mean.
- The tyre's force along the wheel (`_drive_slip`, `_wheel_drive`, `drives`): a steady turn's. The
  spin does not change tick to tick there, so the start slip and the settled slip are one and the
  wheel carries `T / r` at HEAD and after the wheel fix alike. Nothing here reads a launch.
- `_split_drive`, `_axle_drive`, `_diff_split` against `Differential.bias_capacity`
  (`[1, b] / (1 + b)`), `_couple_downstream`'s order and the shaft frame (patch speeds compare as
  `n * omega` does); the TC hold against `tcs_ceiling_spin` and `tcs_take`.
- `k_curve`'s K and `StabilityControl.reference_yaw` are one identity (`delta = L r / v + K v r`).
- `StabilityControl`: `slip_step` (`beta' = a_y / v - r`, signs), `yaw_moment`, `intervention` (the
  side, the axle, `T = M R / (t / 2)`, the rates, the trim), `asked_lat_g`, `roll_application`,
  `corner_torques`, `roll_retardation`, the trailer's stages and its rate filter; `esc_step`'s
  inputs. `BOUND_MARGIN_G`'s "~200 km/h": 202.
- `docs/handling.md`: Ackermann's law and its cotangent mean; the front axle's unloading
  `g * front_share * L / h`; the gate's 37 % at 0.3 of critical; `rear_lat_grip` 1.077
  (`1 + 0.12 * log2(4125 / 2650)`); § Resistance balance's "feeds only" for `force_long` and
  `force_lat` (grep: `wheel.gd:490`, `:610`, nothing else in `src/`); § Stability control against
  the code.

## For unit 4's review (Opus): seen, not acted on

- Wrong comments, `balance_model.gd`: `_split_drive` (`:775`, "as `_corner_state` builds them")
  and `_axle_drive` (`:804`, "`_corner_state` builds each axle inner wheel first"): the wheels are
  built in `_corner_wheels` (`:701-725`). S.
- `corner`'s doc (`:387`) names `_axle_saturation`, a function of `tools/measure_vehicles.gd:2554`,
  for shares this file computes itself (`reach_sum / budget_sum`, `:670-671`). S.
- `wheel_stiffness` and `axles`' `peak_slip` rest on the grip curve being one straight rise to its
  peak, said nowhere. `test_every_grip_curve_peaks_at_the_abs_and_tcs_slip`
  (`tests/test_vehicle_catalog.gd:802`) is the place to check whether a knee before the peak is
  already refused; if not, a line in the comment.
- `yaw_damping_gradient`, `yaw_damp` and `yaw_inertia` in the model: exactly 0 on every shipped
  body (`angular_damping` 0). Their readers are the generator's report, one `measure_vehicles` print
  (`:3808`) and tests; `docs/handling.md`'s "the default 0.1 /s would add 0.10-0.20 deg/g" is what
  they are for. Kept or cut is the review's call.
- `_roll_state`'s `pivot_m` shares the tyres' side force by the static weight split; the air's arm
  (`aero_arm`) moves that share. Nothing at a tractor's speed.
- Downforce follows the body's up (`_apply_downforce`), so a rolled winged body gets
  `D sin(phi)` into the turn, which the model leaves out: under 1 % of the side force on `race`.
- `docs/handling.md` § Resistance balance: "summed tyre force matches `axle_torque / r` to within
  two" holds at a steady speed. In a launch under the slip floor the wheel session measured a
  quarter lost at HEAD, and after the wheel fix the wheel's own inertia takes its share. The line
  wants its state named; the wheel fix's doc list (`docs/vehicles.md` only) does not reach it.
- `slip_step` reads the body's lateral acceleration as the path's, exact only at small body slip.
  A real unit's limit too: a note for the comment, no fix.

## Deferred

Finding 1's fix: one Queue line, tagged for Opus.

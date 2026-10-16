# 14 — The semi's shift ring and its straight-line drift

Shared context: `00_README.md`. Two open findings left by 07b (the patch under the hub,
`docs/vehicles.md` § Pitch), both on the `semi` and both there before 07b. Neither is a 07b defect,
and each has its own point to reassess (§ When to reassess). Size: medium (1), small (2).

## 1. The front axle unloads past steady transfer at the first upshift

- **Measured** 2026-10-15 (`measure_vehicles -- all 45 trace`, `--fixed-fps 60`): the `front axle`
  gate FAILs at 17 points of overshoot against its 5 (`GATE_XFER_GAP`), at 2.78 s, ~0.6 s after
  D1>D2 (2.15 s): the front falls to 44 % of parked at +0.18 g, 18 points under steady transfer.
  The `front split` at that tick: heave +6.1, pitch +8.5, lean +1.3, residual +2.1 points; front
  damper -4.2 kN. `semi-conventional` reads 13 points; the shifts' own handover (`in shifts`) 30 /
  26.
- **Not 07b:** 16 points, same split, at `aa1cb8c` (before 07b).
- **What is known** (`docs/vehicles.md` § The shift policy, the `garbage-truck` bullet; § Pitch):
  through the coupling's slip the engine's whole torque reaches the wheels; locked again, part of it
  spins up the crank, so the drive steps down after the phase and the body rings in pitch.
  Road-band dampers (0.3 / 0.4 of critical) raised the trucks' figure to 13 points; the suspension
  levers did not close `sedan-sports`' similar overshoot either (§ Pitch, *Open*, now 6 points).
- **Hypothesis:** the drive's step at the handover lands near the body's pitch period, so it is a
  driveline question (the handover's torque profile, the coupling's re-lock), not a damping one.
- **Binds:** wheel-side torques stay inside the spin step; the shift policy owns full-pedal upshifts
  (§ The shift policy: a launch's dwell is the gearing's); feel changes follow `vehicle-feel`; the
  semis are hand-authored specs with header derivations.
- **Done when** the semi's (and `semi-conventional`'s) `front axle` gate passes, or the overshoot is
  shown to be a real tractor's at this footprint and the gate's allowance says so per class.

## 2. Centimetres of straight-line drift from a slow yaw mode

- **Measured** 2026-10-15 (`measure_vehicles -- all 45 track strict`): 0.049 m over 200 m, heading
  0.031 deg on both semis (the gate allows 1 m); every other body 0.000. An unperturbed run reads 0.000 only while the left and right
  wheels round identically; any change to the wheel code seeds float noise.
- **Probed:** a 1e-3 rad/s yaw kick at 55 km/h damps 30x in 0.25 s on old and new code alike, then
  a slow residual (~5e-5 rad/s, ~1-2 N of side force on 48 kN wheels) holds or decays: the kicked
  run drifts 0.026 m at `badab3b`, 0.046 m with the patch under the hub. `rear_lat_grip=1.05` reads the same
  (not oversteer); body-relative levers (`basis * anchor` rather than world `contact_point -
  origin`) cut it to 0.025 m without removing it.
- **Open:** what sets the slow mode, the lateral one-tick cap (`lateral_cap_mass`), the stick spring,
  or the tyre's linear rise at these tiny slips. A kicked tracking pass compares versions; an
  unperturbed 0.000 proves nothing.
- **Done when** the slow mode is named, and either removed or stated at its site as the honest model's
  (no hidden damping term: `src/vehicles/CLAUDE.md` § Physics).

## When to reassess

- **(1) next, before 08**: 07b's figures above are the final contact's. Take it together with
  § Pitch's `sedan-sports` open item. Before 08, whose balance is tuned on a body that no longer
  rings at the handover.
- **(2) after 08**: its cornering-stiffness load model and per-axle bars reshape the lateral
  dynamics this mode lives in. Sooner only if a body's drift nears the 1 m gate.

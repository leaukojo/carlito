# 14 — The semi's straight-line drift

Shared context: `00_README.md`. An open finding left by 07b (the patch under the hub,
`docs/vehicles.md` § Pitch), on the `semi` and there before 07b; not a 07b defect. Item 1 (the
shift ring) landed: `docs/vehicles.md` § Pitch, the `front axle` gate. Size: small.

## 2. Centimetres of straight-line drift from a slow yaw mode

- **Measured** 2026-10-15 (`measure_vehicles -- all 45 track strict`): 0.034 / 0.050 m over 200 m,
  heading 0.026 / 0.031 deg on `semi` / `semi-conventional` (0.049 m on both before item 1's torque
  ramp; the gate allows 1 m); every other body 0.000. An unperturbed run reads 0.000 only while the left and right
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

- **(2) when the semis switch the cornering-stiffness law on** (`semi_spec.tres`, the COMPROMISE
  note). The handling-balance work left their lateral model as it was (law off, one bar, single
  tyres; the law's off path is bit-identical), so the kicked pass was not re-run; unperturbed,
  `-- all 45 track strict` reads 0.037 / 0.039 m (2026-10-16; a sweep's semi reading moves with the
  bodies run before it). Sooner only if a drift nears the 1 m gate.

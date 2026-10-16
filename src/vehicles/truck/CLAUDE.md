# Truck & trailers — rules

Tour, signal tables, derivations: `docs/heavy_vehicles.md`. Shared towing and vehicle rules:
`src/vehicles/CLAUDE.md`.

- `hopper_load` reaches the chassis only through `mass`: never a laden term in `axle_load` or
  `engine_load`.
- Pull-away is decided by torque at `Drivetrain.launch_target_rpm`, never the peak: fix
  startability at the low end of the curve.
- The clamps are sized off `corner_mass` (`mass / wheel_count`) and the body's tensor
  (`RayWheel.size_cap_masses`): fix a rig in the spec numbers, never the clamps.
- `conventional_spec.tres` shares `semi_spec.tres`'s drivetrain/brake/suspension/tyre block:
  retune both.
- `Kingpin` Y is frozen (every trailer is authored against it; only the semi's is tested).
- Gooseneck: nothing may hang below the coupling plane over the tractor.
- The tipper valve is `1.0 - input.hitch_request`, not `scv_flow` (an `isobus` signal).

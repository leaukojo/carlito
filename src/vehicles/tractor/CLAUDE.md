# Tractor & implements — rules

Tour: `docs/tractor.md`.

- Draft is ONE force at the hitch and the PTO ONE torque on the crank (`accessory_torque`), both
  from `_tick_extras`; `engine_load`, rpm sag and `wheel_slip` are their consequences, never add a
  draft or PTO term to them (rule 3).
- The draft force sits below the COM on purpose; do not move it to chase pitch.
- `engine_load` is not monotone in draft (delivered over peak torque): verify above peak-torque rpm.
- Suspension IS the tyres: stiff and short-travel is the picture, not a softening target.
- Traction is ballast (`mass`, `front_weight`), never the torque curve or `final_drive`.

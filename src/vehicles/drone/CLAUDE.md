# Drone — rules

Tour, split table, sub-objects: `docs/flight.md` § Drone subsystems. Derivations sit at their
site (`drone.gd` @exports, `drone_modes.gd`, `drone_bus.gd`).

- Tuning knobs stay `@export`s on `drone.tscn`, passed into the sub-objects; a copy on a
  sub-object is a second home.
- Never inflate `prop_torque_ratio` for yaw snap (rule 3).
- `DroneModes.resolve_mode` is the sole mode decider; nothing re-derives one.
- Never fuse the three heights (`altitude`, `agl`, `baro_alt`): the barometer exists to disagree.

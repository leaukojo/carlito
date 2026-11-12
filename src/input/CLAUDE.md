# Input — rules

Input arbitration lives here (standing rule 5). Protocol tour: `docs/systems.md`.

- Keyboard and analog (bridge, gamepad) both drive; vehicles stay realistic for analog. An
  on/off key's feel is shaped here (`key_shaper.gd`), never by detuning a spec; the gamepad and
  the bridge are never shaped. A measure tool that drives through `Input` measures the shaper:
  drive the bridge stash instead.
- Toggle owners (`_lights`, `_hitch_up`, `_pto`, `_scv`, `_body_cmd`, …) live in InputRouter so
  keyboard and touch share one owner; sources only report per-frame edges. Airframe cycles reset
  in `reset_vehicle_cycles()`. Local latches only: what a bridge sends is sloppyCAN's to say.

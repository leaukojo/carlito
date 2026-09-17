# Input — gotchas & hard-won rules

ALL input arbitration lives here (standing rule 5). Protocol tour: `docs/systems.md`.

- **`VehicleInput` is a `class_name` in `vehicle_input.gd`, not an inner class of the autoload** —
  an inner class makes every vehicle's static types depend on the autoload's registered *name*.
  Its fields are **flat except `lamps`**: the router deliberately knows no vehicle family, so every
  group is allocated for every machine. `input.lamps` earns its nesting on ONE RULE (the
  verbatim-mirrored bits, root `CLAUDE.md`), not on one family. Its read sites are `BaseVehicle` →
  LampSet, `TowHost` (the trailer's LampSet), `Dashboard._update_telltales` and the challenge
  frame's lamp checks. `lights` is a level the router cycles, so it stays flat.
- **`get_vehicle_input()` returns the router's own struct, read-only by convention** — there is no
  defensive `copy()`, because a hand-written field mirror is a field that goes missing silently.
  `arbitrate_*` build a fresh struct each tick, so a stashed reference reads stale, never live; a
  caller that needs to keep or change one copies it itself.
- **The raw-intent wire is `Dictionary[StringName, Variant]`** across all four producers
  (`LocalSource`, `TouchControls`, `BridgeSource`, `measure_drone`'s `StickSource`) and
  `merge_local`. **StringName keys catch no typo at parse time** — the guard is two tests:
  `test_every_touch_poll_key_is_merged` (registry `poll_key` ⊆ merge) and
  `test_local_source_and_merge_local_carry_the_same_keys` (set equality), plus
  `test_every_widget_key_is_merged` for the hand-built touch widgets, which write
  `TouchControls.WIDGET_KEYS` directly with no `poll_key` row. `merge_local` builds its
  dict explicitly, so a key on one side only silently drops the keyboard's edge while a touch
  source is registered. `arbitrate_local` / `arbitrate_bridge` stay plain `Dictionary` on purpose:
  they are the wire's consumers and `test_input_arbitration.gd` is their spec. An **untyped dict
  literal is rejected at the call**, not converted — a test passing one inline needs `_intent({...})`
  or a typed declaration.
- Toggle owners (`_lights`, `_hitch_up`, `_pto`, `_scv`, `_body_cmd`, …) live in InputRouter so
  keyboard and touch share one owner; sources only report per-frame edges. Cycles that belong to
  the airframe (`_node_fail`, the drone mode key) are cleared by `register_vehicle` — the keys are
  bound globally, so a press in a car must not follow you into a drone.
- **The challenge bridge-only lock is `set_bridge_only`**: local and touch are never polled, and
  with no live bridge the input is `locked_idle()`. Its keyboard override (`--challenge-keys` /
  `CARLITO_CHALLENGE_KEYS`) is honoured in debug builds only.
- **A live bridge without `accel`/`brake`/`steer` does not drive**: `bridge_drives()` is false,
  `blend_local_driving` takes the driving group from local and the rest from the bridge (never
  under `set_bridge_only`). Ask `bridge_drives()`, not `Bridge.is_active()`, "who drives".
- **The gearbox mode is `set_manual_gearbox`**, set by the shell (selector in free play,
  `ChallengeDef.transmission` in an attempt). It is bridge-only: automatic reads the gear byte as
  PRND, manual takes it exactly (0 = N). Local input always drives automatic.
- **Cycled-control lengths are declared once in `subsystem_counts.gd`** (leaf, no dependencies,
  `preload`ed by the router and by each vehicle class that cycles one) — the router must not depend
  on a vehicle class, so it cannot read `RefuseBody.Cmd` / `DroneBus.NODES` / `DroneModes` /
  `BoatAutopilot`. Where the length is intrinsic to a structure (an enum, the roster array) that
  structure stays the thing you edit and a test pins it against the constant; grow one without the
  other and the local key silently stops reaching the new position while the bridge can still
  command it.
- **Presence-ruled in-signals.** `rudder` overrides `steer` when present (no VehicleInput field).
  `heading_cmd` DOES take a field: it overrides nothing, and every value in its [0,360] is a legal
  bearing, so absent cannot be a sentinel on the wire — `VehicleInput.HEADING_CMD_NONE` is internal
  and `bridge_source` writes the key only when sent. `guidance_curvature` follows the same rule with
  its own field (`GUIDANCE_CURVATURE_NONE`): it overrides `steer`, and `WheelDrive` turns it into a
  wheel angle off the wheelbase, untapered. A commanded dead-straight 0 is a real command, not an
  absence; no vehicle code knows it was steered externally.

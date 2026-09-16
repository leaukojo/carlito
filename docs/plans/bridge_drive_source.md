# Plan — A live bridge that carries no driving controls

sloppyCAN and Carlito can be connected and exchanging data while nothing on the uplink can
drive the vehicle, and the player sees a frozen vehicle with the keyboard locked out. Make every
such case either drivable or explained: sloppyCAN omits the controls it has no source for (absence
is already the contract's honest "no source"), and the game, seeing a live bridge with no driving
controls, lets the local driver drive and says why, while the bridge keeps owning everything it
actually sends.

Written 2026-09-14. Status: **Phase 1 implemented** (2026-09-14, sloppycan working tree,
uncommitted; demo-verified in a browser), awaiting the user's play check. **Phase 2 implemented**
(2026-09-14, carlito working tree, uncommitted), awaiting the user's play check. Drone decision:
`arm`, `climb` and `elevator` joined the driving group, so fallback flies the drone (and pitches
the plane) from the keyboard; the group also gained `gear_request`/`gear_auto` and `horn`.
**Phase 3 implemented** (2026-09-14, sloppycan working tree, uncommitted), awaiting the user's check.
**Phase 4 implemented** (2026-09-14, sloppycan working tree, uncommitted): train.js/plane.js
controls-only panels, pantograph starts raised. **Phase 5 implemented** (2026-09-16, sloppycan
working tree + `docs/systems.md`, uncommitted; self-tests pass): J1939 driver demand in
j1939-flavor.js, N2K rudder order in nmea2000.js. It also fixed a Phase 3 bug (`demoBaseTrafficLabel`
recursed forever under any non-RAMN traffic). After the play check: distil and delete this file.

Delete this file when the last phase ships, after distilling its conclusions into
`docs/systems.md` (§ Input pipeline, § Bridge), the root `CLAUDE.md` § Input, lamps, bridge, and
sloppyCAN's `CLAUDE.md`.

## What is actually wrong: no RAMN frames, not the wrong vehicle

The mismatch is **not** protocol vs vehicle family. Every driving control on the uplink
(`accel`, `brake`, `steer`, `gear`, `key`, `handbrake`, `lights`, the RAMN lamp bits) comes from
`ramn.js`'s `ramnState`, and only **RAMN frames** (11-bit `0x024`/`0x039`/`0x062`/`0x077`/
`0x1B8`/`0x1D3`/...) update it. `carlito.js` pumps `carlitoInput` at ~33 Hz whenever its window is
open, whatever the bus carries, so `Bridge.is_active()` is true and `InputRouter` takes
`arbitrate_bridge` alone. The only other driving source is `drone.js`'s uplink override, live
while the Drone Control window is open.

So **J1939 + truck fails exactly the way J1939 + car does**, and a "select the vehicle that
matches the traffic" warning would send the player to a truck that still does not move.
sloppyCAN already does that: `vehicle-panel.js`'s `PROTO_PANEL` offers the truck when the J1939
mode is selected, and the reload lands in the dead state.

## The scenarios

| # | Situation | What happens | Who |
|---|---|---|---|
| S1 | Demo, base traffic not RAMN (J1939, NMEA 2000, ISO 11783, CHAdeMO, CANopen, DroneCAN) | `demoSetBaseTraffic` stops the RAMN timers but does not clear `ramnState`: the uplink repeats the last decoded values forever (a blank state with key Off if the user accepted "clear the frame buffer"). The RAMN Control Panel still edits `ramnCtrl`, which nothing encodes any more. | every family except a drone with Drone Control open |
| S2 | RAMN Control "Disable traffic", outside a challenge | `ramnClear`: key Off, zero pedals. Silent, because the ignition notice needs `accel > 0`. | same |
| S3 | A real adapter on a bus with no RAMN board (a J1939 truck bus, a CANopen rig, a quiet bus), `carlito-bridge.html` included | `ramnState` never leaves blank. Same as S2. | same |
| S4 | Drone with the Drone Control window closed | the overrides stand aside and the RAMN state applies, so S1-S3 do too. Key Off is the drone's master switch, so it never arms. | drone |
| S5 | Train, any traffic | sloppyCAN sources no `pantograph`, absent reads lowered, traction is cut (`train.gd:95`). The train never moves over the bridge. | train |
| S6 | Plane, any traffic | `elevator`/`flaps` are unsourced (0). It rolls and lifts off on airspeed but cannot pitch: degraded, not stuck. | plane |
| S7 | Manual gearbox selected, gear byte 0 | a real N, by design. Listed so the new notice does not claim it. | wheeled |
| S8 | A challenge attempt | RAMN traffic is off on purpose and the player hand-sends frames; no driving controls until they do is the expected state. | all |

## Decisions already made

- **Absence is the signal.** No new envelope field and no contract change: sloppyCAN omitting a
  control it has no source for is the rule `carlito.js`'s `IN_SOURCES` header already states. The
  game tests *presence* of the driving controls, never "is the bridge fresh".
- **"Seen since the last clear", not a freshness timeout.** A hand-sent `0x039` must keep latching
  the way it does today, or every challenge that sends one frame breaks. Clearing already means
  "nothing on the bus" (`ramnSetTraffic(false)`); leaving RAMN base traffic becomes a clear too.
- **Fallback, not refusal, in free play.** A live bridge with no driving controls hands the
  driving group to local input and keeps every other field bridge-owned. That makes every family
  drivable under every traffic, and the non-RAMN traffics keep their point: the downlink still
  packs the vehicle's telemetry as J1939 / N2K / DroneCAN frames, and bus commands they do carry
  (the ISO 11783 hitch/PTO command, the CiA 422 `body_cmd` RPDO, 127237's nav mode) still command.
- **Never in a challenge.** Under `set_bridge_only` there is no fallback (S8).
- **Either side can ship first.** Phase 1 changes nothing the game can see (every omitted value
  equals the game's own default: accel/brake/steer 0, key 1, lights 1, gear 0, bits off), and
  Phase 2 against an old sloppyCAN never triggers. Both are needed for the effect, but there is no
  paired-promote hazard.

## Phase 1 — sloppyCAN: RAMN controls are omitted until decoded

*Repo: `sloppycan`. Effort **low-medium**, Sonnet 5, **accept-edits**.*

- `ramn.js`: record per field whether its frame has been decoded since the last `ramnClear`, and
  expose it (beside `ramnGetState`). The dashboard's render keeps reading the blank numbers.
- `sloppycan.js` `demoSetBaseTraffic`: leaving `'ramn'` calls `ramnClear` (the "Disable traffic"
  semantics). The optional "clear the frame buffer" confirm stays about the frame buffer only.
- `carlito.js` `IN_SOURCES`: every RAMN-backed entry returns `undefined` while its field is
  unseen, so it is omitted. `beacon`/`strobe` are this file's own clocks and are untouched. They
  keep the bridge fresh, which is why the game must test presence and not freshness.
- Update the `IN_SOURCES` header and the RAMN-state gotcha in sloppyCAN's `CLAUDE.md` (one line).
- Verify: `node --check` on the three files; demo with RAMN traffic drives exactly as before; switch
  to J1939 and the Carlito I/O panel shows the driving fields gone; a challenge with one hand-sent
  `0x039` still drives.

## Phase 2 — Carlito: a live bridge with no driving controls falls back to the local driver

*Repo: `carlito`. Effort **medium**, Opus 5, **plan-mode-first** (rule 5 territory).*

- `bridge_source.gd`: add `&"drive_sourced"`, true when the values carry `accel`, `brake` or
  `steer` (the drone override claims all three; one hand-sent RAMN pedal frame is enough).
- `InputRouter._physics_process`: bridge active, not `drive_sourced`, not `_bridge_only` → run the
  local path (both sources, the router's toggles advancing) and a pure static blend takes the
  **driving group** from `arbitrate_local` and everything else from `arbitrate_bridge`. Driving group:
  throttle, brake, steer, handbrake, key, `brake_lamp` (the foot brake that is driving; the bit is
  absent from the bridge, so nothing verbatim is being overridden) and `lights` (router-cycled, and
  RAMN is its only bridge source; otherwise night driving is impossible in fallback). Local input
  drives automatic, as it always does.
- One predicate, `InputRouter.bridge_drives()`, replaces `Bridge.is_active()` where the question is
  "who drives": `touch_controls.gd`'s driving layer and `pause_menu.gd`'s `ActionRegistry.context`.
  The lights row needs to read local under fallback; every other `bridge_owned` row stays bridge.
- Notice, edge-triggered and cleared by text match on exit (the ignition-notice pattern), plain
  text (rule 10), e.g. `NO DRIVING CONTROLS FROM SLOPPYCAN - KEYBOARD DRIVES`. None in a challenge.
- Drone (S4): fallback gives the keyboard tilt/yaw/key, but `arm`/`climb` stay bridge-owned
  (DroneCAN always sources them), so it still cannot fly. Decide at phase start whether `arm` and
  the vertical axis join the group for the drone, or whether the notice names Drone Control instead.
- Tests: the blend and the bridge-only refusal in `test_input_arbitration.gd`; `drive_sourced` in
  the bridge-source tests. Docs: `docs/systems.md` § Input pipeline; one line in `CLAUDE.md`.
- Verify: suite + headless smoke, then the user drives: sloppyCAN demo, J1939 traffic, truck;
  CANopen traffic, garbage truck (body commands still from the bus); RAMN traffic unchanged; a
  challenge unchanged.

## Phase 3 — sloppyCAN: say it where the player is looking

*Repo: `sloppycan`. Effort **low**, Sonnet 5, **accept-edits**.*

- RAMN Control Panel: greyed with one line ("RAMN traffic is off - the base traffic is J1939")
  whenever the demo's base traffic is not RAMN, reusing `syncTrafficUI`'s disabled styling. Its
  sliders are inert in S1 today and look live.
- `PROTO_PANEL` confirm text: under this traffic the machine is driven from the game's keyboard;
  the RAMN controls need RAMN traffic.
- Carlito window bar: a small "no driving controls on the uplink" state when the built uplink lacks
  all three of `accel`/`brake`/`steer`.

## Phase 4 — source the train's and the plane's own controls (S5, S6)

*Repo: `sloppycan`. Effort **medium**, Sonnet 5, **plan-mode-first** (panel design).*

These fail under every traffic and the fallback does not reach them: `pantograph`/`doors` and
`elevator`/`flaps` are bridge-owned commands whose rest state is the contract's (pantograph down),
and changing that default would break the absent-means-rest rule. The fix is a source: module
entries in `carlitoUplinkSources` behind a control surface: a `'dash'` panel for the train (like
`truck.js`), and for the plane either an elevator axis claimed like `drone.js`'s sticks or an
addition to the RAMN pair. Until then S5 is the one "cannot move" case left, so if Phase 4 slips,
add a train-only notice in Carlito (bridge live, no `pantograph` key).

## Phase 5 (optional) — drive from the protocol itself

*Repos: both. Effort **high**, Opus 5, **plan-mode-first**. Decide after Phase 2's play-test: if
keyboard fallback is enough, drop this phase.*

The J1939 / ISO 11783 traffic drives a truck or tractor from its own driver-demand parameter
groups: the J1939 demo encodes the RAMN Control Panel into them, and an uplink decoder (the
`carlitoUplinkDecoders` pattern) feeds them into the driving controls, so the user's own J1939
tooling on a real bus drives the truck too. NMEA 2000's commanded rudder is the boat's
equivalent. **No PGN/SPN is chosen here**: sloppyCAN's primary-source rule applies (J1939-71,
the isobus.net dictionary; `j1939-71.pdf` sits beside the repos). The accelerator pedal,
brake pedal and steering-wheel-angle parameters are the candidates to look up. This qualifies
under the challenge plan's "general features sloppyCAN would want anyway". CHAdeMO, CANopen and
DroneCAN carry no road driver demand, so fallback remains their answer.

## Out of scope

- The contract-version mismatch, still a console warning on both sides. It could reuse Phase 2's
  notice later.
- A family/traffic compatibility table. Nothing in the diagnosis depends on the family, so there
  is nothing for such a table to say.

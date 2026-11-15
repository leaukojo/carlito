# Plan — CAN solver scripts for the car challenges

Python scripts that solve each car challenge over CAN, so a challenge can be tested locally
end to end: a shared helper (sloppyCAN relay or python-can hardware), challenge start/stop info
lines on the scripting relay, and one short solver per car challenge.

Written 2026-11-15. Status: **in progress.**
Serves: the 12 car `ChallengeDef`s (`ChallengeRegistry.DEFS`), as a repeatable "can this be
solved over CAN" check. The contract is unchanged: the new state rides the `carlitoOutput`
envelope, as `challenge` already does.
State: done: phase 1 game half. Next: phase 1 sloppyCAN half. Open findings: none.

## Decisions (user, 2026-11-15)

- **D1** Car challenges only (the 12 car defs). Truck/tractor wait until they are tested.
- **D2** One solver per challenge, in tools/challenge_solvers. You pick the challenge in the
  game; the script waits for its start line, then drives.
- **D3** On real hardware the RAMN ECUs are silenced first with the UDS frame `04 31 01 02 00`
  on 0x7E1, 0x7E2 and 0x7E3. Driving then uses the RAMN ids, the ones the car challenges teach.
- **D4** Solvers are short and plain: good enough to pass, not the most accurate solution.

## Why the game must change too (pushback)

sloppyCAN alone cannot give the info lines. Today the game sends only `challenge: true/false`
(`src/bridge/bridge.gd:153`). That flag stays true through the result panel and RETRY. It has no
challenge id, and no pass, fail or timeout. So the game has to send the attempt's state. It is a
small change and needs no contract bump: older sloppyCAN pages read `!!d.challenge`, and an
object is truthy, so they keep working.

## Phase 1: challenge state reaches scripts (game + sloppyCAN). Effort medium, accept-edits

**Game (`carlito2`)**
- `src/bridge/bridge.gd`: `_challenge: bool` becomes `_runner: ChallengeRunner` (null = none).
  `set_challenge(runner)` stores it. Add a pure
  `static func challenge_envelope(id, status, elapsed, message) -> Variant`. It returns `false`,
  or `{id, state: "running"|"passed"|"failed", t, msg}`, with `msg` only on a fail. `_publish`
  passes `JSON.stringify(...)` of that value as the second argument. When `runner.attempt` is
  null (the course would not start), the state is "failed" with the runner's error.
- `src/shell/boot.gd`: `_begin_challenge` calls `Bridge.set_challenge(_runner)` after the runner
  is created (now at line 241, before it exists). `_end_challenge` calls `set_challenge(null)`.
- `src/bridge/web/head_include.html`: `challenge: challenge || false` (pass the object through),
  and update the doc comment. Re-paste it into `export_presets.cfg` (guard:
  `node tools/check_head_include.mjs`).
- Test: `challenge_envelope` cases (off, running, passed, failed with msg). Added next to
  `contract_mismatch`'s test in `tests/test_contract.gd`.
- `docs/systems.md:151`: the `challenge` line becomes "`false` or `{id, state, t, msg}`".

**sloppyCAN (`../sloppycan`)**
- `../sloppycan/js/carlito.js`, next to `setChallenge` (~1000-1013):
  - A pure `challengeInfoLines(prev, cur)` returns the lines for one envelope step.
  - `start` when cur is running and prev was not running, the id changed, or `t` dropped (RETRY,
    respawn or a RESET all restart the clock).
  - `pass` or `fail` on the running → finished edge.
  - `exit` when the object goes away. That covers a `false` flag, the game gone and stale
    telemetry (line 1095).
  - The lines are sent through `window.scriptLinkInfo(line)`.
  - Plain `true` from an old game sends no lines.
- Line format: printable ASCII, at most 128 characters (the relay's `MAX_LINE_LEN`), with the
  reason sanitised and truncated:
  ```
  #challenge start car_box_stop
  #challenge pass car_box_stop 14.27
  #challenge fail car_box_stop 9.80 Ran past the box
  #challenge exit car_box_stop
  ```
- `../sloppycan/js/script-link.js`:
  - Add `window.scriptLinkInfo(line)`. It goes into the same outbound batch, and only while
    connected.
  - Inbound lines starting with `#` are ignored silently (not counted as `badLines`).
  - The header documents `#` info lines.
- `window.carlitoChallengeInfoSelfTest` covers the edge cases (it runs in the smoke test like the
  other self-tests).
- Docs: the relay docstring's protocol section (`#` lines are info, never frames), and
  `../sloppycan/.claude/modules.md` § Script link (the carlito.js → script-link.js flow).
  `../sloppycan/scripting/sloppybus.py` already drops non-frame lines, so it is unchanged.

**Commits:** one on `dev` in each repo. No push. The two halves are independent: either one
deploys alone without breaking anything.

## Phase 2: helper + first three solvers. Effort medium, accept-edits

tools/challenge_solvers/carlito_can.py: one module, standard library, with python-can imported
only for hardware.

- **Connect:** `car = connect()` reads the command line.
  - The default is the relay at `127.0.0.1:29541`; `--relay host:port` overrides it.
  - `--can INTERFACE CHANNEL [--bitrate N]` uses python-can. Example: `--can pcan PCAN_USBBUS1`,
    or `--can slcan COM5`.
  - On connect it sends the D3 silence frames (harmless in Demo).
- **Threads:**
  - A reader decodes frames and `#challenge` lines.
  - A sender repeats the RAMN command frames every 20 ms (relay) or 10 ms (hardware). The RAMN
    values latch, and sloppyCAN clears them at a challenge start, so they are re-sent.
- **Commands (attributes):** `key`, `gear` (`N`/`D`/`R`/`P`, 1-6 in manual), `accel`, `brake`,
  `steer` (-100 left .. 100 right), `handbrake`, `lights` (`OFF`/`LOW`/`HIGH`), `turn_left`,
  `turn_right`. They map to RAMN ids:
  - 0x039 accel, 0x024 brake, 0x062 steer, 0x077 gear, 0x1B8 key, 0x1D3 handbrake.
  - 0x1BB holds the lamp bits: low 0x10, high 0x20, left 0x40, right 0x80.
  - Encodings come from `../sloppycan/js/ramn.js:511-555`.
- **Telemetry (attributes):**
  - `kmh`, `speed`, `rpm`, `gear_now` (0x520/0x521), `acc_lat` (0x522), `heading` (0x524),
    `odo` (0x526), `status` (0x527).
  - `x`, `z` are world metres from GPS lat/lon (0x525). This is the exact inverse of
    `VehicleTelemetry.gps_lat/gps_lon` (Paris origin, 111320 m/deg), so it has cm resolution,
    unlike `posX`/`posZ`, which are whole metres.
- **Challenge:**
  - `car.wait_start("car_box_stop")` blocks on the start line. On hardware, where there are no
    info lines, it asks for Enter instead.
  - `car.running` turns false on pass/fail/exit, and the result is printed.
  - `car.finish()` waits for the end, then releases the controls (brake on, accel 0).
  - Ctrl+C always exits cleanly.
- **Driving helpers** (a few lines each):
  - `steer_to(x, z)`: the bearing error times a gain, as steer %.
  - `follow(path)`: aim at the path point a lookahead ahead; returns True at the end.
  - `cruise(kmh)`: P control onto accel/brake.
  - `stop_in(metres)`: brake to the speed `sqrt(2·a·d)`.
- `README.md` in the folder covers setup, both backends and the run line
  (`python car_start_up.py`).
- A `.gitignore` entry for `__pycache__/`.

First solvers, to prove the pipeline before the harder ones:
- car_start_up.py: key on, D, accel 40 %, steer to the Finish line.
- car_hazards.py: stand still and blink left and right together at 1.5 Hz until the challenge
  passes.
- car_speed_trap.py: `cruise(60)`, steering on the start heading.

The user runs these three. Phase 3 starts only once they pass.

## Phase 3: the other nine car solvers. Effort high, accept-edits

Each one is a docstring of 1-3 sentences saying how it solves the challenge, then the code.
Coordinates come from the course scenes (spawn jitter is 0 in every def).

| Script | Approach |
|---|---|
| car_easy_turns | `follow(ROAD)`. `ROAD` is the four touching r=35 arcs around the `Cut0..3` centres, alternating right/left, 25 km/h. |
| car_corner_budget | Imports `ROAD`, at 38 km/h (35 m bends at 4 m/s² allow 42). The Cut zones sit 9.5 m inside the lane. |
| car_lights | `lights = LOW`, then `steer_to` the 6 m Finish across the causeway. |
| car_manual_gearbox | Gear 1, full accel, shift up past a fixed rpm; steer on heading. A 200 m run inside 11.5 s. |
| car_turn_signals | `follow` the window centres in order. The left/right lamp is steadily on while inside its Signal box, off otherwise (a steady lamp meets "never dark > 1.05 s"). |
| car_box_stop | `cruise(60)` until past the gate (odometer +170 m), then `stop_in` to the box centre (+187 m), then handbrake. |
| car_box_blind | The same solve, imported. The fog does not matter to CAN. |
| car_blind_stadium | The stadium built from the start pose: 20 m straight, left semicircle r=15, 40 m, semicircle, 20 m. `follow` at 15 km/h. |
| car_reverse_park | Forward east, turn right to face south at x≈-125, roll to z≈-62. Then reverse north at ~3 km/h holding x=-125 / heading 180, stop at the bay centre z=-83.7, handbrake. The bay is 1.98 m wide, which is why x,z come from GPS. |

`car_reverse_park` is the riskiest (a ±0.24 m lateral margin). If it fails twice, write a
symptoms/hypotheses handoff rather than tune blind (global rule).

## Verification

- Phase 1:
  - `node tools/godot_run.mjs --tests -- -a tests/<bridge test>` and `node tools/check_head_include.mjs`.
  - In sloppycan: `node --check js/carlito.js js/script-link.js`,
    `node .github/scripts/static-checks.mjs`, the relay unittest, `node .github/scripts/smoke.mjs`
    (the new self-test).
- End to end, by the user:
  - Export the web build locally (`docs/deploying.md`, lines 86-88: the main export + the
    `car_arena` patch) and serve `build/web/`.
  - Open local sloppyCAN with `?carlitoUrl=` pointing at it.
  - Run `python sloppycan_relay.py`, click Script → Connect, then `nc 127.0.0.1 29541`. Starting,
    retrying and leaving a challenge must print the four kinds of line.
- Phases 2-3: `python -m py_compile tools/challenge_solvers/*.py`, then the user runs each solver
  against a started challenge and reports pass/fail. The solver prints the result line.
- Hardware path: the user, with a RAMN and python-can. The telemetry frames reach the wire only
  while sloppyCAN's bus is not listen-only.

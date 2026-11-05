# sloppyCAN review: CAN realism, duplication, and the contract

Reviewed on 2026-11-05 against sloppyCAN `0e9e6e9` and carlito `5ec328a`, contract v60. Carlito was read-only. I read `contract/carlito_contract.json`,
`contract/CLAUDE.md`, `src/bridge/` and `src/input/sources/bridge_source.gd`, plus
`tools/gen_js_contract.mjs`, because the generator is what rule 4 is about.

**Checks run here, all green:** `node --check js/*.js`, `static-checks.mjs`, the relay
unittests (6 OK), and `smoke.mjs` (all self-tests, demo traffic, golden frames, "contract
coverage: ok"). None of the findings below is caught by those checks.

**How each finding was established.** Items marked *measured* were run. Everything else comes
from reading the code. The J1939-21, NMEA 2000 and CiA statements below come from my
knowledge of those standards. I did not open a primary source for them, so check each against
the standard before acting on it (repo rule: numbers come off a primary source).

Severity: **H** = wrong frames on the wire today · **M** = wrong or misleading behaviour with a
plausible trigger · **L** = cleanup or latent.

---

## 1. Contract: does sloppyCAN's copy, or its use, disagree with carlito?

### 1.1 The copy itself: in sync *(measured)*
`js/carlito_contract.js` evaluates to the same object as `carlito/contract/carlito_contract.json`.
I compared `JSON.stringify` of both, and they are identical: v60 with 161 signals on both sides.
The version check in `carlito.js:254` and `bridge.gd:_poll_inbound` agrees.

### 1.2 M: drift is guarded by the version number only
The generator (`tools/gen_js_contract.mjs`) is the only producer. The guards are the runtime
version warning and sloppyCAN CI's "Contract copy sanity" step (`ci.yml:39`), which checks only
that the copy loads and has a version and signals. Two builds that both say v60 but differ in an
enum, range or `count` pass silently. Carlito's workflows mention sloppyCAN only in
`promote.yml`'s paired-promote comment. Neither repo compares the copy with its source.

Fix: have the generator stamp a content hash (for example SHA-256 of the canonical JSON) next to
`version` in the generated file. The game publishes the same hash in the `carlitoOutput`
envelope (`head_include.html`, `bridge.gd`). Both sides then warn on a hash mismatch as well as
a version mismatch. In sloppyCAN CI, a cheap complement is to re-serialize
`window.CARLITO_CONTRACT` and diff it against the file. That catches hand edits to the
"generated, never hand-edit" copy, which nothing catches today.

### 1.3 M: `key` labels disagree with the contract enum — **DONE** (sloppycan 93d0462)
The contract `key` enum is `{1: Lock, 2: On, 3: Ignition}`. sloppyCAN hand-types different
labels twice:
- `js/carlito.js:234` `KEY_LBL = ['', 'Off', 'Acc', 'Ign']`
- `js/ramn.js:544` `KEYPOS = { 1: 'Off', 2: 'Acc', 3: 'Ign' }`

"Acc" (accessory) and "On" are different key positions on a real ignition switch, so the debug
panel and the RAMN dashboard name position 2 differently from the game. `LIGHT_LBL` in the same
line is a hand copy too, of `OFF/CLEARANCE/LOW/HIGH`. Read both from the contract:
`vehicle-panel.js` already has `sigDef(name, dir).enum`.

### 1.4 M: `engine_hours` on the boat never reaches NMEA 2000
The contract's `engine_hours` desc says it is "also N2K PGN 127489 … which the boat reads."
`nmea2000.js:236` `nfEngineDynamicPayload` leaves Total Engine Hours (bytes 11-14) "not
available" on purpose ("UNFLAVORED (the base CAN map's job)"). `CAN_MAP_ON_REQUEST.engine_hours`
(`carlito.js:699`) then declares the signal covered by a **J1939** HOURS request (65253). So on
a boat the only way to read the hour meter is a J1939 request on a vessel network. The coverage
check is satisfied, but the boat case the contract describes is not carried.

Fix: when the boat is on the link, write `engine_hours` into 127489's Total Engine Hours field
(bytes 11-14). The resolution I recall is 1 s per bit; verify it against `NMEA2K_DB`'s 127489
entry or the PGN definition. Declare it in the nmea2000 packer's `mirrors`, the same way
heading, lat and lon are mirrored.

### 1.5 L: comments disagree with the contract and the code — **DONE** (sloppycan 184ade4)
- `carlito.js:546`: `// 0=N, 1–6, 0xFE=P, 0xFF=R`. The contract is `1-24`.
- `carlito.js:579`: "fast IDs ~10/s, slow IDs ~5/s". The game publishes at 20 Hz
  (`bridge.gd PUBLISH_HZ`), so fast is ~20/s and slow ~10/s, as `carlito.js:954` says.
- `carlito.js:174`: the debug panel says `CAN 520–528`. The map runs to 0x52E.
- `carlito.js:20`: garbled header line `({ ...ramnState })//`.

---

## 2. Standing rule 4: definitions copied by hand instead of read from the contract — **PARTLY DONE**

**DONE:** `carlitoSig` / `carlitoGearTop` (sloppycan b416bdf), `DC_ARM_STATE` and the key/lights
labels (93d0462). **OPEN:** the `bits` contract field (a paired carlito change), so the status,
pre-arm and roster hand copies stay; the carlito-side `bridge_source.gd` items.

The contract is machine-readable where it has fields (`enum`, `range`, `count`) and **prose-only**
for every bitfield and roster. Each prose table has been copied by hand into one or more
sloppyCAN modules:

| Definition | Contract form | Hand copies |
|---|---|---|
| `status` bits 0-11 | prose in `status.desc` (+ `ST_*` in carlito's `vehicle_telemetry.gd`) | `carlito.js:223` (bit 8), `j1939-flavor.js:175` (7-11), `isobus.js:116-117` (0, 3), `boat.js:101` (0, 1, 6), `truck.js:43` `ST` (0, 2, 5, 6, 8-11), `tractor.js:52` `ST` (0, 5, 6, 7), plus the bit numbers again in their tell-tale titles |
| `prearm_fail` bits 0-6 | prose | `dronecan-core.js:1349` `DC_PREARM_BITS` |
| node roster / `node_fail` / `node_online` bit order | prose (`node_health`, `node_fail` descs) | `dronecan-core.js:1128` `DC_ROSTER` (says so itself) |
| `arming_state` enum | **machine-readable `enum`** | `dronecan-core.js:1350` `DC_ARM_STATE`: a copy of data the contract already provides |
| `key` / `lights` enums | machine-readable | `carlito.js:234`, `ramn.js:544` (see 1.3) |
| `gear` P / R bytes (254 / 255) | machine-readable enum | `carlito.js:248-249`, `j1939-flavor.js:398-399`, literals in `ramn.js:472, 509` |
| top gear (`1-N` key) | machine-readable | the same function twice: `ramn.js:655 ramnTopGear` and `j1939-flavor.js:402 jfTopGear` |

**M, recommended fix: a carlito-side contract change, done as a paired change.** Add an
optional `bits: {"0": "ignition", …, "8": "brake_light", …}` to bitfield signals (`status`,
`prearm_fail`, `node_fail`, `node_online`, `esc_fault`), parsed and validated by `contract.gd`
the way `enum` is. The frozen, append-only rule then has a machine-readable home that CI can
diff. sloppyCAN gets one helper, `carlitoBit('status', 'brake_light')`, and every row above
becomes a lookup. Until that lands, the row that needs no contract change is `DC_ARM_STATE`:
read `arming_state.enum`.

**L: eleven separate "find this signal in the contract" lookups, across nine files.** `carlito-registry.js:36`,
`carlito.js:241`, `cleanopen.js:46`, `dronecan-core.js:1094/1108/1283`, `dronecan.js:966`,
`isobus.js:279`, `j1939-flavor.js:403`, `ramn.js:656` and `vehicle-panel.js:165` each walk
`CARLITO_CONTRACT.signals` themselves. `carlito-registry.js` loads first on both pages, so it can
own a single `carlitoSig(name, dir)`. `jfTopGear` and `ramnTopGear` then collapse into
`carlitoGearTop()`.

**On the carlito side (read-only here; recommendations only):**
- `bridge_source.gd` normalizes all 49 "in" signals by hand. Each line repeats the contract's
  unit scaling (`/ 100.0` for `%`, clamped to `range`) and adds an absent-default the contract
  does not record. The contract's own note says the inbound path "normalizes each signal by
  hand, per name". `bridge_source.gd` does not iterate the contract. Whether a test pins every
  "in" name to an entry in `poll()` is outside the files I read.
  - A data-driven `poll()` would read `unit`, `range` and a new `default` field per signal.
    Only the presence-gated trio (`rudder`, `guidance_curvature`, `heading_cmd`) would keep
    special code.
  - Smaller step: add a test that `poll()`'s keys cover `Contract.data.signals` with `dir == "in"`.
- `gimbal_pitch` and `gimbal_yaw` are the only ranged "in" signals that `bridge_source.gd`
  passes through without clamping to the contract range (`[-90, 30]`, `[-120, 120]`). Clamping
  may happen downstream, but every other ranged input is clamped here.

---

## 3. Unrealistic CAN behaviour

### 3.1 H: the standalone bridge cuts every multi-frame transfer to one frame *(measured)* — **DONE** (sloppycan 8c1249f; smoke step 0ed0a3d)
`carlito-bridge.js:213-222` coalesces the downlink by CAN id
(`txLatest.set(frame.id, frame)`) to drop stale telemetry. That is right for single-frame
periodic telemetry and wrong for a transfer whose frames **all share one id**. NMEA 2000 Fast
Packet and DroneCAN multi-frame transfers both work that way, and the bridge page loads
`nmea2000.js` and `dronecan-core.js`.

I ran headless Chromium on `carlito-bridge.html` with a fake open SLCAN port, injected a boat
and then a drone telemetry payload (two ticks each, one fast and one slow), and counted frames
per id. Every single-frame id arrived intact. Every multi-frame transfer was cut to one frame:

| Transfer | CAN id | Frames packed | Frames sent |
|---|---|---|---|
| N2K 127489 Engine Dynamic | `09F20100` | 4 | 1 |
| N2K 127237 Heading/Track Control | `09F10501` | 4 | 1 |
| N2K 130577 Direction Data | `0DFE1102` | 3 | 1 |
| DroneCAN 1063 Fix2 (GNSS, node 20) | `14042714` | 8 | 1 |
| DroneCAN 1092 BatteryInfo (POWER, node 21) | `14044415` | 4 | 1 |
| DroneCAN 1000 ahrs.Solution (AHRS, node 22) | `1403E816` | 5 | 1 |
| DroneCAN 1034 esc.Status (each of nodes 11-14) | `14040A0B`-`0E` | 3 | 1 |

Five more DroneCAN multi-frame ids show the same drop.

A receiver drops every one of these transfers: wrong frame counter or toggle, a missing start,
a failed transfer CRC. The full app (`sloppycan.js:5222`) does not coalesce and is unaffected.

The probe is `/tmp/claude-0/-home-user-carlito/ca92d6bd-225c-5a58-b3ab-d854e403d680/scratchpad/pptr/bridge_probe.mjs`;
it may not survive the session. The method:
- Stub `sendCommand` to record lines.
- Set `busIsOpen`, `port` and `connMode`, and uncheck `#listenOnly`.
- Wrap `canForward` to record what was packed.
- Call `carlitoDebugInjectTelemetry` twice per payload, because ticks alternate fast and slow.

Fix options:
- Coalesce per **transfer**: key on `id` plus a transfer tag that `nfFastPacket` and
  `dcFrameSplit` attach, and queue a whole transfer atomically.
- Or bypass coalescing for any frame that carries a multi-frame marker.

Either way, add the probe as a smoke-test step so it stays fixed.

### 3.2 M: the J1939 request server NACKs global requests
`j1939.js:687-719` `j1939ServeRequest` sends an ACKM NACK whenever a matching server's builder
returns null, whatever the request's destination. J1939-21 (from memory; verify) says a
responder does **not** NACK a request sent to the global address (DA 0xFF), only a
destination-specific one.

Examples:
- With a car on the link, a global request for VW (65258) gets a NACK from "Axle - Drive #1"
  (0x09), an ECU a passenger car does not have.
- A global CCSS request on a boat gets a NACK from "Engine #1".

A related problem: the servers answer for any vehicle family that publishes the signal. A
boat's HOURS request is *answered* on J1939 (see 1.4), and so is a car's CCSS, although neither
vehicle has a J1939 network.

Fix: when `parsed.da === 0xFF` and `build` returns null, stay silent. Optionally serve only
families that have a J1939 network, using `carlitoIsFamily`, the same gate the mirrors use.

### 3.3 M: the 0x52x telemetry encoders wrap instead of saturating — **DONE** (sloppycan e6fbf8f, 4af91b0)
`carlito.js:582-588` `enc.*` masks to width (`& 0xFF`, `& 0xFFFF`) and never clamps. An
out-of-range value silently aliases to a plausible small one, or to the "not available" code:
- `impact` (u8, 1 m/s²/bit): the contract range is [0, 200], but the field is a crash peak.
  255 encodes as 0xFF, the NA code, and 260 encodes as 0x04, a gentle bump.
- `altitude` (u16 ×10, unsigned): any negative value wraps to ~6550 m.
- `posX` and `posZ` (i16, 1 m) wrap at ±32.7 km. They have no contract range.

`J1939Pack.put` already clamps under the reserved codes for the J1939 and N2K packers. The
proprietary block should do the same: clamp to `[min, NA − 1]` for unsigned fields and
`[−max, NA − 1]` for signed ones. Add a golden frame for an over-range impact.

### 3.4 M: demo J1939 traffic ignores the standard's rates and priorities — **DONE** (sloppycan c512779, e437509)
`sloppycan.js:2875` drives `j1939BaseDemoFrames` every 100 ms. Every group in it goes out at
10 Hz, including ET1, DD and VEP1, whose J1939-71 rate is 1 s. That rate is recorded in
`j1939-flavor.js:115-117`, and the game-driven packer respects it.

`j1939.js:1051` `n2kFrame` also hard-codes priority 6 for every PGN, so the demo's EEC1 is
`18F00400`. The game's EEC1 from the same SA is `0CF00400` (priority 3, `JF_MSGS.EEC1`). One
PGN from one ECU appears under two different CAN ids depending on whether the demo or the game
is producing it.

Fix: build the demo frames through the `jfEec1`/`jfEt1`/`jfDd`/`jfVep1` encoders (see 4.1) and
gate them by `JF_MSGS[*].ms`.

### 3.5 L: game-driven rates slower than the standard (declared, but one shared cap)
VDC2 (10 ms per J1939-71) and EEC1 (engine-speed dependent, typically 10-20 ms) go out at the
bridge's 50 ms tick (`j1939-flavor.js:295, 298`). The code states this honestly, and it is a
transport limit: the game publishes at 20 Hz. If the realism matters, the only lever is
`bridge.gd PUBLISH_HZ`, which is carlito-side.

### 3.6 L: NMEA 2000 instance fields left "not available"
`nfRudder` (`nmea2000.js:149`), `nfEngineRapid` (`:159`) and `nfEngineDynamicPayload` (`:236`)
leave byte 0, the Rudder or Engine **Instance**, at 0xFF. Instance is a key field. N2K displays
bind a gauge to instance 0 (port or single engine) and generally ignore 0xFF, so on real
hardware these PGNs probably reach no gauge. A single-engine, single-rudder boat should send
instance 0.

Related: none of the N2K sources (SA 0-4) ever sends ISO Address Claim (60928) or Product
Information (126996). Certified displays commonly list or accept only sources that have claimed
an address. Both statements are from memory; verify against NMEA 2000 Appendix B.

### 3.7 L: only the implement claims an address
On the J1939 side the engine, brakes, axle, transmission and cluster (`j1939-flavor.js:84-94`)
transmit without ever sending Address Claim. The demo claims for Engine #1, but the game-driven
path does not. Each J1939-81 control function claims at power-up. Sending one 60928 per SA on
`resetPackers()` would make a bus capture start the way a real one does.

### 3.8 L: RAMN steer encode and decode are asymmetric
`ramn.js:470` spans the right half by 0x800, while `ramn.js:504` decodes both halves by 0x7FF.
Full right lock therefore reads 100.05%. The game clamps it, so this is harmless, but the two
directions differ by a count.

### 3.9 L (latent): `gsUsbPackFrame` derives an RTR's DLC from its data — **DONE** (sloppycan 690216c)
`can-link.js:480` takes the DLC from `dataBytes.length`. An RTR's DLC is the requested length,
and an RTR has no data bytes. Today nothing sends a wrong frame:
- The full app's only RTR path (`gsUsbBuildFrame`, `sloppycan.js:1231`) pads the data to
  `msg.dlc` through `txDataBytes`, so the DLC comes out right. The gs_usb frame then carries
  `dlc` zero bytes that an RTR does not need.
- The other three callers pass `isRtr` false, or pass the frame's real data.

A future caller that passes `isRtr` with empty data would send DLC 0. Take the DLC as an
explicit parameter.

---

## 4. Duplicated code

### 4.1 M: two J1939 encoders for the same groups — **DONE** (sloppycan c512779)
The demo (`j1939.js:1110-1135`) hand-builds EEC1, ET1, CCVS, VEP1 and DD with literal scalings:
`/0.125`, `+40`, `(x+273)/0.03125`, `/0.05`, `/0.4`. It uses its own `n2kU16`/`n2kU32` and none
of the 0xFA clamping. `j1939-flavor.js` builds the same groups through `J1939Pack.put` with the
scalings in one place. Two encoders for one wire format will drift. The priority mismatch in
3.4 is the first symptom.

`j1939-pack.js`'s header says the packing helpers "used to be four near-identical local
copies". This is the copy that was missed. Export the `jf*` builders on `window.J1939Pack` or
`window.j1939FlavorBuilders`, and have the demo feed them a synthetic `t`.

### 4.2 L: two SLCAN and two gs_usb outbound encoders — **DONE** (sloppycan 690216c, incl. the hex round trip)
- SLCAN: `carlito-bridge.js:250 buildSlcan(frame)` and `sloppycan.js:533 txBuildSlcan(msg)`.
- gs_usb: `can-link.js:479 gsUsbPackFrame` and `sloppycan.js:1230 gsUsbBuildFrame`, a wrapper
  over a hex-string message.

`can-link.js` is the shared transport that both pages load. One `slcanEncode(frame)` there
removes the copy.

On the same path, `sloppycan.js:5229` `canForward` turns a frame's byte array into a hex
string so that `txTransmitRaw` can parse it back into bytes. Give `txTransmitRaw` a frame
overload and drop the round trip.

### 4.3 L: `enc.u16` and `enc.i16` are the same function — **DONE** (resolved by sloppycan e6fbf8f: they now saturate to different ranges)
`carlito.js:583-584`: the comment says the receiver picks the interpretation. One `enc.b16` is
enough, or keep the two names and alias one to the other.

---

## 5. Dead code and needless complexity — **PARTLY DONE**

**DONE:** `ms` is now read (sloppycan c512779), stale comments and the "See memory:" pointer
(184ade4). **OPEN:** `CAN_MAP_UNPACKABLE` / `checkCanCoverage` size, the `coerceIn` branch, the
override precedence, the gs_usb `withTxLock` caveat.

- **L: `ms` in `JF_MSGS` and `IB_MSGS` is never read** (`j1939-flavor.js:101-118`,
  `isobus.js:85-101`). The comments say it is "recorded so the gate … can be checked against
  it", but nothing checks it. The gates are hard-coded `slow`/1000/500 branches. Either have
  the packers gate on `ms` (which also fixes 3.4 if the demo uses them), or turn the field into
  a comment.
- **L: `CAN_MAP_UNPACKABLE = {}`** (`carlito.js:677`) and its three warnings in `report()` exist
  for a state no signal is in. The mechanism is cheap, but `checkCanCoverage` (`:762-853`) is
  ~90 lines and a dozen near-identical `filter` + `warn` lines for a run-once console check.
  `report()` would be half the size as a table of `[predicate, message]` rows iterated once.
- **L: unreachable `count > 1` branch in `coerceIn`** (`carlito.js:389-395`). `contract.gd`
  already rejects `count` on an "in" signal at parse, and the branch says it is unreachable.
  The contract-hash guard in 1.2 would cover it. Otherwise keep it as a one-line assert.
- **M: uplink override precedence depends on load order.** `carlitoUplinkOverrides` entries
  compose by wrapping the previous closure (`j1939-flavor.js:506-512`), and drone.js "composes
  the other way round, so the Drone Control panel wins whichever file loads first". Precedence
  that is correct only because two files wrap in opposite directions is fragile. A third
  claimant has to read both files to know where it lands. A `{ name: [{ prio, fn }] }` list,
  asked in priority order, states the rule once.
- **L: stale or dangling comments.**
  - `sloppycan.js:2780` says "Simulates 9 CAN IDs"; `DEMO_CONFIG` has 10.
  - `sloppycan.js:557` says "See memory: slcan-write-serialization". That points at an agent
    memory, not a file in the repo.
  - The same note says gs_usb TX is not serialized, while `window.withTxLock` exists
    (`sloppycan.js:732`). Either route `canForward`'s gs_usb branch through it or drop the
    caveat.

---

## What I checked and found correct (no action)

- **J1939 scalings and positions** match J1939-71 as I know it: EEC1 SPN 190, EEC2 SPN 91/92,
  ET1 SPN 110, DD SPN 96, VEP1 SPN 168, CCVS SPN 84/70/597, EBC1 SPN 521/1238, VDC2 SPN
  1807-1810 (resolutions and offsets), ETC2 SPN 523/524/526, AIR1 SPN 1087/1088, ERC1 SPN 520.
  The Table 1 clamp in `J1939Pack.put` (0xFA / 0xFAFF) and the PDU1/PDU2 id build are right.
- **NMEA 2000 layouts:** 127250, 129025, 129026, 128259, 128267, 130306 (reference codes),
  127489's 26-byte layout and 0.1 L/h fuel rate, signed-NA = max positive, and the Fast Packet
  header.
- **DroneCAN v0 framing:** tail byte, toggle starting at 0, CRC-16-CCITT seeded with the
  little-endian signature, single-frame for 7 bytes or fewer, response tid copied from the
  request.
- **ISO 11783 NAME bit packing** (`isobus.js:236`) and the device-class-as-vehicle-system
  mapping.
- **Every 0x52x DLC is 8 or less.** NA bytes are all-ones for unsigned and max-positive for
  signed fields.

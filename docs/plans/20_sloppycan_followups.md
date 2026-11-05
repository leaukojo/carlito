# Plan — sloppyCAN follow-ups: standards checks, cleanup, the paired contract change

The open part of the sloppyCAN review. Four behaviours rest on a standard the reviewer read from
memory. Section 5's cleanups and the RAMN steer asymmetry remain. Two fixes need a carlito
contract change: a content hash beside `version`, and a machine-readable `bits` field. Phases 1–2
are sloppyCAN-only; phase 3 is paired. Findings: `reviews/E_sloppycan.md` 1.2, 1.4, 2 (open
part), 3.2, 3.6, 3.7, 3.8, 5 (open part). 3.5 (the 20 Hz publish rate) is a declared transport
limit and stays out.

Written 2026-11-05. Status: **not started.**
Serves: sloppyCAN's frames matching the standards a real tool expects, and rule 4 (one contract
file; everything else generated from or validated against it).
State: done — nothing; next — phase 1; open findings — none.

## Phase 1 — Standards-checked fixes (effort: high; mode: plan-mode-first)

Each item is checked first against the local PDFs (`../j1939-71.pdf`, `../Open SAE J1939.pdf`,
plus an NMEA 2000 source the user provides or a page opened), with the page cited. An item the
standard does not confirm is dropped.
- 3.2: no NACK to a global request (DA 0xFF). Serve requests only for families with a J1939
  network (`carlitoIsFamily`).
- 1.4: `engine_hours` in 127489 bytes 11–14, at the resolution the PGN definition gives, declared
  in the nmea2000 packer's `mirrors`.
- 3.6: instance 0 on the rudder and engine PGNs. Decide whether to add Address Claim and Product
  Information for the N2K sources.
- 3.7: one Address Claim (60928) per J1939 SA on `resetPackers()`.
- Each change gets a golden frame. Done when the smoke test is green and the user has checked a
  capture (bust the browser JS cache first).

## Phase 2 — Cleanup (effort: medium; mode: accept-edits)

- 5: uplink override precedence as an explicit priority list, with behaviour unchanged (the Drone
  Control panel still wins).
- 5: `checkCanCoverage`'s `report()` as a table of rows.
- 5: `coerceIn`'s unreachable branch becomes a one-line assert.
- 5: the gs_usb `withTxLock` caveat: route through the lock or drop the caveat.
- 3.8: the RAMN steer encode and decode use one span.
- Done when sloppyCAN's CI checks (`node --check`, the static checks, the relay unittests, the
  smoke test) are green.

## Phase 3 — The paired contract change (effort: high; mode: plan-mode-first)

- Use the `contract-edit` skill, one bump, paired promote.
- 1.2: `gen_js_contract.mjs` stamps a SHA-256 of the canonical JSON beside `version`. The game
  publishes it in the `carlitoOutput` envelope, and both sides warn on a mismatch. sloppyCAN CI
  diffs the re-serialized copy against the file.
- 2: an optional `bits` field on the bitfield signals (`status`, `prearm_fail`, `node_fail`,
  `node_online`, `esc_fault`), parsed and validated by `contract.gd`. sloppyCAN gets
  `carlitoBit(name, bit)`, and the hand copies in the review's table become lookups.
- Carlito side: a test that `bridge_source.gd`'s `poll()` keys cover every "in" signal, and
  `gimbal_pitch` / `gimbal_yaw` clamped to their range. A data-driven `poll()` is the user's call;
  the coverage test is the recommended step.
- Done when both repos' checks are green and a version-matched, hash-mismatched pair warns.

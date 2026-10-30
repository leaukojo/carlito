# Plan — Docs headroom

The top-level docs sit at their line cap (`tools/check_docs.mjs` `DOCS_LINE_CAP`, raised to 3460
for plan 3's phase 4) and the measured-figure cap (25/25): the next doc change fails the check.
This plan wins room back by tightening, never by moving content out of reach: restated code,
history, duplicated derivations and figures quoted outside a `<!-- measure:<id> -->` region go;
constraints and their reasons stay (root CLAUDE.md § Where things go).

Written 2026-10-25. Status: **not started.**
Serves: room for the next plan's docs without raising a cap again.
State: done — nothing; next — phase 0; open findings — none.

## Phase 0 — Find the cuts (effort: medium; mode: plan-mode-first)

- Read the largest top-level docs (`check_docs.mjs` lists them) for: prose that restates code or
  a code comment, history ("used to", phase names), a derivation told twice, loose figures a region
  already carries, tables a generated region could replace. List each cut with its line count.
- Ask the user: the target headroom (lines and figures), and whether `DOCS_LINE_CAP` comes back
  down to 3400 once the cuts land.

## Phase 1 — Cut (effort: medium; mode: accept-edits)

- Apply the approved cuts; every reference still resolves (`node tools/check_docs.mjs`); the cap
  per phase 0's answer. Done when the check passes with the agreed headroom.

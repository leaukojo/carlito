# Plan: built but never wired

Sonnet, effort **low**, mode: direct. Delete this file when done.

## Problem

Round two found a roster node with no consumer (POWER), `ChallengeRunner.restart()` dead on
the shipped path, and `ShellPrefs` fully written but disabled. Features get built to the
interface and the last wiring step slips silently.

## Prompt

1. Write `tools/check_orphans.mjs` (or `.gd` `extends SceneTree` if it needs the class graph):
   for every non-underscore `func` in `src/` and `kit/`, count call sites outside `tests/` and
   its own file (text search is enough; treat `call("name")`, signal connects and `has_method`
   probes as callers). Print functions with zero callers. Exclude Godot lifecycle overrides and
   anything listed in a `tools/orphans_allow.txt`.
2. Run it once, triage the list with the user: each hit is either wired now, deleted, or added
   to the allow-list with a reason.
3. Add it to `tools/preflight.ps1` as a gate. One line in root `CLAUDE.md` under Running.
Separately decide `ShellPrefs.ENABLED`: it has been `false` long enough that either the boot
path is tested and it flips, or the prefs code is dead weight — ask, do not guess.

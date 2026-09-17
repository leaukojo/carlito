# Plan: comments that promise what code does not do

Opus, effort **medium**, mode: delegate, read-only. Delete this file when done.

## Problem

The drone respawn comment described leaving the crate behind while the code teleported it;
`boot.gd` promised persistence that `ShellPrefs.ENABLED = false` cannot keep; `TrainSim` said
"set by TrainVehicle" and nothing set it; `BoatSail` said its axes arrived flattened. The
codebase is comment-rich and every sentence is a claim that can drift.

## Prompt

Walk `src/` and `kit/` (skip sloppycan, addons, generated files). For every comment or
docstring that makes a checkable claim about behaviour — "X is reset on Y", "never negative",
"already normalised", "caller guarantees", "only called from" — verify it against the code and
callers. Report only mismatches: `file:line`, the claim, what the code does, and whether the
COMMENT or the CODE is wrong (the CLAUDE.md rule: a comment states the live constraint; a
promise the code cannot keep is either a bug or a stale comment). Aim for 15-30 items with
confidence. Then a Sonnet fixer (effort low) applies the comment-side corrections in one batch
and lists the code-side ones for a follow-up.

# Plan: byte-deterministic bake output

Sonnet, effort **medium**, mode: direct. Delete this file when done.

## Problem

A full `bake_levels` run rewrites the `output_hash` of levels whose `input_hash` did not change
(seen on level_1/2/4/5 after touching only the sun in three other levels), so every re-bake
dirties every manifest. `output_hash` is `FileAccess.get_sha256` over the raw `.baked.scn`
(`kit/bake/level_baker.gd`), and something in the bake serialises in varying order:
dictionary iteration, sub-resource ids or generated uids are the usual suspects. Because of
this the manifest `stats` block, not the output bytes, is the comparand that proves a refactor
changed nothing (`kit/CLAUDE.md` § baked output).

## Prompt

Read `kit/CLAUDE.md` first. Bake one level twice, diff the two `.baked.scn` as text (save a
`.tscn` twin for the diff), and find the varying field. Fix the source (sorted iteration,
stable ids) or hash a canonical form. Prove it: two consecutive full bakes must leave every
manifest unchanged. Then rewrite the `kit/CLAUDE.md` paragraph that explains why `stats` is the
comparand, and bump `BAKER_VERSION` if the pack bytes changed.

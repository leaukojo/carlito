# Plan: shader warmup for post-load materials

Sonnet, effort **medium**, mode: measure-then-fix. Delete this file when done.

## Problem

`ShaderWarmup` (`src/shell/shader_warmup.gd`) compiles every material the level holds at load,
hidden instances included, but gl_compatibility still compiles synchronously on the first draw
of anything that arrives later: a V / garage body swap, an E attachment or trailer, and the
light-count variants when headlights or night first light a material. Each is a one-frame hitch
on web.

## Prompt

Measure first: frame-time spikes on the deployed dev build (F3 overlay) for a body swap, an
attachment, and headlights-on at night; skip any case that does not hitch. Then add a warmup
pass per swap (instantiate the body off-screen for a frame with grown cull margins) and a
load-time frame with headlights on. Re-measure on the deployed build; record the before/after in
`src/ui/CLAUDE.md` or beside `shader_warmup.gd`'s header, whichever the code constrains.

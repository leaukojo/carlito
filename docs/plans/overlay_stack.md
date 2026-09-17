# Plan: shell overlays as a stack

Sonnet, effort **medium**, mode: direct. Delete this file when done.

## Problem

`boot.gd` holds five independent nullable overlay refs (`_pause`, `_select`, `_challenges`,
`_vehicles`, `_briefing`). Round two replaced the "unpause if `_pause == null`" checks with a
derived `_any_overlay_open()`, which stops the world running under a modal, but `_on_menu_key`
still closes in a fixed order rather than the order they were opened, and each `_show_*` guards
only against its own instance.

## Prompt

Read `src/shell/boot.gd`'s overlay code and `docs/systems.md` § shell. Replace the five refs
with one `_overlays: Array[Control]` stack: `_push_overlay(node)`, `_pop_overlay()`, Esc pops
the top, a menu key for an overlay already in the stack pops down to it instead of stacking a
duplicate, and pause/touch state derives from `_overlays.is_empty()`. Keep the public shape
(the same signals, the same F-keys). Cover it in `tests/test_shell_menus.gd`: open LEVEL then
CHALLENGES, Esc closes CHALLENGES only, world stays paused; INFO during an attempt then LEVEL
then Esc twice returns to the attempt with the timer having not advanced. Headless boot after.

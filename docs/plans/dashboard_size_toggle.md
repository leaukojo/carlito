# Plan — Dashboard size button and AUTO default

Add a MORE/LESS button on the dashboard itself that switches COMPACT and FULL for the current
vehicle family (kept after a reload), and make a new AUTO setting the default: FULL when it fits
the window, else COMPACT.

Written 2026-11-15. Status: **in progress.**
Serves: the FULL bars (engine_load, temps, air, ...) that levels exist to show, seen on screens
where they fit. No contract signal changes.
State: done: phases 1-3, review fixes (AUTO's measure counts the wrapped flow rows; touch-sized
tab). Next: the user drives
(Verification); then distil into docs and delete this plan. Open findings: none.

## Context

Size is only reachable via Settings or F2 (cycle COMPACT → FULL → OFF), and the default is
COMPACT everywhere, so a desktop player never sees the bars unless they find F2. A phone needs
COMPACT; the drone's FULL (26 bar rows) is too tall even on a laptop. Decided with the user:
the button **pins per vehicle family, saved**; AUTO = **"FULL if it fits"** (no per-family table).

## Design

**Settings (`src/ui/dashboard.gd`)**
- `Density` gains `AUTO`, appended (`{FULL, COMPACT, OFF, AUTO}`). `DENSITY_KEYS` cycle:
  AUTO → COMPACT → FULL → OFF → AUTO. `set_density_setting` fallback and `key_of` default → AUTO.
- New `_layout: int` = the concrete density built (FULL/COMPACT/OFF). Every build-time read of
  `_density` reads `_layout` instead.
- Resolution order: setting OFF → OFF; else the family's pin if any; else setting COMPACT/FULL;
  else AUTO → fit.
- Pins: family → `"compact"|"full"`; `set_pins(d)` from the shell.

**AUTO's fit**
- `static func full_fits(full_size: Vector2, view: Vector2) -> bool`:
  `x <= view.x and y <= view.y * AUTO_MAX_H`, `AUTO_MAX_H := 0.34` (tuned by driving).
- Under AUTO, `_build` builds FULL, reads `panel.get_combined_minimum_size()`, and if it does not
  fit, rebuilds COMPACT. The trial's measurements are kept, so `NOTIFICATION_RESIZED` re-resolves
  only when the fit flips.
- Fallback if the min size reads wrong in practice: measure after one frame with the trial panel
  transparent. Not built unless needed.

**The button**
- A small `Button` ("MORE" in COMPACT, "LESS" in FULL) as a tab centred on the panel's top edge:
  the bottom corners are under the touch joystick and pedals. `focus_mode = FOCUS_NONE`.
- Press emits `signal size_pinned(family: String, layout: int)` and applies the pin locally.

**Persistence and shell**
- `src/shell/user_settings.gd`: key `"density"` → `"dashboard"` default `AUTO` (drops every old
  file's stale COMPACT); new `"dash_pins": {}` (String → String).
- `src/shell/boot.gd`: applies pins; `size_pinned` → save pin; a Settings/F2 pick clears all pins.
- `src/ui/pause_menu.gd`: `DENSITY_HELP` mentions AUTO and the button.

## Phases

1. **Dashboard: AUTO, `_layout`, fit, button** — effort medium, accept-edits.
2. **Settings + shell + pause menu wiring** — effort low, accept-edits.
3. **Tests + docs** — effort low, accept-edits. `test_dashboard`, `test_user_settings`,
   `test_shell_menus`; `docs/guide/controls.md`, `docs/systems.md`.

## Verification

- `test_dashboard.gd`, `test_user_settings.gd`, `test_shell_menus.gd`, full suite, smoke.
- User drives: desktop car → FULL by default, drone → COMPACT; click MORE/LESS, reload, pin kept
  for that family only; Settings/F2 clears pins; a small window → COMPACT; phone → COMPACT, button
  clear of the touch pads and not pressed by Space.

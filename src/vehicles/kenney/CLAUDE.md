# Kenney bodies — gotchas & hard-won rules

- Kenney lamp placement is **measured, never guessed**: a lens is not a named node (each
  vehicle is one merged mesh on a shared colormap atlas), so `gen_kenney_vehicles.gd` samples
  the atlas at every triangle's UV centroid and unions welded same-shade triangles into lens
  clusters (amber = front, red = rear). Each end's lens is then SPLIT along its width — inboard
  65% = head/brake lamp, outboard 35% = turn indicator, since the kit paints no indicator of
  its own. The run prints a per-variant lens report; `fallback` means that end has no painted
  lamp and the body-box formula placed it — a guess, so `_fallback_lamp_y` overrides its HEIGHT
  per variant where driving showed the box centre wrong. Correct a fallback lamp THERE, never
  in the `.tscn`: `Lamps` is generator-owned. Filter candidates BEFORE merging or a lens fuses
  into a same-hue body panel (the firetruck is red all over).
- Kenney vehicle **hand-authored anatomy is preserved across regens, by whitelist**:
  `gen_kenney_vehicles.gd` writes only `Model` + `Lamps` (`GENERATED_CHILDREN`) and transplants
  every other direct child of the existing scene — the hand-tuned
  `CollisionLower`/`CollisionUpper` box pair, and the tractor's `ThreePointHitch` instance. A
  whitelist of what the generator OWNS, never a list of what to save, so a hand-added node
  survives by default. Only a brand-new variant with no scene yet gets a generated convex hull.
  Extras are **reparented** out of an instance loaded with `GEN_EDIT_STATE_INSTANCE`, not
  duplicated: `duplicate()` loses the scene-instance state, so `pack()` writes the instanced
  scene's own properties back out and the hitch lands carrying a `script=` pinning the vehicle
  scene to today's hitch script. Adding a new generated child means adding its name to
  `GENERATED_CHILDREN`, or the old one is transplanted alongside the new one. To reset a
  variant's collision to the auto hull, delete its collision nodes from the .tscn first, then
  regen.
  - A NODE survives a regen; a hand-written `;` COMMENT in the `.tscn` does not. `pack()`
    writes a scene graph, so there is nowhere for a comment to live, and while one is in the
    file the generator is not idempotent either — `_save_scene_stable` only keeps the old bytes
    when the two files are otherwise identical, so the whole scene re-churns its `unique_id`s
    on every run. Put that kind of note in this file or in the generator, never in generated
    output.

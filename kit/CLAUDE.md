# Kit, bake & editor tools — rules

Authoring tour, conform and rail detail: `docs/level_kit.md`. A level edit ends with the
`level-edit` skill.

- Roads: the ribbon derives from curve + profile alone (never reads terrain), on a custom frame
  (never `sample_baked_with_rotation`: parallel transport accumulates roll). The profile default
  is set in editor `_ready`, never as a preload export default (a default-equal value is omitted
  from the `.tscn`, an input-hash hole).
- A generator that owns a level overwrites it, hand edits included.
- COMPROMISE: colormap `451b163d` ships three byte-identical times (garage, parked, kenney
  vehicles). Deleting a copy silently reverts (each `.glb` re-resolves its sibling `Textures/` on
  every import); undoing it costs GLB surgery or content-hash dedup in the baker.
